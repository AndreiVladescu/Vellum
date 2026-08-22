//! Personal data: what belongs to *you* rather than to the library.
//!
//! Highlights, notes, bookmarks, reading sittings, the private note you keep
//! about a book, and your profile photo. Until these existed an account was
//! only a key to a shared library; three devices signed into it kept three
//! disjoint sets of everything personal, silently and forever.
//!
//! **One rule holds the whole module together: `user_id` comes from the token,
//! never from a body or a path.** A shared library holds several people's
//! highlights in the same book, and one person's reading is not another's
//! business. `reading_progress` (see `reading.rs`) established the pattern;
//! this follows it, including the join against `access_predicate()` so a book
//! that stops being shared with you stops returning your rows too.
//!
//! Two shapes of data, deliberately handled differently:
//!
//! - **Annotations and notes are mutable**, so they carry `updated_at` for
//!   last-write-wins and — for annotations — lean on the shared `deletion`
//!   table so a delete propagates instead of the row returning on the next
//!   pull.
//! - **Sessions are immutable facts.** A sitting happened; nothing about it is
//!   ever edited. Merging is a union keyed by id, so re-pushing one is
//!   idempotent and there is no conflict to resolve at all.

use axum::Json;
use axum::body::Bytes;
use axum::extract::{Path, Query, State};
use axum::http::{StatusCode, header};
use axum::response::Response;
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::access::book_access;
use crate::auth::AuthUser;
use crate::books::access_predicate;
use crate::error::{AppError, AppResult};

/// Same `cursor`-presence convention as `books::list` and `reading::list`:
/// present (even empty) selects the `{ server_now, entries }` envelope, absent
/// returns a bare array. Keeping it identical is what lets the app's sync loop
/// treat every entity the same way.
#[derive(Deserialize)]
pub struct ListQuery {
    pub cursor: Option<String>,
}

/// Wraps a delta list in the envelope the sync cursor needs.
async fn envelope<T: Serialize>(
    state: &AppState,
    cursor: &Option<String>,
    entries: Vec<T>,
) -> AppResult<Json<serde_json::Value>> {
    if cursor.is_some() {
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

fn since(cursor: &Option<String>) -> Option<&str> {
    cursor.as_deref().map(str::trim).filter(|c| !c.is_empty())
}

/// The caller must be able to see the book before anything of theirs may be
/// attached to it. `book_access` answers `None` for a missing book as well, so
/// this covers 404 without telling an unauthorized caller which ids exist.
async fn require_view(state: &AppState, user: &AuthUser, book_id: &str) -> AppResult<()> {
    if !book_access(state, user, book_id).await?.can_view() {
        return Err(AppError::NotFound("no such book".into()));
    }
    Ok(())
}

// ---- annotations ----------------------------------------------------------

#[derive(Serialize, sqlx::FromRow)]
pub struct AnnotationDto {
    pub id: String,
    pub book_id: String,
    pub kind: String,
    pub page: Option<i64>,
    pub chapter: Option<i64>,
    pub locator: Option<String>,
    pub quoted_text: Option<String>,
    pub note: Option<String>,
    pub color: Option<i64>,
    pub created_at: String,
    pub updated_at: String,
}

#[derive(Deserialize)]
pub struct AnnotationInput {
    pub book_id: String,
    pub kind: String,
    pub page: Option<i64>,
    pub chapter: Option<i64>,
    pub locator: Option<String>,
    pub quoted_text: Option<String>,
    pub note: Option<String>,
    pub color: Option<i64>,
    pub created_at: Option<String>,
    /// The writing device's clock, and the last-write-wins comparison key.
    pub updated_at: Option<String>,
}

pub async fn list_annotations(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<ListQuery>,
) -> AppResult<Json<serde_json::Value>> {
    // Filtered on the *server's* clock, not the writing device's: a note made
    // on Monday and pushed on Friday has to reach a device that synced on
    // Wednesday. See migration 0034.
    let filter = if since(&q.cursor).is_some() {
        " AND a.synced_at >= ?"
    } else {
        ""
    };
    let sql = format!(
        "SELECT a.id, a.book_id, a.kind, a.page, a.chapter, a.locator, \
                a.quoted_text, a.note, a.color, a.created_at, a.updated_at \
         FROM annotation a JOIN book b ON b.id = a.book_id \
         WHERE a.user_id = ? AND {} {filter} \
         ORDER BY a.synced_at",
        access_predicate()
    );
    let mut query = sqlx::query_as::<_, AnnotationDto>(sqlx::AssertSqlSafe(sql.as_str()))
        .bind(&user.id)
        .bind(&user.id)
        .bind(user.is_master)
        .bind(&user.id);
    if let Some(ts) = since(&q.cursor) {
        query = query.bind(ts.to_string());
    }
    let entries = query.fetch_all(&state.db).await?;
    envelope(&state, &q.cursor, entries).await
}

pub async fn upsert_annotation(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(input): Json<AnnotationInput>,
) -> AppResult<Json<AnnotationDto>> {
    crate::ids::check("annotation", &id)?;
    if !matches!(input.kind.as_str(), "highlight" | "note" | "bookmark") {
        return Err(AppError::BadRequest(
            "kind must be 'highlight', 'note' or 'bookmark'".into(),
        ));
    }
    require_view(&state, &user, &input.book_id).await?;

    // `user_id` is in the WHERE of the update half, so a client cannot take
    // over someone else's annotation by guessing its id: the insert would fail
    // the primary key and the update would match no row.
    let affected = sqlx::query(
        "INSERT INTO annotation \
            (id, user_id, book_id, kind, page, chapter, locator, quoted_text, note, color, \
             created_at, updated_at, synced_at) \
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, \
                 COALESCE(?, datetime('now')), COALESCE(?, datetime('now')), datetime('now')) \
         ON CONFLICT(id) DO UPDATE SET \
            kind = excluded.kind, page = excluded.page, chapter = excluded.chapter, \
            locator = excluded.locator, quoted_text = excluded.quoted_text, \
            note = excluded.note, color = excluded.color, \
            updated_at = excluded.updated_at, synced_at = datetime('now') \
         WHERE annotation.user_id = ? AND excluded.updated_at >= annotation.updated_at",
    )
    .bind(&id)
    .bind(&user.id)
    .bind(&input.book_id)
    .bind(&input.kind)
    .bind(input.page)
    .bind(input.chapter)
    .bind(&input.locator)
    .bind(&input.quoted_text)
    .bind(&input.note)
    .bind(input.color)
    .bind(&input.created_at)
    .bind(&input.updated_at)
    .bind(&user.id)
    .execute(&state.db)
    .await?
    .rows_affected();

    let row: Option<AnnotationDto> = sqlx::query_as(
        "SELECT id, book_id, kind, page, chapter, locator, quoted_text, note, color, \
                created_at, updated_at \
         FROM annotation WHERE id = ? AND user_id = ?",
    )
    .bind(&id)
    .bind(&user.id)
    .fetch_optional(&state.db)
    .await?;

    match row {
        Some(row) => Ok(Json(row)),
        // Nothing written and nothing readable means the id belongs to someone
        // else. Say "not found" rather than "forbidden": which ids exist is
        // not something an unrelated caller gets to learn.
        None if affected == 0 => Err(AppError::NotFound("no such annotation".into())),
        None => Err(AppError::NotFound("no such annotation".into())),
    }
}

pub async fn delete_annotation(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    let deleted = sqlx::query("DELETE FROM annotation WHERE id = ? AND user_id = ?")
        .bind(&id)
        .bind(&user.id)
        .execute(&state.db)
        .await?
        .rows_affected();
    if deleted == 0 {
        return Err(AppError::NotFound("no such annotation".into()));
    }
    // A tombstone, so the other devices stop showing it instead of pushing it
    // back on their next sync. `owner_id` scopes it to this user — another
    // account's pull must not see it.
    sqlx::query(
        "INSERT INTO deletion (entity_id, owner_id, kind, deleted_at) \
         VALUES (?, ?, 'annotation', datetime('now')) \
         ON CONFLICT(kind, entity_id) DO UPDATE SET deleted_at = excluded.deleted_at",
    )
    .bind(&id)
    .bind(&user.id)
    .execute(&state.db)
    .await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

#[derive(Serialize, sqlx::FromRow)]
pub struct AnnotationTombstoneDto {
    pub id: String,
    pub deleted_at: String,
}

/// The caller's own annotation tombstones.
///
/// Its own endpoint rather than a `kind=annotation` filter on `/deletions`,
/// because that one is deliberately unscoped — book and shelf tombstones are
/// library-wide facts. These are not: which of my highlights I threw away is
/// mine, and routing them through the shared list would hand every account the
/// ids of every other account's deletions.
pub async fn list_annotation_deletions(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<ListQuery>,
) -> AppResult<Json<serde_json::Value>> {
    let filter = if since(&q.cursor).is_some() {
        " AND deleted_at >= ?"
    } else {
        ""
    };
    let sql = format!(
        "SELECT entity_id AS id, deleted_at FROM deletion \
         WHERE kind = 'annotation' AND owner_id = ? {filter} ORDER BY deleted_at"
    );
    let mut query = sqlx::query_as::<_, AnnotationTombstoneDto>(sqlx::AssertSqlSafe(sql.as_str()))
        .bind(&user.id);
    if let Some(ts) = since(&q.cursor) {
        query = query.bind(ts.to_string());
    }
    let entries = query.fetch_all(&state.db).await?;
    envelope(&state, &q.cursor, entries).await
}

// ---- reading sessions -----------------------------------------------------

#[derive(Serialize, sqlx::FromRow)]
pub struct SessionDto {
    pub id: String,
    pub book_id: String,
    pub device_id: Option<String>,
    pub device_label: Option<String>,
    pub started_at: String,
    pub ended_at: String,
    pub start_page: Option<i64>,
    pub end_page: Option<i64>,
    pub updated_at: String,
}

#[derive(Deserialize)]
pub struct SessionInput {
    pub book_id: String,
    pub device_id: Option<String>,
    pub device_label: Option<String>,
    pub started_at: String,
    pub ended_at: String,
    pub start_page: Option<i64>,
    pub end_page: Option<i64>,
}

pub async fn list_sessions(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<ListQuery>,
) -> AppResult<Json<serde_json::Value>> {
    let filter = if since(&q.cursor).is_some() {
        " AND s.synced_at >= ?"
    } else {
        ""
    };
    let sql = format!(
        "SELECT s.id, s.book_id, s.device_id, s.device_label, s.started_at, s.ended_at, \
                s.start_page, s.end_page, s.updated_at \
         FROM reading_session s JOIN book b ON b.id = s.book_id \
         WHERE s.user_id = ? AND {} {filter} \
         ORDER BY s.synced_at",
        access_predicate()
    );
    let mut query = sqlx::query_as::<_, SessionDto>(sqlx::AssertSqlSafe(sql.as_str()))
        .bind(&user.id)
        .bind(&user.id)
        .bind(user.is_master)
        .bind(&user.id);
    if let Some(ts) = since(&q.cursor) {
        query = query.bind(ts.to_string());
    }
    let entries = query.fetch_all(&state.db).await?;
    envelope(&state, &q.cursor, entries).await
}

/// Record a sitting. Idempotent by id: a session is a fact that already
/// happened, so a re-push is the same fact arriving twice, not a second row and
/// not a conflict.
pub async fn upsert_session(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(input): Json<SessionInput>,
) -> AppResult<Json<SessionDto>> {
    crate::ids::check("session", &id)?;
    require_view(&state, &user, &input.book_id).await?;
    sqlx::query(
        "INSERT INTO reading_session \
            (id, user_id, book_id, device_id, device_label, started_at, ended_at, \
             start_page, end_page, updated_at, synced_at) \
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now'), datetime('now')) \
         ON CONFLICT(id) DO NOTHING",
    )
    .bind(&id)
    .bind(&user.id)
    .bind(&input.book_id)
    .bind(&input.device_id)
    .bind(&input.device_label)
    .bind(&input.started_at)
    .bind(&input.ended_at)
    .bind(input.start_page)
    .bind(input.end_page)
    .execute(&state.db)
    .await?;

    let row: SessionDto = sqlx::query_as(
        "SELECT id, book_id, device_id, device_label, started_at, ended_at, \
                start_page, end_page, updated_at \
         FROM reading_session WHERE id = ? AND user_id = ?",
    )
    .bind(&id)
    .bind(&user.id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("no such session".into()))?;
    Ok(Json(row))
}

// ---- private notes about a book -------------------------------------------

#[derive(Serialize, sqlx::FromRow)]
pub struct BookNoteDto {
    pub book_id: String,
    pub note: String,
    pub updated_at: String,
}

#[derive(Deserialize)]
pub struct BookNoteInput {
    pub note: String,
    pub updated_at: Option<String>,
}

pub async fn list_notes(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<ListQuery>,
) -> AppResult<Json<serde_json::Value>> {
    let filter = if since(&q.cursor).is_some() {
        " AND n.synced_at >= ?"
    } else {
        ""
    };
    let sql = format!(
        "SELECT n.book_id, n.note, n.updated_at \
         FROM book_note n JOIN book b ON b.id = n.book_id \
         WHERE n.user_id = ? AND {} {filter} \
         ORDER BY n.synced_at",
        access_predicate()
    );
    let mut query = sqlx::query_as::<_, BookNoteDto>(sqlx::AssertSqlSafe(sql.as_str()))
        .bind(&user.id)
        .bind(&user.id)
        .bind(user.is_master)
        .bind(&user.id);
    if let Some(ts) = since(&q.cursor) {
        query = query.bind(ts.to_string());
    }
    let entries = query.fetch_all(&state.db).await?;
    envelope(&state, &q.cursor, entries).await
}

/// Where a book stands with *you*: unread, reading, finished, wanted.
///
/// Per user rather than on the book row — migration 0006 took reading state off
/// `book` and 0034 explains why it stays off. In a shared library "I finished
/// it" is a fact about the reader, not the book.
#[derive(Serialize, sqlx::FromRow)]
pub struct BookStatusDto {
    pub book_id: String,
    pub status: String,
    pub started_at: Option<String>,
    pub finished_at: Option<String>,
    pub read_count: i64,
    pub updated_at: String,
}

#[derive(Deserialize)]
pub struct BookStatusInput {
    pub status: String,
    pub started_at: Option<String>,
    pub finished_at: Option<String>,
    #[serde(default)]
    pub read_count: i64,
    /// The writing device's clock, and the last-write-wins comparison key.
    pub updated_at: Option<String>,
}

pub async fn list_statuses(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<ListQuery>,
) -> AppResult<Json<serde_json::Value>> {
    let filter = if since(&q.cursor).is_some() {
        " AND s.synced_at >= ?"
    } else {
        ""
    };
    let sql = format!(
        "SELECT s.book_id, s.status, s.started_at, s.finished_at, s.read_count, \
                s.updated_at \
         FROM book_status s JOIN book b ON b.id = s.book_id \
         WHERE s.user_id = ? AND {} {filter} \
         ORDER BY s.synced_at",
        access_predicate()
    );
    let mut query = sqlx::query_as::<_, BookStatusDto>(sqlx::AssertSqlSafe(sql.as_str()))
        .bind(&user.id)
        .bind(&user.id)
        .bind(user.is_master)
        .bind(&user.id);
    if let Some(ts) = since(&q.cursor) {
        query = query.bind(ts.to_string());
    }
    let entries = query.fetch_all(&state.db).await?;
    envelope(&state, &q.cursor, entries).await
}

/// Last-write-wins on the whole row: the status and its dates are one act, and
/// a "finished" that arrived without its finish date would be half a fact.
///
/// The status string is not checked against a list. A device that learns a new
/// state should not need its server upgraded before its own other devices can
/// see it; an unknown value reads back as whatever the app makes of it.
pub async fn upsert_status(
    State(state): State<AppState>,
    user: AuthUser,
    Path(book_id): Path<String>,
    Json(input): Json<BookStatusInput>,
) -> AppResult<Json<BookStatusDto>> {
    if input.status.trim().is_empty() {
        return Err(AppError::BadRequest("status must not be empty".into()));
    }
    require_view(&state, &user, &book_id).await?;
    sqlx::query(
        "INSERT INTO book_status \
            (user_id, book_id, status, started_at, finished_at, read_count, \
             updated_at, synced_at) \
         VALUES (?, ?, ?, ?, ?, ?, COALESCE(?, datetime('now')), datetime('now')) \
         ON CONFLICT(user_id, book_id) DO UPDATE SET \
            status = excluded.status, \
            started_at = excluded.started_at, \
            finished_at = excluded.finished_at, \
            read_count = excluded.read_count, \
            updated_at = excluded.updated_at, \
            synced_at = datetime('now') \
         WHERE excluded.updated_at >= book_status.updated_at",
    )
    .bind(&user.id)
    .bind(&book_id)
    .bind(input.status.trim())
    .bind(&input.started_at)
    .bind(&input.finished_at)
    .bind(input.read_count)
    .bind(&input.updated_at)
    .execute(&state.db)
    .await?;

    let row: BookStatusDto = sqlx::query_as(
        "SELECT book_id, status, started_at, finished_at, read_count, updated_at \
         FROM book_status WHERE user_id = ? AND book_id = ?",
    )
    .bind(&user.id)
    .bind(&book_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(row))
}

/// Last-write-wins on the note text. Clearing it stores an empty string rather
/// than deleting the row: there is nothing else in the row to lose, and a
/// tombstone for one string is more machinery than the case deserves.
pub async fn upsert_note(
    State(state): State<AppState>,
    user: AuthUser,
    Path(book_id): Path<String>,
    Json(input): Json<BookNoteInput>,
) -> AppResult<Json<BookNoteDto>> {
    require_view(&state, &user, &book_id).await?;
    sqlx::query(
        "INSERT INTO book_note (user_id, book_id, note, updated_at, synced_at) \
         VALUES (?, ?, ?, COALESCE(?, datetime('now')), datetime('now')) \
         ON CONFLICT(user_id, book_id) DO UPDATE SET \
            note = excluded.note, updated_at = excluded.updated_at, \
            synced_at = datetime('now') \
         WHERE excluded.updated_at >= book_note.updated_at",
    )
    .bind(&user.id)
    .bind(&book_id)
    .bind(&input.note)
    .bind(&input.updated_at)
    .execute(&state.db)
    .await?;

    let row: BookNoteDto = sqlx::query_as(
        "SELECT book_id, note, updated_at FROM book_note WHERE user_id = ? AND book_id = ?",
    )
    .bind(&user.id)
    .bind(&book_id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(row))
}

// ---- profile --------------------------------------------------------------

#[derive(Serialize, sqlx::FromRow)]
pub struct ProfileDto {
    pub display_name: String,
    pub email: String,
    pub has_avatar: bool,
    pub profile_updated_at: String,
}

#[derive(Deserialize)]
pub struct ProfileInput {
    pub display_name: Option<String>,
}

pub async fn get_profile(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<ProfileDto>> {
    let row: ProfileDto = sqlx::query_as(
        "SELECT display_name, email, avatar_path IS NOT NULL AS has_avatar, \
                profile_updated_at \
         FROM app_user WHERE id = ?",
    )
    .bind(&user.id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(row))
}

pub async fn update_profile(
    State(state): State<AppState>,
    user: AuthUser,
    Json(input): Json<ProfileInput>,
) -> AppResult<Json<ProfileDto>> {
    if let Some(name) = input.display_name.as_deref() {
        let name = name.trim();
        if name.is_empty() {
            return Err(AppError::BadRequest("display_name cannot be empty".into()));
        }
        sqlx::query(
            "UPDATE app_user SET display_name = ?, profile_updated_at = datetime('now') \
             WHERE id = ?",
        )
        .bind(name)
        .bind(&user.id)
        .execute(&state.db)
        .await?;
    }
    get_profile(State(state), user).await
}

/// The avatar's path under the data dir. Named by user id rather than by
/// content hash: there is exactly one per account, and a stable name means
/// replacing it doesn't leave the old one behind to sweep up.
fn avatar_rel(user_id: &str) -> String {
    format!("avatars/{user_id}")
}

pub async fn put_avatar(
    State(state): State<AppState>,
    user: AuthUser,
    body: Bytes,
) -> AppResult<Json<ProfileDto>> {
    if body.is_empty() {
        return Err(AppError::BadRequest("empty upload".into()));
    }
    // A cap far above any avatar: the app scales to 512px before uploading, so
    // anything larger is a client that didn't, not a photo that needs it.
    if body.len() > 4 * 1024 * 1024 {
        return Err(AppError::BadRequest("avatar must be under 4 MB".into()));
    }
    // Judged by magic bytes rather than a declared type — the same check the
    // cover upload makes, for the same reason.
    if !matches!(
        crate::blobs::sniff(&body),
        crate::blobs::Sniffed::Jpeg
            | crate::blobs::Sniffed::Png
            | crate::blobs::Sniffed::Gif
            | crate::blobs::Sniffed::WebP
    ) {
        return Err(AppError::BadRequest("avatar must be an image".into()));
    }

    let rel = avatar_rel(&user.id);
    let full = state.data_dir.join(&rel);
    if let Some(parent) = full.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|e| AppError::Internal(e.to_string()))?;
    }
    tokio::fs::write(&full, &body)
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;

    sqlx::query(
        "UPDATE app_user SET avatar_path = ?, profile_updated_at = datetime('now') WHERE id = ?",
    )
    .bind(&rel)
    .bind(&user.id)
    .execute(&state.db)
    .await?;
    get_profile(State(state), user).await
}

pub async fn get_avatar(State(state): State<AppState>, user: AuthUser) -> AppResult<Response> {
    let stored: Option<String> =
        sqlx::query_scalar("SELECT avatar_path FROM app_user WHERE id = ?")
            .bind(&user.id)
            .fetch_one(&state.db)
            .await?;
    let rel = stored.ok_or_else(|| AppError::NotFound("no avatar".into()))?;
    let bytes = tokio::fs::read(state.data_dir.join(&rel))
        .await
        .map_err(|_| AppError::NotFound("no avatar".into()))?;
    let content_type = match crate::blobs::sniff(&bytes) {
        crate::blobs::Sniffed::Png => "image/png",
        crate::blobs::Sniffed::Jpeg => "image/jpeg",
        crate::blobs::Sniffed::Gif => "image/gif",
        crate::blobs::Sniffed::WebP => "image/webp",
        _ => "application/octet-stream",
    };
    Response::builder()
        .status(StatusCode::OK)
        .header(header::CONTENT_TYPE, content_type)
        .body(bytes.into())
        .map_err(|e| AppError::Internal(e.to_string()))
}

pub async fn delete_avatar(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<ProfileDto>> {
    let stored: Option<String> =
        sqlx::query_scalar("SELECT avatar_path FROM app_user WHERE id = ?")
            .bind(&user.id)
            .fetch_one(&state.db)
            .await?;
    if let Some(rel) = stored {
        let _ = tokio::fs::remove_file(state.data_dir.join(&rel)).await;
    }
    sqlx::query(
        "UPDATE app_user SET avatar_path = NULL, profile_updated_at = datetime('now') \
         WHERE id = ?",
    )
    .bind(&user.id)
    .execute(&state.db)
    .await?;
    get_profile(State(state), user).await
}
