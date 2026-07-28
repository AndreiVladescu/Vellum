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

    crate::events::publish(&state, "copy", &id, "upsert");
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

    crate::events::publish(&state, "copy", &id, "delete");
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


// ---- copy photos (plan 6 #4) ----------------------------------------------
//
// Photos of a copy are library data, not personal data: they hang off a copy,
// which already syncs, and are visible to whoever the book is shared with —
// like its covers and files. So this follows the *blob* pattern rather than
// `personal.rs`: a row holding a path, with the bytes going through the same
// store as everything else.

#[derive(Serialize, sqlx::FromRow)]
pub struct CopyPhotoDto {
    pub id: String,
    pub copy_id: String,
    pub path: String,
    pub caption: Option<String>,
    pub taken_at: String,
    pub updated_at: String,
}

#[derive(Deserialize)]
pub struct CopyPhotoInput {
    pub copy_id: String,
    pub caption: Option<String>,
    pub taken_at: Option<String>,
    pub updated_at: Option<String>,
}

pub async fn list_photos(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<ListQuery>,
) -> AppResult<Json<serde_json::Value>> {
    let since = q.cursor.as_deref().map(str::trim).filter(|c| !c.is_empty());
    let filter = if since.is_some() {
        " AND cp.updated_at >= ?"
    } else {
        ""
    };
    // Two joins deep: a photo belongs to a copy, which belongs to a book, and
    // the book is what access is decided on.
    let sql = format!(
        "SELECT cp.id, cp.copy_id, cp.path, cp.caption, cp.taken_at, cp.updated_at \
         FROM copy_photo cp \
         JOIN physical_copy pc ON pc.id = cp.copy_id \
         JOIN book b ON b.id = pc.book_id \
         WHERE {} {filter} ORDER BY cp.id",
        access_predicate()
    );
    let mut query = sqlx::query_as::<_, CopyPhotoDto>(&sql)
        .bind(&user.id)
        .bind(user.is_master)
        .bind(&user.id);
    if let Some(ts) = since {
        query = query.bind(ts.to_string());
    }
    let photos = query.fetch_all(&state.db).await?;

    if q.cursor.is_some() {
        let server_now: String = sqlx::query_scalar("SELECT datetime('now')")
            .fetch_one(&state.db)
            .await?;
        Ok(Json(serde_json::json!({
            "server_now": server_now,
            "photos": photos,
        })))
    } else {
        Ok(Json(serde_json::to_value(photos)?))
    }
}

/// Records a photo against a copy. The bytes are uploaded separately, to
/// `PUT /copy-photos/{id}/image` — same split as a book and its file, so a
/// metadata push doesn't carry megabytes and a failed byte transfer doesn't
/// lose the caption.
pub async fn upsert_photo(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(input): Json<CopyPhotoInput>,
) -> AppResult<Json<CopyPhotoDto>> {
    if !crate::access::copy_access(&state, &user, &input.copy_id)
        .await?
        .can_edit()
    {
        return Err(AppError::NotFound("no such copy".into()));
    }
    // The path is server-chosen, never client-supplied: the same rule that
    // closed H1 for covers. A client that could name the path could name one
    // outside the store.
    let rel = format!("copy-photos/{id}");
    sqlx::query(
        "INSERT INTO copy_photo (id, copy_id, path, caption, taken_at, updated_at) \
         VALUES (?, ?, ?, ?, COALESCE(?, datetime('now')), COALESCE(?, datetime('now'))) \
         ON CONFLICT(id) DO UPDATE SET \
            caption = excluded.caption, taken_at = excluded.taken_at, \
            updated_at = excluded.updated_at \
         WHERE excluded.updated_at >= copy_photo.updated_at",
    )
    .bind(&id)
    .bind(&input.copy_id)
    .bind(&rel)
    .bind(&input.caption)
    .bind(&input.taken_at)
    .bind(&input.updated_at)
    .execute(&state.db)
    .await?;

    let row: CopyPhotoDto = sqlx::query_as(
        "SELECT id, copy_id, path, caption, taken_at, updated_at FROM copy_photo WHERE id = ?",
    )
    .bind(&id)
    .fetch_one(&state.db)
    .await?;
    Ok(Json(row))
}

pub async fn delete_photo(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    let copy_id: Option<String> = sqlx::query_scalar("SELECT copy_id FROM copy_photo WHERE id = ?")
        .bind(&id)
        .fetch_optional(&state.db)
        .await?;
    let copy_id = copy_id.ok_or_else(|| AppError::NotFound("no such photo".into()))?;
    if !crate::access::copy_access(&state, &user, &copy_id)
        .await?
        .can_edit()
    {
        return Err(AppError::NotFound("no such photo".into()));
    }
    sqlx::query("DELETE FROM copy_photo WHERE id = ?")
        .bind(&id)
        .execute(&state.db)
        .await?;
    let _ = tokio::fs::remove_file(state.data_dir.join(format!("copy-photos/{id}"))).await;
    sqlx::query(
        "INSERT INTO deletion (book_id, kind, deleted_at) \
         VALUES (?, 'copy_photo', datetime('now')) \
         ON CONFLICT(book_id) DO UPDATE SET deleted_at = excluded.deleted_at",
    )
    .bind(&id)
    .execute(&state.db)
    .await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

/// Uploads the photo's bytes. Sniffed by magic number like every other image
/// here — a declared content type is a claim, not evidence — and capped by the
/// route's own body limit rather than by a check that can never fire.
pub async fn put_photo_image(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    body: axum::body::Bytes,
) -> AppResult<Json<serde_json::Value>> {
    let copy_id: Option<String> = sqlx::query_scalar("SELECT copy_id FROM copy_photo WHERE id = ?")
        .bind(&id)
        .fetch_optional(&state.db)
        .await?;
    let copy_id = copy_id.ok_or_else(|| AppError::NotFound("no such photo".into()))?;
    if !crate::access::copy_access(&state, &user, &copy_id)
        .await?
        .can_edit()
    {
        return Err(AppError::NotFound("no such photo".into()));
    }
    if !matches!(
        crate::blobs::sniff(&body),
        crate::blobs::Sniffed::Jpeg
            | crate::blobs::Sniffed::Png
            | crate::blobs::Sniffed::Gif
            | crate::blobs::Sniffed::WebP
    ) {
        return Err(AppError::BadRequest("that is not an image".into()));
    }
    let full = state.data_dir.join(format!("copy-photos/{id}"));
    if let Some(parent) = full.parent() {
        tokio::fs::create_dir_all(parent)
            .await
            .map_err(|e| AppError::Internal(e.to_string()))?;
    }
    tokio::fs::write(&full, &body)
        .await
        .map_err(|e| AppError::Internal(e.to_string()))?;
    Ok(Json(serde_json::json!({ "ok": true, "size": body.len() })))
}

pub async fn get_photo_image(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<axum::response::Response> {
    let copy_id: Option<String> = sqlx::query_scalar("SELECT copy_id FROM copy_photo WHERE id = ?")
        .bind(&id)
        .fetch_optional(&state.db)
        .await?;
    let copy_id = copy_id.ok_or_else(|| AppError::NotFound("no such photo".into()))?;
    // View, not edit: seeing a shelf you have read access to is reading.
    if !crate::access::copy_access(&state, &user, &copy_id)
        .await?
        .can_view()
    {
        return Err(AppError::NotFound("no such photo".into()));
    }
    let bytes = tokio::fs::read(state.data_dir.join(format!("copy-photos/{id}")))
        .await
        .map_err(|_| AppError::NotFound("no image yet".into()))?;
    let content_type = match crate::blobs::sniff(&bytes) {
        crate::blobs::Sniffed::Png => "image/png",
        crate::blobs::Sniffed::Jpeg => "image/jpeg",
        crate::blobs::Sniffed::Gif => "image/gif",
        crate::blobs::Sniffed::WebP => "image/webp",
        _ => "application/octet-stream",
    };
    axum::response::Response::builder()
        .status(axum::http::StatusCode::OK)
        .header(axum::http::header::CONTENT_TYPE, content_type)
        .body(bytes.into())
        .map_err(|e| AppError::Internal(e.to_string()))
}
