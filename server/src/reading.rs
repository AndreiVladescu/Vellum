//! Optional cross-device reading position (plan 5 #5).
//!
//! The one part of "reading state" that may reach the server, and only because
//! it lives entirely outside the book row: see `migrations/0011` for why that
//! distinction matters. Three rules hold this endpoint together:
//!
//! 1. `user_id` always comes from the token, never from a body. A shared
//!    library holds several users' positions in the same book, and one user's
//!    reading is not another's business.
//! 2. A row is keyed by `(book_id, user_id, device_id)`, so there is no
//!    conflict resolution at all — every writer owns its own row.
//! 3. Reading needs only *view* access to the book. Recording where you are in
//!    a book someone shared with you read-only is still your own data.

use axum::Json;
use axum::extract::{Path, Query, State};
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::access::book_access;
use crate::auth::AuthUser;
use crate::books::access_predicate;
use crate::error::{AppError, AppResult};

/// One device's position in one book. `user_id` is deliberately absent: every
/// row a caller can read is their own, so echoing it back would only invite a
/// client to think it could ask for someone else's.
#[derive(Serialize, sqlx::FromRow)]
pub struct ProgressDto {
    pub book_id: String,
    pub device_id: String,
    pub device_label: Option<String>,
    pub progress: Option<f64>,
    pub page: Option<i64>,
    pub unit: Option<String>,
    pub scroll: Option<f64>,
    pub updated_at: String,
}

#[derive(Deserialize)]
pub struct ProgressInput {
    pub device_id: String,
    pub device_label: Option<String>,
    pub progress: Option<f64>,
    pub page: Option<i64>,
    /// `'page'` (PDF) or `'chapter'` (EPUB) — what `page` counts. Anything
    /// else is rejected rather than stored, so a client can trust the value it
    /// reads back when phrasing a prompt.
    pub unit: Option<String>,
    pub scroll: Option<f64>,
    /// The writing device's clock. Unlike every other synced entity this is
    /// *not* a LWW comparison key — a device only ever overwrites its own row
    /// — it is what other devices order "who is furthest ahead" by. Defaults
    /// to the server's clock when absent.
    #[serde(default)]
    pub updated_at: Option<String>,
}

/// The caller's own rows, for books the caller can still see. The book join is
/// not redundant with the `user_id` filter: a book can be *un*shared after a
/// position was recorded, and this endpoint must stop returning it then.
/// `updated_since` narrows to a delta pull with the same `>=` convention as
/// `books::visible_books`.
async fn my_progress(
    state: &AppState,
    user: &AuthUser,
    updated_since: Option<&str>,
) -> AppResult<Vec<ProgressDto>> {
    let filter = if updated_since.is_some() {
        " AND rp.updated_at >= ?"
    } else {
        ""
    };
    let sql = format!(
        "SELECT rp.book_id, rp.device_id, rp.device_label, rp.progress, rp.page, \
                rp.unit, rp.scroll, rp.updated_at \
         FROM reading_progress rp JOIN book b ON b.id = rp.book_id \
         WHERE rp.user_id = ? AND {} {filter} \
         ORDER BY rp.book_id, rp.device_id",
        access_predicate()
    );
    let mut query = sqlx::query_as::<_, ProgressDto>(&sql)
        .bind(&user.id)
        .bind(&user.id)
        .bind(user.is_master)
        .bind(&user.id);
    if let Some(ts) = updated_since {
        query = query.bind(ts.to_string());
    }
    Ok(query.fetch_all(&state.db).await?)
}

/// Same `cursor`-presence convention as `books::list` and friends: present
/// (even empty) selects the `{ server_now, entries }` envelope; absent returns
/// a bare array.
#[derive(Deserialize)]
pub struct ListQuery {
    pub cursor: Option<String>,
}

pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<ListQuery>,
) -> AppResult<Json<serde_json::Value>> {
    let since = q.cursor.as_deref().map(str::trim).filter(|c| !c.is_empty());
    let entries = my_progress(&state, &user, since).await?;

    if q.cursor.is_some() {
        let server_now: String = sqlx::query_scalar("SELECT datetime('now')")
            .fetch_one(&state.db)
            .await?;
        Ok(Json(serde_json::json!({
            "server_now": server_now,
            "entries": entries,
        })))
    } else {
        Ok(Json(serde_json::to_value(entries)?))
    }
}

/// Record this device's position in a book. Creates or replaces exactly the
/// `(book, caller, device)` row — never another device's, and never another
/// user's. Requires only view access (rule 3 in the module docs).
pub async fn upsert(
    State(state): State<AppState>,
    user: AuthUser,
    Path(book_id): Path<String>,
    Json(input): Json<ProgressInput>,
) -> AppResult<Json<ProgressDto>> {
    if input.device_id.trim().is_empty() {
        return Err(AppError::BadRequest("device_id is required".into()));
    }
    if let Some(unit) = input.unit.as_deref()
        && !matches!(unit, "page" | "chapter")
    {
        return Err(AppError::BadRequest(
            "unit must be 'page' or 'chapter'".into(),
        ));
    }
    // `book_access` returns `None` for a missing book too, so this covers 404
    // without telling an unauthorized caller which ids exist.
    if !book_access(&state, &user, &book_id).await?.can_view() {
        return Err(AppError::NotFound("no such book".into()));
    }

    let device_id = input.device_id.trim();
    sqlx::query(
        "INSERT INTO reading_progress \
            (book_id, user_id, device_id, device_label, progress, page, unit, scroll, updated_at) \
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, COALESCE(?, datetime('now'))) \
         ON CONFLICT(book_id, user_id, device_id) DO UPDATE SET \
            device_label = excluded.device_label, \
            progress = excluded.progress, \
            page = excluded.page, \
            unit = excluded.unit, \
            scroll = excluded.scroll, \
            updated_at = excluded.updated_at",
    )
    .bind(&book_id)
    .bind(&user.id)
    .bind(device_id)
    .bind(&input.device_label)
    .bind(input.progress)
    .bind(input.page)
    .bind(&input.unit)
    .bind(input.scroll)
    .bind(&input.updated_at)
    .execute(&state.db)
    .await?;

    let row: ProgressDto = sqlx::query_as(
        "SELECT book_id, device_id, device_label, progress, page, unit, scroll, updated_at \
         FROM reading_progress WHERE book_id = ? AND user_id = ? AND device_id = ?",
    )
    .bind(&book_id)
    .bind(&user.id)
    .bind(device_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(row))
}

#[derive(Deserialize)]
pub struct ForgetQuery {
    /// Which device's rows to drop. Required: a blanket "delete everything I
    /// ever read" is not what turning a per-device setting off means.
    pub device_id: String,
}

/// Drop every row this device published, for the caller only. What makes the
/// opt-in honest: turning "Sync reading position" off un-publishes what turning
/// it on published, rather than leaving it on the server forever.
pub async fn forget_device(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<ForgetQuery>,
) -> AppResult<Json<serde_json::Value>> {
    let device_id = q.device_id.trim();
    if device_id.is_empty() {
        return Err(AppError::BadRequest("device_id is required".into()));
    }
    let deleted = sqlx::query("DELETE FROM reading_progress WHERE user_id = ? AND device_id = ?")
        .bind(&user.id)
        .bind(device_id)
        .execute(&state.db)
        .await?
        .rows_affected();
    Ok(Json(serde_json::json!({ "deleted": deleted })))
}
