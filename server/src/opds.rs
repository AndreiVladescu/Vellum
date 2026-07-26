//! OPDS, so third-party e-reader apps can browse and download the library.
//!
//! **1.2 by default, 2.0 on request.** OPDS 1.2 is Atom XML and is what Kobo,
//! KOReader, Moon+, Aldiko and the rest actually implement; OPDS 2.0 is JSON and
//! is what newer clients prefer. Both are the same aggregation with a different
//! serialisation, so serving both costs almost nothing (plan 5 #34).
//!
//! **Navigation before acquisition.** A flat 1,000-entry feed is unusable on an
//! e-ink device — it downloads and re-renders the whole thing to scroll. So
//! `/opds` is now a *navigation* feed (Recent / All / By author / By genre /
//! By tag) and every acquisition feed is **paged** with `rel="next"`, which is
//! how OPDS clients expect to walk a large catalogue.
//!
//! Auth is HTTP Basic (see the `AuthUser` extractor), which is what e-readers
//! speak, and every feed is filtered by the same access predicate as
//! `/api/books` — a shared library must not leak through its catalogue.

use axum::extract::{Path, Query, State};
use axum::http::{HeaderMap, HeaderValue, StatusCode, header};
use axum::response::{IntoResponse, Response};
use serde::Deserialize;

use crate::AppState;
use crate::auth::AuthUser;
use crate::books::{BookDto, access_predicate, author_map, files_map};
use crate::error::AppResult;

const ACQUISITION: &str = "application/atom+xml;profile=opds-catalog;kind=acquisition";
const NAVIGATION: &str = "application/atom+xml;profile=opds-catalog;kind=navigation";
const OPENSEARCH: &str = "application/opensearchdescription+xml";
const OPDS2: &str = "application/opds+json";

/// Entries per acquisition page. Big enough that a 200-book shelf is a few
/// pages, small enough that an e-ink client renders one without stalling.
const PAGE_SIZE: i64 = 50;

#[derive(Deserialize, Default)]
pub struct FeedQuery {
    pub page: Option<i64>,
    pub q: Option<String>,
}

impl FeedQuery {
    fn page(&self) -> i64 {
        self.page.unwrap_or(1).max(1)
    }
    fn offset(&self) -> i64 {
        (self.page() - 1) * PAGE_SIZE
    }
}

// ---- the navigation root --------------------------------------------------

pub async fn root(State(state): State<AppState>, user: AuthUser) -> AppResult<Response> {
    let base = base_of(&state);
    let now = now_rfc3339(&state).await;
    let mut entries = String::new();
    for (path, title, description) in nav_sections(&state) {
        entries.push_str(&nav_entry(&base, path, title, description, &now));
    }
    // The root lists sections; each one re-checks access itself. Requiring auth
    // here anyway is deliberate: an unauthenticated client should be challenged
    // at the catalogue root, not two clicks in.
    let _ = user;

    let xml = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog">
  <id>{base}/opds</id>
  <title>Vellum Library</title>
  <updated>{now}</updated>
  <author><name>Vellum</name></author>
  <link rel="self" href="{base}/opds" type="{NAVIGATION}"/>
  <link rel="start" href="{base}/opds" type="{NAVIGATION}"/>
  <link rel="search" href="{base}/opds/search.xml" type="{OPENSEARCH}"/>
  <link rel="alternate" href="{base}/opds/v2" type="{OPDS2}"/>
{entries}</feed>
"#
    );
    Ok(([(header::CONTENT_TYPE, NAVIGATION)], xml).into_response())
}

/// The sections the root offers. The full-text entry appears only when this
/// server actually has a content index (plan 5 #32) — a catalogue entry that
/// leads to an error is worse than one that isn't there.
fn nav_sections(state: &AppState) -> Vec<(&'static str, &'static str, &'static str)> {
    let mut sections = vec![
        (
            "/opds/recent",
            "Recently added",
            "The newest arrivals first",
        ),
        ("/opds/all", "All books", "Everything, by title"),
        ("/opds/authors", "By author", "Browse by who wrote it"),
        ("/opds/genres", "By genre", "Browse by genre"),
        ("/opds/groups", "By tag", "Your tags and collections"),
    ];
    if state.index_text {
        sections.push((
            "/opds/search.xml",
            "Search inside books",
            "Full-text search of book contents",
        ));
    }
    sections
}

fn nav_entry(base: &str, path: &str, title: &str, description: &str, now: &str) -> String {
    format!(
        "  <entry>\n\
         \x20   <id>{base}{path}</id>\n\
         \x20   <title>{title}</title>\n\
         \x20   <updated>{now}</updated>\n\
         \x20   <content type=\"text\">{description}</content>\n\
         \x20   <link rel=\"subsection\" href=\"{base}{path}\" type=\"{NAVIGATION}\"/>\n\
         \x20 </entry>\n",
        title = escape(title),
        description = escape(description),
    )
}

// ---- acquisition feeds ----------------------------------------------------

pub async fn all(
    State(state): State<AppState>,
    user: AuthUser,
    headers: HeaderMap,
    Query(q): Query<FeedQuery>,
) -> AppResult<Response> {
    page_feed(
        &state,
        &user,
        &headers,
        &q,
        "All books",
        "/opds/all",
        "b.title, b.id",
        None,
    )
    .await
}

pub async fn recent(
    State(state): State<AppState>,
    user: AuthUser,
    headers: HeaderMap,
    Query(q): Query<FeedQuery>,
) -> AppResult<Response> {
    page_feed(
        &state,
        &user,
        &headers,
        &q,
        "Recently added",
        "/opds/recent",
        "b.created_at DESC, b.id",
        None,
    )
    .await
}

pub async fn by_author(
    State(state): State<AppState>,
    user: AuthUser,
    headers: HeaderMap,
    Path(name): Path<String>,
    Query(q): Query<FeedQuery>,
) -> AppResult<Response> {
    let filter = Filter {
        sql: "EXISTS (SELECT 1 FROM book_author ba JOIN author a ON a.id = ba.author_id \
              WHERE ba.book_id = b.id AND a.name = ?)",
        bind: name.clone(),
    };
    page_feed(
        &state,
        &user,
        &headers,
        &q,
        &format!("Books by {name}"),
        &format!("/opds/authors/{}", urlencode(&name)),
        "b.title, b.id",
        Some(filter),
    )
    .await
}

pub async fn by_genre(
    State(state): State<AppState>,
    user: AuthUser,
    headers: HeaderMap,
    Path(name): Path<String>,
    Query(q): Query<FeedQuery>,
) -> AppResult<Response> {
    let filter = Filter {
        sql: "EXISTS (SELECT 1 FROM book_genre bg JOIN genre g ON g.id = bg.genre_id \
              WHERE bg.book_id = b.id AND g.name = ?)",
        bind: name.clone(),
    };
    page_feed(
        &state,
        &user,
        &headers,
        &q,
        &name,
        &format!("/opds/genres/{}", urlencode(&name)),
        "b.title, b.id",
        Some(filter),
    )
    .await
}

pub async fn by_group(
    State(state): State<AppState>,
    user: AuthUser,
    headers: HeaderMap,
    Path(id): Path<String>,
    Query(q): Query<FeedQuery>,
) -> AppResult<Response> {
    let name: Option<String> = sqlx::query_scalar("SELECT name FROM book_group WHERE id = ?")
        .bind(&id)
        .fetch_optional(&state.db)
        .await?;
    let filter = Filter {
        sql: "EXISTS (SELECT 1 FROM book_group_item gi WHERE gi.book_id = b.id \
              AND gi.group_id = ?)",
        bind: id.clone(),
    };
    page_feed(
        &state,
        &user,
        &headers,
        &q,
        &name.unwrap_or_else(|| "Tag".into()),
        &format!("/opds/groups/{}", urlencode(&id)),
        "b.title, b.id",
        Some(filter),
    )
    .await
}

/// `GET /opds/search?q=…`
///
/// Matches titles, subtitles, ISBNs and author names — and, when the server has
/// a content index (#32), any book whose *text* matches too. The union is
/// deliberate: an e-reader has one search box, and a reader who remembers a
/// phrase from inside a book shouldn't have to know which index answers.
pub async fn search(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<FeedQuery>,
) -> AppResult<Response> {
    let trimmed = q.q.clone().unwrap_or_default().trim().to_string();
    let now = now_rfc3339(&state).await;
    if trimmed.is_empty() {
        // Not an error: a client probing the descriptor gets an empty,
        // well-formed feed rather than a 400 it can't render.
        return Ok(feed_response(
            &state,
            "Search",
            "/opds/search?q=",
            String::new(),
            1,
            0,
            &now,
            None,
        ));
    }

    let like = format!("%{trimmed}%");
    let mut sql = "(b.title LIKE ? OR b.subtitle LIKE ? OR b.isbn LIKE ? \
         OR EXISTS (SELECT 1 FROM book_author ba JOIN author a ON a.id = ba.author_id \
                    WHERE ba.book_id = b.id AND a.name LIKE ?)"
        .to_string();
    let mut binds = vec![like.clone(), like.clone(), like.clone(), like];
    if state.index_text
        && let Some(expression) = crate::text_index::to_match_expression(&trimmed)
    {
        sql.push_str(
            " OR EXISTS (SELECT 1 FROM book_text_fts f \
             WHERE f.book_id = b.id AND book_text_fts MATCH ?)",
        );
        binds.push(expression);
    }
    sql.push(')');

    let (books, total) = query_page(
        &state,
        &user,
        &sql,
        &binds,
        "b.title, b.id",
        PAGE_SIZE,
        q.offset(),
    )
    .await?;
    let entries = entries_for(&state, &books).await?;
    Ok(feed_response(
        &state,
        &format!("Search: {trimmed}"),
        &format!("/opds/search?q={}", urlencode(&trimmed)),
        entries,
        q.page(),
        total,
        &now,
        None,
    ))
}

/// The OpenSearch descriptor every OPDS client fetches to learn the query URL.
pub async fn search_description(State(state): State<AppState>) -> Response {
    let base = base_of(&state);
    let xml = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<OpenSearchDescription xmlns="http://a9.com/-/spec/opensearch/1.1/">
  <ShortName>Vellum</ShortName>
  <Description>Search this Vellum library</Description>
  <InputEncoding>UTF-8</InputEncoding>
  <Url type="{ACQUISITION}" template="{base}/opds/search?q={{searchTerms}}"/>
</OpenSearchDescription>
"#
    );
    ([(header::CONTENT_TYPE, OPENSEARCH)], xml).into_response()
}

// ---- browse-by navigation feeds -------------------------------------------

pub async fn authors(State(state): State<AppState>, user: AuthUser) -> AppResult<Response> {
    let names: Vec<String> = sqlx::query_scalar(&format!(
        "SELECT DISTINCT a.name FROM author a \
         JOIN book_author ba ON ba.author_id = a.id \
         JOIN book b ON b.id = ba.book_id \
         WHERE {} ORDER BY a.name",
        access_predicate()
    ))
    .bind(&user.id)
    .bind(user.is_master)
    .bind(&user.id)
    .fetch_all(&state.db)
    .await?;
    Ok(name_list(&state, "By author", "/opds/authors", &names).await)
}

pub async fn genres(State(state): State<AppState>, user: AuthUser) -> AppResult<Response> {
    let names: Vec<String> = sqlx::query_scalar(&format!(
        "SELECT DISTINCT g.name FROM genre g \
         JOIN book_genre bg ON bg.genre_id = g.id \
         JOIN book b ON b.id = bg.book_id \
         WHERE {} ORDER BY g.name",
        access_predicate()
    ))
    .bind(&user.id)
    .bind(user.is_master)
    .bind(&user.id)
    .fetch_all(&state.db)
    .await?;
    Ok(name_list(&state, "By genre", "/opds/genres", &names).await)
}

/// Tags (groups) the caller can actually see books in — an empty tag would be a
/// dead end on a device where going back is expensive.
pub async fn groups(State(state): State<AppState>, user: AuthUser) -> AppResult<Response> {
    let rows: Vec<(String, String)> = sqlx::query_as(&format!(
        "SELECT DISTINCT gr.id, gr.name FROM book_group gr \
         JOIN book_group_item gi ON gi.group_id = gr.id \
         JOIN book b ON b.id = gi.book_id \
         WHERE {} ORDER BY gr.name",
        access_predicate()
    ))
    .bind(&user.id)
    .bind(user.is_master)
    .bind(&user.id)
    .fetch_all(&state.db)
    .await?;

    let base = base_of(&state);
    let now = now_rfc3339(&state).await;
    let mut entries = String::new();
    for (id, name) in rows {
        entries.push_str(&format!(
            "  <entry>\n\
             \x20   <id>{base}/opds/groups/{id}</id>\n\
             \x20   <title>{title}</title>\n\
             \x20   <updated>{now}</updated>\n\
             \x20   <link rel=\"subsection\" href=\"{base}/opds/groups/{id}\" type=\"{ACQUISITION}\"/>\n\
             \x20 </entry>\n",
            id = urlencode(&id),
            title = escape(&name),
        ));
    }
    Ok(nav_response(&base, "By tag", "/opds/groups", entries, &now))
}

async fn name_list(state: &AppState, title: &str, path: &str, names: &[String]) -> Response {
    let base = base_of(state);
    let now = now_rfc3339(state).await;
    let mut entries = String::new();
    for name in names {
        entries.push_str(&format!(
            "  <entry>\n\
             \x20   <id>{base}{path}/{slug}</id>\n\
             \x20   <title>{label}</title>\n\
             \x20   <updated>{now}</updated>\n\
             \x20   <link rel=\"subsection\" href=\"{base}{path}/{slug}\" type=\"{ACQUISITION}\"/>\n\
             \x20 </entry>\n",
            slug = urlencode(name),
            label = escape(name),
        ));
    }
    nav_response(&base, title, path, entries, &now)
}

fn nav_response(base: &str, title: &str, path: &str, entries: String, now: &str) -> Response {
    let xml = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog">
  <id>{base}{path}</id>
  <title>{title}</title>
  <updated>{now}</updated>
  <link rel="self" href="{base}{path}" type="{NAVIGATION}"/>
  <link rel="start" href="{base}/opds" type="{NAVIGATION}"/>
  <link rel="up" href="{base}/opds" type="{NAVIGATION}"/>
  <link rel="search" href="{base}/opds/search.xml" type="{OPENSEARCH}"/>
{entries}</feed>
"#,
        title = escape(title),
    );
    ([(header::CONTENT_TYPE, NAVIGATION)], xml).into_response()
}

// ---- OPDS 2.0 -------------------------------------------------------------

/// The same navigation root as JSON. Cheap — one more serialisation of an
/// aggregation that already exists — and it is what newer clients ask for.
pub async fn v2_root(State(state): State<AppState>, user: AuthUser) -> AppResult<Response> {
    let base = base_of(&state);
    let _ = user;
    let navigation: Vec<serde_json::Value> = nav_sections(&state)
        .into_iter()
        .map(|(path, title, _)| {
            serde_json::json!({
                "href": format!("{base}{path}"),
                "title": title,
                "type": ACQUISITION,
            })
        })
        .collect();
    let body = serde_json::json!({
        "metadata": { "title": "Vellum Library" },
        "links": [
            { "rel": "self", "href": format!("{base}/opds/v2"), "type": OPDS2 },
            {
                "rel": "search",
                "href": format!("{base}/opds/search?q={{searchTerms}}"),
                "type": ACQUISITION,
                "templated": true,
            },
        ],
        "navigation": navigation,
    });
    Ok(([(header::CONTENT_TYPE, OPDS2)], body.to_string()).into_response())
}

// ---- shared plumbing ------------------------------------------------------

struct Filter {
    sql: &'static str,
    bind: String,
}

#[allow(clippy::too_many_arguments)]
async fn page_feed(
    state: &AppState,
    user: &AuthUser,
    headers: &HeaderMap,
    q: &FeedQuery,
    title: &str,
    path: &str,
    order: &str,
    filter: Option<Filter>,
) -> AppResult<Response> {
    let (sql, binds) = match &filter {
        Some(f) => (f.sql.to_string(), vec![f.bind.clone()]),
        None => ("1 = 1".to_string(), Vec::new()),
    };

    // The catalogue changes only when a book does, so an e-reader that polls
    // hourly can be told "nothing new" for the price of one aggregate query.
    let tag = etag(state, user).await?;
    if headers
        .get(header::IF_NONE_MATCH)
        .and_then(|v| v.to_str().ok())
        == Some(tag.as_str())
    {
        return Ok(StatusCode::NOT_MODIFIED.into_response());
    }

    let (books, total) =
        query_page(state, user, &sql, &binds, order, PAGE_SIZE, q.offset()).await?;
    let now = now_rfc3339(state).await;
    let entries = entries_for(state, &books).await?;
    Ok(feed_response(
        state,
        title,
        path,
        entries,
        q.page(),
        total,
        &now,
        Some(tag),
    ))
}

/// One page of visible books matching `extra`, plus how many match in total.
async fn query_page(
    state: &AppState,
    user: &AuthUser,
    extra: &str,
    extra_binds: &[String],
    order: &str,
    limit: i64,
    offset: i64,
) -> AppResult<(Vec<BookDto>, i64)> {
    let where_sql = format!("{} AND {extra}", access_predicate());
    let sql = format!(
        "SELECT {} FROM book b WHERE {where_sql} ORDER BY {order} LIMIT ? OFFSET ?",
        crate::books::BOOK_COLUMNS
    );
    let mut query = sqlx::query_as::<_, BookDto>(&sql)
        .bind(&user.id)
        .bind(user.is_master)
        .bind(&user.id);
    for bind in extra_binds {
        query = query.bind(bind.clone());
    }
    let items = query.bind(limit).bind(offset).fetch_all(&state.db).await?;

    let count_sql = format!("SELECT COUNT(*) FROM book b WHERE {where_sql}");
    let mut count = sqlx::query_scalar::<_, i64>(&count_sql)
        .bind(&user.id)
        .bind(user.is_master)
        .bind(&user.id);
    for bind in extra_binds {
        count = count.bind(bind.clone());
    }
    let total = count.fetch_one(&state.db).await?;
    Ok((items, total))
}

/// The XML for a page of books.
///
/// The author and file maps are two library-wide scans rather than two queries
/// per book — the OPDS N+1 the flat feed already avoided, kept here.
async fn entries_for(state: &AppState, books: &[BookDto]) -> AppResult<String> {
    if books.is_empty() {
        return Ok(String::new());
    }
    let base = base_of(state);
    let authors_by_book = author_map(state).await?;
    let files_by_book = files_map(state).await?;
    let mut entries = String::new();
    for book in books {
        let authors = authors_by_book
            .get(&book.id)
            .map(Vec::as_slice)
            .unwrap_or(&[]);
        let files = files_by_book
            .get(&book.id)
            .map(Vec::as_slice)
            .unwrap_or(&[]);
        entries.push_str(&entry_xml(&base, book, authors, files));
    }
    Ok(entries)
}

#[allow(clippy::too_many_arguments)]
fn feed_response(
    state: &AppState,
    title: &str,
    path: &str,
    entries: String,
    page: i64,
    total: i64,
    now: &str,
    tag: Option<String>,
) -> Response {
    let base = base_of(state);
    let joiner = if path.contains('?') { "&" } else { "?" };
    let last_page = ((total + PAGE_SIZE - 1) / PAGE_SIZE).max(1);

    let mut paging = format!(
        "  <link rel=\"first\" href=\"{base}{path}{joiner}page=1\" type=\"{ACQUISITION}\"/>\n"
    );
    if page > 1 {
        paging.push_str(&format!(
            "  <link rel=\"previous\" href=\"{base}{path}{joiner}page={}\" type=\"{ACQUISITION}\"/>\n",
            page - 1
        ));
    }
    if page < last_page {
        paging.push_str(&format!(
            "  <link rel=\"next\" href=\"{base}{path}{joiner}page={}\" type=\"{ACQUISITION}\"/>\n",
            page + 1
        ));
    }
    paging.push_str(&format!(
        "  <link rel=\"last\" href=\"{base}{path}{joiner}page={last_page}\" type=\"{ACQUISITION}\"/>\n"
    ));

    let xml = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog"
      xmlns:opensearch="http://a9.com/-/spec/opensearch/1.1/">
  <id>{base}{path}</id>
  <title>{title}</title>
  <updated>{now}</updated>
  <author><name>Vellum</name></author>
  <opensearch:totalResults>{total}</opensearch:totalResults>
  <opensearch:itemsPerPage>{PAGE_SIZE}</opensearch:itemsPerPage>
  <opensearch:startIndex>{start}</opensearch:startIndex>
  <link rel="self" href="{base}{path}{joiner}page={page}" type="{ACQUISITION}"/>
  <link rel="start" href="{base}/opds" type="{NAVIGATION}"/>
  <link rel="up" href="{base}/opds" type="{NAVIGATION}"/>
  <link rel="search" href="{base}/opds/search.xml" type="{OPENSEARCH}"/>
{paging}{entries}</feed>
"#,
        title = escape(title),
        start = (page - 1) * PAGE_SIZE + 1,
    );

    let mut map = HeaderMap::new();
    map.insert(header::CONTENT_TYPE, HeaderValue::from_static(ACQUISITION));
    if let Some(tag) = tag
        && let Ok(value) = HeaderValue::from_str(&tag)
    {
        map.insert(header::ETAG, value);
    }
    (map, xml).into_response()
}

/// A cache validator over what this caller can see: how many books, and the
/// newest change among them. Per-user on purpose — a share granted to one
/// account must not be served from another's cached feed.
async fn etag(state: &AppState, user: &AuthUser) -> AppResult<String> {
    let row: (i64, Option<String>) = sqlx::query_as(&format!(
        "SELECT COUNT(*), MAX(b.updated_at) FROM book b WHERE {}",
        access_predicate()
    ))
    .bind(&user.id)
    .bind(user.is_master)
    .bind(&user.id)
    .fetch_one(&state.db)
    .await?;
    Ok(format!(
        "\"{}-{}\"",
        row.0,
        row.1.unwrap_or_default().replace([' ', ':', '-'], "")
    ))
}

fn base_of(state: &AppState) -> String {
    state.public_base_url.trim_end_matches('/').to_string()
}

fn entry_xml(base: &str, book: &BookDto, authors: &[String], files: &[(String, String)]) -> String {
    let mut authors_xml = String::new();
    for name in authors {
        authors_xml.push_str(&format!(
            "    <author><name>{}</name></author>\n",
            escape(name)
        ));
    }

    let mut links = String::new();
    if book.cover_path.is_some() {
        links.push_str(&format!(
            "    <link rel=\"http://opds-spec.org/image\" href=\"{base}/api/books/{id}/cover\"/>\n\
             \x20   <link rel=\"http://opds-spec.org/image/thumbnail\" href=\"{base}/api/books/{id}/cover?w=160\"/>\n",
            id = escape(&book.id)
        ));
    }
    for (file_id, format) in files {
        links.push_str(&format!(
            "    <link rel=\"http://opds-spec.org/acquisition\" type=\"{mime}\" href=\"{base}/api/files/{fid}\"/>\n",
            mime = mime_for(format),
            fid = escape(file_id),
        ));
    }

    let summary = book
        .description
        .as_deref()
        .map(|d| format!("    <summary>{}</summary>\n", escape(d)))
        .unwrap_or_default();
    let updated = rfc3339(&book.updated_at);

    format!(
        "  <entry>\n\
         \x20   <id>urn:uuid:{id}</id>\n\
         \x20   <title>{title}</title>\n\
         {authors_xml}\
         \x20   <updated>{updated}</updated>\n\
         {summary}{links}  </entry>\n",
        id = escape(&book.id),
        title = escape(&book.title),
    )
}

fn mime_for(format: &str) -> &'static str {
    match format {
        "epub" => "application/epub+zip",
        "pdf" => "application/pdf",
        _ => "application/octet-stream",
    }
}

/// The stored `YYYY-MM-DD HH:MM:SS` timestamp as RFC 3339 (Atom requires it).
fn rfc3339(stored: &str) -> String {
    if stored.len() == 19 {
        format!("{}T{}Z", &stored[..10], &stored[11..])
    } else {
        stored.to_string()
    }
}

async fn now_rfc3339(state: &AppState) -> String {
    let now: String = sqlx::query_scalar("SELECT datetime('now')")
        .fetch_one(&state.db)
        .await
        .unwrap_or_default();
    rfc3339(&now)
}

/// Percent-encodes a path/query segment.
///
/// Author and genre names go into feed URLs, and they contain spaces,
/// ampersands and slashes — an unencoded "Le Guin, Ursula K." would produce a
/// link no client can follow back.
fn urlencode(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    for byte in raw.as_bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' => {
                out.push(*byte as char)
            }
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

fn escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn names_with_punctuation_survive_a_feed_url() {
        assert_eq!(
            urlencode("Le Guin, Ursula K."),
            "Le%20Guin%2C%20Ursula%20K."
        );
        assert_eq!(urlencode("Rock & Roll"), "Rock%20%26%20Roll");
        assert_eq!(urlencode("sci-fi/fantasy"), "sci-fi%2Ffantasy");
    }

    #[test]
    fn xml_special_characters_are_escaped() {
        assert_eq!(escape("Ana & <Bob>"), "Ana &amp; &lt;Bob&gt;");
    }

    #[test]
    fn paging_offsets_start_at_zero_and_never_go_negative() {
        let q = |page: i64| FeedQuery {
            page: Some(page),
            q: None,
        };
        assert_eq!(q(1).offset(), 0);
        assert_eq!(q(3).offset(), PAGE_SIZE * 2);
        // A client that asks for page 0 or -5 gets the first page rather than a
        // SQL error from a negative OFFSET.
        assert_eq!(q(0).offset(), 0);
        assert_eq!(q(-5).offset(), 0);
        assert_eq!(q(-5).page(), 1);
    }
}
