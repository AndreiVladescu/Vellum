use std::net::SocketAddr;

use axum::routing::{delete, get, post};
use axum::Router;
use sqlx::sqlite::{SqliteConnectOptions, SqlitePool, SqlitePoolOptions};

mod access;
mod auth;
mod books;
mod error;
mod groups;
mod shares;

/// Shared handler state: the database pool and the base URL used to build public
/// share links (override with `VELLUM_PUBLIC_URL`).
#[derive(Clone)]
pub struct AppState {
    pub db: SqlitePool,
    pub public_base_url: String,
}

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();

    let db_path = std::env::var("VELLUM_DB").unwrap_or_else(|_| "vellum.db".into());
    let options = SqliteConnectOptions::new()
        .filename(&db_path)
        .create_if_missing(true)
        .foreign_keys(true);
    let db = SqlitePoolOptions::new().connect_with(options).await?;
    sqlx::migrate!().run(&db).await?;

    let public_base_url = std::env::var("VELLUM_PUBLIC_URL")
        .unwrap_or_else(|_| "http://localhost:3000".into());

    let state = AppState { db, public_base_url };

    let app = Router::new()
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
        .with_state(state);

    let port: u16 = std::env::var("VELLUM_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(3000);
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("vellum-server listening on http://{addr} (db: {db_path})");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

async fn health() -> &'static str {
    "ok"
}
