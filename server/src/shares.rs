use axum::extract::{Path, State};
use axum::Json;
use serde::{Deserialize, Serialize};

use crate::auth::{sha256_hex, AuthUser};
use crate::books::BookDto;
use crate::error::{AppError, AppResult};
use crate::AppState;

// ===========================================================================
// User-to-user shares
// ===========================================================================

#[derive(Serialize, sqlx::FromRow)]
pub struct ShareDto {
    pub id: String,
    pub scope: String,
    pub scope_id: Option<String>,
    pub scope_label: Option<String>,
    pub permission: String,
    pub owner_email: String,
    pub grantee_email: String,
    pub created_at: String,
}

#[derive(Deserialize)]
pub struct ShareInput {
    /// "all", "group", or "book".
    pub scope: String,
    /// Group or book id; omit for "all".
    pub scope_id: Option<String>,
    pub grantee_email: String,
    /// "viewer" (default) or "editor".
    pub permission: Option<String>,
}

/// Shares the caller created or received.
pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Vec<ShareDto>>> {
    let shares = sqlx::query_as::<_, ShareDto>(&format!(
        "{SHARE_SELECT} WHERE s.owner_id = ? OR s.grantee_id = ? ORDER BY s.created_at DESC"
    ))
    .bind(&user.id)
    .bind(&user.id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(shares))
}

pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(input): Json<ShareInput>,
) -> AppResult<Json<ShareDto>> {
    let permission = normalize_permission(input.permission.as_deref())?;

    // Validate the scope and that the caller is entitled to share it.
    match input.scope.as_str() {
        "all" => {}
        "group" => {
            let gid = input
                .scope_id
                .as_deref()
                .ok_or_else(|| AppError::BadRequest("scope_id (group) is required".into()))?;
            let owner: Option<String> =
                sqlx::query_scalar("SELECT owner_id FROM book_group WHERE id = ?")
                    .bind(gid)
                    .fetch_optional(&state.db)
                    .await?;
            let owner = owner.ok_or_else(|| AppError::NotFound("group not found".into()))?;
            if !user.is_master && owner != user.id {
                return Err(AppError::Forbidden("you do not own this group".into()));
            }
        }
        "book" => {
            let bid = input
                .scope_id
                .as_deref()
                .ok_or_else(|| AppError::BadRequest("scope_id (book) is required".into()))?;
            require_owns_book(&state, &user, bid).await?;
        }
        other => {
            return Err(AppError::BadRequest(format!("unknown scope '{other}'")));
        }
    }

    let grantee_id = lookup_user_by_email(&state, &input.grantee_email).await?;
    if grantee_id == user.id {
        return Err(AppError::BadRequest("you cannot share with yourself".into()));
    }

    let id = uuid::Uuid::new_v4().to_string();
    let scope_id = if input.scope == "all" { None } else { input.scope_id.clone() };
    sqlx::query(
        "INSERT INTO share (id, owner_id, grantee_id, scope, scope_id, permission) \
         VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(&user.id)
    .bind(&grantee_id)
    .bind(&input.scope)
    .bind(&scope_id)
    .bind(&permission)
    .execute(&state.db)
    .await?;

    let share = sqlx::query_as::<_, ShareDto>(&format!("{SHARE_SELECT} WHERE s.id = ?"))
        .bind(&id)
        .fetch_one(&state.db)
        .await?;
    Ok(Json(share))
}

/// Revoke a share — its creator or the master only.
pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    let owner: Option<String> = sqlx::query_scalar("SELECT owner_id FROM share WHERE id = ?")
        .bind(&id)
        .fetch_optional(&state.db)
        .await?;
    let owner = owner.ok_or_else(|| AppError::NotFound("share not found".into()))?;
    if !user.is_master && owner != user.id {
        return Err(AppError::Forbidden("only the share's creator may revoke it".into()));
    }
    sqlx::query("DELETE FROM share WHERE id = ?")
        .bind(&id)
        .execute(&state.db)
        .await?;
    Ok(Json(serde_json::json!({ "revoked": id })))
}

const SHARE_SELECT: &str = "SELECT s.id, s.scope, s.scope_id, s.permission, s.created_at, \
        ou.email AS owner_email, gu.email AS grantee_email, \
        CASE s.scope \
            WHEN 'all'   THEN 'Entire library' \
            WHEN 'group' THEN (SELECT name FROM book_group WHERE id = s.scope_id) \
            WHEN 'book'  THEN (SELECT title FROM book WHERE id = s.scope_id) \
        END AS scope_label \
    FROM share s \
    JOIN app_user ou ON ou.id = s.owner_id \
    JOIN app_user gu ON gu.id = s.grantee_id";

// ===========================================================================
// Public share links (single book, no account required)
// ===========================================================================

#[derive(Serialize, sqlx::FromRow)]
pub struct LinkDto {
    pub id: String,
    pub book_id: String,
    pub book_title: String,
    pub permission: String,
    pub created_at: String,
    pub expires_at: Option<String>,
    pub revoked: bool,
}

#[derive(Deserialize)]
pub struct LinkInput {
    pub book_id: String,
    pub permission: Option<String>,
    /// Days until the link expires; omit for a link that never expires.
    pub expires_in_days: Option<i64>,
}

#[derive(Serialize)]
pub struct LinkCreated {
    pub id: String,
    pub book_id: String,
    /// The full public URL. Shown once — only its hash is stored.
    pub url: String,
    pub expires_at: Option<String>,
}

pub async fn list_links(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Vec<LinkDto>>> {
    let links = sqlx::query_as::<_, LinkDto>(
        "SELECT l.id, l.book_id, b.title AS book_title, l.permission, l.created_at, \
            l.expires_at, l.revoked \
         FROM share_link l JOIN book b ON b.id = l.book_id \
         WHERE ? = 1 OR l.owner_id = ? \
         ORDER BY l.created_at DESC",
    )
    .bind(user.is_master)
    .bind(&user.id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(links))
}

pub async fn create_link(
    State(state): State<AppState>,
    user: AuthUser,
    Json(input): Json<LinkInput>,
) -> AppResult<Json<LinkCreated>> {
    require_owns_book(&state, &user, &input.book_id).await?;
    let permission = normalize_permission(input.permission.as_deref())?;

    let token = {
        use rand_core::{OsRng, RngCore};
        let mut bytes = [0u8; 24];
        OsRng.fill_bytes(&mut bytes);
        hex::encode(bytes)
    };
    let id = uuid::Uuid::new_v4().to_string();
    let modifier = input.expires_in_days.map(|d| format!("+{d} days"));

    sqlx::query(
        "INSERT INTO share_link (id, owner_id, book_id, token_hash, permission, expires_at) \
         VALUES (?, ?, ?, ?, ?, CASE WHEN ? IS NULL THEN NULL ELSE datetime('now', ?) END)",
    )
    .bind(&id)
    .bind(&user.id)
    .bind(&input.book_id)
    .bind(sha256_hex(&token))
    .bind(&permission)
    .bind(&modifier)
    .bind(&modifier)
    .execute(&state.db)
    .await?;

    let expires_at: Option<String> =
        sqlx::query_scalar("SELECT expires_at FROM share_link WHERE id = ?")
            .bind(&id)
            .fetch_one(&state.db)
            .await?;

    Ok(Json(LinkCreated {
        id,
        book_id: input.book_id,
        url: format!("{}/api/public/{}", state.public_base_url, token),
        expires_at,
    }))
}

/// Revoke a public link — its creator or the master only.
pub async fn delete_link(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    let owner: Option<String> = sqlx::query_scalar("SELECT owner_id FROM share_link WHERE id = ?")
        .bind(&id)
        .fetch_optional(&state.db)
        .await?;
    let owner = owner.ok_or_else(|| AppError::NotFound("link not found".into()))?;
    if !user.is_master && owner != user.id {
        return Err(AppError::Forbidden("only the link's creator may revoke it".into()));
    }
    sqlx::query("UPDATE share_link SET revoked = 1 WHERE id = ?")
        .bind(&id)
        .execute(&state.db)
        .await?;
    Ok(Json(serde_json::json!({ "revoked": id })))
}

#[derive(Serialize)]
pub struct PublicBook {
    #[serde(flatten)]
    pub book: BookDto,
    pub authors: Vec<String>,
}

/// Anonymous access to a single book via its share-link token. No auth header.
pub async fn public_book(
    State(state): State<AppState>,
    Path(token): Path<String>,
) -> AppResult<Json<PublicBook>> {
    let book_id: Option<String> = sqlx::query_scalar(
        "SELECT book_id FROM share_link \
         WHERE token_hash = ? AND revoked = 0 \
           AND (expires_at IS NULL OR expires_at > datetime('now'))",
    )
    .bind(sha256_hex(&token))
    .fetch_optional(&state.db)
    .await?;
    let book_id = book_id.ok_or_else(|| AppError::NotFound("link is invalid or expired".into()))?;

    let book = sqlx::query_as::<_, BookDto>(
        "SELECT id, title, subtitle, description, isbn, publisher, published_year, \
            page_count, cover_path, spine_style, owner_id, created_at, updated_at \
         FROM book WHERE id = ?",
    )
    .bind(&book_id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("book not found".into()))?;

    let authors: Vec<String> = sqlx::query_scalar(
        "SELECT a.name FROM author a JOIN book_author ba ON ba.author_id = a.id \
         WHERE ba.book_id = ? ORDER BY ba.position",
    )
    .bind(&book_id)
    .fetch_all(&state.db)
    .await?;

    Ok(Json(PublicBook { book, authors }))
}

// ---- shared helpers -------------------------------------------------------

fn normalize_permission(value: Option<&str>) -> AppResult<String> {
    match value.unwrap_or("viewer") {
        "viewer" => Ok("viewer".to_string()),
        "editor" => Ok("editor".to_string()),
        other => Err(AppError::BadRequest(format!("unknown permission '{other}'"))),
    }
}

async fn lookup_user_by_email(state: &AppState, email: &str) -> AppResult<String> {
    sqlx::query_scalar("SELECT id FROM app_user WHERE email = ?")
        .bind(email.trim().to_lowercase())
        .fetch_optional(&state.db)
        .await?
        .ok_or_else(|| AppError::NotFound(format!("no account for {email}")))
}

/// A book may only be shared by its owner or the master.
async fn require_owns_book(state: &AppState, user: &AuthUser, book_id: &str) -> AppResult<()> {
    let owner: Option<Option<String>> =
        sqlx::query_scalar("SELECT owner_id FROM book WHERE id = ?")
            .bind(book_id)
            .fetch_optional(&state.db)
            .await?;
    let owner = owner.ok_or_else(|| AppError::NotFound("book not found".into()))?;
    if user.is_master || owner.as_deref() == Some(user.id.as_str()) {
        Ok(())
    } else {
        Err(AppError::Forbidden("only the book's owner may share it".into()))
    }
}
