//! Reading a book in the browser (plan 5 #33).
//!
//! **Why it exists.** The console could manage and download but not read, so a
//! machine without Vellum installed couldn't use the library — and a share link
//! meant "here's a 40 MB download" rather than "here's the chapter".
//!
//! **EPUB is rendered server-side into sanitised HTML** and styled by the
//! console's own CSS: no new JavaScript dependency, and nothing from the book
//! can execute (see `blobs::sanitize_html` — an allowlist, not a blocklist,
//! because in the share-link case the markup is attacker-supplied).
//!
//! **PDF is served as page images**, rendered through the *existing* sandboxed
//! shell-out and cached on disk. The alternative was vendoring ~1 MB of pdf.js
//! into the binary; the plan recommends starting here, and this way the reader
//! works in any browser with no script at all. Rendered pages are cached under
//! `pages/<file id>/<n>.jpg`, so the second reader of a chapter pays nothing.
//!
//! **A share link is not consumed by reading.** `max_uses` counts *downloads* —
//! the one-time link exists so a file can be handed over once. Burning it on a
//! page turn would make "read in the browser" the thing that destroys the link
//! the moment it is used, which is precisely backwards.

use axum::Json;
use axum::extract::{Path as AxPath, State};
use axum::http::header;
use axum::response::{IntoResponse, Response};
use serde::Serialize;
use std::path::PathBuf;

use crate::AppState;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};

/// What the reader needs to lay out a book before fetching anything.
#[derive(Serialize)]
pub struct ReadManifest {
    pub book_id: String,
    pub title: String,
    /// "epub" | "pdf" | "none"
    pub kind: &'static str,
    /// Spine sections (EPUB) or page count (PDF).
    pub units: usize,
    /// Whether this reader may also download the file. False for a share link,
    /// which is the whole point of the distinction: a read-only link lets
    /// someone read a book without handing them the file.
    pub downloadable: bool,
}

/// The newest readable file of a book: its id, path on disk, and format.
async fn readable_file(state: &AppState, book_id: &str) -> Option<(String, PathBuf, String)> {
    // EPUB first: it reads far better in a browser than a wall of page images,
    // so a book with both is offered as an EPUB.
    for format in ["epub", "pdf"] {
        let row: Option<(String, String)> = sqlx::query_as(
            "SELECT id, path FROM book_file WHERE book_id = ? AND format = ? \
             ORDER BY added_at DESC LIMIT 1",
        )
        .bind(book_id)
        .bind(format)
        .fetch_optional(&state.db)
        .await
        .ok()
        .flatten();
        if let Some((id, rel)) = row
            && crate::blobs::is_safe_rel(&rel)
        {
            return Some((id, state.data_dir.join(&rel), format.to_string()));
        }
    }
    None
}

async fn manifest_for(
    state: &AppState,
    book_id: &str,
    downloadable: bool,
) -> AppResult<Json<ReadManifest>> {
    let title: String = sqlx::query_scalar("SELECT title FROM book WHERE id = ?")
        .bind(book_id)
        .fetch_optional(&state.db)
        .await?
        .ok_or_else(|| AppError::NotFound("book not found".into()))?;

    let Some((_, path, format)) = readable_file(state, book_id).await else {
        return Ok(Json(ReadManifest {
            book_id: book_id.to_string(),
            title,
            kind: "none",
            units: 0,
            downloadable,
        }));
    };

    let (kind, units) = if format == "epub" {
        let owned = path.clone();
        let count = tokio::task::spawn_blocking(move || crate::blobs::epub_spine_len(&owned))
            .await
            .unwrap_or(0);
        ("epub", count)
    } else {
        let pages: Option<i64> = sqlx::query_scalar("SELECT page_count FROM book WHERE id = ?")
            .bind(book_id)
            .fetch_optional(&state.db)
            .await?
            .flatten();
        ("pdf", pages.unwrap_or(0).max(0) as usize)
    };

    Ok(Json(ReadManifest {
        book_id: book_id.to_string(),
        title,
        kind,
        units,
        downloadable,
    }))
}

/// One readable unit: an EPUB section as HTML, or a PDF page as a JPEG.
async fn unit_for(state: &AppState, book_id: &str, index: usize) -> AppResult<Response> {
    let Some((file_id, path, format)) = readable_file(state, book_id).await else {
        return Err(AppError::NotFound("this book has no readable file".into()));
    };

    if format == "epub" {
        let owned = path.clone();
        let section =
            tokio::task::spawn_blocking(move || crate::blobs::epub_section_html(&owned, index))
                .await
                .ok()
                .flatten()
                .ok_or_else(|| AppError::NotFound("no such section".into()))?;
        return Ok(Json(serde_json::json!({
            "index": index,
            "title": section.0,
            "html": section.1,
        }))
        .into_response());
    }

    // PDF: a rendered page, cached. The cache key is the file id, so replacing
    // a book's PDF cannot serve the old book's pages.
    let page = (index + 1) as u32;
    let rel = format!("pages/{file_id}/{page}.jpg");
    let out = state.data_dir.join(&rel);
    if !crate::blobs::nonempty_file(&out).await {
        if let Some(parent) = out.parent() {
            let _ = tokio::fs::create_dir_all(parent).await;
        }
        // Bounded by the same semaphore as cover rendering: a reader flipping
        // pages must not be able to fork a process per keystroke.
        let permit = state.render_semaphore.acquire().await;
        let ok = crate::blobs::render_page(&path, &out, page).await;
        drop(permit);
        if !ok {
            return Err(AppError::NotFound("could not render that page".into()));
        }
    }
    let bytes = tokio::fs::read(&out)
        .await
        .map_err(|_| AppError::NotFound("could not render that page".into()))?;
    Ok((
        [
            (header::CONTENT_TYPE, "image/jpeg"),
            // Immutable: the key includes the file id, so a cached page can
            // never be the wrong one.
            (header::CACHE_CONTROL, "private, max-age=86400"),
        ],
        bytes,
    )
        .into_response())
}

/// An image out of the EPUB's own archive, referenced by the sanitised HTML.
async fn asset_for(state: &AppState, book_id: &str, name: &str) -> AppResult<Response> {
    let Some((_, path, format)) = readable_file(state, book_id).await else {
        return Err(AppError::NotFound("not found".into()));
    };
    if format != "epub" {
        return Err(AppError::NotFound("not found".into()));
    }
    let owned = path.clone();
    let wanted = name.to_string();
    let bytes =
        tokio::task::spawn_blocking(move || crate::blobs::epub_entry_bytes(&owned, &wanted))
            .await
            .ok()
            .flatten()
            .ok_or_else(|| AppError::NotFound("not found".into()))?;

    // Served as whatever image it sniffs as, and *only* if it sniffs as one:
    // the reader must never be able to serve arbitrary bytes from inside a book
    // under a content type a browser will execute.
    let mime = crate::blobs::image_mime(&bytes)
        .ok_or_else(|| AppError::NotFound("not an image".into()))?;
    Ok((
        [
            (header::CONTENT_TYPE, mime),
            (header::CACHE_CONTROL, "private, max-age=86400"),
        ],
        bytes,
    )
        .into_response())
}

// ---- authenticated (console) ---------------------------------------------

pub async fn manifest(
    State(state): State<AppState>,
    user: AuthUser,
    AxPath(id): AxPath<String>,
) -> AppResult<Json<ReadManifest>> {
    require_view(&state, &user, &id).await?;
    manifest_for(&state, &id, true).await
}

pub async fn unit(
    State(state): State<AppState>,
    user: AuthUser,
    AxPath((id, index)): AxPath<(String, usize)>,
) -> AppResult<Response> {
    require_view(&state, &user, &id).await?;
    unit_for(&state, &id, index).await
}

pub async fn asset(
    State(state): State<AppState>,
    user: AuthUser,
    AxPath((id, name)): AxPath<(String, String)>,
) -> AppResult<Response> {
    require_view(&state, &user, &id).await?;
    asset_for(&state, &id, &name).await
}

/// 404 rather than 403 for a book the caller can't see — the same rule the rest
/// of the API follows, so the reader can't be used as an existence oracle.
async fn require_view(state: &AppState, user: &AuthUser, book_id: &str) -> AppResult<()> {
    if crate::access::book_access(state, user, book_id)
        .await?
        .can_view()
    {
        Ok(())
    } else {
        Err(AppError::NotFound("book not found".into()))
    }
}

// ---- public (share link) --------------------------------------------------

/// Resolves a share-link token to its book **without consuming a use**.
async fn book_of_link(state: &AppState, token: &str) -> AppResult<String> {
    crate::shares::book_id_for_link(state, token)
        .await?
        .ok_or_else(|| AppError::NotFound("link is invalid or expired".into()))
}

pub async fn public_manifest(
    State(state): State<AppState>,
    client: crate::auth::ClientKey,
    AxPath(token): AxPath<String>,
) -> AppResult<Json<ReadManifest>> {
    if !state.public_limiter.check(&client.0) {
        return Err(AppError::TooManyRequests("too many requests".into()));
    }
    let book_id = book_of_link(&state, &token).await?;
    // Not downloadable: a public reader may read the book, not take the file.
    // That distinction is the reason this endpoint exists.
    manifest_for(&state, &book_id, false).await
}

pub async fn public_unit(
    State(state): State<AppState>,
    client: crate::auth::ClientKey,
    AxPath((token, index)): AxPath<(String, usize)>,
) -> AppResult<Response> {
    if !state.public_limiter.check(&client.0) {
        return Err(AppError::TooManyRequests("too many requests".into()));
    }
    let book_id = book_of_link(&state, &token).await?;
    unit_for(&state, &book_id, index).await
}

pub async fn public_asset(
    State(state): State<AppState>,
    client: crate::auth::ClientKey,
    AxPath((token, name)): AxPath<(String, String)>,
) -> AppResult<Response> {
    if !state.public_limiter.check(&client.0) {
        return Err(AppError::TooManyRequests("too many requests".into()));
    }
    let book_id = book_of_link(&state, &token).await?;
    asset_for(&state, &book_id, &name).await
}
