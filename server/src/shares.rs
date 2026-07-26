use axum::Json;
use axum::extract::{Path, State};
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::auth::{AuthUser, sha256_hex};
use crate::books::BookDto;
use crate::error::{AppError, AppResult};

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
pub async fn list(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Vec<ShareDto>>> {
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
        return Err(AppError::BadRequest(
            "you cannot share with yourself".into(),
        ));
    }

    let id = uuid::Uuid::new_v4().to_string();
    let scope_id = if input.scope == "all" {
        None
    } else {
        input.scope_id.clone()
    };
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
        return Err(AppError::Forbidden(
            "only the share's creator may revoke it".into(),
        ));
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
    pub max_uses: Option<i64>,
    pub use_count: i64,
    pub revoked: bool,
}

#[derive(Deserialize)]
pub struct LinkInput {
    pub book_id: String,
    pub permission: Option<String>,
    /// Days until the link expires; omit for a link that never expires.
    pub expires_in_days: Option<i64>,
    /// Explicit expiry: a date (`YYYY-MM-DD`, inclusive) or full timestamp.
    /// Takes precedence over `expires_in_days`.
    pub expires_at: Option<String>,
    /// Cap on the number of downloads; omit for unlimited.
    pub max_uses: Option<i64>,
    /// Convenience for `max_uses = 1` (a one-time download).
    pub one_time: Option<bool>,
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
            l.expires_at, l.max_uses, l.use_count, l.revoked \
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

    if input.expires_in_days.is_some_and(|d| d <= 0) {
        return Err(AppError::BadRequest(
            "expires_in_days must be positive".into(),
        ));
    }
    if input.max_uses.is_some_and(|n| n <= 0) {
        return Err(AppError::BadRequest("max_uses must be positive".into()));
    }

    let token = {
        use rand_core::{OsRng, RngCore};
        let mut bytes = [0u8; 24];
        OsRng.fill_bytes(&mut bytes);
        hex::encode(bytes)
    };
    let id = uuid::Uuid::new_v4().to_string();

    // Prefer an explicit date; a bare YYYY-MM-DD is treated as end-of-day so the
    // link stays valid through that whole day. Otherwise fall back to +N days.
    // Parse rather than trust the string, so garbage can't become a link that
    // compares as "never expired" against SQLite's datetime().
    let expires_at: Option<String> = match input.expires_at.as_deref().map(str::trim) {
        Some("") | None => input.expires_in_days.map(|d| {
            (chrono::Utc::now() + chrono::Duration::days(d))
                .format("%Y-%m-%d %H:%M:%S")
                .to_string()
        }),
        Some(raw) => {
            let parsed = chrono::NaiveDate::parse_from_str(raw, "%Y-%m-%d")
                .map(|d| d.and_hms_opt(23, 59, 59).unwrap())
                .or_else(|_| chrono::NaiveDateTime::parse_from_str(raw, "%Y-%m-%d %H:%M:%S"))
                .map_err(|_| {
                    AppError::BadRequest(
                        "expires_at must be YYYY-MM-DD or YYYY-MM-DD HH:MM:SS".into(),
                    )
                })?;
            Some(parsed.format("%Y-%m-%d %H:%M:%S").to_string())
        }
    };

    let max_uses = if input.one_time.unwrap_or(false) {
        Some(1)
    } else {
        input.max_uses
    };

    sqlx::query(
        "INSERT INTO share_link \
            (id, owner_id, book_id, token_hash, permission, expires_at, max_uses) \
         VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(&user.id)
    .bind(&input.book_id)
    .bind(sha256_hex(&token))
    .bind(&permission)
    .bind(&expires_at)
    .bind(max_uses)
    .execute(&state.db)
    .await?;

    Ok(Json(LinkCreated {
        id,
        book_id: input.book_id,
        // A friendly landing page rather than the raw API endpoint.
        url: format!("{}/p/{}", state.public_base_url, token),
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
        return Err(AppError::Forbidden(
            "only the link's creator may revoke it".into(),
        ));
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
    /// Whether the link still has a download available (a file + uses left).
    pub download_available: bool,
    /// True when the link permits a single download.
    pub one_time: bool,
}

/// A link is usable when it is not revoked, not past expiry, and has uses left.
const LINK_VALID: &str = "revoked = 0 \
    AND (expires_at IS NULL OR expires_at > datetime('now')) \
    AND (max_uses IS NULL OR use_count < max_uses)";

/// Anonymous metadata for a shared book. Does NOT consume a use (viewing the
/// landing page shouldn't burn a one-time link — only downloading does).
pub async fn public_book(
    State(state): State<AppState>,
    client: crate::auth::ClientKey,
    Path(token): Path<String>,
) -> AppResult<Json<PublicBook>> {
    if !state.public_limiter.check(&client.0) {
        return Err(AppError::TooManyRequests("too many requests".into()));
    }
    let row: Option<(String, Option<i64>)> = sqlx::query_as(&format!(
        "SELECT book_id, max_uses FROM share_link WHERE token_hash = ? AND {LINK_VALID}"
    ))
    .bind(sha256_hex(&token))
    .fetch_optional(&state.db)
    .await?;
    let (book_id, max_uses) =
        row.ok_or_else(|| AppError::NotFound("link is invalid or expired".into()))?;

    let book = sqlx::query_as::<_, BookDto>(&format!(
        "SELECT {} FROM book b WHERE b.id = ?",
        crate::books::BOOK_COLUMNS
    ))
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

    let has_file: bool =
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM book_file WHERE book_id = ?)")
            .bind(&book_id)
            .fetch_one(&state.db)
            .await?;

    Ok(Json(PublicBook {
        book,
        authors,
        download_available: has_file,
        one_time: max_uses == Some(1),
    }))
}

/// Anonymous one-shot download of the shared book's file. Atomically consumes a
/// use, so a one-time link can only be downloaded once even under concurrency.
pub async fn public_file(
    State(state): State<AppState>,
    client: crate::auth::ClientKey,
    Path(token): Path<String>,
) -> AppResult<axum::response::Response> {
    use axum::http::header;
    use axum::response::IntoResponse;

    if !state.public_limiter.check(&client.0) {
        return Err(AppError::TooManyRequests("too many requests".into()));
    }
    let hash = sha256_hex(&token);

    // Which book, and does it have a file? (No consume yet.)
    let book_id: Option<String> = sqlx::query_scalar(&format!(
        "SELECT book_id FROM share_link WHERE token_hash = ? AND {LINK_VALID}"
    ))
    .bind(&hash)
    .fetch_optional(&state.db)
    .await?;
    let book_id =
        book_id.ok_or_else(|| AppError::NotFound("link is invalid, expired, or used up".into()))?;

    let file: Option<(String, String)> = sqlx::query_as(
        "SELECT path, format FROM book_file WHERE book_id = ? ORDER BY added_at LIMIT 1",
    )
    .bind(&book_id)
    .fetch_optional(&state.db)
    .await?;
    let (rel, format) =
        file.ok_or_else(|| AppError::NotFound("this book has no file to download".into()))?;
    if !crate::blobs::is_safe_rel(&rel) {
        return Err(AppError::NotFound("file missing on disk".into()));
    }

    // Open the file BEFORE consuming a use, so a blob missing on disk can't burn
    // a one-time link on a download that then fails.
    let handle = tokio::fs::File::open(state.data_dir.join(&rel))
        .await
        .map_err(|_| AppError::NotFound("file missing on disk".into()))?;
    let len = handle.metadata().await.ok().map(|m| m.len());

    // Consume a use atomically; the WHERE re-checks validity, so concurrent
    // downloads of a one-time link can't both succeed.
    let consumed = sqlx::query(&format!(
        "UPDATE share_link SET use_count = use_count + 1 WHERE token_hash = ? AND {LINK_VALID}"
    ))
    .bind(&hash)
    .execute(&state.db)
    .await?
    .rows_affected();
    if consumed == 0 {
        return Err(AppError::NotFound("link is no longer available".into()));
    }

    let title: String = sqlx::query_scalar("SELECT title FROM book WHERE id = ?")
        .bind(&book_id)
        .fetch_one(&state.db)
        .await?;

    let filename = format!("{}.{}", sanitize_filename(&title), format);
    let mime = match format.as_str() {
        "epub" => "application/epub+zip",
        "pdf" => "application/pdf",
        _ => "application/octet-stream",
    };
    let mut response =
        axum::body::Body::from_stream(tokio_util::io::ReaderStream::new(handle)).into_response();
    let headers = response.headers_mut();
    headers.insert(header::CONTENT_TYPE, mime.parse().unwrap());
    headers.insert(
        header::CONTENT_DISPOSITION,
        format!("attachment; filename=\"{filename}\"")
            .parse()
            .unwrap(),
    );
    if let Some(len) = len {
        headers.insert(header::CONTENT_LENGTH, len.into());
    }
    Ok(response)
}

fn sanitize_filename(title: &str) -> String {
    let cleaned: String = title
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || c == ' ' || c == '-' {
                c
            } else {
                '_'
            }
        })
        .collect();
    let trimmed = cleaned.trim();
    if trimmed.is_empty() {
        "book".to_string()
    } else {
        trimmed.to_string()
    }
}

// ---- shared helpers -------------------------------------------------------

fn normalize_permission(value: Option<&str>) -> AppResult<String> {
    match value.unwrap_or("viewer") {
        "viewer" => Ok("viewer".to_string()),
        "editor" => Ok("editor".to_string()),
        other => Err(AppError::BadRequest(format!(
            "unknown permission '{other}'"
        ))),
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
        Err(AppError::Forbidden(
            "only the book's owner may share it".into(),
        ))
    }
}
