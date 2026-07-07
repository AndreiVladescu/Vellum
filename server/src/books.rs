use axum::extract::{Path, State};
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::access::book_access;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};
use crate::AppState;

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct BookDto {
    pub id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub description: Option<String>,
    pub isbn: Option<String>,
    pub publisher: Option<String>,
    pub published_year: Option<i64>,
    pub page_count: Option<i64>,
    pub cover_path: Option<String>,
    pub spine_style: Option<String>,
    pub owner_id: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

const BOOK_COLUMNS: &str = "id, title, subtitle, description, isbn, publisher, \
    published_year, page_count, cover_path, spine_style, owner_id, created_at, updated_at";

#[derive(Deserialize)]
pub struct BookInput {
    pub title: String,
    pub subtitle: Option<String>,
    pub description: Option<String>,
    pub isbn: Option<String>,
    pub publisher: Option<String>,
    pub published_year: Option<i64>,
    pub page_count: Option<i64>,
    pub cover_path: Option<String>,
    pub spine_style: Option<String>,
}

/// Partial update: every field optional; omitted fields are left unchanged.
#[derive(Deserialize)]
pub struct BookUpdate {
    pub title: Option<String>,
    pub subtitle: Option<String>,
    pub description: Option<String>,
    pub isbn: Option<String>,
    pub publisher: Option<String>,
    pub published_year: Option<i64>,
    pub page_count: Option<i64>,
    pub cover_path: Option<String>,
    pub spine_style: Option<String>,
}

/// Every book the caller can see: the ones they own, plus everything reachable
/// through a share (whole-library, group, or single-book), plus everything if
/// they are the master. Shared by the JSON list and the OPDS feed.
pub async fn visible_books(state: &AppState, user: &AuthUser) -> AppResult<Vec<BookDto>> {
    let books = sqlx::query_as::<_, BookDto>(&format!(
        "SELECT {BOOK_COLUMNS} FROM book b \
         WHERE b.owner_id = ? \
            OR ? = 1 \
            OR EXISTS ( \
                SELECT 1 FROM share s WHERE s.grantee_id = ? AND ( \
                    (s.scope = 'all'   AND s.owner_id = b.owner_id) OR \
                    (s.scope = 'book'  AND s.scope_id = b.id) OR \
                    (s.scope = 'group' AND EXISTS ( \
                        SELECT 1 FROM book_group_item gi \
                        WHERE gi.group_id = s.scope_id AND gi.book_id = b.id)) )) \
         ORDER BY b.title"
    ))
    .bind(&user.id)
    .bind(user.is_master)
    .bind(&user.id)
    .fetch_all(&state.db)
    .await?;
    Ok(books)
}

pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Vec<BookDto>>> {
    Ok(Json(visible_books(&state, &user).await?))
}

pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(input): Json<BookInput>,
) -> AppResult<Json<BookDto>> {
    if input.title.trim().is_empty() {
        return Err(AppError::BadRequest("title is required".into()));
    }
    let id = uuid::Uuid::new_v4().to_string();
    sqlx::query(
        "INSERT INTO book (id, title, subtitle, description, isbn, publisher, \
            published_year, page_count, cover_path, spine_style, owner_id) \
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(input.title.trim())
    .bind(&input.subtitle)
    .bind(&input.description)
    .bind(&input.isbn)
    .bind(&input.publisher)
    .bind(input.published_year)
    .bind(input.page_count)
    .bind(&input.cover_path)
    .bind(&input.spine_style)
    .bind(&user.id)
    .execute(&state.db)
    .await?;
    fetch_book(&state, &id).await
}

/// Upsert a book at a caller-chosen id — the app pushes local books this way so
/// ids stay consistent across push and pull. Creates it (owned by the caller)
/// if absent, otherwise updates it (requires editor access). `cover_path` and
/// `spine_style` are preserved when omitted, since covers sync separately.
pub async fn upsert(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(input): Json<BookInput>,
) -> AppResult<Json<BookDto>> {
    if input.title.trim().is_empty() {
        return Err(AppError::BadRequest("title is required".into()));
    }
    let owner: Option<Option<String>> = sqlx::query_scalar("SELECT owner_id FROM book WHERE id = ?")
        .bind(&id)
        .fetch_optional(&state.db)
        .await?;

    match owner {
        Some(_) => {
            if !book_access(&state, &user, &id).await?.can_edit() {
                return Err(AppError::Forbidden(
                    "you have read-only access to this book".into(),
                ));
            }
            sqlx::query(
                "UPDATE book SET title = ?, subtitle = ?, description = ?, isbn = ?, \
                    publisher = ?, published_year = ?, page_count = ?, \
                    cover_path = COALESCE(?, cover_path), \
                    spine_style = COALESCE(?, spine_style), \
                    updated_at = datetime('now') \
                 WHERE id = ?",
            )
            .bind(input.title.trim())
            .bind(&input.subtitle)
            .bind(&input.description)
            .bind(&input.isbn)
            .bind(&input.publisher)
            .bind(input.published_year)
            .bind(input.page_count)
            .bind(&input.cover_path)
            .bind(&input.spine_style)
            .bind(&id)
            .execute(&state.db)
            .await?;
        }
        None => {
            sqlx::query(
                "INSERT INTO book (id, title, subtitle, description, isbn, publisher, \
                    published_year, page_count, cover_path, spine_style, owner_id) \
                 VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
            )
            .bind(&id)
            .bind(input.title.trim())
            .bind(&input.subtitle)
            .bind(&input.description)
            .bind(&input.isbn)
            .bind(&input.publisher)
            .bind(input.published_year)
            .bind(input.page_count)
            .bind(&input.cover_path)
            .bind(&input.spine_style)
            .bind(&user.id)
            .execute(&state.db)
            .await?;
        }
    }
    fetch_book(&state, &id).await
}

pub async fn get(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<BookDto>> {
    if !book_access(&state, &user, &id).await?.can_view() {
        return Err(AppError::NotFound("book not found".into()));
    }
    fetch_book(&state, &id).await
}

/// Partial update — requires editor (or owner/master) access. Omitted fields
/// are left unchanged; fields cannot be nulled out through this endpoint.
pub async fn update(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(input): Json<BookUpdate>,
) -> AppResult<Json<BookDto>> {
    let access = book_access(&state, &user, &id).await?;
    if !access.can_view() {
        return Err(AppError::NotFound("book not found".into()));
    }
    if !access.can_edit() {
        return Err(AppError::Forbidden("you have read-only access to this book".into()));
    }
    sqlx::query(
        "UPDATE book SET \
            title = COALESCE(?, title), \
            subtitle = COALESCE(?, subtitle), \
            description = COALESCE(?, description), \
            isbn = COALESCE(?, isbn), \
            publisher = COALESCE(?, publisher), \
            published_year = COALESCE(?, published_year), \
            page_count = COALESCE(?, page_count), \
            cover_path = COALESCE(?, cover_path), \
            spine_style = COALESCE(?, spine_style), \
            updated_at = datetime('now') \
         WHERE id = ?",
    )
    .bind(input.title.and_then(nullable))
    .bind(&input.subtitle)
    .bind(&input.description)
    .bind(&input.isbn)
    .bind(&input.publisher)
    .bind(input.published_year)
    .bind(input.page_count)
    .bind(&input.cover_path)
    .bind(&input.spine_style)
    .bind(&id)
    .execute(&state.db)
    .await?;
    fetch_book(&state, &id).await
}

/// Delete — restricted to the book's owner or the master.
pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    let owner: Option<Option<String>> = sqlx::query_scalar("SELECT owner_id FROM book WHERE id = ?")
        .bind(&id)
        .fetch_optional(&state.db)
        .await?;
    let Some(owner_id) = owner else {
        return Err(AppError::NotFound("book not found".into()));
    };
    if !user.is_master && owner_id.as_deref() != Some(user.id.as_str()) {
        return Err(AppError::Forbidden("only the owner may delete this book".into()));
    }
    sqlx::query("DELETE FROM book WHERE id = ?")
        .bind(&id)
        .execute(&state.db)
        .await?;
    Ok(Json(serde_json::json!({ "deleted": id })))
}

async fn fetch_book(state: &AppState, id: &str) -> AppResult<Json<BookDto>> {
    let book = sqlx::query_as::<_, BookDto>(&format!("SELECT {BOOK_COLUMNS} FROM book WHERE id = ?"))
        .bind(id)
        .fetch_optional(&state.db)
        .await?
        .ok_or_else(|| AppError::NotFound("book not found".into()))?;
    Ok(Json(book))
}

/// Treat an empty/blank string as "leave unchanged" for COALESCE updates.
fn nullable(value: String) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}
