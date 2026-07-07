//! Cover-image and book-file storage. Blobs live on the filesystem under the
//! data dir (`VELLUM_DATA_DIR`); the database keeps only paths, sizes, and
//! hashes. Every endpoint is access-checked against the book the blob belongs
//! to, exactly like the book metadata.

use std::path::Path;

use axum::body::Bytes;
use axum::extract::{Path as AxPath, Query, State};
use axum::http::{header, HeaderMap};
use axum::response::{IntoResponse, Response};
use axum::Json;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::access::book_access;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};
use crate::AppState;

#[derive(Serialize, sqlx::FromRow)]
pub struct FileDto {
    pub id: String,
    pub book_id: String,
    pub format: String,
    pub path: String,
    pub size_bytes: i64,
    pub sha256: String,
    pub added_at: String,
}

#[derive(Deserialize)]
pub struct UploadQuery {
    /// Original file name, used to derive the format/extension.
    pub filename: String,
}

// ---- covers ---------------------------------------------------------------

/// Upload (or replace) a book's cover. Raw image bytes in the body; the
/// `Content-Type` header picks the stored extension. Requires editor access.
pub async fn put_cover(
    State(state): State<AppState>,
    user: AuthUser,
    AxPath(id): AxPath<String>,
    headers: HeaderMap,
    body: Bytes,
) -> AppResult<Json<serde_json::Value>> {
    require_edit(&state, &user, &id).await?;
    if body.is_empty() {
        return Err(AppError::BadRequest("empty upload".into()));
    }
    let ext = ext_for_content_type(
        headers.get(header::CONTENT_TYPE).and_then(|v| v.to_str().ok()),
    );

    let previous: Option<Option<String>> =
        sqlx::query_scalar("SELECT cover_path FROM book WHERE id = ?")
            .bind(&id)
            .fetch_optional(&state.db)
            .await?;
    let previous = previous.flatten();

    let rel = format!("covers/{id}.{ext}");
    write_blob(&state, &rel, &body).await?;

    sqlx::query("UPDATE book SET cover_path = ?, updated_at = datetime('now') WHERE id = ?")
        .bind(&rel)
        .bind(&id)
        .execute(&state.db)
        .await?;

    // Clean up an old cover with a different extension.
    if let Some(old) = previous
        && old != rel
    {
        let _ = tokio::fs::remove_file(state.data_dir.join(&old)).await;
    }
    Ok(Json(serde_json::json!({ "cover_path": rel })))
}

pub async fn get_cover(
    State(state): State<AppState>,
    user: AuthUser,
    AxPath(id): AxPath<String>,
) -> AppResult<Response> {
    require_view(&state, &user, &id).await?;
    let rel: Option<Option<String>> =
        sqlx::query_scalar("SELECT cover_path FROM book WHERE id = ?")
            .bind(&id)
            .fetch_optional(&state.db)
            .await?;
    let rel = rel
        .flatten()
        .ok_or_else(|| AppError::NotFound("no cover".into()))?;
    serve_blob(&state, &rel).await
}

// ---- book files -----------------------------------------------------------

/// Attach a digital file to a book (PDF/EPUB/...). Raw bytes in the body;
/// `?filename=` supplies the name we derive the format from. Requires editor.
pub async fn upload_file(
    State(state): State<AppState>,
    user: AuthUser,
    AxPath(id): AxPath<String>,
    Query(q): Query<UploadQuery>,
    body: Bytes,
) -> AppResult<Json<FileDto>> {
    require_edit(&state, &user, &id).await?;
    if body.is_empty() {
        return Err(AppError::BadRequest("empty upload".into()));
    }
    let ext = Path::new(&q.filename)
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase())
        .filter(|e| !e.is_empty())
        .unwrap_or_else(|| "bin".to_string());

    let file_id = uuid::Uuid::new_v4().to_string();
    let rel = format!("files/{file_id}.{ext}");
    write_blob(&state, &rel, &body).await?;

    let sha = {
        let mut hasher = Sha256::new();
        hasher.update(&body);
        hex::encode(hasher.finalize())
    };
    let size = body.len() as i64;
    sqlx::query(
        "INSERT INTO book_file (id, book_id, format, path, size_bytes, sha256) \
         VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(&file_id)
    .bind(&id)
    .bind(&ext)
    .bind(&rel)
    .bind(size)
    .bind(&sha)
    .execute(&state.db)
    .await?;

    let file = sqlx::query_as::<_, FileDto>(
        "SELECT id, book_id, format, path, size_bytes, sha256, added_at \
         FROM book_file WHERE id = ?",
    )
    .bind(&file_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(file))
}

pub async fn list_files(
    State(state): State<AppState>,
    user: AuthUser,
    AxPath(id): AxPath<String>,
) -> AppResult<Json<Vec<FileDto>>> {
    require_view(&state, &user, &id).await?;
    let files = sqlx::query_as::<_, FileDto>(
        "SELECT id, book_id, format, path, size_bytes, sha256, added_at \
         FROM book_file WHERE book_id = ? ORDER BY added_at",
    )
    .bind(&id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(files))
}

pub async fn download_file(
    State(state): State<AppState>,
    user: AuthUser,
    AxPath(file_id): AxPath<String>,
) -> AppResult<Response> {
    let row: Option<(String, String)> =
        sqlx::query_as("SELECT book_id, path FROM book_file WHERE id = ?")
            .bind(&file_id)
            .fetch_optional(&state.db)
            .await?;
    let (book_id, rel) = row.ok_or_else(|| AppError::NotFound("file not found".into()))?;
    require_view(&state, &user, &book_id).await?;
    serve_blob(&state, &rel).await
}

// ---- helpers --------------------------------------------------------------

async fn require_view(state: &AppState, user: &AuthUser, book_id: &str) -> AppResult<()> {
    if book_access(state, user, book_id).await?.can_view() {
        Ok(())
    } else {
        Err(AppError::NotFound("book not found".into()))
    }
}

async fn require_edit(state: &AppState, user: &AuthUser, book_id: &str) -> AppResult<()> {
    let access = book_access(state, user, book_id).await?;
    if !access.can_view() {
        return Err(AppError::NotFound("book not found".into()));
    }
    if !access.can_edit() {
        return Err(AppError::Forbidden("you have read-only access to this book".into()));
    }
    Ok(())
}

async fn write_blob(state: &AppState, rel: &str, body: &[u8]) -> AppResult<()> {
    let full = state.data_dir.join(rel);
    if let Some(parent) = full.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|e| AppError::Internal(e.to_string()))?;
    }
    tokio::fs::write(&full, body)
        .await
        .map_err(|e| AppError::Internal(e.to_string()))
}

async fn serve_blob(state: &AppState, rel: &str) -> AppResult<Response> {
    let full = state.data_dir.join(rel);
    let bytes = tokio::fs::read(&full)
        .await
        .map_err(|_| AppError::NotFound("blob missing on disk".into()))?;
    let ext = Path::new(rel)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("");
    Ok(([(header::CONTENT_TYPE, content_type_for_ext(ext))], bytes).into_response())
}

fn ext_for_content_type(content_type: Option<&str>) -> &'static str {
    match content_type.unwrap_or("") {
        c if c.starts_with("image/png") => "png",
        c if c.starts_with("image/webp") => "webp",
        c if c.starts_with("image/gif") => "gif",
        _ => "jpg",
    }
}

fn content_type_for_ext(ext: &str) -> &'static str {
    match ext {
        "png" => "image/png",
        "webp" => "image/webp",
        "gif" => "image/gif",
        "jpg" | "jpeg" => "image/jpeg",
        "pdf" => "application/pdf",
        "epub" => "application/epub+zip",
        _ => "application/octet-stream",
    }
}
