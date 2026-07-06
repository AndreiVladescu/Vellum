use std::net::SocketAddr;

use axum::{Json, Router, extract::State, routing::get};
use serde::Serialize;
use sqlx::sqlite::{SqliteConnectOptions, SqlitePool, SqlitePoolOptions};

#[derive(Clone)]
struct AppState {
    db: SqlitePool,
}

#[derive(Serialize, sqlx::FromRow)]
struct BookSummary {
    id: String,
    title: String,
    isbn: Option<String>,
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

    let app = Router::new()
        .route("/health", get(health))
        .route("/api/books", get(list_books))
        .with_state(AppState { db });

    let addr = SocketAddr::from(([0, 0, 0, 0], 3000));
    tracing::info!("vellum-server listening on http://{addr} (db: {db_path})");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, app).await?;
    Ok(())
}

async fn health() -> &'static str {
    "ok"
}

async fn list_books(State(state): State<AppState>) -> Json<Vec<BookSummary>> {
    let books = sqlx::query_as::<_, BookSummary>("SELECT id, title, isbn FROM book ORDER BY title")
        .fetch_all(&state.db)
        .await
        .unwrap_or_default();
    Json(books)
}
