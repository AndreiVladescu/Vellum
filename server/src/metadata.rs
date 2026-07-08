//! Online book metadata search — the server-side twin of the app's
//! `metadata.dart`: query Open Library first, fall back to Google Books.

use serde::{Deserialize, Serialize};
use serde_json::Value;

use crate::error::{AppError, AppResult};

/// One edition/work found by a metadata search. Doubles as the body the console
/// posts back to add the chosen book.
#[derive(Debug, Clone, Serialize, Deserialize)]
pub struct BookSearchResult {
    #[serde(default)]
    pub work_key: String,
    pub title: String,
    #[serde(default)]
    pub subtitle: Option<String>,
    #[serde(default)]
    pub authors: Vec<String>,
    #[serde(default)]
    pub first_publish_year: Option<i64>,
    #[serde(default)]
    pub isbn: Option<String>,
    #[serde(default)]
    pub cover_id: Option<i64>,
    #[serde(default)]
    pub cover_url: Option<String>,
    #[serde(default)]
    pub description: Option<String>,
    #[serde(default)]
    pub subjects: Vec<String>,
    #[serde(default)]
    pub publisher: Option<String>,
    #[serde(default)]
    pub page_count: Option<i64>,
}

impl BookSearchResult {
    /// Full-size cover URL, preferring the Open Library cover id.
    pub fn large_cover_url(&self) -> Option<String> {
        match self.cover_id {
            Some(id) => Some(format!("https://covers.openlibrary.org/b/id/{id}-L.jpg")),
            None => self.cover_url.clone(),
        }
    }
}

/// Open Library first; Google Books only if it returns nothing or errors. A
/// source error is treated as "no results" so callers can offer to create a
/// custom book instead of failing.
pub async fn search(http: &reqwest::Client, query: &str) -> AppResult<Vec<BookSearchResult>> {
    let open_library = open_library_search(http, query).await.unwrap_or_default();
    if !open_library.is_empty() {
        return Ok(open_library);
    }
    Ok(google_books_search(http, query).await.unwrap_or_default())
}

/// The work's description (Open Library holds it separately from search).
pub async fn fetch_description(
    http: &reqwest::Client,
    work_key: &str,
) -> AppResult<Option<String>> {
    if work_key.is_empty() {
        return Ok(None);
    }
    let res = http
        .get(format!("https://openlibrary.org{work_key}.json"))
        .send()
        .await
        .map_err(net)?;
    if !res.status().is_success() {
        return Ok(None);
    }
    let body: Value = res.json().await.map_err(net)?;
    Ok(match body.get("description") {
        Some(Value::String(s)) => Some(s.clone()),
        Some(Value::Object(o)) => o.get("value").and_then(|v| v.as_str()).map(String::from),
        _ => None,
    })
}

/// Downloads the full-size cover for a result, or None if it has none / fails.
pub async fn download_cover(http: &reqwest::Client, result: &BookSearchResult) -> Option<Vec<u8>> {
    let url = result.large_cover_url()?;
    let res = http.get(url).send().await.ok()?;
    if !res.status().is_success() {
        return None;
    }
    let bytes = res.bytes().await.ok()?;
    (!bytes.is_empty()).then(|| bytes.to_vec())
}

async fn open_library_search(
    http: &reqwest::Client,
    query: &str,
) -> AppResult<Vec<BookSearchResult>> {
    let res = http
        .get("https://openlibrary.org/search.json")
        .query(&[
            ("q", query),
            (
                "fields",
                "key,title,subtitle,author_name,first_publish_year,isbn,cover_i,\
                 subject,publisher,number_of_pages_median",
            ),
            ("limit", "20"),
        ])
        .send()
        .await
        .map_err(net)?;
    if !res.status().is_success() {
        return Err(AppError::Internal(format!(
            "Open Library search failed (HTTP {})",
            res.status()
        )));
    }
    let body: Value = res.json().await.map_err(net)?;
    let docs = body.get("docs").and_then(Value::as_array);
    Ok(docs
        .map(|d| d.iter().filter_map(parse_open_library_doc).collect())
        .unwrap_or_default())
}

async fn google_books_search(
    http: &reqwest::Client,
    query: &str,
) -> AppResult<Vec<BookSearchResult>> {
    let res = http
        .get("https://www.googleapis.com/books/v1/volumes")
        .query(&[("q", query), ("maxResults", "20"), ("printType", "books")])
        .send()
        .await
        .map_err(net)?;
    if !res.status().is_success() {
        return Err(AppError::Internal(format!(
            "Google Books search failed (HTTP {})",
            res.status()
        )));
    }
    let body: Value = res.json().await.map_err(net)?;
    let items = body.get("items").and_then(Value::as_array);
    Ok(items
        .map(|i| i.iter().filter_map(parse_google_volume).collect())
        .unwrap_or_default())
}

fn parse_open_library_doc(doc: &Value) -> Option<BookSearchResult> {
    let title = str_field(doc, "title")?;
    if title.is_empty() {
        return None;
    }
    Some(BookSearchResult {
        work_key: str_field(doc, "key").unwrap_or_default(),
        title,
        subtitle: str_field(doc, "subtitle"),
        authors: str_array(doc, "author_name"),
        first_publish_year: doc.get("first_publish_year").and_then(Value::as_i64),
        isbn: str_array(doc, "isbn").into_iter().next(),
        cover_id: doc.get("cover_i").and_then(Value::as_i64),
        cover_url: None,
        description: None,
        subjects: str_array(doc, "subject"),
        publisher: str_array(doc, "publisher").into_iter().next(),
        page_count: doc.get("number_of_pages_median").and_then(Value::as_i64),
    })
}

fn parse_google_volume(item: &Value) -> Option<BookSearchResult> {
    let info = item.get("volumeInfo")?;
    let title = str_field(info, "title")?;
    if title.is_empty() {
        return None;
    }

    let year = str_field(info, "publishedDate")
        .and_then(|d| d.get(0..4).and_then(|y| y.parse::<i64>().ok()));

    // Prefer an ISBN-13, else whatever identifier is present.
    let mut isbn = None;
    if let Some(ids) = info.get("industryIdentifiers").and_then(Value::as_array) {
        for id in ids {
            if let Some(value) = str_field(id, "identifier") {
                isbn.get_or_insert(value.clone());
                if str_field(id, "type").as_deref() == Some("ISBN_13") {
                    isbn = Some(value);
                    break;
                }
            }
        }
    }

    let thumbnail = info
        .get("imageLinks")
        .and_then(|links| links.get("thumbnail").or_else(|| links.get("smallThumbnail")))
        .and_then(Value::as_str)
        .map(|s| s.replace("http://", "https://"));

    Some(BookSearchResult {
        work_key: String::new(),
        title,
        subtitle: str_field(info, "subtitle"),
        authors: str_array(info, "authors"),
        first_publish_year: year,
        isbn,
        cover_id: None,
        cover_url: thumbnail,
        description: str_field(info, "description"),
        subjects: str_array(info, "categories"),
        publisher: str_field(info, "publisher"),
        page_count: info.get("pageCount").and_then(Value::as_i64),
    })
}

fn net(e: reqwest::Error) -> AppError {
    AppError::Internal(format!("metadata source error: {e}"))
}

fn str_field(value: &Value, key: &str) -> Option<String> {
    value.get(key).and_then(Value::as_str).map(String::from)
}

fn str_array(value: &Value, key: &str) -> Vec<String> {
    value
        .get(key)
        .and_then(Value::as_array)
        .map(|a| a.iter().filter_map(Value::as_str).map(String::from).collect())
        .unwrap_or_default()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn parses_an_open_library_doc() {
        let doc = serde_json::json!({
            "key": "/works/OL45883W",
            "title": "Dune",
            "author_name": ["Frank Herbert"],
            "first_publish_year": 1965,
            "isbn": ["9780441013593"],
            "cover_i": 12345,
            "number_of_pages_median": 412
        });
        let parsed = parse_open_library_doc(&doc).unwrap();
        assert_eq!(parsed.title, "Dune");
        assert_eq!(parsed.authors, vec!["Frank Herbert".to_string()]);
        assert_eq!(parsed.first_publish_year, Some(1965));
        assert_eq!(parsed.cover_id, Some(12345));
        assert_eq!(
            parsed.large_cover_url().as_deref(),
            Some("https://covers.openlibrary.org/b/id/12345-L.jpg")
        );
    }

    #[test]
    fn parses_a_google_volume() {
        let item = serde_json::json!({
            "volumeInfo": {
                "title": "Neuromancer",
                "authors": ["William Gibson"],
                "publishedDate": "1984-07-01",
                "industryIdentifiers": [
                    {"type": "ISBN_10", "identifier": "0441569595"},
                    {"type": "ISBN_13", "identifier": "9780441569595"}
                ],
                "pageCount": 271
            }
        });
        let parsed = parse_google_volume(&item).unwrap();
        assert_eq!(parsed.title, "Neuromancer");
        assert_eq!(parsed.first_publish_year, Some(1984));
        assert_eq!(parsed.isbn.as_deref(), Some("9780441569595"));
        assert_eq!(parsed.page_count, Some(271));
    }
}
