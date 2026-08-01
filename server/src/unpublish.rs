//! Taking a resource back off the server (next features #8).
//!
//! The app can already stop syncing a resource, but "stop syncing my loans" and
//! "the loans I already sent are still up there" are different states, and only
//! one of them is what someone unticking a box means. Reading position has had
//! its answer since plan 5 #5 (`reading::forget_device`); this is the same idea
//! for the rest.
//!
//! **Everything here is scoped to the caller, never to the library.** Library
//! data — copies, loans, copy photos — is reached through the *books you own*,
//! so un-publishing your loans cannot touch a loan on somebody else's book that
//! merely happens to be shared with you. Personal data — annotations, sittings,
//! private notes — is scoped by `user_id` straight from the token, which is the
//! rule the whole personal channel already follows.
//!
//! Tombstones are written for the library kinds, so *other* devices remove the
//! rows on their next pull instead of pushing them all back. The personal kinds
//! don't need them: they are per-account, and the account is the one asking.

use axum::Json;
use axum::extract::{Path, State};

use crate::AppState;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};

/// `DELETE /api/mine/{resource}` — remove everything of one kind that belongs
/// to the caller.
pub async fn forget(
    State(state): State<AppState>,
    user: AuthUser,
    Path(resource): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    let deleted = match resource.as_str() {
        "copies" => forget_copies(&state, &user).await?,
        "loans" => forget_loans(&state, &user).await?,
        "copy-photos" => forget_copy_photos(&state, &user).await?,
        "annotations" => forget_annotations(&state, &user).await?,
        "sessions" => forget_sessions(&state, &user).await?,
        other => {
            return Err(AppError::BadRequest(format!(
                "'{other}' is not something that can be un-published"
            )));
        }
    };
    Ok(Json(serde_json::json!({ "deleted": deleted })))
}

/// Books the caller owns. The master is not treated as owning everything here:
/// "forget my loans" from the master account should mean *theirs*, not the
/// whole server's, and an operator wiping a member's data has `admin/sweep`
/// and the console for that.
const MY_BOOKS: &str = "SELECT id FROM book WHERE owner_id = ?";

async fn tombstone(state: &AppState, ids: &[String], kind: &str, owner: &str) -> AppResult<()> {
    for id in ids {
        sqlx::query(
            "INSERT INTO deletion (entity_id, owner_id, kind, deleted_at) \
             VALUES (?, ?, ?, datetime('now')) \
             ON CONFLICT(kind, entity_id) DO UPDATE SET deleted_at = excluded.deleted_at",
        )
        .bind(id)
        .bind(owner)
        .bind(kind)
        .execute(&state.db)
        .await?;
    }
    Ok(())
}

async fn forget_copies(state: &AppState, user: &AuthUser) -> AppResult<u64> {
    // Photos and loans hang off a copy, so they go first — the same order
    // `physical_copies::delete` uses, and for the same foreign keys.
    forget_copy_photos(state, user).await?;
    forget_loans(state, user).await?;

    let ids: Vec<String> = sqlx::query_scalar(sqlx::AssertSqlSafe(format!(
        "SELECT id FROM physical_copy WHERE book_id IN ({MY_BOOKS})"
    )))
    .bind(&user.id)
    .fetch_all(&state.db)
    .await?;
    sqlx::query(sqlx::AssertSqlSafe(format!(
        "DELETE FROM physical_copy WHERE book_id IN ({MY_BOOKS})"
    )))
    .bind(&user.id)
    .execute(&state.db)
    .await?;
    tombstone(state, &ids, "copy", &user.id).await?;
    Ok(ids.len() as u64)
}

async fn forget_loans(state: &AppState, user: &AuthUser) -> AppResult<u64> {
    let ids: Vec<String> = sqlx::query_scalar(sqlx::AssertSqlSafe(format!(
        "SELECT l.id FROM loan l JOIN physical_copy pc ON pc.id = l.copy_id \
         WHERE pc.book_id IN ({MY_BOOKS})"
    )))
    .bind(&user.id)
    .fetch_all(&state.db)
    .await?;
    for id in &ids {
        sqlx::query("DELETE FROM loan WHERE id = ?")
            .bind(id)
            .execute(&state.db)
            .await?;
    }
    tombstone(state, &ids, "loan", &user.id).await?;
    Ok(ids.len() as u64)
}

async fn forget_copy_photos(state: &AppState, user: &AuthUser) -> AppResult<u64> {
    let ids: Vec<String> = sqlx::query_scalar(sqlx::AssertSqlSafe(format!(
        "SELECT cp.id FROM copy_photo cp \
         JOIN physical_copy pc ON pc.id = cp.copy_id \
         WHERE pc.book_id IN ({MY_BOOKS})"
    )))
    .bind(&user.id)
    .fetch_all(&state.db)
    .await?;
    for id in &ids {
        sqlx::query("DELETE FROM copy_photo WHERE id = ?")
            .bind(id)
            .execute(&state.db)
            .await?;
        // Best effort, like every other blob unlink: a stray image wastes
        // space, a missing row shows a broken picture, and the row is the half
        // that matters.
        let _ = tokio::fs::remove_file(state.data_dir.join(format!("copy-photos/{id}"))).await;
    }
    tombstone(state, &ids, "copy_photo", &user.id).await?;
    Ok(ids.len() as u64)
}

async fn forget_annotations(state: &AppState, user: &AuthUser) -> AppResult<u64> {
    // Reader notes go with the highlights: a `book_note` is the same personal
    // channel under another name, and the app's switch covers both.
    let notes = sqlx::query("DELETE FROM book_note WHERE user_id = ?")
        .bind(&user.id)
        .execute(&state.db)
        .await?
        .rows_affected();
    let ids: Vec<String> = sqlx::query_scalar("SELECT id FROM annotation WHERE user_id = ?")
        .bind(&user.id)
        .fetch_all(&state.db)
        .await?;
    sqlx::query("DELETE FROM annotation WHERE user_id = ?")
        .bind(&user.id)
        .execute(&state.db)
        .await?;
    // Scoped tombstones, so this account's *other* devices drop them too —
    // `personal::list_annotation_deletions` filters by owner, so nobody else
    // ever sees these.
    tombstone(state, &ids, "annotation", &user.id).await?;
    Ok(ids.len() as u64 + notes)
}

async fn forget_sessions(state: &AppState, user: &AuthUser) -> AppResult<u64> {
    Ok(sqlx::query("DELETE FROM reading_session WHERE user_id = ?")
        .bind(&user.id)
        .execute(&state.db)
        .await?
        .rows_affected())
}
