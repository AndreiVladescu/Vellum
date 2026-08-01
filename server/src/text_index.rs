//! Full-text search over book *contents* (plan 5 #32).
//!
//! **Why this lives on the server and nowhere else.** Everything else Vellum
//! does works offline against the local database, on purpose. Indexing the text
//! of a few hundred PDFs does not: it is gigabytes of extraction and an index
//! nobody wants on a phone. So this is the one capability that is genuinely
//! better connected — and the strongest argument for running a server at all.
//!
//! **Opt-in per server** (`VELLUM_INDEX_TEXT=1`). The index is roughly the size
//! of the text it holds, and an operator who only wants sync should not silently
//! start paying for a search engine. When it is off, nothing is extracted, the
//! `content_search` capability is not advertised, and `/api/search` says so.
//!
//! **The queue is the table.** A `book_text` row with `status='pending'` *is*
//! the work item, so a server killed mid-extraction resumes exactly where it
//! stopped, and `POST /api/admin/reindex` is one UPDATE. No channel to lose, no
//! job state in memory.
//!
//! **No OCR, ever.** A scanned PDF records `status='no_text'` — a real outcome,
//! not a failure. Adding tesseract would contradict the single-binary rule the
//! rest of the server is built around.

use axum::Json;
use axum::extract::{Query, State};
use serde::{Deserialize, Serialize};
use std::path::Path;

use crate::AppState;
use crate::auth::AuthUser;
use crate::books::access_predicate;
use crate::error::{AppError, AppResult};

pub const PENDING: &str = "pending";
pub const OK: &str = "ok";
pub const NO_TEXT: &str = "no_text";
pub const FAILED: &str = "failed";
pub const SKIPPED: &str = "skipped";

/// Cap on the text stored per file. A 900-page technical PDF is a few
/// megabytes of text; this bounds a pathological or adversarial file without
/// truncating anything anyone would actually search.
const MAX_TEXT_BYTES: usize = 24 * 1024 * 1024;

/// Cap on the number of page/section rows per file, for the same reason.
const MAX_PAGES: usize = 5000;

/// One extracted page (or, for an EPUB, one spine section).
pub struct ExtractedPage {
    pub page: i64,
    pub body: String,
}

pub struct Extraction {
    pub status: &'static str,
    pub pages: Vec<ExtractedPage>,
}

/// Marks a file as needing extraction. Idempotent: re-uploading or re-indexing
/// simply puts the row back to `pending`.
pub async fn enqueue(state: &AppState, file_id: &str, book_id: &str) {
    if !state.index_text {
        return;
    }
    let _ = sqlx::query(
        "INSERT INTO book_text (file_id, book_id, status, extracted_at) \
         VALUES (?, ?, ?, datetime('now')) \
         ON CONFLICT(file_id) DO UPDATE SET status = excluded.status, \
             book_id = excluded.book_id, extracted_at = excluded.extracted_at",
    )
    .bind(file_id)
    .bind(book_id)
    .bind(PENDING)
    .execute(&state.db)
    .await;
    state.text_notify.notify_one();
}

/// Queues every file that has no `book_text` row yet.
///
/// Called at startup, which is what makes turning the feature on retroactive:
/// a server that ran for a year without indexing catches up on the next boot
/// rather than only indexing what is uploaded from now on.
pub async fn enqueue_missing(state: &AppState) -> AppResult<u64> {
    let result = sqlx::query(
        "INSERT INTO book_text (file_id, book_id, status, extracted_at) \
         SELECT f.id, f.book_id, ?, datetime('now') FROM book_file f \
         WHERE NOT EXISTS (SELECT 1 FROM book_text t WHERE t.file_id = f.id)",
    )
    .bind(PENDING)
    .execute(&state.db)
    .await?;
    state.text_notify.notify_one();
    Ok(result.rows_affected())
}

/// The background worker. Runs forever; spawned once at startup.
///
/// One file at a time, deliberately: extraction is CPU- and IO-heavy and this
/// must never compete with serving requests. The wait is a `Notify` plus a
/// slow poll, so an upload is indexed within moments while an idle server does
/// nothing.
pub async fn run_worker(state: AppState) {
    loop {
        match take_next(&state).await {
            Ok(Some((file_id, book_id))) => {
                index_one(&state, &file_id, &book_id).await;
            }
            Ok(None) => {
                // Nothing to do: sleep until an upload wakes us, or until the
                // slow poll catches work a missed notification left behind.
                tokio::select! {
                    _ = state.text_notify.notified() => {}
                    _ = tokio::time::sleep(std::time::Duration::from_secs(60)) => {}
                }
            }
            Err(e) => {
                tracing::warn!("text index: queue read failed: {e:?}");
                tokio::time::sleep(std::time::Duration::from_secs(30)).await;
            }
        }
    }
}

/// Processes everything currently queued, then returns.
///
/// The worker's loop body, minus the loop — so a test (and `reindex`'s caller)
/// can index deterministically instead of sleeping and hoping. Bounded so a
/// bug that re-queues a file can't spin forever.
pub async fn drain(state: &AppState) -> usize {
    let mut done = 0;
    while let Ok(Some((file_id, book_id))) = take_next(state).await {
        index_one(state, &file_id, &book_id).await;
        done += 1;
        if done > 10_000 {
            break;
        }
    }
    done
}

async fn take_next(state: &AppState) -> AppResult<Option<(String, String)>> {
    Ok(sqlx::query_as::<_, (String, String)>(
        "SELECT file_id, book_id FROM book_text WHERE status = ? LIMIT 1",
    )
    .bind(PENDING)
    .fetch_optional(&state.db)
    .await?)
}

/// Extracts and indexes one file, then records its outcome.
pub async fn index_one(state: &AppState, file_id: &str, book_id: &str) {
    let row: Option<(String, String)> =
        sqlx::query_as("SELECT path, format FROM book_file WHERE id = ?")
            .bind(file_id)
            .fetch_optional(&state.db)
            .await
            .ok()
            .flatten();
    let Some((rel_path, format)) = row else {
        // The file vanished between enqueue and now (a delete raced us). Drop
        // the queue entry rather than retrying it forever.
        let _ = sqlx::query("DELETE FROM book_text WHERE file_id = ?")
            .bind(file_id)
            .execute(&state.db)
            .await;
        return;
    };

    let path = state.data_dir.join(&rel_path);
    let extraction = extract(state, &path, &format).await;

    let mut tx = match crate::write_tx(&state.db).await {
        Ok(tx) => tx,
        Err(e) => {
            tracing::warn!("text index: {file_id}: {e}");
            return;
        }
    };
    // Replace, never append: re-indexing a file must not double every hit.
    let _ = sqlx::query("DELETE FROM book_text_fts WHERE file_id = ?")
        .bind(file_id)
        .execute(&mut *tx)
        .await;
    for page in &extraction.pages {
        let _ = sqlx::query(
            "INSERT INTO book_text_fts (body, page, file_id, book_id) VALUES (?, ?, ?, ?)",
        )
        .bind(&page.body)
        .bind(page.page)
        .bind(file_id)
        .bind(book_id)
        .execute(&mut *tx)
        .await;
    }
    let _ = sqlx::query(
        "UPDATE book_text SET status = ?, pages = ?, extracted_at = datetime('now') \
         WHERE file_id = ?",
    )
    .bind(extraction.status)
    .bind(extraction.pages.len() as i64)
    .bind(file_id)
    .execute(&mut *tx)
    .await;
    if let Err(e) = tx.commit().await {
        tracing::warn!("text index: {file_id}: {e}");
    }
}

/// Pulls the text out of one file.
pub async fn extract(state: &AppState, path: &Path, format: &str) -> Extraction {
    match format {
        "epub" => {
            let owned = path.to_path_buf();
            // Zip + string work is blocking; keep it off the async runtime.
            tokio::task::spawn_blocking(move || extract_epub(&owned))
                .await
                .unwrap_or(Extraction {
                    status: FAILED,
                    pages: Vec::new(),
                })
        }
        "pdf" => extract_pdf(state, path).await,
        _ => Extraction {
            status: SKIPPED,
            pages: Vec::new(),
        },
    }
}

/// EPUB text, in spine order.
///
/// An EPUB has no pages, so `page` is the **1-based spine position** — the
/// chapter you'd land in. Pretending to know a page number for a reflowable
/// format would be a lie the reader can't act on.
fn extract_epub(path: &Path) -> Extraction {
    let Some(sections) = crate::blobs::epub_section_texts(path) else {
        return Extraction {
            status: FAILED,
            pages: Vec::new(),
        };
    };
    let mut pages = Vec::new();
    let mut total = 0usize;
    for (i, text) in sections.into_iter().enumerate() {
        if text.trim().is_empty() {
            continue;
        }
        total += text.len();
        pages.push(ExtractedPage {
            page: i as i64 + 1,
            body: text,
        });
        if total > MAX_TEXT_BYTES || pages.len() >= MAX_PAGES {
            break;
        }
    }
    Extraction {
        status: if pages.is_empty() { NO_TEXT } else { OK },
        pages,
    }
}

/// PDF text: `lopdf` first, then the sandboxed CLI fallback.
///
/// `lopdf` is pure Rust and needs no external tool, but it gives up on plenty
/// of real-world PDFs (unusual encodings, compressed object streams it can't
/// follow). Rather than add a second, weaker shell-out, the fallback reuses the
/// **same sandbox as the cover renderer** (L6): wall timeout, `setrlimit` caps,
/// and the shared semaphore that stops ten uploads forking ten processes.
async fn extract_pdf(state: &AppState, path: &Path) -> Extraction {
    let owned = path.to_path_buf();
    let native = tokio::task::spawn_blocking(move || pdf_text_lopdf(&owned))
        .await
        .unwrap_or_default();
    if let Some(pages) = native
        && !pages.is_empty()
    {
        return Extraction { status: OK, pages };
    }

    match crate::blobs::pdf_text_via_cli(state, path).await {
        Some(text) if !text.trim().is_empty() => Extraction {
            status: OK,
            // The CLI tools separate pages with a form feed, which is how the
            // page numbers survive the round trip through a text file.
            pages: split_form_feeds(&text),
        },
        // Reached the tools and got nothing: a scanned PDF, which is a real,
        // reportable state rather than an error.
        Some(_) => Extraction {
            status: NO_TEXT,
            pages: Vec::new(),
        },
        None => Extraction {
            status: FAILED,
            pages: Vec::new(),
        },
    }
}

fn split_form_feeds(text: &str) -> Vec<ExtractedPage> {
    let mut pages = Vec::new();
    let mut total = 0usize;
    for (i, chunk) in text.split('\u{c}').enumerate() {
        if chunk.trim().is_empty() {
            continue;
        }
        total += chunk.len();
        pages.push(ExtractedPage {
            page: i as i64 + 1,
            body: chunk.to_string(),
        });
        if total > MAX_TEXT_BYTES || pages.len() >= MAX_PAGES {
            break;
        }
    }
    pages
}

fn pdf_text_lopdf(path: &Path) -> Option<Vec<ExtractedPage>> {
    let doc = lopdf::Document::load(path).ok()?;
    let mut pages = Vec::new();
    let mut total = 0usize;
    for (number, _) in doc.get_pages() {
        let Ok(text) = doc.extract_text(&[number]) else {
            continue;
        };
        if text.trim().is_empty() {
            continue;
        }
        total += text.len();
        pages.push(ExtractedPage {
            page: number as i64,
            body: text,
        });
        if total > MAX_TEXT_BYTES || pages.len() >= MAX_PAGES {
            break;
        }
    }
    Some(pages)
}

// ---- search ---------------------------------------------------------------

#[derive(Deserialize)]
pub struct SearchQuery {
    pub q: String,
    pub limit: Option<i64>,
}

#[derive(Serialize, sqlx::FromRow)]
pub struct SearchHit {
    pub book_id: String,
    pub title: String,
    pub file_id: String,
    pub page: i64,
    /// The matching text with `[` … `]` around the hit, from FTS5's `snippet()`.
    pub snippet: String,
}

/// Turns what a person typed into an FTS5 MATCH expression.
///
/// Raw user text cannot go into MATCH: `foo AND` or a stray quote is a syntax
/// error, and FTS5's operators would let a search string mean something the
/// person did not type. So every run of word characters becomes one quoted
/// term, the terms are ANDed, and the last one gets a `*` so results narrow as
/// you type rather than appearing only on the final keystroke.
pub fn to_match_expression(raw: &str) -> Option<String> {
    let terms: Vec<String> = raw
        .split(|c: char| !c.is_alphanumeric())
        .filter(|t| !t.is_empty())
        .take(16)
        .map(|t| t.to_lowercase())
        .collect();
    if terms.is_empty() {
        return None;
    }
    let last = terms.len() - 1;
    Some(
        terms
            .iter()
            .enumerate()
            .map(|(i, t)| {
                if i == last {
                    format!("\"{t}\"*")
                } else {
                    format!("\"{t}\"")
                }
            })
            .collect::<Vec<_>>()
            .join(" AND "),
    )
}

pub async fn search(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<SearchQuery>,
) -> AppResult<Json<serde_json::Value>> {
    if !state.index_text {
        return Err(AppError::BadRequest(
            "content search is not enabled on this server".into(),
        ));
    }
    let Some(expression) = to_match_expression(&q.q) else {
        return Ok(Json(serde_json::json!({ "hits": [] })));
    };
    let limit = q.limit.unwrap_or(30).clamp(1, 200);

    // RBAC exactly as `/api/books`: the index is joined back to `book` and
    // filtered by the same predicate, so a hit can never reveal the contents of
    // a book the caller cannot see.
    let sql = format!(
        "SELECT f.book_id AS book_id, b.title AS title, f.file_id AS file_id, \
                f.page AS page, snippet(book_text_fts, 0, '[', ']', '…', 12) AS snippet \
         FROM book_text_fts f \
         JOIN book b ON b.id = f.book_id \
         WHERE book_text_fts MATCH ? AND {} \
         ORDER BY rank LIMIT ?",
        access_predicate()
    );
    let hits = sqlx::query_as::<_, SearchHit>(sqlx::AssertSqlSafe(sql.as_str()))
        .bind(&expression)
        .bind(&user.id)
        .bind(user.is_master)
        .bind(&user.id)
        .bind(limit)
        .fetch_all(&state.db)
        .await?;

    Ok(Json(serde_json::json!({ "query": q.q, "hits": hits })))
}

/// `POST /api/admin/reindex` — master-only. Puts every file back in the queue.
///
/// Cheap and idempotent by construction: it is an UPDATE, the worker does the
/// rest, and running it twice re-extracts rather than duplicating, because
/// `index_one` deletes a file's rows before inserting.
pub async fn reindex(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<serde_json::Value>> {
    if !user.is_master {
        return Err(AppError::Forbidden(
            "only the master account may reindex".into(),
        ));
    }
    if !state.index_text {
        return Err(AppError::BadRequest(
            "content search is not enabled on this server".into(),
        ));
    }
    let queued = enqueue_missing(&state).await?;
    let reset = sqlx::query("UPDATE book_text SET status = ?")
        .bind(PENDING)
        .execute(&state.db)
        .await?
        .rows_affected();
    state.text_notify.notify_one();
    Ok(Json(serde_json::json!({
        "queued": queued,
        "pending": reset,
    })))
}

/// `GET /api/search/status` — how much of the library is indexed, so the
/// console can say "still working" instead of "no results".
pub async fn status(
    State(state): State<AppState>,
    _user: AuthUser,
) -> AppResult<Json<serde_json::Value>> {
    if !state.index_text {
        return Ok(Json(serde_json::json!({ "enabled": false })));
    }
    let rows: Vec<(String, i64)> =
        sqlx::query_as("SELECT status, COUNT(*) FROM book_text GROUP BY status")
            .fetch_all(&state.db)
            .await?;
    let mut counts = serde_json::Map::new();
    for (status, count) in rows {
        counts.insert(status, serde_json::json!(count));
    }
    Ok(Json(serde_json::json!({
        "enabled": true,
        "counts": counts,
    })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_plain_query_becomes_anded_quoted_terms_with_a_prefix() {
        assert_eq!(
            to_match_expression("levenshtein distance"),
            Some("\"levenshtein\" AND \"distance\"*".to_string())
        );
    }

    #[test]
    fn fts_operators_in_user_text_are_neutralised() {
        // The bug this prevents: `foo AND` or `"` reaching MATCH is a syntax
        // error, and OR/NEAR would silently mean something the user didn't type.
        assert_eq!(
            to_match_expression("foo AND"),
            Some("\"foo\" AND \"and\"*".to_string())
        );
        assert_eq!(
            to_match_expression("a \" OR b"),
            Some("\"a\" AND \"or\" AND \"b\"*".to_string())
        );
        assert_eq!(
            to_match_expression("NEAR(x y)"),
            Some("\"near\" AND \"x\" AND \"y\"*".to_string())
        );
    }

    #[test]
    fn punctuation_only_queries_match_nothing_rather_than_erroring() {
        assert_eq!(to_match_expression("   "), None);
        assert_eq!(to_match_expression("*&^%"), None);
    }

    #[test]
    fn very_long_queries_are_bounded() {
        let raw = (0..50)
            .map(|i| format!("w{i}"))
            .collect::<Vec<_>>()
            .join(" ");
        let expression = to_match_expression(&raw).unwrap();
        assert_eq!(expression.matches(" AND ").count(), 15);
    }

    #[test]
    fn form_feeds_become_page_numbers() {
        let pages = split_form_feeds("one\u{c}two\u{c}\u{c}four");
        assert_eq!(pages.len(), 3);
        assert_eq!(pages[0].page, 1);
        assert_eq!(pages[1].page, 2);
        // An empty page is skipped but does not shift the numbering after it —
        // a hit that names page 4 has to be on page 4.
        assert_eq!(pages[2].page, 4);
        assert_eq!(pages[2].body, "four");
    }
}
