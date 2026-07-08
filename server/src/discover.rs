//! Book discovery: search the online metadata sources and add a chosen result
//! as a real book (the console's search flow; the app has its own client).

use axum::extract::{Query, State};
use axum::Json;
use serde::Deserialize;

use crate::auth::AuthUser;
use crate::books::{fetch_book, BookDto};
use crate::error::{AppError, AppResult};
use crate::metadata::{self, BookSearchResult};
use crate::AppState;

#[derive(Deserialize)]
pub struct SearchQuery {
    pub q: String,
}

/// Search Open Library / Google Books. Requires a logged-in user.
pub async fn search(
    State(state): State<AppState>,
    _user: AuthUser,
    Query(query): Query<SearchQuery>,
) -> AppResult<Json<Vec<BookSearchResult>>> {
    let q = query.q.trim();
    if q.is_empty() {
        return Ok(Json(Vec::new()));
    }
    Ok(Json(metadata::search(&state.http, q).await?))
}

/// Create a book from a chosen search result: fetch its description and cover,
/// then store it (owned by the caller) with its authors and a few genres.
pub async fn add_from_search(
    State(state): State<AppState>,
    user: AuthUser,
    Json(result): Json<BookSearchResult>,
) -> AppResult<Json<BookDto>> {
    if result.title.trim().is_empty() {
        return Err(AppError::BadRequest("title is required".into()));
    }
    let id = uuid::Uuid::new_v4().to_string();

    let description = match &result.description {
        Some(d) => Some(d.clone()),
        None => metadata::fetch_description(&state.http, &result.work_key)
            .await
            .unwrap_or(None),
    };

    let mut cover_path: Option<String> = None;
    if let Some(bytes) = metadata::download_cover(&state.http, &result).await {
        let rel = format!("covers/{id}.jpg");
        let full = state.data_dir.join(&rel);
        if let Some(parent) = full.parent() {
            let _ = tokio::fs::create_dir_all(parent).await;
        }
        if tokio::fs::write(&full, &bytes).await.is_ok() {
            cover_path = Some(rel);
        }
    }

    sqlx::query(
        "INSERT INTO book (id, title, subtitle, description, isbn, publisher, \
            published_year, page_count, cover_path, owner_id) \
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(result.title.trim())
    .bind(&result.subtitle)
    .bind(&description)
    .bind(&result.isbn)
    .bind(&result.publisher)
    .bind(result.first_publish_year)
    .bind(result.page_count)
    .bind(&cover_path)
    .bind(&user.id)
    .execute(&state.db)
    .await?;

    for (position, name) in result.authors.iter().enumerate() {
        let author_id = id_for_name(&state, "author", name).await?;
        sqlx::query(
            "INSERT OR IGNORE INTO book_author (book_id, author_id, position) VALUES (?, ?, ?)",
        )
        .bind(&id)
        .bind(&author_id)
        .bind(position as i64)
        .execute(&state.db)
        .await?;
    }

    // Open Library subjects are noisy; keep a few short, clean ones as genres.
    for name in result
        .subjects
        .iter()
        .filter(|s| s.len() <= 28 && !s.contains(':'))
        .take(3)
    {
        let genre_id = id_for_name(&state, "genre", name).await?;
        sqlx::query("INSERT OR IGNORE INTO book_genre (book_id, genre_id) VALUES (?, ?)")
            .bind(&id)
            .bind(&genre_id)
            .execute(&state.db)
            .await?;
    }

    Ok(Json(fetch_book(&state, &id).await?.0))
}

/// Get-or-create by name for the `author` / `genre` lookup tables. `table` is a
/// fixed literal from this module, never user input.
async fn id_for_name(state: &AppState, table: &str, name: &str) -> AppResult<String> {
    let name = name.trim();
    let existing: Option<String> =
        sqlx::query_scalar(&format!("SELECT id FROM {table} WHERE name = ?"))
            .bind(name)
            .fetch_optional(&state.db)
            .await?;
    if let Some(id) = existing {
        return Ok(id);
    }
    let id = uuid::Uuid::new_v4().to_string();
    sqlx::query(&format!("INSERT INTO {table} (id, name) VALUES (?, ?)"))
        .bind(&id)
        .bind(name)
        .execute(&state.db)
        .await?;
    Ok(id)
}
