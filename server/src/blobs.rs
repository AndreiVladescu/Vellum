//! Cover-image and book-file storage. Blobs live on the filesystem under the
//! data dir (`VELLUM_DATA_DIR`); the database keeps only paths, sizes, and
//! hashes. Every endpoint is access-checked against the book the blob belongs
//! to, exactly like the book metadata.

use std::path::{Component, Path, PathBuf};

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
    // The cover changed, so any cached thumbnails are stale.
    invalidate_thumbs(&state, &id).await;
    Ok(Json(serde_json::json!({ "cover_path": rel })))
}

/// Thumbnail widths we generate and cache. A whitelist so a caller can't drive
/// arbitrary-size renders; add sizes here as the UI needs them.
const THUMB_WIDTHS: &[u32] = &[160];

#[derive(Deserialize)]
pub struct CoverQuery {
    /// Optional cached thumbnail width (must be in [`THUMB_WIDTHS`]).
    pub w: Option<u32>,
}

pub async fn get_cover(
    State(state): State<AppState>,
    user: AuthUser,
    AxPath(id): AxPath<String>,
    Query(q): Query<CoverQuery>,
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

    // A whitelisted ?w= serves a cached, downscaled JPEG so a table of 40px
    // thumbnails doesn't pull hundreds of MB of full first-page renders.
    let serve_rel = match q.w {
        Some(w) if THUMB_WIDTHS.contains(&w) => ensure_thumb(&state, &id, &rel, w).await?,
        _ => rel,
    };

    // Covers have no stored hash, so use a weak size+mtime validator.
    let etag = weak_etag(&state, &serve_rel).await;
    let inm = headers
        .get(header::IF_NONE_MATCH)
        .and_then(|v| v.to_str().ok());
    let range = headers.get(header::RANGE).and_then(|v| v.to_str().ok());
    let if_range = headers.get(header::IF_RANGE).and_then(|v| v.to_str().ok());
    serve_blob(&state, &serve_rel, etag, inm, range, if_range).await
}

/// Relative path of a book's cached thumbnail at width `w`.
fn thumb_rel(id: &str, w: u32) -> String {
    format!("covers/thumbs/{id}-w{w}.jpg")
}

/// A weak size+mtime ETag for the blob at `rel`, or None if it can't be stat'd.
async fn weak_etag(state: &AppState, rel: &str) -> Option<String> {
    let m = tokio::fs::metadata(state.data_dir.join(rel)).await.ok()?;
    let mtime = m
        .modified()
        .ok()
        .and_then(|t| t.duration_since(std::time::UNIX_EPOCH).ok())
        .map(|d| d.as_secs())
        .unwrap_or(0);
    Some(format!("W/\"{}-{mtime}\"", m.len()))
}

/// Ensure a cached thumbnail exists for the cover and return its relative path.
/// Generates it (decode → downscale → JPEG) on first request; on any failure
/// falls back to serving the full cover so a thumbnail can never 500 a row.
async fn ensure_thumb(state: &AppState, id: &str, cover_rel: &str, w: u32) -> AppResult<String> {
    let rel = thumb_rel(id, w);
    let thumb_full = state.data_dir.join(&rel);
    if tokio::fs::metadata(&thumb_full).await.is_ok() {
        return Ok(rel); // already cached
    }
    if let Some(parent) = thumb_full.parent() {
        let _ = tokio::fs::create_dir_all(parent).await;
    }
    let cover_full = state.data_dir.join(cover_rel);
    let out = thumb_full.clone();
    // Decode + encode is CPU-bound; keep it off the async runtime.
    let made = tokio::task::spawn_blocking(move || make_thumb(&cover_full, &out, w))
        .await
        .unwrap_or(false);
    Ok(if made { rel } else { cover_rel.to_string() })
}

/// Decode `cover`, downscale to fit width `w` (aspect-preserving), and write a
/// JPEG to `out`. Returns whether it succeeded.
fn make_thumb(cover: &Path, out: &Path, w: u32) -> bool {
    // Bound decode work so a small "pixel bomb" cover (valid header, enormous
    // declared dimensions) can't allocate gigabytes and OOM-kill the process.
    // See docs/SECURITY_AUDIT.md (M1).
    let mut limits = image::Limits::no_limits();
    limits.max_image_width = Some(12_000);
    limits.max_image_height = Some(12_000);
    limits.max_alloc = Some(256 * 1024 * 1024);
    let Ok(mut reader) = image::ImageReader::open(cover).and_then(|r| r.with_guessed_format())
    else {
        return false;
    };
    reader.limits(limits);
    let Ok(img) = reader.decode() else {
        return false;
    };
    // A tall height cap so width is the binding dimension for portrait covers.
    let thumb = img.thumbnail(w, w * 4);
    let Ok(mut file) = std::fs::File::create(out) else {
        return false;
    };
    thumb.write_to(&mut file, image::ImageFormat::Jpeg).is_ok()
}

/// Delete every cached thumbnail for a book, so a changed cover isn't served
/// stale. Called whenever the cover blob is replaced.
async fn invalidate_thumbs(state: &AppState, id: &str) {
    for &w in THUMB_WIDTHS {
        let _ = tokio::fs::remove_file(state.data_dir.join(thumb_rel(id, w))).await;
    }
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

    // Promote the temp file into its content-addressed home (plan 5 #9).
    //
    // The rename only happens when the target is absent: identical bytes are
    // already on disk, and overwriting them would rewrite a file other rows
    // point at for no gain. Same-directory rename is atomic, so a reader never
    // sees a half-written blob.
    let sha = hex::encode(hasher.finalize());
    let rel = content_addressed_rel(&sha, &ext);
    let full = state.data_dir.join(&rel);
    if let Some(parent) = full.parent() {
        tokio::fs::create_dir_all(parent).await.map_err(internal)?;
    }
    if tokio::fs::metadata(&full).await.is_ok() {
        let _ = tokio::fs::remove_file(&tmp).await;
    } else {
        tokio::fs::rename(&tmp, &full).await.map_err(internal)?;
    }
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

    crate::audit::record(
        &state,
        Some(&user),
        "file.upload",
        "book",
        &id,
        Some(&q.filename),
    )
    .await;

    // The heavy enrichment — page-count parse, first-page cover render (a
    // shell-out that can take seconds), and file-name metadata — runs in a
    // detached task *after* the response, so a big upload's HTTP reply isn't
    // held open by Ghostscript. The book_file row and blob are already
    // committed; the console refetches the row and the app pushes its own, so
    // nothing user-visible is lost if this fails.
    let bg = state.clone();
    let bg_id = id.clone();
    let bg_file_id = file_id.clone();
    let bg_full = full.clone();
    let bg_filename = q.filename.clone();
    let is_pdf = ext == "pdf";
    let is_epub = ext == "epub";
    tokio::spawn(async move {
        if is_pdf {
            // A PDF's page count is ground truth for the digital copy; parse it
            // off the async runtime (CPU-bound), reading the file back from disk.
            let pages = tokio::task::spawn_blocking(move || pdf_page_count_at(&bg_full))
                .await
                .ok()
                .flatten();
            if let Some(pages) = pages {
                let _ = sqlx::query(
                    "UPDATE book SET page_count = ?, updated_at = datetime('now') WHERE id = ?",
                )
                .bind(pages)
                .bind(&bg_id)
                .execute(&bg.db)
                .await;
            }
            // The PDF's own first page is the preferred cover, overriding any
            // online cover a prior lookup may have stored.
            if let Some(rel) = render_pdf_cover(&bg, &bg_id).await {
                let _ = sqlx::query(
                    "UPDATE book SET cover_path = ?, updated_at = datetime('now') WHERE id = ?",
                )
                .bind(&rel)
                .bind(&bg_id)
                .execute(&bg.db)
                .await;
            }
        } else if is_epub {
            // An EPUB declares its cover in the OPF manifest; extract and store
            // it (store_epub_cover updates cover_path itself).
            let _ = store_epub_cover(&bg, &bg_id).await;
        }
        // Fill still-missing author / title / publisher / year from the file-name
        // convention (so a later online lookup can search a clean title).
        let _ = crate::discover::apply_filename_metadata(&bg, &bg_id, &bg_filename).await;
        // Queue the contents for indexing (plan 5 #32). A no-op unless the
        // server opted in, and never on the request path: extracting a 900-page
        // PDF must not hold an upload open.
        crate::text_index::enqueue(&bg, &bg_file_id, &bg_id).await;
    });

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

    // What the cover is now, so we can delete it if the render stores a
    // different extension (e.g. an earlier uploaded .png cover).
    let previous: Option<String> = sqlx::query_scalar("SELECT cover_path FROM book WHERE id = ?")
        .bind(book_id)
        .fetch_optional(&state.db)
        .await
        .ok()
        .flatten();

    let out_rel = format!("covers/{book_id}.jpg");
    let out_full = state.data_dir.join(&out_rel);
    if let Some(parent) = out_full.parent() {
        let _ = tokio::fs::create_dir_all(parent).await;
    }

    // Bound concurrent shell-outs: ten parallel uploads shouldn't fork ten `gs`.
    let _permit = state.render_semaphore.acquire().await.ok()?;
    let ok = render_first_page(&input, &out_full).await;
    drop(_permit);
    if !ok {
        return None;
    }

    // Replicate put_cover's cleanup: drop a stale cover under a different name.
    if let Some(old) = previous
        && old != out_rel
    {
        let _ = tokio::fs::remove_file(state.data_dir.join(&old)).await;
    }
    invalidate_thumbs(state, book_id).await;
    Some(out_rel)
}

/// Extract the declared cover image from the book's newest EPUB and store it as
/// the cover. Mirrors [`render_pdf_cover`] for EPUBs — but an EPUB *declares*
/// its cover in the OPF manifest, so it's a plain zip read, no renderer. Returns
/// the stored cover path, or None when there's no EPUB, none is declared, or the
/// bytes aren't a supported image.
pub(crate) async fn store_epub_cover(state: &AppState, book_id: &str) -> Option<String> {
    let rel: Option<String> = sqlx::query_scalar(
        "SELECT path FROM book_file WHERE book_id = ? AND format = 'epub' \
         ORDER BY added_at DESC LIMIT 1",
    )
    .bind(book_id)
    .fetch_optional(&state.db)
    .await
    .ok()
    .flatten();
    let input = state.data_dir.join(rel?);

    // Zip IO is blocking; keep it off the async runtime.
    let bytes = tokio::task::spawn_blocking(move || epub_cover_bytes(&input))
        .await
        .ok()
        .flatten()?;
    // Only images we can serve back (the app's covers are the same set).
    let ext = image_ext(sniff(&bytes))?;

    let previous: Option<String> = sqlx::query_scalar("SELECT cover_path FROM book WHERE id = ?")
        .bind(book_id)
        .fetch_optional(&state.db)
        .await
        .ok()
        .flatten();

    let out_rel = format!("covers/{book_id}.{ext}");
    write_blob(state, &out_rel, &bytes).await.ok()?;
    sqlx::query("UPDATE book SET cover_path = ?, updated_at = datetime('now') WHERE id = ?")
        .bind(&out_rel)
        .bind(book_id)
        .execute(&state.db)
        .await
        .ok()?;
    if let Some(old) = previous
        && old != out_rel
    {
        let _ = tokio::fs::remove_file(state.data_dir.join(&old)).await;
    }
    invalidate_thumbs(state, book_id).await;
    Some(out_rel)
}

/// Pull an EPUB's declared cover-image bytes out of its zip (EPUB3
/// `properties="cover-image"`, else the EPUB2 `<meta name="cover" content=..>`
/// convention). Best-effort, blocking — returns None on any parse failure. The
/// OPF is scanned rather than fully parsed to avoid pulling in an XML crate; the
/// app's parser (reader/epub_book.dart) is the robust path and pushes covers
/// back on sync.
fn epub_cover_bytes(path: &Path) -> Option<Vec<u8>> {
    let file = std::fs::File::open(path).ok()?;
    let mut zip = zip::ZipArchive::new(file).ok()?;

    fn entry(zip: &mut zip::ZipArchive<std::fs::File>, name: &str) -> Option<Vec<u8>> {
        use std::io::Read;
        // Cap the *decompressed* read so a zip-bomb entry (a tiny compressed
        // blob that inflates to gigabytes) can't exhaust memory. The OPF and
        // container are tiny; a real cover is well under this. See M1.
        const MAX_ENTRY_BYTES: u64 = 32 * 1024 * 1024;
        let f = zip.by_name(name).ok()?;
        let mut buf = Vec::new();
        f.take(MAX_ENTRY_BYTES).read_to_end(&mut buf).ok()?;
        Some(buf)
    }

    // container.xml names the OPF package file.
    let container = String::from_utf8(entry(&mut zip, "META-INF/container.xml")?).ok()?;
    let opf_path = tag_attr(find_tag(&container, "rootfile")?, "full-path")?.to_string();
    let opf = String::from_utf8(entry(&mut zip, &opf_path)?).ok()?;
    let opf_dir = opf_path.rsplit_once('/').map(|(d, _)| d).unwrap_or("");

    // EPUB3: the manifest <item> flagged properties="cover-image".
    let mut cover_href: Option<String> = None;
    for tag in item_tags(&opf) {
        if tag_attr(tag, "properties")
            .map(|p| p.split_whitespace().any(|w| w == "cover-image"))
            .unwrap_or(false)
        {
            cover_href = tag_attr(tag, "href").map(str::to_string);
            break;
        }
    }
    // EPUB2: <meta name="cover" content="<id>"/> -> that item's href.
    if cover_href.is_none()
        && let Some(cover_id) = meta_content(&opf, "cover")
    {
        for tag in item_tags(&opf) {
            if tag_attr(tag, "id") == Some(cover_id) {
                cover_href = tag_attr(tag, "href").map(str::to_string);
                break;
            }
        }
    }
    let href = cover_href?;
    let full = join_posix(opf_dir, &href);
    entry(&mut zip, &full)
}

/// Every spine section of an EPUB as plain text, in reading order (plan 5 #32).
///
/// Reuses the same zip + tiny-XML reading as [`epub_cover_bytes`] — an EPUB is
/// a zip of XHTML, so its text costs nothing but a strip of the tags. Sections
/// that fail to read are skipped rather than aborting the file: one broken
/// chapter should not make a whole book unsearchable.
///
/// Returns None only when the archive itself can't be read as an EPUB.
pub(crate) fn epub_section_texts(path: &Path) -> Option<Vec<String>> {
    let file = std::fs::File::open(path).ok()?;
    let mut zip = zip::ZipArchive::new(file).ok()?;

    fn entry(zip: &mut zip::ZipArchive<std::fs::File>, name: &str) -> Option<Vec<u8>> {
        use std::io::Read;
        // Same zip-bomb cap as the cover read (M1): a tiny compressed entry
        // must not be able to inflate into gigabytes of memory.
        const MAX_ENTRY_BYTES: u64 = 32 * 1024 * 1024;
        let f = zip.by_name(name).ok()?;
        let mut buf = Vec::new();
        f.take(MAX_ENTRY_BYTES).read_to_end(&mut buf).ok()?;
        Some(buf)
    }

    let container = String::from_utf8(entry(&mut zip, "META-INF/container.xml")?).ok()?;
    let opf_path = tag_attr(find_tag(&container, "rootfile")?, "full-path")?.to_string();
    let opf = String::from_utf8(entry(&mut zip, &opf_path)?).ok()?;
    let opf_dir = opf_path.rsplit_once('/').map(|(d, _)| d).unwrap_or("");

    // id -> href for every manifest item, then walk the spine's itemrefs, which
    // is what defines reading order.
    let manifest: Vec<(String, String)> = item_tags(&opf)
        .filter_map(|tag| {
            Some((
                tag_attr(tag, "id")?.to_string(),
                tag_attr(tag, "href")?.to_string(),
            ))
        })
        .collect();

    let mut sections = Vec::new();
    for idref in itemref_ids(&opf) {
        let Some((_, href)) = manifest.iter().find(|(id, _)| id == idref) else {
            continue;
        };
        let full = join_posix(opf_dir, href);
        let Some(bytes) = entry(&mut zip, &full) else {
            continue;
        };
        let Ok(xhtml) = String::from_utf8(bytes) else {
            continue;
        };
        sections.push(strip_markup(&xhtml));
    }
    Some(sections)
}

/// One EPUB spine section as **sanitised** HTML, for browser reading
/// (plan 5 #33): the section's title (from its first heading, else its file
/// name) and its body markup.
///
/// Returns None when the archive can't be read or the index is past the end.
pub(crate) fn epub_section_html(path: &Path, index: usize) -> Option<(String, String)> {
    let (opf_dir, hrefs) = epub_spine_hrefs(path)?;
    let href = hrefs.get(index)?.clone();
    let full = join_posix(&opf_dir, &href);

    let file = std::fs::File::open(path).ok()?;
    let mut zip = zip::ZipArchive::new(file).ok()?;
    let xhtml = {
        use std::io::Read;
        const MAX_ENTRY_BYTES: u64 = 32 * 1024 * 1024;
        let f = zip.by_name(&full).ok()?;
        let mut buf = Vec::new();
        f.take(MAX_ENTRY_BYTES).read_to_end(&mut buf).ok()?;
        String::from_utf8_lossy(&buf).into_owned()
    };

    let base_dir = full
        .rsplit_once('/')
        .map(|(d, _)| d)
        .unwrap_or("")
        .to_string();
    let body = body_of(&xhtml);
    let title = first_heading(&body).unwrap_or_else(|| {
        href.rsplit('/')
            .next()
            .unwrap_or(&href)
            .trim_end_matches(".xhtml")
            .trim_end_matches(".html")
            .to_string()
    });
    Some((title, sanitize_html(&body, &base_dir)))
}

/// Spine hrefs in reading order, with the OPF's directory (hrefs are relative
/// to it). Shared by [`epub_section_html`] and [`epub_section_texts`].
fn epub_spine_hrefs(path: &Path) -> Option<(String, Vec<String>)> {
    use std::io::Read;
    const MAX_ENTRY_BYTES: u64 = 32 * 1024 * 1024;
    let file = std::fs::File::open(path).ok()?;
    let mut zip = zip::ZipArchive::new(file).ok()?;

    let mut read = |name: &str| -> Option<String> {
        let f = zip.by_name(name).ok()?;
        let mut buf = Vec::new();
        f.take(MAX_ENTRY_BYTES).read_to_end(&mut buf).ok()?;
        String::from_utf8(buf).ok()
    };
    let container = read("META-INF/container.xml")?;
    let opf_path = tag_attr(find_tag(&container, "rootfile")?, "full-path")?.to_string();
    let opf = read(&opf_path)?;
    let opf_dir = opf_path
        .rsplit_once('/')
        .map(|(d, _)| d)
        .unwrap_or("")
        .to_string();

    let manifest: Vec<(String, String)> = item_tags(&opf)
        .filter_map(|tag| {
            Some((
                tag_attr(tag, "id")?.to_string(),
                tag_attr(tag, "href")?.to_string(),
            ))
        })
        .collect();
    let hrefs = itemref_ids(&opf)
        .into_iter()
        .filter_map(|idref| {
            manifest
                .iter()
                .find(|(id, _)| id == idref)
                .map(|(_, href)| href.clone())
        })
        .collect();
    Some((opf_dir, hrefs))
}

/// How many spine sections an EPUB has, for the reader's chapter list.
pub(crate) fn epub_spine_len(path: &Path) -> usize {
    epub_spine_hrefs(path).map(|(_, h)| h.len()).unwrap_or(0)
}

/// A zip entry's bytes, for serving an EPUB's own images to the reader.
///
/// Reads **by name from the archive**, never through the filesystem, so a
/// crafted entry name like `../../etc/passwd` addresses nothing outside the
/// book — there is no path to traverse.
pub(crate) fn epub_entry_bytes(path: &Path, name: &str) -> Option<Vec<u8>> {
    use std::io::Read;
    const MAX_ENTRY_BYTES: u64 = 32 * 1024 * 1024;
    let file = std::fs::File::open(path).ok()?;
    let mut zip = zip::ZipArchive::new(file).ok()?;
    let f = zip.by_name(name).ok()?;
    let mut buf = Vec::new();
    f.take(MAX_ENTRY_BYTES).read_to_end(&mut buf).ok()?;
    Some(buf)
}

/// Everything between `<body …>` and `</body>`, or the whole document when
/// there is no body element.
fn body_of(xhtml: &str) -> String {
    let lower = xhtml.to_ascii_lowercase();
    let Some(open) = lower.find("<body") else {
        return xhtml.to_string();
    };
    let Some(after) = xhtml[open..].find('>').map(|e| open + e + 1) else {
        return xhtml.to_string();
    };
    let end = lower[after..]
        .find("</body>")
        .map(|e| after + e)
        .unwrap_or(xhtml.len());
    xhtml[after..end].to_string()
}

fn first_heading(body: &str) -> Option<String> {
    for level in 1..=3 {
        let open = format!("<h{level}");
        let close = format!("</h{level}>");
        let lower = body.to_ascii_lowercase();
        if let Some(at) = lower.find(&open)
            && let Some(gt) = body[at..].find('>').map(|e| at + e + 1)
            && let Some(end) = lower[gt..].find(&close).map(|e| gt + e)
        {
            let text = strip_markup(&body[gt..end]);
            let trimmed = text.split_whitespace().collect::<Vec<_>>().join(" ");
            if !trimmed.is_empty() {
                return Some(trimmed);
            }
        }
    }
    None
}

/// The `idref` of every `<itemref>`, in document order — the EPUB spine.
fn itemref_ids(opf: &str) -> Vec<&str> {
    let mut ids = Vec::new();
    for (i, _) in opf.match_indices("<itemref") {
        let rest = &opf[i..];
        let Some(end) = rest.find('>') else { continue };
        if let Some(id) = tag_attr(&rest[..end], "idref") {
            ids.push(id);
        }
    }
    ids
}

/// EPUB markup to something safe to inject into the reader page (plan 5 #33).
///
/// **An allowlist, not a blocklist.** Book files are attacker-supplied in the
/// share-link case — anyone with a link is reading markup somebody else
/// uploaded — and a blocklist of dangerous tags is a list you get wrong once.
/// So only known-harmless elements survive, with a known-harmless set of
/// attributes each; everything else has its *tags* removed while its text is
/// kept, which is what a reader wants anyway.
///
/// Three specific holes this closes: `on*` handlers (dropped with every
/// unlisted attribute), `javascript:` and `data:` URLs (only relative links,
/// `http(s)` and in-document `#fragment`s pass), and `<script>`/`<style>`
/// bodies (removed entirely, contents included). The CSP forbids inline script
/// on top of this — but a page that depends on its CSP alone is one header away
/// from being wrong.
///
/// Image `src`s are rewritten to `asset/<zip path>` so the reader can serve them
/// out of the book's own archive; anything not resolvable inside the book turns
/// into no image rather than an outbound request.
fn sanitize_html(body: &str, base_dir: &str) -> String {
    const ALLOWED: &[&str] = &[
        "p",
        "br",
        "hr",
        "div",
        "span",
        "section",
        "article",
        "blockquote",
        "pre",
        "code",
        "em",
        "strong",
        "i",
        "b",
        "u",
        "s",
        "small",
        "sup",
        "sub",
        "h1",
        "h2",
        "h3",
        "h4",
        "h5",
        "h6",
        "ul",
        "ol",
        "li",
        "dl",
        "dt",
        "dd",
        "table",
        "thead",
        "tbody",
        "tr",
        "td",
        "th",
        "figure",
        "figcaption",
        "a",
        "img",
        "cite",
        "q",
        "abbr",
        "ruby",
        "rt",
        "rp",
    ];
    const DROP_WITH_CONTENT: &[(&str, &str)] = &[
        ("<script", "</script>"),
        ("<style", "</style>"),
        ("<iframe", "</iframe>"),
        ("<object", "</object>"),
        ("<embed", "</embed>"),
        ("<svg", "</svg>"),
    ];

    let lower = body.to_ascii_lowercase();
    let mut out = String::with_capacity(body.len());
    let mut i = 0;
    while i < body.len() {
        let Some(rel) = body[i..].find('<') else {
            out.push_str(&body[i..]);
            break;
        };
        out.push_str(&body[i..i + rel]);
        let at = i + rel;

        if let Some((_, close)) = DROP_WITH_CONTENT
            .iter()
            .find(|(open, _)| lower[at..].starts_with(open))
        {
            i = lower[at..]
                .find(close)
                .map(|e| at + e + close.len())
                .unwrap_or(body.len());
            continue;
        }

        let Some(end) = body[at..].find('>').map(|e| at + e + 1) else {
            break; // an unterminated `<` at the end: drop the rest
        };
        let tag = &body[at..end];
        let closing = tag.starts_with("</");
        let name: String = tag
            .trim_start_matches('<')
            .trim_start_matches('/')
            .chars()
            .take_while(|c| c.is_ascii_alphanumeric())
            .collect::<String>()
            .to_ascii_lowercase();

        if ALLOWED.contains(&name.as_str()) {
            if closing {
                out.push_str(&format!("</{name}>"));
            } else {
                out.push_str(&rebuild_tag(&name, tag, base_dir));
            }
        } else {
            // Unknown element: keep its text, lose its tag — and a space, so
            // "end.<x/>Next" doesn't become one word.
            out.push(' ');
        }
        i = end;
    }
    out
}

/// Rebuilds one opening tag with only the attributes that are safe to keep.
fn rebuild_tag(name: &str, tag: &str, base_dir: &str) -> String {
    let self_closing = tag.trim_end().trim_end_matches('>').ends_with('/');
    let mut rebuilt = format!("<{name}");
    match name {
        "a" => {
            if let Some(href) = tag_attr(tag, "href").and_then(safe_link) {
                rebuilt.push_str(&format!(" href=\"{}\"", attr_escape(&href)));
                // Never let a book's link take over the reader's tab.
                rebuilt.push_str(" target=\"_blank\" rel=\"noopener noreferrer\"");
            }
        }
        "img" => {
            match tag_attr(tag, "src").and_then(|src| book_asset(src, base_dir)) {
                Some(src) => rebuilt.push_str(&format!(" src=\"{}\"", attr_escape(&src))),
                // No resolvable image beats an image element pointing nowhere.
                None => return String::new(),
            }
            if let Some(alt) = tag_attr(tag, "alt") {
                rebuilt.push_str(&format!(" alt=\"{}\"", attr_escape(alt)));
            }
        }
        _ => {}
    }
    rebuilt.push_str(if self_closing { "/>" } else { ">" });
    rebuilt
}

/// Relative, `http(s)` and in-document links only. Everything else — most of
/// all `javascript:` — becomes no link at all.
fn safe_link(href: &str) -> Option<String> {
    let trimmed = href.trim();
    if trimmed.is_empty() {
        return None;
    }
    let lower = trimmed.to_ascii_lowercase();
    if lower.starts_with("http://") || lower.starts_with("https://") || trimmed.starts_with('#') {
        return Some(trimmed.to_string());
    }
    // Anything else — a `javascript:`/`data:` URL, or a relative link to
    // another file inside the book — loses its href. The anchor's *text* is
    // still shown, so a cross-chapter footnote reads as words rather than
    // vanishing or becoming a broken link.
    None
}

/// An EPUB-internal image path, resolved against the section's directory and
/// handed back as the reader's own asset URL.
fn book_asset(src: &str, base_dir: &str) -> Option<String> {
    let trimmed = src.trim();
    if trimmed.is_empty() || trimmed.contains(':') {
        return None; // absolute or data: — not something inside this book
    }
    let resolved = join_posix(base_dir, trimmed);
    if resolved.is_empty() {
        return None;
    }
    Some(format!("asset/{}", url_escape(&resolved)))
}

fn url_escape(raw: &str) -> String {
    let mut out = String::with_capacity(raw.len());
    for byte in raw.as_bytes() {
        match byte {
            b'A'..=b'Z' | b'a'..=b'z' | b'0'..=b'9' | b'-' | b'_' | b'.' | b'~' | b'/' => {
                out.push(*byte as char)
            }
            _ => out.push_str(&format!("%{byte:02X}")),
        }
    }
    out
}

fn attr_escape(raw: &str) -> String {
    raw.replace('&', "&amp;")
        .replace('<', "&lt;")
        .replace('>', "&gt;")
        .replace('"', "&quot;")
}

/// XHTML to searchable text: drop `<script>`/`<style>` bodies, then every tag,
/// then decode the handful of entities that actually appear in prose.
///
/// A real HTML parser would be more correct and is not worth a dependency here:
/// the output is only ever fed to an FTS tokenizer, which throws away
/// punctuation anyway. What matters is that no tag *name* ends up as a search
/// term — "div" must not match every book.
fn strip_markup(xhtml: &str) -> String {
    const SKIP: [(&str, &str); 2] = [("<script", "</script>"), ("<style", "</style>")];
    let lower = xhtml.to_ascii_lowercase();
    let mut text = String::with_capacity(xhtml.len() / 2);
    let mut i = 0;
    while i < xhtml.len() {
        let Some(open) = xhtml[i..].find('<') else {
            text.push_str(&xhtml[i..]);
            break;
        };
        text.push_str(&xhtml[i..i + open]);
        let tag_at = i + open;

        // Skip the *contents* of script/style, not merely their tags —
        // otherwise a variable name inside a <script> becomes a search term
        // that matches a book nobody can see it in.
        if let Some((_, close)) = SKIP
            .iter()
            .find(|(open_tag, _)| lower[tag_at..].starts_with(open_tag))
        {
            i = lower[tag_at..]
                .find(close)
                .map(|e| tag_at + e + close.len())
                .unwrap_or(xhtml.len());
            continue;
        }

        // Any other tag is dropped and replaced by a space: without that,
        // "end.<p>Next" would index as the single word "end.Next".
        text.push(' ');
        i = xhtml[tag_at..]
            .find('>')
            .map(|e| tag_at + e + 1)
            .unwrap_or(xhtml.len());
    }
    decode_entities(&text)
}

fn decode_entities(raw: &str) -> String {
    raw.replace("&nbsp;", " ")
        .replace("&amp;", "&")
        .replace("&lt;", "<")
        .replace("&gt;", ">")
        .replace("&quot;", "\"")
        .replace("&#39;", "'")
        .replace("&apos;", "'")
}

/// PDF text via the sandboxed CLI tools (plan 5 #32).
///
/// The **same** sandbox as the cover renderer, on purpose: wall timeout,
/// `setrlimit` caps, `kill_on_drop`, and the shared semaphore. Adding a second,
/// weaker shell-out path for text would undo L6 for exactly the files most
/// likely to be hostile.
///
/// Returns the text (possibly empty, which means "reached the tool, the PDF has
/// no text layer") or None when no tool could be run at all.
pub(crate) async fn pdf_text_via_cli(state: &AppState, input: &Path) -> Option<String> {
    let out = state
        .data_dir
        .join(format!(".text-{}.txt", uuid::Uuid::new_v4()));
    let _permit = state.render_semaphore.acquire().await.ok()?;

    // poppler's pdftotext keeps page breaks as form feeds by default, which is
    // how the page numbers survive.
    let mut cmd = std::process::Command::new("pdftotext");
    cmd.arg("-q").arg(input).arg(&out);
    let mut ran = run_render(cmd).await;
    if !ran {
        let _ = tokio::fs::remove_file(&out).await;
        let mut cmd = std::process::Command::new("mutool");
        cmd.args(["draw", "-F", "txt", "-o"]).arg(&out).arg(input);
        ran = run_render(cmd).await;
    }
    drop(_permit);

    let text = tokio::fs::read_to_string(&out).await.ok();
    let _ = tokio::fs::remove_file(&out).await;
    if ran {
        text.or(Some(String::new()))
    } else {
        None
    }
}

/// The substring `<name ...>` for the first element called `name`, or None. The
/// character after the name must end it, so `rootfile` won't match `rootfiles`.
fn find_tag<'a>(xml: &'a str, name: &str) -> Option<&'a str> {
    let needle = format!("<{name}");
    let mut from = 0;
    while let Some(rel) = xml[from..].find(&needle) {
        let start = from + rel;
        let after = start + needle.len();
        let ends = matches!(
            xml.as_bytes().get(after),
            Some(c) if c.is_ascii_whitespace() || *c == b'>' || *c == b'/'
        );
        if ends {
            let rest = &xml[start..];
            return rest.find('>').map(|end| &rest[..end]);
        }
        from = after;
    }
    None
}

/// Every `<item ...>` element tag (not `<itemref>`), as raw substrings.
fn item_tags(opf: &str) -> impl Iterator<Item = &str> {
    opf.match_indices("<item").filter_map(|(i, _)| {
        let rest = &opf[i..];
        // Skip `<itemref>`: the char after "<item" must end the name.
        match rest.as_bytes().get(5) {
            Some(c) if c.is_ascii_whitespace() || *c == b'/' || *c == b'>' => {}
            _ => return None,
        }
        let end = rest.find('>')?;
        Some(&rest[..end])
    })
}

/// The `content` of the first `<meta name="<name>" .../>` element, or None.
fn meta_content<'a>(opf: &'a str, name: &str) -> Option<&'a str> {
    for (i, _) in opf.match_indices("<meta") {
        let rest = &opf[i..];
        let end = match rest.find('>') {
            Some(e) => e,
            None => continue,
        };
        let tag = &rest[..end];
        if tag_attr(tag, "name") == Some(name) {
            return tag_attr(tag, "content");
        }
    }
    None
}

/// Read attribute `name` out of a single element tag substring. Matches a
/// space-delimited `name="value"` (or single-quoted), so it won't match an
/// attribute that merely ends in `name`.
fn tag_attr<'a>(tag: &'a str, name: &str) -> Option<&'a str> {
    let key = format!(" {name}=");
    let at = tag.find(&key)? + key.len();
    let rest = &tag[at..];
    let quote = rest.as_bytes().first().copied()?;
    if quote != b'"' && quote != b'\'' {
        return None;
    }
    let rest = &rest[1..];
    let end = rest.find(quote as char)?;
    Some(&rest[..end])
}

/// Join an EPUB-internal href to its base directory, resolving `.`/`..`. Paths
/// inside an EPUB are always posix.
fn join_posix(base: &str, href: &str) -> String {
    let href = href.split('#').next().unwrap_or(href);
    let combined = if base.is_empty() {
        href.to_string()
    } else {
        format!("{base}/{href}")
    };
    let mut parts: Vec<&str> = Vec::new();
    for seg in combined.split('/') {
        match seg {
            "" | "." => {}
            ".." => {
                parts.pop();
            }
            other => parts.push(other),
        }
    }
    parts.join("/")
}

/// Resource caps applied to each render subprocess before `exec` (Unix only):
/// bound the address space, CPU time, output-file size, and forbid core dumps.
/// These sandbox an attacker-supplied PDF so that even within the 30 s wall
/// timeout it can't drive `gs`/`mutool`/poppler into exhausting host memory or
/// filling the disk. Defence-in-depth alongside `-dSAFER` and the semaphore.
/// See docs/SECURITY_AUDIT.md (L6).
#[cfg(unix)]
fn apply_render_rlimits(cmd: &mut std::process::Command) {
    use std::os::unix::process::CommandExt;
    // SAFETY: the closure runs in the forked child before exec and calls only
    // async-signal-safe `setrlimit`. Failures are ignored — a cap we can't set
    // just isn't applied; the wall timeout still bounds the child.
    unsafe {
        cmd.pre_exec(|| {
            let set = |resource, limit: u64| {
                let rl = libc::rlimit {
                    rlim_cur: limit,
                    rlim_max: limit,
                };
                libc::setrlimit(resource, &rl);
            };
            set(libc::RLIMIT_AS, 1024 * 1024 * 1024); // 1 GiB address space
            set(libc::RLIMIT_CPU, 30); // 30 s CPU time
            set(libc::RLIMIT_FSIZE, 64 * 1024 * 1024); // 64 MiB output file
            set(libc::RLIMIT_CORE, 0); // no core dumps
            Ok(())
        });
    }
}

#[cfg(not(unix))]
fn apply_render_rlimits(_cmd: &mut std::process::Command) {}

/// Run one render command with a hard timeout, reaping the child if it hangs on
/// a pathological PDF. Applies per-process resource caps, then `kill_on_drop`
/// means a timed-out (dropped) child is killed rather than leaked.
async fn run_render(mut cmd: std::process::Command) -> bool {
    apply_render_rlimits(&mut cmd);
    let mut cmd = Command::from(cmd);
    cmd.kill_on_drop(true);
    match tokio::time::timeout(std::time::Duration::from_secs(30), cmd.status()).await {
        Ok(Ok(status)) => status.success(),
        // Timed out (child killed on drop) or failed to spawn.
        _ => false,
    }
}

/// Try each known PDF CLI in turn until one writes a non-empty JPEG.
async fn render_first_page(input: &Path, out_jpg: &Path) -> bool {
    render_page(input, out_jpg, 1).await
}

/// Render page `page` (1-based) of a PDF to a JPEG, trying each known CLI in
/// turn until one writes a non-empty file.
///
/// Generalised from the cover renderer for browser reading (plan 5 #33) — the
/// same sandbox, the same tools, one more argument. A second renderer would
/// mean a second set of resource limits to keep in step with L6.
pub(crate) async fn render_page(input: &Path, out_jpg: &Path, page: u32) -> bool {
    let page = page.max(1);
    let n = page.to_string();
    // poppler: pdftoppm / pdftocairo write "<prefix>.jpg" with -singlefile.
    let prefix = out_jpg.with_extension("");
    for tool in ["pdftoppm", "pdftocairo"] {
        let _ = tokio::fs::remove_file(out_jpg).await;
        let mut cmd = std::process::Command::new(tool);
        cmd.args([
            "-jpeg",
            "-f",
            &n,
            "-l",
            &n,
            "-singlefile",
            "-scale-to",
            "1400",
        ])
        .arg(input)
        .arg(&prefix);
        if run_render(cmd).await && nonempty(out_jpg).await {
            return true;
        }
    }
    // MuPDF: writes exactly to -o.
    let _ = tokio::fs::remove_file(out_jpg).await;
    let mut cmd = std::process::Command::new("mutool");
    cmd.args(["draw", "-F", "jpeg", "-w", "1400", "-o"])
        .arg(out_jpg)
        .arg(input)
        .arg(&n);
    if run_render(cmd).await && nonempty(out_jpg).await {
        return true;
    }
    // Ghostscript. -dSAFER (default since gs 9.50, set explicitly here) blocks
    // file/pipe access from the PostScript/PDF program itself.
    let _ = tokio::fs::remove_file(out_jpg).await;
    let mut cmd = std::process::Command::new("gs");
    cmd.args([
        "-q",
        "-dSAFER",
        "-dBATCH",
        "-dNOPAUSE",
        "-sDEVICE=jpeg",
        &format!("-dFirstPage={n}"),
        &format!("-dLastPage={n}"),
        "-r150",
    ])
    .arg(format!("-sOutputFile={}", out_jpg.display()))
    .arg(input);
    run_render(cmd).await && nonempty(out_jpg).await
}

/// Whether a path exists and has bytes — used by the reader's page cache.
pub(crate) async fn nonempty_file(p: &Path) -> bool {
    nonempty(p).await
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
    let range = headers.get(header::RANGE).and_then(|v| v.to_str().ok());
    let if_range = headers.get(header::IF_RANGE).and_then(|v| v.to_str().ok());
    serve_blob(
        &state,
        &rel,
        Some(format!("\"{sha}\"")),
        inm,
        range,
        if_range,
    )
    .await
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

/// Whether a stored relative blob path is safe to resolve under the data dir: a
/// non-empty *relative* path made only of normal segments — no `..`, no absolute
/// root, no Windows prefix. A defence-in-depth backstop so that even a poisoned
/// `cover_path` row can't turn a blob read into an arbitrary-file read. See
/// docs/SECURITY_AUDIT.md (H1).
/// The MIME type of a sniffed image, or None when the bytes are not an image
/// we recognise. The reader serves EPUB-internal assets through this so a book
/// can never get arbitrary bytes served under a type a browser will execute.
pub(crate) fn image_mime(bytes: &[u8]) -> Option<&'static str> {
    match sniff(bytes) {
        Sniffed::Jpeg => Some("image/jpeg"),
        Sniffed::Png => Some("image/png"),
        Sniffed::Gif => Some("image/gif"),
        Sniffed::WebP => Some("image/webp"),
        _ => None,
    }
}

/// Where a book file with content hash [sha] and extension [ext] lives
/// (plan 5 #9).
///
/// Content-addressed, so the same bytes are stored once no matter how many
/// books or users reference them: `book_file.sha256` was already computed and
/// stored on every upload, so the dedupe key existed and was simply unused.
/// The two-hex-character shard keeps any one directory to a few hundred entries
/// on a large library rather than tens of thousands, which some filesystems
/// handle badly and every `ls` handles badly.
///
/// **Covers deliberately stay keyed by book id.** A cover is one-per-book by
/// construction, so content-addressing them would dedupe only identical art
/// across different books — a small win that would also change `cover_path`,
/// which travels in the sync payload and is validated by
/// `books::validate_cover_path`. Not worth a cross-cutting change.
pub(crate) fn content_addressed_rel(sha: &str, ext: &str) -> String {
    format!("files/{}/{}.{}", &sha[..2], sha, ext)
}

/// Moves every pre-#9 book file into the content-addressed layout.
///
/// A migration can't do this — SQL cannot move files — so it runs once at
/// startup, guarded by a marker in `meta`. Three properties make it safe to
/// run against a live library:
///
/// - **Idempotent.** A path already in the new layout is skipped, so an
///   interrupted run simply continues on the next boot, and the marker is only
///   a shortcut past work that would otherwise be a no-op.
/// - **Rehashes rather than trusting `sha256`.** The stored hash is what the
///   uploader computed; if a blob was ever replaced out of band the two would
///   disagree, and moving the file to a name that lies about its contents would
///   bake that in forever.
/// - **Database last.** The file is copied into place *before* the row is
///   updated, so a crash between the two leaves a duplicate blob (harmless, and
///   the orphan sweep finds it) rather than a row pointing at nothing.
pub async fn backfill_content_addressed(state: &AppState) -> anyhow::Result<u64> {
    let done: Option<String> = sqlx::query_scalar("SELECT value FROM meta WHERE key = ?")
        .bind(BLOB_BACKFILL_KEY)
        .fetch_optional(&state.db)
        .await?;
    if done.is_some() {
        return Ok(0);
    }

    let rows: Vec<(String, String, String)> =
        sqlx::query_as("SELECT id, path, format FROM book_file")
            .fetch_all(&state.db)
            .await?;
    let mut moved = 0u64;
    for (id, rel, format) in rows {
        if is_content_addressed(&rel) || !is_safe_rel(&rel) {
            continue;
        }
        let from = state.data_dir.join(&rel);
        let Ok(bytes) = tokio::fs::read(&from).await else {
            // The row points at nothing; the integrity sweep reports it as a
            // missing file. Leaving the path alone keeps that report honest.
            continue;
        };
        let sha = hex::encode(Sha256::digest(&bytes));
        let ext = if format.is_empty() {
            std::path::Path::new(&rel)
                .extension()
                .and_then(|e| e.to_str())
                .unwrap_or("bin")
                .to_ascii_lowercase()
        } else {
            format.to_ascii_lowercase()
        };
        let new_rel = content_addressed_rel(&sha, &ext);
        let to = state.data_dir.join(&new_rel);
        if let Some(parent) = to.parent() {
            tokio::fs::create_dir_all(parent).await?;
        }
        if tokio::fs::metadata(&to).await.is_err() {
            tokio::fs::rename(&from, &to).await?;
        }
        sqlx::query("UPDATE book_file SET path = ?, sha256 = ? WHERE id = ?")
            .bind(&new_rel)
            .bind(&sha)
            .bind(&id)
            .execute(&state.db)
            .await?;
        // The old file is only removed once nothing points at it: two rows may
        // have shared one pre-#9 blob if it was ever hand-linked.
        if from != to {
            unlink_if_unreferenced(state, &rel).await;
        }
        moved += 1;
    }

    sqlx::query("INSERT OR REPLACE INTO meta (key, value) VALUES (?, ?)")
        .bind(BLOB_BACKFILL_KEY)
        .bind(moved.to_string())
        .execute(&state.db)
        .await?;
    if moved > 0 {
        tracing::info!(moved, "blobs: migrated to the content-addressed layout");
    }
    Ok(moved)
}

const BLOB_BACKFILL_KEY: &str = "blobs.content_addressed";

/// Whether [rel] is one of our own content-addressed file paths.
///
/// Stricter than [`is_safe_rel`], and used when *writing* a path into the
/// database: the traversal guard proves a path can't escape the data dir, this
/// proves it is a blob we minted rather than any other file inside it.
pub(crate) fn is_content_addressed(rel: &str) -> bool {
    let Some(rest) = rel.strip_prefix("files/") else {
        return false;
    };
    let Some((shard, name)) = rest.split_once('/') else {
        return false;
    };
    let Some((sha, ext)) = name.rsplit_once('.') else {
        return false;
    };
    shard.len() == 2
        && sha.len() == 64
        && sha.starts_with(shard)
        && sha
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit())
        && sha.bytes().all(|b| b.is_ascii_hexdigit())
        && !ext.is_empty()
        && ext
            .bytes()
            .all(|b| b.is_ascii_lowercase() || b.is_ascii_digit())
}

/// Whether any row still points at [rel], so a blob is only unlinked when the
/// last reference to it goes (plan 5 #9).
///
/// Content addressing means two books can legitimately share one file on disk;
/// deleting either used to take the bytes with it and silently break the other.
/// Covers are checked too — they are book-id keyed today, but a refcount that
/// only knew about half the tables would be a trap for whoever changes that.
pub(crate) async fn blob_is_referenced(
    db: &sqlx::SqlitePool,
    rel: &str,
    excluding_file_id: Option<&str>,
) -> bool {
    let files: i64 =
        sqlx::query_scalar("SELECT COUNT(*) FROM book_file WHERE path = ? AND id IS NOT ?")
            .bind(rel)
            .bind(excluding_file_id)
            .fetch_one(db)
            .await
            .unwrap_or(0);
    if files > 0 {
        return true;
    }
    let covers: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM book WHERE cover_path = ?")
        .bind(rel)
        .fetch_one(db)
        .await
        .unwrap_or(0);
    covers > 0
}

/// Unlinks [rel] only when nothing references it any more.
pub(crate) async fn unlink_if_unreferenced(state: &AppState, rel: &str) {
    if blob_is_referenced(&state.db, rel, None).await {
        return;
    }
    let _ = tokio::fs::remove_file(state.data_dir.join(rel)).await;
}

pub(crate) fn is_safe_rel(rel: &str) -> bool {
    let p = Path::new(rel);
    !rel.is_empty() && !p.is_absolute() && p.components().all(|c| matches!(c, Component::Normal(_)))
}

/// Resolves a stored relative blob path to an absolute one, refusing anything
/// that would escape the data dir.
///
/// The same defence-in-depth `serve_blob` applies, exposed for callers that
/// read a blob's *bytes* rather than streaming it as a response — today the
/// email attachment path (plan 5 #53).
pub(crate) fn blob_file_path(state: &AppState, rel: &str) -> AppResult<PathBuf> {
    if !is_safe_rel(rel) {
        return Err(AppError::NotFound("blob missing on disk".into()));
    }
    Ok(state.data_dir.join(rel))
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

/// The outcome of interpreting a `Range` header against a known file size.
enum RangeSpec {
    /// No usable single range (absent, multipart, or garbage) — send the whole
    /// file with `200`.
    Full,
    /// A satisfiable inclusive byte range `[start, end]`.
    Partial(u64, u64),
    /// A syntactically valid but out-of-bounds range — answer `416`.
    Unsatisfiable,
}

/// Parse a single `bytes=a-b` / `bytes=a-` / `bytes=-N` (suffix) range. Multipart
/// (comma) and unparseable values degrade to [`RangeSpec::Full`] so the caller
/// just returns the whole body.
fn parse_range(header: &str, total: u64) -> RangeSpec {
    let Some(spec) = header.strip_prefix("bytes=") else {
        return RangeSpec::Full;
    };
    if spec.contains(',') {
        return RangeSpec::Full; // multipart ranges: send the full body
    }
    let Some((a, b)) = spec.split_once('-') else {
        return RangeSpec::Full;
    };
    let (a, b) = (a.trim(), b.trim());
    let (start, end) = if a.is_empty() {
        // Suffix range: the last N bytes.
        let Ok(n) = b.parse::<u64>() else {
            return RangeSpec::Full;
        };
        if n == 0 || total == 0 {
            return RangeSpec::Unsatisfiable;
        }
        (total.saturating_sub(n.min(total)), total - 1)
    } else {
        let Ok(start) = a.parse::<u64>() else {
            return RangeSpec::Full;
        };
        let end = if b.is_empty() {
            total.saturating_sub(1)
        } else {
            match b.parse::<u64>() {
                Ok(e) => e,
                Err(_) => return RangeSpec::Full,
            }
        };
        (start, end)
    };
    if total == 0 || start >= total {
        return RangeSpec::Unsatisfiable;
    }
    let end = end.min(total - 1);
    if start > end {
        return RangeSpec::Unsatisfiable;
    }
    RangeSpec::Partial(start, end)
}

/// Streams a stored blob to the client without reading it all into memory.
///
/// - A matching `If-None-Match` short-circuits to `304 Not Modified`.
/// - A single `Range` header yields `206 Partial Content` (seek + take), so
///   e-readers can resume interrupted downloads and viewers can load lazily; an
///   `If-Range` that doesn't match the ETag makes the range be ignored, and an
///   unsatisfiable range returns `416`. All `200`s advertise `Accept-Ranges`.
async fn serve_blob(
    state: &AppState,
    rel: &str,
    etag: Option<String>,
    if_none_match: Option<&str>,
    range: Option<&str>,
    if_range: Option<&str>,
) -> AppResult<Response> {
    // Never resolve a path that escapes the blob store, whatever the DB holds.
    if !is_safe_rel(rel) {
        return Err(AppError::NotFound("blob missing on disk".into()));
    }
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
    let mut file = tokio::fs::File::open(&full)
        .await
        .map_err(|_| AppError::NotFound("blob missing on disk".into()))?;
    let total = file.metadata().await.ok().map(|m| m.len());
    let ext = Path::new(rel)
        .extension()
        .and_then(|e| e.to_str())
        .unwrap_or("");
    let ctype = content_type_for_ext(ext);

    // A range only applies when the size is known and any If-Range matches our
    // ETag (an If-Range we can't validate means: ignore the range, send full).
    let if_range_ok = match (if_range, etag.as_deref()) {
        (Some(ir), Some(tag)) => ir == tag,
        (Some(_), None) => false,
        (None, _) => true,
    };
    if let (Some(total), Some(range_hdr)) = (total, range)
        && if_range_ok
    {
        match parse_range(range_hdr, total) {
            RangeSpec::Partial(start, end) => {
                use tokio::io::{AsyncReadExt, AsyncSeekExt};
                file.seek(std::io::SeekFrom::Start(start))
                    .await
                    .map_err(|e| AppError::Internal(e.to_string()))?;
                let len = end - start + 1;
                let body = axum::body::Body::from_stream(tokio_util::io::ReaderStream::new(
                    file.take(len),
                ));
                let mut response = Response::new(body);
                *response.status_mut() = StatusCode::PARTIAL_CONTENT;
                let h = response.headers_mut();
                h.insert(header::CONTENT_TYPE, ctype.parse().unwrap());
                h.insert(header::CONTENT_LENGTH, len.into());
                h.insert(
                    header::CONTENT_RANGE,
                    format!("bytes {start}-{end}/{total}").parse().unwrap(),
                );
                h.insert(header::ACCEPT_RANGES, "bytes".parse().unwrap());
                if let Some(etag) = etag {
                    h.insert(header::ETAG, etag.parse().unwrap());
                }
                return Ok(response);
            }
            RangeSpec::Unsatisfiable => {
                let mut response = Response::new(axum::body::Body::empty());
                *response.status_mut() = StatusCode::RANGE_NOT_SATISFIABLE;
                response.headers_mut().insert(
                    header::CONTENT_RANGE,
                    format!("bytes */{total}").parse().unwrap(),
                );
                return Ok(response);
            }
            RangeSpec::Full => {} // fall through to the full body
        }
    }

    let body = axum::body::Body::from_stream(tokio_util::io::ReaderStream::new(file));
    let mut response = Response::new(body);
    let headers = response.headers_mut();
    headers.insert(header::CONTENT_TYPE, ctype.parse().unwrap());
    headers.insert(header::ACCEPT_RANGES, "bytes".parse().unwrap());
    if let Some(len) = total {
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
    fn is_safe_rel_blocks_traversal() {
        // Legitimate server-generated blob paths.
        assert!(is_safe_rel("covers/abc.jpg"));
        assert!(is_safe_rel("covers/thumbs/abc-w160.jpg"));
        assert!(is_safe_rel("files/abc.pdf"));
        // Traversal / absolute / empty must all be rejected.
        assert!(!is_safe_rel("../vellum.db"));
        assert!(!is_safe_rel("covers/../../etc/passwd"));
        assert!(!is_safe_rel("/etc/passwd"));
        assert!(!is_safe_rel(".."));
        assert!(!is_safe_rel(""));
    }

    #[test]
    fn image_ext_maps_only_images() {
        assert_eq!(image_ext(Sniffed::Png), Some("png"));
        assert_eq!(image_ext(Sniffed::Jpeg), Some("jpg"));
        assert_eq!(image_ext(Sniffed::WebP), Some("webp"));
        assert_eq!(image_ext(Sniffed::Pdf), None);
        assert_eq!(image_ext(Sniffed::Unknown), None);
    }

    #[test]
    fn epub_cover_bytes_reads_the_declared_cover() {
        use std::io::Write;
        const CONTAINER: &str = "<?xml version=\"1.0\"?>\
            <container><rootfiles><rootfile full-path=\"content.opf\"/></rootfiles></container>";
        const OPF: &str = "<?xml version=\"1.0\"?>\
            <package version=\"2.0\"><metadata><meta name=\"cover\" content=\"cov\"/></metadata>\
            <manifest><item id=\"cov\" href=\"cover.png\" media-type=\"image/png\"/>\
            <item id=\"c1\" href=\"ch1.xhtml\" media-type=\"application/xhtml+xml\"/></manifest>\
            <spine><itemref idref=\"c1\"/></spine></package>";
        let mut zw = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
        for (name, data) in [
            ("META-INF/container.xml", CONTAINER.as_bytes().to_vec()),
            ("content.opf", OPF.as_bytes().to_vec()),
            ("cover.png", b"\x89PNG\r\n\x1a\n cover".to_vec()),
        ] {
            zw.start_file(name, zip::write::SimpleFileOptions::default())
                .unwrap();
            zw.write_all(&data).unwrap();
        }
        let bytes = zw.finish().unwrap().into_inner();
        let dir = std::env::temp_dir().join(format!("vellum_epub_{}", uuid::Uuid::new_v4()));
        std::fs::create_dir_all(&dir).unwrap();
        let path = dir.join("book.epub");
        std::fs::write(&path, &bytes).unwrap();

        let cover = epub_cover_bytes(&path).expect("cover extracted");
        assert_eq!(sniff(&cover), Sniffed::Png);
        std::fs::remove_dir_all(&dir).ok();
    }
}
