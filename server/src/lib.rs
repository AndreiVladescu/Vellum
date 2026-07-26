//! Vellum sync server as a library, so integration tests in `tests/` can build
//! the same router the binary serves. `main.rs` is a thin wrapper over this.

use std::path::PathBuf;

use axum::Router;
use axum::extract::{DefaultBodyLimit, Request};
use axum::handler::Handler;
use axum::http::HeaderValue;
use axum::http::header::{CONTENT_SECURITY_POLICY, X_CONTENT_TYPE_OPTIONS, X_FRAME_OPTIONS};
use axum::middleware::Next;
use axum::response::Response;
use axum::routing::{delete, get, post, put};
use sqlx::sqlite::{SqliteConnectOptions, SqlitePool, SqlitePoolOptions};

mod access;
mod auth;
mod blobs;
mod books;
mod capabilities;
mod discover;
mod error;
mod groups;
mod loans;
mod metadata;
mod opds;
mod physical_copies;
mod reading;
mod shares;
mod shelves;
mod throttle;
pub mod tls;
mod web;

pub use throttle::RateLimiter;

/// Shared handler state: the database pool, the base URL used to build public
/// share links (`VELLUM_PUBLIC_URL`), and the directory holding cover/file
/// blobs (`VELLUM_DATA_DIR`).
#[derive(Clone)]
pub struct AppState {
    pub db: SqlitePool,
    pub public_base_url: String,
    pub data_dir: PathBuf,
    /// Shared client for outbound metadata lookups (Open Library, Google Books).
    pub http: reqwest::Client,
    /// Largest upload (book file) accepted, in bytes (`VELLUM_MAX_UPLOAD_MB`).
    pub max_upload_bytes: usize,
    /// In-memory failed-login limiter, shared across requests.
    pub throttle: std::sync::Arc<throttle::LoginThrottle>,
    /// Bounds concurrent PDF-cover shell-outs so many parallel uploads can't
    /// fork many `gs`/`mutool` processes at once.
    pub render_semaphore: std::sync::Arc<tokio::sync::Semaphore>,
    /// Short-lived cache of successful Basic-auth verifications, so per-request
    /// OPDS Basic auth doesn't cost an Argon2 verify every time.
    pub basic_cache: std::sync::Arc<auth::BasicAuthCache>,
    /// Per-IP limiter for the unauthenticated public-link endpoints.
    pub public_limiter: std::sync::Arc<throttle::RateLimiter>,
    /// Per-user limiter for outbound metadata search (shared Open Library /
    /// Google Books quota).
    pub search_limiter: std::sync::Arc<throttle::RateLimiter>,
    /// When TLS is on, the served certificate's path + SHA-256 fingerprint, so
    /// the web console can offer it for import into the app. `None` over plain
    /// HTTP (nothing to import).
    pub tls_cert: Option<TlsCertInfo>,
}

/// The active TLS leaf certificate, surfaced to the console's "import
/// certificate" affordance. The certificate is public (presented in every
/// handshake); the private key is never exposed.
#[derive(Clone)]
pub struct TlsCertInfo {
    pub cert_path: PathBuf,
    pub fingerprint: String,
}

/// Open (creating if missing) the SQLite database at `path` and run migrations.
pub async fn connect_db(path: &str) -> anyhow::Result<SqlitePool> {
    let options = SqliteConnectOptions::new()
        .filename(path)
        .create_if_missing(true)
        .foreign_keys(true)
        // WAL lets readers (the console's list, OPDS) run concurrently with a
        // writer (a streaming upload's INSERT); NORMAL sync is the standard WAL
        // pairing (durable except in a narrow power-loss window). A busy timeout
        // turns a transient lock into a short wait instead of a SQLITE_BUSY 500.
        .journal_mode(sqlx::sqlite::SqliteJournalMode::Wal)
        .synchronous(sqlx::sqlite::SqliteSynchronous::Normal)
        .busy_timeout(std::time::Duration::from_secs(5));
    let db = SqlitePoolOptions::new().connect_with(options).await?;
    sqlx::migrate!().run(&db).await?;
    // Drop already-expired sessions so the table doesn't grow without bound.
    sqlx::query("DELETE FROM session WHERE expires_at <= datetime('now')")
        .execute(&db)
        .await?;
    Ok(db)
}

/// Every `/api/*` route, built with paths relative to that prefix (`/books`,
/// not `/api/books`) so it can be `nest`ed under both `/api` (the permanent
/// alias — OPDS entries, the console, and existing public links all embed
/// this form, and it stays valid forever) and `/api/v1` (what new clients
/// should prefer; see `capabilities::get` for the version they're on). Same
/// handlers, zero duplication — this is the only place these routes exist.
fn api_routes(max_upload: usize) -> Router<AppState> {
    Router::new()
        .route("/capabilities", get(capabilities::get))
        .route("/memberships", get(web::memberships))
        // The active TLS certificate (public), for the console's import affordance.
        .route("/cert", get(web::server_cert))
        // Accounts & sessions.
        .route("/auth/register", post(auth::register))
        .route("/auth/login", post(auth::login))
        .route("/auth/logout", post(auth::logout))
        .route("/auth/me", get(auth::me))
        .route("/users", get(auth::list_users).post(auth::create_user))
        // Online metadata search + add a chosen result.
        .route("/metadata/search", get(discover::search))
        .route("/metadata/analyze", post(discover::analyze))
        .route("/books/from-search", post(discover::add_from_search))
        .route("/books/{id}/enrich", post(discover::enrich))
        // Books (visibility-filtered by RBAC).
        .route("/deletions", get(books::deletions))
        .route("/books", get(books::list).post(books::create))
        // Batch metadata push (plan 5 #7): fewer round trips for a large
        // first sync. Shares books::upsert's exact per-book logic.
        .route("/books:batch", post(books::batch_upsert))
        .route(
            "/books/{id}",
            get(books::get)
                .put(books::upsert)
                .patch(books::update)
                .delete(books::delete),
        )
        // Cover images and book files (filesystem-backed blobs). The big upload
        // limit is scoped to just these two write handlers, so every other
        // endpoint — including unauthenticated ones like login — keeps axum's
        // small default and can't be used to buffer gigabytes of body in RAM.
        .route(
            "/books/{id}/cover",
            put(blobs::put_cover.layer(DefaultBodyLimit::max(32 * 1024 * 1024)))
                .get(blobs::get_cover),
        )
        .route(
            "/books/{id}/files",
            get(blobs::list_files)
                .post(blobs::upload_file.layer(DefaultBodyLimit::max(max_upload))),
        )
        .route("/files/{file_id}", get(blobs::download_file))
        // Book groups.
        .route("/groups", get(groups::list).post(groups::create))
        .route("/groups/{id}", get(groups::get).delete(groups::delete))
        .route("/groups/{id}/books", post(groups::add_book))
        .route("/groups/{id}/books/{book_id}", delete(groups::remove_book))
        // Custom shelves (plan 5 #4) — cursor-pull list, id-chosen upsert (a
        // push always sends the whole ordered membership), delete.
        .route("/shelves", get(shelves::list))
        .route(
            "/shelves/{id}",
            put(shelves::upsert).delete(shelves::delete),
        )
        // Physical copies (plan 5 #4) — same cursor-pull/upsert/delete shape
        // as shelves, but no owner of its own (access derives from the book).
        .route("/copies", get(physical_copies::list))
        .route(
            "/copies/{id}",
            put(physical_copies::upsert).delete(physical_copies::delete),
        )
        // Loan history (plan 5 #4, last of the trio) — same shape again.
        .route("/loans", get(loans::list))
        .route("/loans/{id}", put(loans::upsert).delete(loans::delete))
        // Optional cross-device reading position (plan 5 #5). Per-(book, user,
        // device) rows, so there is nothing to merge; DELETE un-publishes one
        // device's rows when the user turns the setting back off.
        .route(
            "/reading-progress",
            get(reading::list).delete(reading::forget_device),
        )
        .route("/reading-progress/{book_id}", put(reading::upsert))
        // User-to-user shares.
        .route("/shares", get(shares::list).post(shares::create))
        .route("/shares/{id}", delete(shares::delete))
        // Public per-book links (no account required to read).
        .route(
            "/share-links",
            get(shares::list_links).post(shares::create_link),
        )
        .route("/share-links/{id}", delete(shares::delete_link))
        .route("/public/{token}", get(shares::public_book))
        .route("/public/{token}/file", get(shares::public_file))
        // Book detail (metadata + authors + genres + files) for the console.
        .route("/books/{id}/detail", get(books::detail))
}

/// Build the full application router.
pub fn router(state: AppState) -> Router {
    let api = api_routes(state.max_upload_bytes);
    Router::new()
        .route("/health", get(health))
        // Web admin console + public landing page.
        .route("/", get(web::console))
        .route("/assets/console.css", get(web::console_css))
        .route("/assets/console.js", get(web::console_js))
        .route("/assets/logo.svg", get(web::logo))
        .route("/favicon.svg", get(web::favicon))
        .route("/p/{token}", get(web::public_page))
        // OPDS catalog for third-party e-readers (HTTP Basic auth) — not
        // versioned: readers have this exact URL saved, it never moves.
        .route("/opds", get(opds::feed))
        .nest("/api", api.clone())
        .nest("/api/v1", api)
        .with_state(state)
        // Baseline security headers on every response (defence in depth for the
        // console/public pages and blob downloads). See docs/SECURITY_AUDIT.md (L3).
        .layer(axum::middleware::from_fn(security_headers))
}

/// A restrictive Content-Security-Policy that still lets the self-hosted console
/// and public landing page work: everything loads from same-origin, images may
/// also be `data:` (inline placeholders) or `blob:` (the console fetches
/// authenticated covers with an `Authorization` header and shows them via an
/// object URL, so the token never rides the URL), and the pages' inline
/// `<style>`/`<script>` (no external/CDN assets) are permitted. `object-src` and
/// framing are denied outright.
const CSP: &str = "default-src 'self'; img-src 'self' data: blob:; \
    style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; \
    object-src 'none'; base-uri 'none'; frame-ancestors 'none'";

/// Adds baseline hardening headers to every response: block MIME-sniffing,
/// forbid framing (clickjacking), and apply the CSP above.
async fn security_headers(req: Request, next: Next) -> Response {
    let mut res = next.run(req).await;
    let h = res.headers_mut();
    h.insert(X_CONTENT_TYPE_OPTIONS, HeaderValue::from_static("nosniff"));
    h.insert(X_FRAME_OPTIONS, HeaderValue::from_static("DENY"));
    h.insert(CONTENT_SECURITY_POLICY, HeaderValue::from_static(CSP));
    res
}

async fn health() -> &'static str {
    "ok"
}
