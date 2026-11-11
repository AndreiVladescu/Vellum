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
    pub ink: Option<String>,
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
    /// The marks themselves, for `kind = 'ink'`: strokes and text boxes in
    /// page-relative coordinates, as the versioned JSON migration 0036
    /// describes. Stored and returned verbatim — the server does not read it.
    pub ink: Option<String>,
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
                a.quoted_text, a.note, a.color, a.ink, a.created_at, a.updated_at \
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
    if !matches!(
        input.kind.as_str(),
        "highlight" | "note" | "bookmark" | "ink"
    ) {
        return Err(AppError::BadRequest(
            "kind must be 'highlight', 'note', 'bookmark' or 'ink'".into(),
        ));
    }
    require_view(&state, &user, &input.book_id).await?;

    // `user_id` is in the WHERE of the update half, so a client cannot take
    // over someone else's annotation by guessing its id: the insert would fail
    // the primary key and the update would match no row.
    let affected = sqlx::query(
        "INSERT INTO annotation \
            (id, user_id, book_id, kind, page, chapter, locator, quoted_text, note, color, \
             ink, created_at, updated_at, synced_at) \
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, \
                 COALESCE(?, datetime('now')), COALESCE(?, datetime('now')), datetime('now')) \
         ON CONFLICT(id) DO UPDATE SET \
            kind = excluded.kind, page = excluded.page, chapter = excluded.chapter, \
            locator = excluded.locator, quoted_text = excluded.quoted_text, \
            note = excluded.note, color = excluded.color, ink = excluded.ink, \
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
    .bind(&input.ink)
    .bind(&input.created_at)
    .bind(&input.updated_at)
    .bind(&user.id)
    .execute(&state.db)
    .await?
    .rows_affected();

    let row: Option<AnnotationDto> = sqlx::query_as(
        "SELECT id, book_id, kind, page, chapter, locator, quoted_text, note, color, ink, \
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

/// Record a sitting.
///
/// Idempotent by id, and *correctable*: the end of a sitting is not known when
/// it starts, and a client that syncs mid-read pushes a row that is true so far
/// and wrong by the time the reader puts the book down. `DO NOTHING` froze that
/// half-sitting for good — every other device then held a sitting that ended
/// early, and the pace measured from it was wrong. Only the mutable half moves,
/// and only forwards: where it started is a fact, where it ended is a fact that
/// was still being made.
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
         ON CONFLICT(id) DO UPDATE SET \
            ended_at = excluded.ended_at, \
            end_page = excluded.end_page, \
            device_label = excluded.device_label, \
            updated_at = datetime('now'), \
            synced_at = datetime('now') \
         WHERE reading_session.user_id = ? \
           AND excluded.ended_at >= reading_session.ended_at",
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
    .bind(&user.id)
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

/// Where a book stands with *you*: unread, reading, finished, wanted — and what
/// you thought of it.
///
/// Per user rather than on the book row — migration 0006 took reading state off
/// `book` and 0034 explains why it stays off. In a shared library "I finished
/// it" and "five stars" are facts about the reader, not the book.
///
/// The rating (migration 0038) has its own clock, `rating_updated_at`: null
/// means no rating-aware client has written it, so nobody knows; with a clock,
/// `rating` null is "unrated" and 1–5 is the rating. `inferred` says the status
/// was guessed by the app (opening an unread book) rather than chosen. See
/// [`merge_status`] for how both are used.
#[derive(Serialize, sqlx::FromRow, Clone, Debug, PartialEq)]
pub struct BookStatusDto {
    pub book_id: String,
    pub status: String,
    pub started_at: Option<String>,
    pub finished_at: Option<String>,
    pub read_count: i64,
    pub inferred: bool,
    pub updated_at: String,
    pub rating: Option<i64>,
    pub rating_updated_at: Option<String>,
}

#[derive(Deserialize)]
pub struct BookStatusInput {
    pub status: String,
    pub started_at: Option<String>,
    pub finished_at: Option<String>,
    #[serde(default)]
    pub read_count: i64,
    /// The status came from the automatic unread → reading transition rather
    /// than from the reader. Absent means chosen, which is what older apps meant.
    #[serde(default)]
    pub inferred: bool,
    /// The writing device's clock for the status, and the last-write-wins
    /// comparison key for it.
    pub updated_at: Option<String>,
    /// 1–5, or null for unrated. Only read when `rating_updated_at` is present.
    pub rating: Option<i64>,
    /// When the rating was last changed on the writing device. Absent means the
    /// push says nothing about the rating — what every app older than migration
    /// 0038 sends, and what a device that never rated the book sends — and must
    /// not clear a rating another device set.
    pub rating_updated_at: Option<String>,
}

/// How a pushed status combines with the one already stored.
///
/// One row, two clocks: the status and its dates on `updated_at`, the rating on
/// `rating_updated_at`. They are separate acts — tapping a star is not choosing
/// a status — and one clock would let either overwrite the other from a stale
/// device: rating a book on a tablet that missed the phone's "finished" would
/// publish the tablet's "unread" as the newest status. Each half is
/// last-write-wins on its own clock, and a rating with no clock is unknown, so
/// any rating that has one fills it.
///
/// The status half has two refinements, each for a case plain LWW gets wrong:
///
/// - **An inference yields to a choice.** "Reading" set automatically by
///   opening the book is a guess from what that device knew. A device offline
///   since before the book was finished elsewhere makes that guess with a
///   *newer* clock than the finish, and plain LWW would let it win. So an
///   inferred status never replaces a chosen one that says something (anything
///   but `unread`), and a chosen one that says something replaces an inference
///   whichever is newer. Between two choices, or two guesses, the clock decides.
/// - **The read count only grows.** It counts finishes, and the app never
///   lowers it — moving back out of `finished` clears the date, not the count.
///   So the merge takes the larger of the two rather than the newer one: a
///   stale device's later "abandoned" must not erase a finish it never heard
///   of. Two devices that each mark the same reading finished while offline
///   count it once, which is what almost always happened; a genuine second
///   reading finished on two devices without syncing in between also counts
///   once, and that is the accepted cost — nothing on the wire tells the two
///   apart, and summing would double-count the common case instead.
///
/// The status clock becomes the later of the two, so a device holding either
/// copy is never newer than the merged result.
pub fn merge_status(existing: Option<&BookStatusDto>, incoming: BookStatusDto) -> BookStatusDto {
    let Some(old) = existing else {
        return incoming;
    };
    let newer = incoming.updated_at >= old.updated_at;
    let take_status = if incoming.inferred && !old.inferred && old.status != "unread" {
        false
    } else if !incoming.inferred && old.inferred && incoming.status != "unread" {
        true
    } else {
        newer
    };
    let from = if take_status { &incoming } else { old };
    // `None < Some(_)` for `Option`, so a rating nobody has dated loses to any
    // that has been.
    let take_rating =
        incoming.rating_updated_at.is_some() && incoming.rating_updated_at >= old.rating_updated_at;
    let rating_from = if take_rating { &incoming } else { old };
    BookStatusDto {
        book_id: old.book_id.clone(),
        status: from.status.clone(),
        started_at: from.started_at.clone(),
        finished_at: from.finished_at.clone(),
        inferred: from.inferred,
        read_count: old.read_count.max(incoming.read_count),
        updated_at: old.updated_at.clone().max(incoming.updated_at.clone()),
        rating: rating_from.rating,
        rating_updated_at: rating_from.rating_updated_at.clone(),
    }
}

const STATUS_COLUMNS: &str = "book_id, status, started_at, finished_at, read_count, \
     status_inferred AS inferred, updated_at, rating, rating_updated_at";

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
                s.status_inferred AS inferred, s.updated_at, s.rating, s.rating_updated_at \
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

/// Records where a book stands with the caller, merged with what is already
/// stored by [`merge_status`], and answers with the result. That is not always
/// what was sent, so a device can adopt the merge at once instead of learning it
/// a sync later.
///
/// The status and its dates still travel as one act — a "finished" that
/// arrived without its finish date would be half a fact — so they are taken or
/// left together.
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
    if let Some(r) = input.rating
        && !(1..=5).contains(&r)
    {
        return Err(AppError::BadRequest(
            "rating must be 1-5, or null for unrated".into(),
        ));
    }
    require_view(&state, &user, &book_id).await?;

    // Read, merge, write in one immediate transaction, so two pushes for the
    // same book cannot both merge against the row as it was before either.
    let mut tx = crate::write_tx(&state.db).await?;
    let existing: Option<BookStatusDto> = sqlx::query_as(sqlx::AssertSqlSafe(format!(
        "SELECT {STATUS_COLUMNS} FROM book_status WHERE user_id = ? AND book_id = ?"
    )))
    .bind(&user.id)
    .bind(&book_id)
    .fetch_optional(&mut *tx)
    .await?;
    let updated_at = match input.updated_at {
        Some(t) => t,
        None => {
            sqlx::query_scalar("SELECT datetime('now')")
                .fetch_one(&mut *tx)
                .await?
        }
    };
    let incoming = BookStatusDto {
        book_id: book_id.clone(),
        status: input.status.trim().to_string(),
        started_at: input.started_at,
        finished_at: input.finished_at,
        read_count: input.read_count.max(0),
        inferred: input.inferred,
        updated_at,
        // An undated rating says nothing, so it is not even carried.
        rating: input.rating.filter(|_| input.rating_updated_at.is_some()),
        rating_updated_at: input.rating_updated_at,
    };
    let merged = merge_status(existing.as_ref(), incoming);

    // Nothing changed, nothing written: `synced_at` is what hands a row to the
    // other devices, and re-sending what they already hold is noise.
    if existing.as_ref() != Some(&merged) {
        sqlx::query(
            "INSERT INTO book_status \
                (user_id, book_id, status, started_at, finished_at, read_count, \
                 status_inferred, updated_at, rating, rating_updated_at, synced_at) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, datetime('now')) \
             ON CONFLICT(user_id, book_id) DO UPDATE SET \
                status = excluded.status, \
                started_at = excluded.started_at, \
                finished_at = excluded.finished_at, \
                read_count = excluded.read_count, \
                status_inferred = excluded.status_inferred, \
                updated_at = excluded.updated_at, \
                rating = excluded.rating, \
                rating_updated_at = excluded.rating_updated_at, \
                synced_at = datetime('now')",
        )
        .bind(&user.id)
        .bind(&book_id)
        .bind(&merged.status)
        .bind(&merged.started_at)
        .bind(&merged.finished_at)
        .bind(merged.read_count)
        .bind(merged.inferred)
        .bind(&merged.updated_at)
        .bind(merged.rating)
        .bind(&merged.rating_updated_at)
        .execute(&mut *tx)
        .await?;
    }
    tx.commit().await?;
    Ok(Json(merged))
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
