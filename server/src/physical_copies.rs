//! Physical copies (plan 5 #4, second of three): a book's real-world copies
//! now sync like books/shelves rather than living only on one device. Unlike
//! shelf, a copy has no owner of its own — visibility and edit rights derive
//! entirely from its parent book (see `access::copy_access` and
//! `books::access_predicate`, reused here via a join on `book`).

use axum::Json;
use axum::extract::{Path, Query, State};
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::access::copy_access;
use crate::auth::AuthUser;
use crate::books::access_predicate;
use crate::error::{AppError, AppResult};

#[derive(Serialize, sqlx::FromRow)]
pub struct CopyDto {
    pub id: String,
    pub book_id: String,
    pub location: Option<String>,
    pub condition: Option<String>,
    pub notes: Option<String>,
    pub updated_at: String,
}

const COPY_COLUMNS: &str = "id, book_id, location, condition, notes, updated_at";

#[derive(Deserialize)]
pub struct CopyInput {
    /// Which book this copy belongs to. Only meaningful when creating a new
    /// copy id; [`upsert`] rejects a push that tries to change it on an
    /// existing one (a copy moving to a different book isn't a supported
    /// operation, and silently allowing it would let a stale owner-check
    /// linger).
    pub book_id: String,
    pub location: Option<String>,
    pub condition: Option<String>,
    pub notes: Option<String>,
    /// The pushing client's sync clock, same LWW convention as `BookInput`.
    #[serde(default)]
    pub updated_at: Option<String>,
}

/// Copies of books the caller can see, joined through `access_predicate()`
/// on the parent book — a copy has no share/ownership of its own.
/// `updated_since` narrows to a delta pull, same `>=` convention as
/// `books::visible_books`.
async fn visible_copies(
    state: &AppState,
    user: &AuthUser,
    updated_since: Option<&str>,
) -> AppResult<Vec<CopyDto>> {
    let filter = if updated_since.is_some() {
        " AND pc.updated_at >= ?"
    } else {
        ""
    };
    let sql = format!(
        "SELECT pc.id, pc.book_id, pc.location, pc.condition, pc.notes, pc.updated_at \
         FROM physical_copy pc JOIN book b ON b.id = pc.book_id \
         WHERE {} {filter} ORDER BY pc.id",
        access_predicate()
    );
    let mut query = sqlx::query_as::<_, CopyDto>(&sql)
        .bind(&user.id)
        .bind(user.is_master)
        .bind(&user.id);
    if let Some(ts) = updated_since {
        query = query.bind(ts.to_string());
    }
    Ok(query.fetch_all(&state.db).await?)
}

/// Query params: same `cursor`-presence convention as `books::list`/
/// `shelves::list` — present (even empty) selects the `{ server_now, copies
/// }` envelope, filtered to copies changed since it when non-empty; absent
/// returns a bare array. No paged/console shape, same as shelves.
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
    let copies = visible_copies(&state, &user, since).await?;

    if q.cursor.is_some() {
        let server_now: String = sqlx::query_scalar("SELECT datetime('now')")
            .fetch_one(&state.db)
            .await?;
        Ok(Json(serde_json::json!({
            "server_now": server_now,
            "copies": copies,
        })))
    } else {
        Ok(Json(serde_json::to_value(copies)?))
    }
}

/// Upsert a copy at a caller-chosen id: creates it (requires editor access to
/// `book_id`) if absent, otherwise updates it (requires editor access to the
/// copy, i.e. to its book — see `access::copy_access`).
pub async fn upsert(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(input): Json<CopyInput>,
) -> AppResult<Json<CopyDto>> {
    let existing: Option<(String, String)> =
        sqlx::query_as("SELECT book_id, updated_at FROM physical_copy WHERE id = ?")
            .bind(&id)
            .fetch_optional(&state.db)
            .await?;

    let is_update = match &existing {
        Some((stored_book_id, stored_updated_at)) => {
            if &input.book_id != stored_book_id {
                return Err(AppError::BadRequest(
                    "a physical copy cannot change which book it belongs to".into(),
                ));
            }
            if !copy_access(&state, &user, &id).await?.can_edit() {
                return Err(AppError::Forbidden(
                    "you have read-only access to this copy".into(),
                ));
            }
            if let Some(incoming) = input.updated_at.as_deref()
                && incoming <= stored_updated_at.as_str()
            {
                return fetch_copy(&state, &id).await;
            }
            true
        }
        None => {
            if !crate::access::book_access(&state, &user, &input.book_id)
                .await?
                .can_edit()
            {
                return Err(AppError::Forbidden(
                    "you have read-only access to this book".into(),
                ));
            }
            false
        }
    };

    // No-op guard, same reasoning as books::upsert/shelves::upsert: skip the
    // write (and the updated_at churn) when the push wouldn't change anything.
    if is_update {
        let current = fetch_copy(&state, &id).await?.0;
        let tombstoned: bool =
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM deletion WHERE book_id = ?)")
                .bind(&id)
                .fetch_one(&state.db)
                .await?;
        if current.location == input.location
            && current.condition == input.condition
            && current.notes == input.notes
            && !tombstoned
        {
            return Ok(Json(current));
        }
    }

    // Metadata write and tombstone clear share one transaction, same reasoning
    // as books::upsert: a crash must never leave a revived copy still
    // tombstoned (which would delete it again on the next pull).
    let mut tx = state.db.begin().await?;
    if is_update {
        sqlx::query(
            "UPDATE physical_copy SET location = ?, condition = ?, notes = ?, \
                updated_at = datetime('now') WHERE id = ?",
        )
        .bind(&input.location)
        .bind(&input.condition)
        .bind(&input.notes)
        .bind(&id)
        .execute(&mut *tx)
        .await?;
    } else {
        sqlx::query(
            "INSERT INTO physical_copy (id, book_id, location, condition, notes) \
             VALUES (?, ?, ?, ?, ?)",
        )
        .bind(&id)
        .bind(&input.book_id)
        .bind(&input.location)
        .bind(&input.condition)
        .bind(&input.notes)
        .execute(&mut *tx)
        .await?;
    }
    sqlx::query("DELETE FROM deletion WHERE book_id = ? AND kind = 'copy'")
        .bind(&id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    fetch_copy(&state, &id).await
}

/// Delete — restricted to the copy's book's owner or the master, same as
/// `books::delete` (a shared editor may edit a copy's metadata but not
/// remove it, mirroring how a shared editor can't delete the book itself).
pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    let owner: Option<Option<String>> = sqlx::query_scalar(
        "SELECT b.owner_id FROM physical_copy pc JOIN book b ON b.id = pc.book_id \
         WHERE pc.id = ?",
    )
    .bind(&id)
    .fetch_optional(&state.db)
    .await?;
    let Some(owner_id) = owner else {
        return Err(AppError::NotFound("physical copy not found".into()));
    };
    if !user.is_master && owner_id.as_deref() != Some(user.id.as_str()) {
        return Err(AppError::Forbidden(
            "only the book's owner may delete this copy".into(),
        ));
    }

    let mut tx = state.db.begin().await?;
    sqlx::query("INSERT OR REPLACE INTO deletion (book_id, owner_id, kind) VALUES (?, ?, 'copy')")
        .bind(&id)
        .bind(&owner_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM physical_copy WHERE id = ?")
        .bind(&id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    Ok(Json(serde_json::json!({ "deleted": id })))
}

async fn fetch_copy(state: &AppState, id: &str) -> AppResult<Json<CopyDto>> {
    let copy = sqlx::query_as::<_, CopyDto>(&format!(
        "SELECT {COPY_COLUMNS} FROM physical_copy WHERE id = ?"
    ))
    .bind(id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("physical copy not found".into()))?;
    Ok(Json(copy))
}
