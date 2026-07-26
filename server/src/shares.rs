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
        // A published room (plan 5 #47). Viewer only — `editor` would mean two
        // people dragging the same shelf, and the document model has no answer
        // for that beyond the 409 the publisher already sees.
        "layout" => {
            let lid = input
                .scope_id
                .as_deref()
                .ok_or_else(|| AppError::BadRequest("scope_id (layout) is required".into()))?;
            let owner = crate::layouts::owner_of(&state, lid)
                .await?
                .ok_or_else(|| AppError::NotFound("layout not found".into()))?;
            if !user.is_master && owner != user.id {
                return Err(AppError::Forbidden("you do not own this room".into()));
            }
            if permission != "viewer" {
                return Err(AppError::BadRequest(
                    "a room can only be shared for viewing".into(),
                ));
            }
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
    crate::audit::record(
        &state,
        Some(&user),
        "share.create",
        "share",
        &id,
        Some(&format!("{} to {}", input.scope, input.grantee_email)),
    )
    .await;
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
    crate::audit::record(&state, Some(&user), "share.delete", "share", &id, None).await;
    Ok(Json(serde_json::json!({ "revoked": id })))
}

const SHARE_SELECT: &str = "SELECT s.id, s.scope, s.scope_id, s.permission, s.created_at, \
        ou.email AS owner_email, gu.email AS grantee_email, \
        CASE s.scope \
            WHEN 'all'   THEN 'Entire library' \
            WHEN 'group' THEN (SELECT name FROM book_group WHERE id = s.scope_id) \
            WHEN 'book'  THEN (SELECT title FROM book WHERE id = s.scope_id) \
            WHEN 'layout' THEN (SELECT name FROM layout WHERE id = s.scope_id) \
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
    /// 'book' or 'layout' (plan 5 #48).
    pub kind: String,
    pub book_id: Option<String>,
    pub layout_id: Option<String>,
    /// What the link points at, whichever kind it is — so the console can list
    /// and revoke a room link without knowing the difference.
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
    /// 'book' (default) or 'layout' — a public link can point at a published
    /// room since plan 5 #48. Exactly one of `book_id`/`layout_id` applies.
    #[serde(default)]
    pub kind: Option<String>,
    #[serde(default)]
    pub book_id: Option<String>,
    #[serde(default)]
    pub layout_id: Option<String>,
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
    /// Room links only: let anonymous viewers see the titles of the books in
    /// the room's `Room: <name>` tag. Off by default — see the column comment
    /// in migration 0019.
    #[serde(default)]
    pub show_books: Option<bool>,
}

#[derive(Serialize)]
pub struct LinkCreated {
    pub id: String,
    /// Set for a book link; null for a room link (plan 5 #48).
    pub book_id: Option<String>,
    pub layout_id: Option<String>,
    /// The full public URL. Shown once — only its hash is stored.
    pub url: String,
    pub expires_at: Option<String>,
}

pub async fn list_links(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Vec<LinkDto>>> {
    // LEFT JOINs, not inner: a room link has no book, and an inner join would
    // quietly drop it from the list — leaving a live link nobody can revoke.
    let links = sqlx::query_as::<_, LinkDto>(
        "SELECT l.id, l.kind, l.book_id, l.layout_id, \
            COALESCE(b.title, r.name, '(deleted)') AS book_title, \
            l.permission, l.created_at, \
            l.expires_at, l.max_uses, l.use_count, l.revoked \
         FROM share_link l \
         LEFT JOIN book b ON b.id = l.book_id \
         LEFT JOIN layout r ON r.id = l.layout_id \
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
    let kind = input.kind.as_deref().unwrap_or("book");
    // Resolve the target first: a link to something you don't own, or to
    // nothing at all, must fail before a token is ever minted.
    let (book_id, layout_id) = match kind {
        "book" => {
            let bid = input
                .book_id
                .clone()
                .ok_or_else(|| AppError::BadRequest("book_id is required".into()))?;
            require_owns_book(&state, &user, &bid).await?;
            (Some(bid), None)
        }
        "layout" => {
            let lid = input
                .layout_id
                .clone()
                .ok_or_else(|| AppError::BadRequest("layout_id is required".into()))?;
            let owner = crate::layouts::owner_of(&state, &lid)
                .await?
                .ok_or_else(|| AppError::NotFound("layout not found".into()))?;
            if !user.is_master && owner != user.id {
                return Err(AppError::Forbidden("you do not own this room".into()));
            }
            (None, Some(lid))
        }
        other => return Err(AppError::BadRequest(format!("unknown link kind '{other}'"))),
    };
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
            (id, owner_id, kind, book_id, layout_id, token_hash, permission, \
             expires_at, max_uses, show_books) \
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(&user.id)
    .bind(kind)
    .bind(&book_id)
    .bind(&layout_id)
    .bind(sha256_hex(&token))
    .bind(&permission)
    .bind(&expires_at)
    .bind(max_uses)
    .bind(kind == "layout" && input.show_books.unwrap_or(false))
    .execute(&state.db)
    .await?;

    Ok(Json(LinkCreated {
        id,
        book_id,
        layout_id,
        // A friendly landing page rather than the raw API endpoint. A room link
        // lands on /r-room/ so the page knows what it is showing without a
        // round trip that might 404.
        url: if kind == "layout" {
            format!("{}/pr/{}", state.public_base_url, token)
        } else {
            format!("{}/p/{}", state.public_base_url, token)
        },
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

/// The published room a share-link token points at (plan 5 #48), and whether
/// its books were shared alongside it.
///
/// A room link never consumes a use — there is nothing to download, and
/// `max_uses` counts downloads.
pub(crate) async fn layout_for_link(
    state: &AppState,
    token: &str,
) -> AppResult<Option<(String, bool)>> {
    Ok(sqlx::query_as(&format!(
        "SELECT l.layout_id, l.show_books FROM share_link l \
         WHERE l.token_hash = ? AND l.kind = 'layout' AND {LINK_VALID}"
    ))
    .bind(sha256_hex(token))
    .fetch_optional(&state.db)
    .await?)
}

/// `GET /api/public/{token}/room` — the room document for an anonymous viewer.
pub async fn public_room(
    State(state): State<AppState>,
    client: crate::auth::ClientKey,
    Path(token): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    if !state.public_limiter.check(&client.0) {
        return Err(AppError::TooManyRequests("too many requests".into()));
    }
    let (layout_id, show_books) = layout_for_link(&state, &token)
        .await?
        .ok_or_else(|| AppError::NotFound("link is invalid or expired".into()))?;

    let row: Option<(String, i64, String)> =
        sqlx::query_as("SELECT name, revision, doc FROM layout WHERE id = ?")
            .bind(&layout_id)
            .fetch_optional(&state.db)
            .await?;
    let (name, revision, doc) = row.ok_or_else(|| AppError::NotFound("room not found".into()))?;

    // The books an anonymous viewer may name: none unless this *link* was
    // created with `show_books`, and even then only those the owner collected
    // under the room's `Room: <name>` tag. Anonymous spines are the default —
    // which is the whole reason the document carries no titles.
    let named = if show_books {
        public_room_books(&state, &layout_id, &name).await?
    } else {
        Vec::new()
    };

    Ok(Json(serde_json::json!({
        "name": name,
        "revision": revision,
        "doc": serde_json::from_str::<serde_json::Value>(&doc)
            .unwrap_or(serde_json::Value::Null),
        "books": named,
    })))
}

/// Titles for the books of a public room, scoped to the room's own tag.
///
/// Only ever called for a link created with `show_books`. Scoping to the
/// `Room: <name>` group (rather than to every book in the document) means the
/// owner controls exactly which books are named by what they put in the tag —
/// the same collection they'd share with a named member, and no second path to
/// the library.
async fn public_room_books(
    state: &AppState,
    layout_id: &str,
    room_name: &str,
) -> AppResult<Vec<serde_json::Value>> {
    let owner: Option<String> = sqlx::query_scalar("SELECT owner_id FROM layout WHERE id = ?")
        .bind(layout_id)
        .fetch_optional(&state.db)
        .await?;
    let Some(owner) = owner else {
        return Ok(Vec::new());
    };
    let group: Option<String> =
        sqlx::query_scalar("SELECT id FROM book_group WHERE owner_id = ? AND name = ?")
            .bind(&owner)
            .bind(format!("Room: {room_name}"))
            .fetch_optional(&state.db)
            .await?;
    let Some(group) = group else {
        return Ok(Vec::new());
    };

    let rows: Vec<(String, String, Option<String>)> = sqlx::query_as(
        "SELECT b.id, b.title, b.cover_path FROM book b \
         JOIN book_group_item gi ON gi.book_id = b.id \
         WHERE gi.group_id = ?",
    )
    .bind(&group)
    .fetch_all(&state.db)
    .await?;

    Ok(rows
        .into_iter()
        .map(|(id, title, cover)| {
            serde_json::json!({
                "book_id": id,
                "title": title,
                "has_cover": cover.is_some(),
            })
        })
        .collect())
}

/// The book a share-link token points at, **without consuming a use**.
///
/// Reading in the browser (plan 5 #33) goes through here: `max_uses` counts
/// *downloads*, and burning a one-time link on a page turn would destroy it the
/// moment someone opened the book.
pub(crate) async fn book_id_for_link(state: &AppState, token: &str) -> AppResult<Option<String>> {
    Ok(sqlx::query_scalar(&format!(
        "SELECT book_id FROM share_link WHERE token_hash = ? AND kind = 'book' \
         AND {LINK_VALID}"
    ))
    .bind(sha256_hex(token))
    .fetch_optional(&state.db)
    .await?)
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

// ---- Emailed invites (plan 5 #31, stage 3) ---------------------------------

#[derive(Deserialize)]
pub struct InviteInput {
    pub email: String,
    /// Optional grant to apply when the invite is redeemed, same shape as a
    /// share: `all`, `group` or `book`. Omit for "just give them an account".
    #[serde(default)]
    pub scope: Option<String>,
    #[serde(default)]
    pub scope_id: Option<String>,
    #[serde(default)]
    pub permission: Option<String>,
}

#[derive(Serialize)]
pub struct InviteCreated {
    pub email: String,
    pub expires_at: String,
    /// True when the link was emailed. False means mail is off and the operator
    /// has to pass `url` along themselves — better than refusing to invite at
    /// all on a LAN server.
    pub emailed: bool,
    /// Only returned when it could *not* be emailed; otherwise the link exists
    /// solely in the recipient's inbox.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub url: Option<String>,
}

/// `POST /api/invites` — master-only: mint an invite and email a join link.
///
/// Registration is closed after the first account, so this is how a second
/// person gets in without the master typing a password on their behalf and
/// sending it over a chat app.
pub async fn create_invite(
    State(state): State<AppState>,
    user: AuthUser,
    Json(input): Json<InviteInput>,
) -> AppResult<Json<InviteCreated>> {
    if !user.is_master {
        return Err(AppError::Forbidden("only the master may invite".into()));
    }
    let email = input.email.trim().to_lowercase();
    if !email.contains('@') {
        return Err(AppError::BadRequest("a valid email is required".into()));
    }
    let exists: bool = sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM app_user WHERE email = ?)")
        .bind(&email)
        .fetch_one(&state.db)
        .await?;
    if exists {
        // Unlike `forgot`, saying so is right here: the master is entitled to
        // know who already has an account in their own library.
        return Err(AppError::Conflict(
            "that email already has an account".into(),
        ));
    }

    let permission = normalize_permission(input.permission.as_deref())?;
    if let Some(scope) = input.scope.as_deref() {
        if !matches!(scope, "all" | "group" | "book") {
            return Err(AppError::BadRequest(
                "scope must be all, group, or book".into(),
            ));
        }
        if scope != "all" && input.scope_id.is_none() {
            return Err(AppError::BadRequest(
                "scope_id is required for a group or book invite".into(),
            ));
        }
    }

    // One outstanding invite per address, so re-inviting supersedes rather than
    // leaving two live links.
    sqlx::query("DELETE FROM invite WHERE email = ?")
        .bind(&email)
        .execute(&state.db)
        .await?;

    let token = crate::auth::new_token_for_invite();
    sqlx::query(
        "INSERT INTO invite (token_hash, email, invited_by, scope, scope_id, \
            permission, expires_at) \
         VALUES (?, ?, ?, ?, ?, ?, datetime('now', '+14 days'))",
    )
    .bind(crate::auth::sha256_hex(&token))
    .bind(&email)
    .bind(&user.id)
    .bind(&input.scope)
    .bind(&input.scope_id)
    .bind(permission)
    .execute(&state.db)
    .await?;

    let url = format!(
        "{}/join/{token}",
        state.public_base_url.trim_end_matches('/')
    );
    let expires_at: String = sqlx::query_scalar("SELECT expires_at FROM invite WHERE email = ?")
        .bind(&email)
        .fetch_one(&state.db)
        .await?;

    let emailed = match state.mailer.clone() {
        Some(mailer) => {
            let body = format!(
                "{} has invited you to their Vellum library.\n\n\
                 Open this link within two weeks to choose a password and join:\n\n\
                 {url}\n\n\
                 If you weren't expecting this, ignore it — the link expires on \n\
                 its own and nothing was created for you.\n",
                user.display_name
            );
            mailer
                .send(&email, "You've been invited to a Vellum library", &body)
                .await
                .is_ok()
        }
        None => false,
    };

    Ok(Json(InviteCreated {
        email,
        expires_at,
        emailed,
        // Handing the link back when mail is off is the difference between a
        // usable LAN server and a feature that only works with SMTP.
        url: (!emailed).then_some(url),
    }))
}

/// One outstanding invite, as the redeem path reads it.
#[derive(sqlx::FromRow)]
struct PendingInvite {
    email: String,
    scope: Option<String>,
    scope_id: Option<String>,
    permission: String,
    invited_by: String,
}

#[derive(Deserialize)]
pub struct RedeemInput {
    pub token: String,
    pub display_name: String,
    pub password: String,
}

/// `POST /api/invites/redeem` — create the account and apply the grant.
///
/// Unauthenticated by necessity: the invitee has no account yet. The token is
/// the whole credential, so it is single-use, short-lived, and the account it
/// creates uses the invited address rather than one the caller chooses — a
/// forwarded link must not become an open registration endpoint.
pub async fn redeem_invite(
    State(state): State<AppState>,
    Json(input): Json<RedeemInput>,
) -> AppResult<Json<serde_json::Value>> {
    let hash = crate::auth::sha256_hex(input.token.trim());
    let row: Option<PendingInvite> = sqlx::query_as(
        "SELECT email, scope, scope_id, permission, invited_by FROM invite \
         WHERE token_hash = ? AND used_at IS NULL AND expires_at > datetime('now')",
    )
    .bind(&hash)
    .fetch_optional(&state.db)
    .await?;
    let Some(PendingInvite {
        email,
        scope,
        scope_id,
        permission,
        invited_by,
    }) = row
    else {
        return Err(AppError::BadRequest(
            "this invitation is invalid or has expired".into(),
        ));
    };

    let user_id = crate::auth::create_invited_user(
        &state,
        &email,
        input.display_name.trim(),
        &input.password,
    )
    .await?;

    let mut tx = state.db.begin().await?;
    let consumed = sqlx::query(
        "UPDATE invite SET used_at = datetime('now') \
         WHERE token_hash = ? AND used_at IS NULL",
    )
    .bind(&hash)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if consumed == 0 {
        return Err(AppError::BadRequest(
            "this invitation is invalid or has expired".into(),
        ));
    }
    if let Some(scope) = scope {
        sqlx::query(
            "INSERT INTO share (id, owner_id, grantee_id, scope, scope_id, permission) \
             VALUES (?, ?, ?, ?, ?, ?)",
        )
        .bind(uuid::Uuid::new_v4().to_string())
        .bind(&invited_by)
        .bind(&user_id)
        .bind(&scope)
        .bind(&scope_id)
        .bind(&permission)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;

    tracing::info!(user_id, "invite redeemed");
    Ok(Json(
        serde_json::json!({ "status": "account created", "email": email }),
    ))
}
