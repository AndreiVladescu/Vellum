//! Request ids, request logging, and a stats endpoint (plan 5 #37).
//!
//! The problem this solves: when a sync misbehaves in the field, the app reports
//! a `SyncIssue` and the server writes a log line, and nothing connects the two.
//! Every response now carries an `X-Request-Id` — echoed from the caller when it
//! supplies one, generated otherwise — which appears in the log line *and* in the
//! body of an error, so a user can paste one string into an issue and the
//! operator can find the request.
//!
//! Written as a small middleware rather than `tower-http`'s `TraceLayer`: the
//! whole job is one header, one span and one log line, and this server keeps its
//! dependency surface deliberately small (see the in-house EPUB parser for the
//! same trade-off).

use axum::Json;
use axum::body::Body;
use axum::extract::{Request, State};
use axum::http::{HeaderName, HeaderValue};
use axum::middleware::Next;
use axum::response::{IntoResponse, Response};
use serde::Serialize;
use tracing::Instrument;

use crate::AppState;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};

pub const REQUEST_ID_HEADER: HeaderName = HeaderName::from_static("x-request-id");

/// Bodies larger than this are never rewritten to carry the request id. Error
/// bodies are a few dozen bytes; the cap exists so a surprising response can't
/// be buffered into memory.
const MAX_REWRITTEN_BODY: usize = 8 * 1024;

/// Attaches a request id, logs the request, and echoes the id back.
///
/// An inbound `X-Request-Id` is trusted only as far as *correlation* — it is
/// sanitised to a bounded, printable string before being logged, so a hostile
/// client can't inject newlines into the log or unbounded junk into memory.
pub async fn request_id(request: Request, next: Next) -> Response {
    let id = request
        .headers()
        .get(REQUEST_ID_HEADER)
        .and_then(|v| v.to_str().ok())
        .map(sanitize_request_id)
        .filter(|s| !s.is_empty())
        .unwrap_or_else(|| uuid::Uuid::new_v4().to_string());

    let method = request.method().clone();
    let path = redact_path(request.uri().path());
    let started = std::time::Instant::now();

    let span = tracing::info_span!("request", %method, path = %path, request_id = %id);

    // `.instrument(span)` rather than `span.enter()`: a guard is dropped at the
    // first `.await`, so entering the span here would attach the request id only
    // to handlers that never yield — i.e. to everything except the slow requests
    // this exists to diagnose. (Observed exactly that before the fix: /health
    // carried the id, every request that touched the database did not.)
    let response = async move {
        let response = next.run(request).await;
        let elapsed = started.elapsed();
        let status = response.status();

        // One line per request, at a level that matches the outcome: a 500 in a
        // personal server's log should stand out without turning on debug
        // logging.
        if status.is_server_error() {
            tracing::error!(%status, ms = elapsed.as_millis(), "{method} {path}");
        } else if status.is_client_error() {
            tracing::warn!(%status, ms = elapsed.as_millis(), "{method} {path}");
        } else {
            tracing::info!(%status, ms = elapsed.as_millis(), "{method} {path}");
        }
        response
    }
    .instrument(span)
    .await;
    let status = response.status();

    let mut response = if status.is_client_error() || status.is_server_error() {
        with_request_id_in_body(response, &id).await
    } else {
        response
    };
    if let Ok(value) = HeaderValue::from_str(&id) {
        response.headers_mut().insert(REQUEST_ID_HEADER, value);
    }
    response
}

/// Replaces secret path segments before a path is logged.
///
/// Some URLs *are* credentials: a password-reset link and a public share link
/// both carry a token in the path, and logging them verbatim would put a live
/// secret in a file that gets tailed, shipped and pasted into issues. (This is
/// the same class as L1 in `docs/SECURITY_AUDIT.md`, which is about `?token=` in
/// query strings — the request logger must not reintroduce it in the path.)
///
/// The *shape* of the request is kept, because that is what the log is for.
fn redact_path(path: &str) -> String {
    // (prefix, how many segments to keep after it)
    const SECRET_PREFIXES: [&str; 3] = ["/reset/", "/p/", "/api/public/"];
    for prefix in SECRET_PREFIXES {
        if let Some(rest) = path.strip_prefix(prefix) {
            // Keep any trailing sub-path (e.g. `/file`), drop only the token.
            let tail = rest.split_once('/').map(|(_, tail)| tail).unwrap_or("");
            return if tail.is_empty() {
                format!("{prefix}<redacted>")
            } else {
                format!("{prefix}<redacted>/{tail}")
            };
        }
    }
    path.to_string()
}

/// Keeps an inbound id usable as a log field: printable ASCII only, bounded.
fn sanitize_request_id(raw: &str) -> String {
    raw.chars()
        .filter(|c| c.is_ascii_alphanumeric() || matches!(c, '-' | '_' | '.'))
        .take(64)
        .collect()
}

/// Adds `"request_id"` to a JSON error body, so the id is in the thing users
/// actually copy — a header is invisible in an app's error message.
async fn with_request_id_in_body(response: Response, id: &str) -> Response {
    let (mut parts, body) = response.into_parts();
    let bytes = match axum::body::to_bytes(body, MAX_REWRITTEN_BODY).await {
        Ok(bytes) => bytes,
        // Too big or unreadable: hand back an empty body rather than losing the
        // status. The header still carries the id.
        Err(_) => return (parts, Body::empty()).into_response(),
    };
    let rewritten = serde_json::from_slice::<serde_json::Value>(&bytes)
        .ok()
        .and_then(|mut json| {
            let object = json.as_object_mut()?;
            object.insert("request_id".into(), serde_json::json!(id));
            serde_json::to_vec(&json).ok()
        });
    match rewritten {
        Some(body) => {
            // The length changed; a stale Content-Length would truncate it.
            parts.headers.remove(axum::http::header::CONTENT_LENGTH);
            (parts, Body::from(body)).into_response()
        }
        None => (parts, Body::from(bytes)).into_response(),
    }
}

#[derive(Serialize)]
pub struct ServerStats {
    pub books: i64,
    pub authors: i64,
    pub users: i64,
    pub files: i64,
    pub shares: i64,
    pub share_links: i64,
    /// Bytes on disk under the data directory (covers + book files).
    pub blob_bytes: u64,
    /// Bytes of the SQLite database itself, WAL sidecars included.
    pub database_bytes: u64,
    pub server_version: &'static str,
}

/// `GET /api/admin/stats` — what the console's dashboard shows.
///
/// Master-only: counts of other people's shares and accounts are not a member's
/// business, and this is the kind of endpoint that quietly becomes an
/// information leak if it is left open.
pub async fn stats(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<ServerStats>> {
    if !user.is_master {
        return Err(AppError::Forbidden("master only".into()));
    }

    async fn count(db: &sqlx::SqlitePool, table: &str) -> AppResult<i64> {
        Ok(sqlx::query_scalar(&format!("SELECT COUNT(*) FROM {table}"))
            .fetch_one(db)
            .await?)
    }

    Ok(Json(ServerStats {
        books: count(&state.db, "book").await?,
        authors: count(&state.db, "author").await?,
        users: count(&state.db, "app_user").await?,
        files: count(&state.db, "book_file").await?,
        shares: count(&state.db, "share").await?,
        share_links: count(&state.db, "share_link").await?,
        blob_bytes: directory_size(&state.data_dir).await,
        database_bytes: database_size().await,
        server_version: env!("CARGO_PKG_VERSION"),
    }))
}

/// Recursive size of a directory, best-effort: an unreadable entry contributes
/// zero rather than failing the whole endpoint.
async fn directory_size(root: &std::path::Path) -> u64 {
    let mut total = 0;
    let mut stack = vec![root.to_path_buf()];
    while let Some(dir) = stack.pop() {
        let Ok(mut entries) = tokio::fs::read_dir(&dir).await else {
            continue;
        };
        while let Ok(Some(entry)) = entries.next_entry().await {
            match entry.file_type().await {
                Ok(kind) if kind.is_dir() => stack.push(entry.path()),
                Ok(_) => {
                    if let Ok(meta) = entry.metadata().await {
                        total += meta.len();
                    }
                }
                Err(_) => continue,
            }
        }
    }
    total
}

/// Size of the database file plus its WAL sidecars — in WAL mode the `-wal` file
/// is part of the database, and reporting only the `.db` understates it, often by
/// a lot right after a big import.
async fn database_size() -> u64 {
    let base = std::env::var("VELLUM_DB").unwrap_or_else(|_| "vellum.db".into());
    let mut total = 0;
    for suffix in ["", "-wal", "-shm"] {
        if let Ok(meta) = tokio::fs::metadata(format!("{base}{suffix}")).await {
            total += meta.len();
        }
    }
    total
}

#[cfg(test)]
mod tests {
    use super::redact_path;

    #[test]
    fn secret_bearing_paths_are_redacted() {
        // These tokens are credentials for as long as they live; a log line is
        // not a place to keep one.
        assert_eq!(redact_path("/reset/abc123"), "/reset/<redacted>");
        assert_eq!(redact_path("/p/sharetoken"), "/p/<redacted>");
        assert_eq!(
            redact_path("/api/public/sharetoken"),
            "/api/public/<redacted>"
        );
        // The shape of the request survives — that is what the log is for.
        assert_eq!(
            redact_path("/api/public/sharetoken/file"),
            "/api/public/<redacted>/file"
        );
    }

    #[test]
    fn ordinary_paths_are_untouched() {
        assert_eq!(redact_path("/api/books"), "/api/books");
        assert_eq!(redact_path("/api/books/abc/cover"), "/api/books/abc/cover");
        assert_eq!(redact_path("/health"), "/health");
    }
}
