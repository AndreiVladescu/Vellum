//! Vellum sync server as a library, so integration tests in `tests/` can build
//! the same router the binary serves. `main.rs` is a thin wrapper over this.

use std::path::PathBuf;

use axum::extract::DefaultBodyLimit;
use axum::routing::{delete, get, post, put};
use axum::Router;
use sqlx::sqlite::{SqliteConnectOptions, SqlitePool, SqlitePoolOptions};

mod access;
mod auth;
mod blobs;
mod books;
mod error;
mod groups;
mod shares;

/// Largest blob (book file) the server accepts in one upload.
const MAX_UPLOAD_BYTES: usize = 256 * 1024 * 1024;

/// Shared handler state: the database pool, the base URL used to build public
/// share links (`VELLUM_PUBLIC_URL`), and the directory holding cover/file
/// blobs (`VELLUM_DATA_DIR`).
#[derive(Clone)]
pub struct AppState {
    pub db: SqlitePool,
    pub public_base_url: String,
    pub data_dir: PathBuf,
}

/// Open (creating if missing) the SQLite database at `path` and run migrations.
pub async fn connect_db(path: &str) -> anyhow::Result<SqlitePool> {
    let options = SqliteConnectOptions::new()
        .filename(path)
        .create_if_missing(true)
        .foreign_keys(true);
    let db = SqlitePoolOptions::new().connect_with(options).await?;
    sqlx::migrate!().run(&db).await?;
    Ok(db)
}

/// Build the full application router.
pub fn router(state: AppState) -> Router {
    Router::new()
        .route("/health", get(health))
        // Accounts & sessions.
        .route("/api/auth/register", post(auth::register))
        .route("/api/auth/login", post(auth::login))
        .route("/api/auth/me", get(auth::me))
        .route("/api/users", get(auth::list_users).post(auth::create_user))
        // Books (visibility-filtered by RBAC).
        .route("/api/books", get(books::list).post(books::create))
        .route(
            "/api/books/{id}",
            get(books::get).patch(books::update).delete(books::delete),
        )
        // Cover images and book files (filesystem-backed blobs).
        .route(
            "/api/books/{id}/cover",
            put(blobs::put_cover).get(blobs::get_cover),
        )
        .route(
            "/api/books/{id}/files",
            get(blobs::list_files).post(blobs::upload_file),
        )
        .route("/api/files/{file_id}", get(blobs::download_file))
        // Book groups.
        .route("/api/groups", get(groups::list).post(groups::create))
        .route("/api/groups/{id}", get(groups::get).delete(groups::delete))
        .route("/api/groups/{id}/books", post(groups::add_book))
        .route("/api/groups/{id}/books/{book_id}", delete(groups::remove_book))
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
        .layer(DefaultBodyLimit::max(MAX_UPLOAD_BYTES))
        .with_state(state)
}

async fn health() -> &'static str {
    "ok"
}
