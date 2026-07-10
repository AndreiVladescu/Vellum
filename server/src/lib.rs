//! Vellum sync server as a library, so integration tests in `tests/` can build
//! the same router the binary serves. `main.rs` is a thin wrapper over this.

use std::path::PathBuf;

use axum::Router;
use axum::extract::DefaultBodyLimit;
use axum::handler::Handler;
use axum::routing::{delete, get, post, put};
use sqlx::sqlite::{SqliteConnectOptions, SqlitePool, SqlitePoolOptions};

mod access;
mod auth;
mod blobs;
mod books;
mod discover;
mod error;
mod groups;
mod metadata;
mod opds;
mod shares;
mod throttle;
mod web;

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

/// Build the full application router.
pub fn router(state: AppState) -> Router {
    let max_upload = state.max_upload_bytes;
    Router::new()
        .route("/health", get(health))
        // Web admin console + public landing page.
        .route("/", get(web::console))
        .route("/p/{token}", get(web::public_page))
        .route("/api/memberships", get(web::memberships))
        // Accounts & sessions.
        .route("/api/auth/register", post(auth::register))
        .route("/api/auth/login", post(auth::login))
        .route("/api/auth/logout", post(auth::logout))
        .route("/api/auth/me", get(auth::me))
        .route("/api/users", get(auth::list_users).post(auth::create_user))
        // Online metadata search + add a chosen result.
        .route("/api/metadata/search", get(discover::search))
        .route("/api/metadata/analyze", post(discover::analyze))
        .route("/api/books/from-search", post(discover::add_from_search))
        .route("/api/books/{id}/enrich", post(discover::enrich))
        // Books (visibility-filtered by RBAC).
        .route("/api/deletions", get(books::deletions))
        .route("/api/books", get(books::list).post(books::create))
        .route(
            "/api/books/{id}",
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
            "/api/books/{id}/cover",
            put(blobs::put_cover.layer(DefaultBodyLimit::max(32 * 1024 * 1024)))
                .get(blobs::get_cover),
        )
        .route(
            "/api/books/{id}/files",
            get(blobs::list_files)
                .post(blobs::upload_file.layer(DefaultBodyLimit::max(max_upload))),
        )
        .route("/api/files/{file_id}", get(blobs::download_file))
        // Book groups.
        .route("/api/groups", get(groups::list).post(groups::create))
        .route("/api/groups/{id}", get(groups::get).delete(groups::delete))
        .route("/api/groups/{id}/books", post(groups::add_book))
        .route(
            "/api/groups/{id}/books/{book_id}",
            delete(groups::remove_book),
        )
        // User-to-user shares.
        .route("/api/shares", get(shares::list).post(shares::create))
        .route("/api/shares/{id}", delete(shares::delete))
        // Public per-book links (no account required to read).
        .route(
            "/api/share-links",
            get(shares::list_links).post(shares::create_link),
        )
        .route("/api/share-links/{id}", delete(shares::delete_link))
        .route("/api/public/{token}", get(shares::public_book))
        .route("/api/public/{token}/file", get(shares::public_file))
        // OPDS catalog for third-party e-readers (HTTP Basic auth).
        .route("/opds", get(opds::feed))
        // Book detail (metadata + authors + genres + files) for the console.
        .route("/api/books/{id}/detail", get(books::detail))
        .with_state(state)
}

async fn health() -> &'static str {
    "ok"
}
