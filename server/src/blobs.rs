//! Cover-image and book-file storage. Blobs live on the filesystem under the
//! data dir (`VELLUM_DATA_DIR`); the database keeps only paths, sizes, and
//! hashes. Every endpoint is access-checked against the book the blob belongs
//! to, exactly like the book metadata.

use std::path::Path;

use axum::Json;
use axum::body::Bytes;
use axum::extract::{Path as AxPath, Query, State};
use axum::http::{HeaderMap, StatusCode, header};
use axum::response::Response;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};
use tokio::process::Command;

use crate::AppState;
use crate::access::book_access;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};

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

// ---- content sniffing -----------------------------------------------------

/// What a blob's leading bytes say it actually is — judged by magic bytes, not
/// by the client's declared filename or Content-Type. Mirrors the app's
/// `book_file_validation.dart` so both ends agree on what a real book/image is.
#[derive(Debug, PartialEq, Clone, Copy)]
pub(crate) enum Sniffed {
    Pdf,
    Zip,
    Jpeg,
    Png,
    Gif,
    WebP,
    Unknown,
}

pub(crate) fn sniff(head: &[u8]) -> Sniffed {
    if head.starts_with(b"%PDF") {
        return Sniffed::Pdf;
    }
    if head.starts_with(&[0x50, 0x4B, 0x03, 0x04]) {
        return Sniffed::Zip; // ZIP container — EPUB is a zip
    }
    if head.starts_with(&[0xFF, 0xD8, 0xFF]) {
        return Sniffed::Jpeg;
    }
    if head.starts_with(&[0x89, 0x50, 0x4E, 0x47]) {
        return Sniffed::Png;
    }
    if head.starts_with(b"GIF8") {
        return Sniffed::Gif;
    }
    if head.len() >= 12 && &head[0..4] == b"RIFF" && &head[8..12] == b"WEBP" {
        return Sniffed::WebP;
    }
    Sniffed::Unknown
}

/// The stored file extension for a sniffed image, or None if it isn't an image.
fn image_ext(sniffed: Sniffed) -> Option<&'static str> {
    match sniffed {
        Sniffed::Jpeg => Some("jpg"),
        Sniffed::Png => Some("png"),
        Sniffed::Gif => Some("gif"),
        Sniffed::WebP => Some("webp"),
        _ => None,
    }
}

// ---- covers ---------------------------------------------------------------

/// Upload (or replace) a book's cover. Raw image bytes in the body; the
/// `Content-Type` header picks the stored extension. Requires editor access.
pub async fn put_cover(
    State(state): State<AppState>,
    user: AuthUser,
    AxPath(id): AxPath<String>,
    body: Bytes,
) -> AppResult<Json<serde_json::Value>> {
    require_edit(&state, &user, &id).await?;
    if body.is_empty() {
        return Err(AppError::BadRequest("empty upload".into()));
    }
    // The stored extension comes from the actual bytes, not the Content-Type.
    let ext = image_ext(sniff(&body))
        .ok_or_else(|| AppError::BadRequest("not a supported image (jpeg/png/gif/webp)".into()))?;

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
    headers: HeaderMap,
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
    // Covers have no stored hash, so use a weak size+mtime validator.
    let etag = tokio::fs::metadata(state.data_dir.join(&rel))
        .await
        .ok()
        .map(|m| {
            let mtime = m
                .modified()
                .ok()
                .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
                .map(|d| d.as_secs())
                .unwrap_or(0);
            format!("W/\"{}-{mtime}\"", m.len())
        });
    let inm = headers
        .get(header::IF_NONE_MATCH)
        .and_then(|v| v.to_str().ok());
    serve_blob(&state, &rel, etag, inm).await
}

// ---- book files -----------------------------------------------------------

/// Attach a digital file to a book (PDF/EPUB/...). The raw file streams in the
/// body; `?filename=` supplies the name we derive the format from. Requires
/// editor. Streams to a temp file (never buffering the whole upload in memory),
/// hashing as it goes and validating by magic bytes before committing it.
pub async fn upload_file(
    State(state): State<AppState>,
    user: AuthUser,
    AxPath(id): AxPath<String>,
    Query(q): Query<UploadQuery>,
    body: axum::body::Body,
) -> AppResult<Json<FileDto>> {
    use futures_util::StreamExt;
    use tokio::io::AsyncWriteExt;

    require_edit(&state, &user, &id).await?;
    let internal = |e: std::io::Error| AppError::Internal(e.to_string());

    let ext = Path::new(&q.filename)
        .extension()
        .and_then(|e| e.to_str())
        .map(|e| e.to_lowercase())
        .filter(|e| !e.is_empty())
        .unwrap_or_default();
    // Reject unsupported extensions up front, before reading a single byte.
    if ext != "pdf" && ext != "epub" {
        return Err(AppError::BadRequest(
            "only pdf and epub files are supported".into(),
        ));
    }

    let file_id = uuid::Uuid::new_v4().to_string();
    let files_dir = state.data_dir.join("files");
    tokio::fs::create_dir_all(&files_dir)
        .await
        .map_err(internal)?;
    let tmp = files_dir.join(format!(".tmp-{file_id}"));

    // Stream the body to the temp file, hashing and capturing the leading bytes
    // (for the magic-byte check) as chunks arrive.
    let mut out = tokio::fs::File::create(&tmp).await.map_err(internal)?;
    let mut hasher = Sha256::new();
    let mut head: Vec<u8> = Vec::with_capacity(16);
    let mut size: i64 = 0;
    let mut stream = body.into_data_stream();
    while let Some(chunk) = stream.next().await {
        let chunk = match chunk {
            Ok(c) => c,
            Err(e) => {
                let _ = tokio::fs::remove_file(&tmp).await;
                return Err(AppError::BadRequest(format!("upload aborted: {e}")));
            }
        };
        if head.len() < 16 {
            let take = (16 - head.len()).min(chunk.len());
            head.extend_from_slice(&chunk[..take]);
        }
        hasher.update(&chunk);
        out.write_all(&chunk).await.map_err(internal)?;
        size += chunk.len() as i64;
    }
    out.flush().await.map_err(internal)?;
    drop(out);

    // Validate the finished upload; clean up the temp file on any rejection.
    if size == 0 {
        let _ = tokio::fs::remove_file(&tmp).await;
        return Err(AppError::BadRequest("empty upload".into()));
    }
    let sniffed = sniff(&head);
    let content_ok = matches!(
        (ext.as_str(), sniffed),
        ("pdf", Sniffed::Pdf) | ("epub", Sniffed::Zip)
    );
    if !content_ok {
        let _ = tokio::fs::remove_file(&tmp).await;
        let msg = if ext == "pdf" {
            "file is not a valid PDF"
        } else {
            "file is not a valid EPUB"
        };
        return Err(AppError::BadRequest(msg.into()));
    }

    // Promote the temp file to its final name and record it.
    let rel = format!("files/{file_id}.{ext}");
    let full = state.data_dir.join(&rel);
    tokio::fs::rename(&tmp, &full).await.map_err(internal)?;

    let sha = hex::encode(hasher.finalize());
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

    // A PDF carries its own page count, which is ground truth for a digital
    // copy, so it overrides whatever an online guess supplied. Parsing runs off
    // the async runtime (it's CPU-bound), reading the file back from disk.
    if ext == "pdf" {
        let path = full.clone();
        let pages = tokio::task::spawn_blocking(move || pdf_page_count_at(&path))
            .await
            .ok()
            .flatten();
        if let Some(pages) = pages {
            sqlx::query(
                "UPDATE book SET page_count = ?, updated_at = datetime('now') WHERE id = ?",
            )
            .bind(pages)
            .bind(&id)
            .execute(&state.db)
            .await?;
        }

        // The PDF's own first page is the preferred cover: render it now and
        // set it, overriding any online cover a prior lookup may have stored.
        if let Some(rel) = render_pdf_cover(&state, &id).await {
            sqlx::query(
                "UPDATE book SET cover_path = ?, updated_at = datetime('now') WHERE id = ?",
            )
            .bind(&rel)
            .bind(&id)
            .execute(&state.db)
            .await?;
        }
    }

    // Pull author / title / publisher / year out of the file name convention,
    // filling only what the book is still missing (so a later online lookup can
    // search a clean title).
    crate::discover::apply_filename_metadata(&state, &id, &q.filename).await?;

    let file = sqlx::query_as::<_, FileDto>(
        "SELECT id, book_id, format, path, size_bytes, sha256, added_at \
         FROM book_file WHERE id = ?",
    )
    .bind(&file_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(file))
}

/// Best-effort page count from a PDF's page tree; None if the bytes don't parse.
#[cfg(test)]
fn pdf_page_count(bytes: &[u8]) -> Option<i64> {
    let doc = lopdf::Document::load_mem(bytes).ok()?;
    let n = doc.get_pages().len();
    (n > 0).then_some(n as i64)
}

/// Same, reading the PDF from disk (the upload path streams to a file, so it
/// never holds the whole document in memory).
fn pdf_page_count_at(path: &Path) -> Option<i64> {
    let doc = lopdf::Document::load(path).ok()?;
    let n = doc.get_pages().len();
    (n > 0).then_some(n as i64)
}

/// Render the first page of the book's newest PDF into its JPEG cover, using
/// whatever PDF CLI the host provides. Returns the stored cover path, or None if
/// the book has no PDF or no renderer is installed. The server links no PDF
/// library of its own — see DESIGN.md — so this is a best-effort convenience
/// that simply no-ops when the tooling is absent.
pub(crate) async fn render_pdf_cover(state: &AppState, book_id: &str) -> Option<String> {
    let rel: Option<String> = sqlx::query_scalar(
        "SELECT path FROM book_file WHERE book_id = ? AND format = 'pdf' \
         ORDER BY added_at DESC LIMIT 1",
    )
    .bind(book_id)
    .fetch_optional(&state.db)
    .await
    .ok()
    .flatten();
    let input = state.data_dir.join(rel?);

    let out_rel = format!("covers/{book_id}.jpg");
    let out_full = state.data_dir.join(&out_rel);
    if let Some(parent) = out_full.parent() {
        let _ = tokio::fs::create_dir_all(parent).await;
    }
    render_first_page(&input, &out_full)
        .await
        .then_some(out_rel)
}

/// Try each known PDF CLI in turn until one writes a non-empty JPEG.
async fn render_first_page(input: &Path, out_jpg: &Path) -> bool {
    // poppler: pdftoppm / pdftocairo write "<prefix>.jpg" with -singlefile.
    let prefix = out_jpg.with_extension("");
    for tool in ["pdftoppm", "pdftocairo"] {
        let _ = tokio::fs::remove_file(out_jpg).await;
        let ran = Command::new(tool)
            .args([
                "-jpeg",
                "-f",
                "1",
                "-l",
                "1",
                "-singlefile",
                "-scale-to",
                "1400",
            ])
            .arg(input)
            .arg(&prefix)
            .status()
            .await
            .map(|s| s.success())
            .unwrap_or(false);
        if ran && nonempty(out_jpg).await {
            return true;
        }
    }
    // MuPDF: writes exactly to -o.
    let _ = tokio::fs::remove_file(out_jpg).await;
    let ran = Command::new("mutool")
        .args(["draw", "-F", "jpeg", "-w", "1400", "-o"])
        .arg(out_jpg)
        .arg(input)
        .arg("1")
        .status()
        .await
        .map(|s| s.success())
        .unwrap_or(false);
    if ran && nonempty(out_jpg).await {
        return true;
    }
    // Ghostscript.
    let _ = tokio::fs::remove_file(out_jpg).await;
    let ran = Command::new("gs")
        .args([
            "-q",
            "-dSAFER",
            "-dBATCH",
            "-dNOPAUSE",
            "-sDEVICE=jpeg",
            "-dFirstPage=1",
            "-dLastPage=1",
            "-r150",
        ])
        .arg(format!("-sOutputFile={}", out_jpg.display()))
        .arg(input)
        .status()
        .await
        .map(|s| s.success())
        .unwrap_or(false);
    ran && nonempty(out_jpg).await
}

async fn nonempty(p: &Path) -> bool {
    tokio::fs::metadata(p)
        .await
        .map(|m| m.len() > 0)
        .unwrap_or(false)
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
    headers: HeaderMap,
) -> AppResult<Response> {
    let row: Option<(String, String, String)> =
        sqlx::query_as("SELECT book_id, path, sha256 FROM book_file WHERE id = ?")
            .bind(&file_id)
            .fetch_optional(&state.db)
            .await?;
    let (book_id, rel, sha) = row.ok_or_else(|| AppError::NotFound("file not found".into()))?;
    require_view(&state, &user, &book_id).await?;
    // A file's content hash is a strong, stable ETag.
    let inm = headers
        .get(header::IF_NONE_MATCH)
        .and_then(|v| v.to_str().ok());
    serve_blob(&state, &rel, Some(format!("\"{sha}\"")), inm).await
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
        return Err(AppError::Forbidden(
            "you have read-only access to this book".into(),
        ));
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

/// Streams a stored blob to the client without reading it all into memory. When
/// an [etag] is supplied it is sent on the response and honored: a matching
/// `If-None-Match` short-circuits to `304 Not Modified` so the client reuses its
/// cached copy instead of re-downloading the whole file.
async fn serve_blob(
    state: &AppState,
    rel: &str,
    etag: Option<String>,
    if_none_match: Option<&str>,
) -> AppResult<Response> {
    if let (Some(etag), Some(inm)) = (etag.as_deref(), if_none_match)
        && inm == etag
    {
        let mut not_modified = Response::new(axum::body::Body::empty());
        *not_modified.status_mut() = StatusCode::NOT_MODIFIED;
        not_modified
            .headers_mut()
            .insert(header::ETAG, etag.parse().unwrap());
        return Ok(not_modified);
    }

    let full = state.data_dir.join(rel);
    let file = tokio::fs::File::open(&full)
        .await
        .map_err(|_| AppError::NotFound("blob missing on disk".into()))?;
    let len = file.metadata().await.ok().map(|m| m.len());
    let ext = Path::new(rel)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("");
    let body = axum::body::Body::from_stream(tokio_util::io::ReaderStream::new(file));
    let mut response = Response::new(body);
    let headers = response.headers_mut();
    headers.insert(
        header::CONTENT_TYPE,
        content_type_for_ext(ext).parse().unwrap(),
    );
    if let Some(len) = len {
        headers.insert(header::CONTENT_LENGTH, len.into());
    }
    if let Some(etag) = etag {
        headers.insert(header::ETAG, etag.parse().unwrap());
        headers.insert(
            header::CACHE_CONTROL,
            "private, max-age=0, must-revalidate".parse().unwrap(),
        );
    }
    Ok(response)
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

#[cfg(test)]
mod tests {
    use super::*;
    use lopdf::{Document, Object, dictionary};

    #[test]
    fn counts_pages_of_a_pdf() {
        // Build a valid two-page PDF with lopdf, then read the count back.
        let mut doc = Document::with_version("1.5");
        let pages_id = doc.new_object_id();
        let p1 = doc.add_object(dictionary! { "Type" => "Page", "Parent" => pages_id });
        let p2 = doc.add_object(dictionary! { "Type" => "Page", "Parent" => pages_id });
        let pages = dictionary! {
            "Type" => "Pages",
            "Kids" => vec![Object::Reference(p1), Object::Reference(p2)],
            "Count" => 2,
        };
        doc.objects.insert(pages_id, Object::Dictionary(pages));
        let catalog = doc.add_object(dictionary! { "Type" => "Catalog", "Pages" => pages_id });
        doc.trailer.set("Root", catalog);
        let mut buf = Vec::new();
        doc.save_to(&mut buf).unwrap();

        assert_eq!(pdf_page_count(&buf), Some(2));
    }

    #[test]
    fn non_pdf_bytes_have_no_page_count() {
        assert_eq!(pdf_page_count(b"this is not a pdf"), None);
    }

    #[test]
    fn sniff_recognizes_book_and_image_signatures() {
        assert_eq!(sniff(b"%PDF-1.7 ..."), Sniffed::Pdf);
        assert_eq!(sniff(&[0x50, 0x4B, 0x03, 0x04, 0x00]), Sniffed::Zip);
        assert_eq!(sniff(&[0xFF, 0xD8, 0xFF, 0xE0]), Sniffed::Jpeg);
        assert_eq!(sniff(b"\x89PNG\r\n\x1a\n"), Sniffed::Png);
        assert_eq!(sniff(b"GIF89a"), Sniffed::Gif);
        assert_eq!(sniff(b"RIFF\0\0\0\0WEBPVP8 "), Sniffed::WebP);
        assert_eq!(sniff(b"not a known format"), Sniffed::Unknown);
        assert_eq!(sniff(b""), Sniffed::Unknown);
    }

    #[test]
    fn image_ext_maps_only_images() {
        assert_eq!(image_ext(Sniffed::Png), Some("png"));
        assert_eq!(image_ext(Sniffed::Jpeg), Some("jpg"));
        assert_eq!(image_ext(Sniffed::WebP), Some("webp"));
        assert_eq!(image_ext(Sniffed::Pdf), None);
        assert_eq!(image_ext(Sniffed::Unknown), None);
    }
}
