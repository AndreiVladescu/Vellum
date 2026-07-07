use axum::extract::{Path, State};
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::access::group_access;
use crate::auth::AuthUser;
use crate::books::BookDto;
use crate::error::{AppError, AppResult};
use crate::AppState;

#[derive(Serialize, sqlx::FromRow)]
pub struct GroupDto {
    pub id: String,
    pub owner_id: String,
    pub name: String,
    pub created_at: String,
    pub book_count: i64,
}

#[derive(Serialize)]
pub struct GroupDetail {
    #[serde(flatten)]
    pub group: GroupDto,
    pub books: Vec<BookDto>,
}

#[derive(Deserialize)]
pub struct GroupInput {
    pub name: String,
}

#[derive(Deserialize)]
pub struct AddBookInput {
    pub book_id: String,
}

/// Groups the caller owns or has been granted (plus everything for the master).
pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Vec<GroupDto>>> {
    let groups = sqlx::query_as::<_, GroupDto>(
        "SELECT g.id, g.owner_id, g.name, g.created_at, \
            (SELECT COUNT(*) FROM book_group_item gi WHERE gi.group_id = g.id) AS book_count \
         FROM book_group g \
         WHERE ? = 1 OR g.owner_id = ? OR EXISTS ( \
            SELECT 1 FROM share s WHERE s.grantee_id = ? AND ( \
                (s.scope = 'group' AND s.scope_id = g.id) OR \
                (s.scope = 'all'   AND s.owner_id = g.owner_id) )) \
         ORDER BY g.created_at DESC",
    )
    .bind(user.is_master)
    .bind(&user.id)
    .bind(&user.id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(groups))
}

pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(input): Json<GroupInput>,
) -> AppResult<Json<GroupDto>> {
    if input.name.trim().is_empty() {
        return Err(AppError::BadRequest("group name is required".into()));
    }
    let id = uuid::Uuid::new_v4().to_string();
    sqlx::query("INSERT INTO book_group (id, owner_id, name) VALUES (?, ?, ?)")
        .bind(&id)
        .bind(&user.id)
        .bind(input.name.trim())
        .execute(&state.db)
        .await?;
    fetch_group(&state, &id).await
}

pub async fn get(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<GroupDetail>> {
    if !group_access(&state, &user, &id).await?.can_view() {
        return Err(AppError::NotFound("group not found".into()));
    }
    let group = single_group(&state, &id).await?;
    let books = sqlx::query_as::<_, BookDto>(
        "SELECT b.id, b.title, b.subtitle, b.description, b.isbn, b.publisher, \
            b.published_year, b.page_count, b.cover_path, b.spine_style, b.owner_id, \
            b.created_at, b.updated_at \
         FROM book b JOIN book_group_item gi ON gi.book_id = b.id \
         WHERE gi.group_id = ? ORDER BY b.title",
    )
    .bind(&id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(GroupDetail { group, books }))
}

pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    require_manage(&state, &user, &id).await?;
    sqlx::query("DELETE FROM book_group WHERE id = ?")
        .bind(&id)
        .execute(&state.db)
        .await?;
    Ok(Json(serde_json::json!({ "deleted": id })))
}

pub async fn add_book(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(input): Json<AddBookInput>,
) -> AppResult<Json<GroupDto>> {
    require_manage(&state, &user, &id).await?;
    let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM book WHERE id = ?)")
        .bind(&input.book_id)
        .fetch_one(&state.db)
        .await?;
    if !exists {
        return Err(AppError::NotFound("book not found".into()));
    }
    sqlx::query("INSERT OR IGNORE INTO book_group_item (group_id, book_id) VALUES (?, ?)")
        .bind(&id)
        .bind(&input.book_id)
        .execute(&state.db)
        .await?;
    fetch_group(&state, &id).await
}

pub async fn remove_book(
    State(state): State<AppState>,
    user: AuthUser,
    Path((id, book_id)): Path<(String, String)>,
) -> AppResult<Json<GroupDto>> {
    require_manage(&state, &user, &id).await?;
    sqlx::query("DELETE FROM book_group_item WHERE group_id = ? AND book_id = ?")
        .bind(&id)
        .bind(&book_id)
        .execute(&state.db)
        .await?;
    fetch_group(&state, &id).await
}

// ---- helpers --------------------------------------------------------------

/// Only the group's owner (or the master) may change its membership.
async fn require_manage(state: &AppState, user: &AuthUser, group_id: &str) -> AppResult<()> {
    match group_access(state, user, group_id).await? {
        crate::access::Access::Editor => Ok(()),
        crate::access::Access::Viewer => {
            Err(AppError::Forbidden("you cannot modify this group".into()))
        }
        crate::access::Access::None => Err(AppError::NotFound("group not found".into())),
    }
}

async fn single_group(state: &AppState, id: &str) -> AppResult<GroupDto> {
    fetch_group(state, id).await.map(|json| json.0)
}

async fn fetch_group(state: &AppState, id: &str) -> AppResult<Json<GroupDto>> {
    let group = sqlx::query_as::<_, GroupDto>(
        "SELECT g.id, g.owner_id, g.name, g.created_at, \
            (SELECT COUNT(*) FROM book_group_item gi WHERE gi.group_id = g.id) AS book_count \
         FROM book_group g WHERE g.id = ?",
    )
    .bind(id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("group not found".into()))?;
    Ok(Json(group))
}
