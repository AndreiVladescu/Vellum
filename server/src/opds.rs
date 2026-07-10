//! OPDS 1.2 acquisition feed, so third-party e-reader apps can browse and
//! download the library. Entries link to each book's cover and file(s); auth is
//! HTTP Basic (see the `AuthUser` extractor), which is what e-readers speak.

use axum::extract::State;
use axum::http::header;
use axum::response::{IntoResponse, Response};

use crate::AppState;
use crate::auth::AuthUser;
use crate::books::{author_map, files_map, visible_books};
use crate::error::AppResult;

const OPDS_CONTENT_TYPE: &str = "application/atom+xml;profile=opds-catalog;kind=acquisition";

pub async fn feed(State(state): State<AppState>, user: AuthUser) -> AppResult<Response> {
    let base = state.public_base_url.trim_end_matches('/');
    let books = visible_books(&state, &user, None).await?;
    let now = now_rfc3339(&state).await;

    // Two library-wide scans instead of two queries per book (the OPDS N+1):
    // a 1,000-book feed was 2,001 queries, now 3.
    let authors_by_book = author_map(&state).await?;
    let files_by_book = files_map(&state).await?;

    let mut entries = String::new();
    for book in &books {
        let authors = authors_by_book
            .get(&book.id)
            .map(Vec::as_slice)
            .unwrap_or(&[]);
        let files = files_by_book
            .get(&book.id)
            .map(Vec::as_slice)
            .unwrap_or(&[]);
        entries.push_str(&entry_xml(base, book, authors, files));
    }

    let xml = format!(
        r#"<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom" xmlns:opds="http://opds-spec.org/2010/catalog">
  <id>{base}/opds</id>
  <title>Vellum Library</title>
  <updated>{now}</updated>
  <author><name>Vellum</name></author>
  <link rel="self" href="{base}/opds" type="{OPDS_CONTENT_TYPE}"/>
  <link rel="start" href="{base}/opds" type="{OPDS_CONTENT_TYPE}"/>
{entries}</feed>
"#
    );

    Ok(([(header::CONTENT_TYPE, OPDS_CONTENT_TYPE)], xml).into_response())
}

fn entry_xml(
    base: &str,
    book: &crate::books::BookDto,
    authors: &[String],
    files: &[(String, String)],
) -> String {
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

fn escape(s: &str) -> String {
    s.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
        .replace('\'', "&apos;")
}
