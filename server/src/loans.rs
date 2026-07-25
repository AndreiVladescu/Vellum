//! Loan history (plan 5 #4, third and last of the trio): a copy's loans now
//! sync like copies rather than living only on one device. Append-mostly —
//! the point is preserving history, so a loan is deleted only via its copy's
//! `ON DELETE CASCADE` (see `physical_copies::delete`); `DELETE /{id}` exists
//! for completeness (removing exactly one loan record) but no app code path
//! calls it today.

use axum::Json;
use axum::extract::{Path, Query, State};
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::access::loan_access;
use crate::auth::AuthUser;
use crate::books::access_predicate;
use crate::error::{AppError, AppResult};

#[derive(Serialize, sqlx::FromRow)]
pub struct LoanDto {
    pub id: String,
    pub copy_id: String,
    pub borrower: String,
    pub loaned_at: String,
    pub returned_at: Option<String>,
    pub updated_at: String,
}

const LOAN_COLUMNS: &str = "id, copy_id, borrower, loaned_at, returned_at, updated_at";

#[derive(Deserialize)]
pub struct LoanInput {
    /// Which copy this loan is for. Only meaningful at creation; [`upsert`]
    /// rejects a push that tries to move an existing loan to a different
    /// copy, same reasoning as `CopyInput::book_id`.
    pub copy_id: String,
    pub borrower: String,
    /// When the loan started. A loan can predate this device's first sync
    /// (lent before the app ever connected to a server), so — unlike
    /// `created_at` elsewhere — this must come from the client, not default
    /// to "now" at creation. Immutable after that, same as `copy_id`.
    pub loaned_at: String,
    pub returned_at: Option<String>,
    /// The pushing client's sync clock, same LWW convention as `CopyInput`.
    #[serde(default)]
    pub updated_at: Option<String>,
}

/// Loans of copies the caller can see, joined through `access_predicate()` on
/// the parent book (via `physical_copy`) — a loan has no share/ownership of
/// its own, same reasoning as `physical_copies::visible_copies`.
async fn visible_loans(
    state: &AppState,
    user: &AuthUser,
    updated_since: Option<&str>,
) -> AppResult<Vec<LoanDto>> {
    let filter = if updated_since.is_some() {
        " AND l.updated_at >= ?"
    } else {
        ""
    };
    let sql = format!(
        "SELECT l.id, l.copy_id, l.borrower, l.loaned_at, l.returned_at, l.updated_at \
         FROM loan l \
         JOIN physical_copy pc ON pc.id = l.copy_id \
         JOIN book b ON b.id = pc.book_id \
         WHERE {} {filter} ORDER BY l.id",
        access_predicate()
    );
    let mut query = sqlx::query_as::<_, LoanDto>(&sql)
        .bind(&user.id)
        .bind(user.is_master)
        .bind(&user.id);
    if let Some(ts) = updated_since {
        query = query.bind(ts.to_string());
    }
    Ok(query.fetch_all(&state.db).await?)
}

/// Query params: same `cursor`-presence convention as `physical_copies::list`.
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
    let loans = visible_loans(&state, &user, since).await?;

    if q.cursor.is_some() {
        let server_now: String = sqlx::query_scalar("SELECT datetime('now')")
            .fetch_one(&state.db)
            .await?;
        Ok(Json(serde_json::json!({
            "server_now": server_now,
            "loans": loans,
        })))
    } else {
        Ok(Json(serde_json::to_value(loans)?))
    }
}

/// Upsert a loan at a caller-chosen id: creates it (requires editor access to
/// `copy_id`'s book) if absent, otherwise updates it (requires editor access
/// to the loan, i.e. to its copy's book — see `access::loan_access`).
pub async fn upsert(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(input): Json<LoanInput>,
) -> AppResult<Json<LoanDto>> {
    if input.borrower.trim().is_empty() {
        return Err(AppError::BadRequest("borrower is required".into()));
    }
    let existing: Option<(String, String)> =
        sqlx::query_as("SELECT copy_id, updated_at FROM loan WHERE id = ?")
            .bind(&id)
            .fetch_optional(&state.db)
            .await?;

    let is_update = match &existing {
        Some((stored_copy_id, stored_updated_at)) => {
            if &input.copy_id != stored_copy_id {
                return Err(AppError::BadRequest(
                    "a loan cannot change which copy it belongs to".into(),
                ));
            }
            if !loan_access(&state, &user, &id).await?.can_edit() {
                return Err(AppError::Forbidden(
                    "you have read-only access to this loan".into(),
                ));
            }
            if let Some(incoming) = input.updated_at.as_deref()
                && incoming <= stored_updated_at.as_str()
            {
                return fetch_loan(&state, &id).await;
            }
            true
        }
        None => {
            let book_id: Option<String> =
                sqlx::query_scalar("SELECT book_id FROM physical_copy WHERE id = ?")
                    .bind(&input.copy_id)
                    .fetch_optional(&state.db)
                    .await?;
            let Some(book_id) = book_id else {
                return Err(AppError::BadRequest("no such physical copy".into()));
            };
            if !crate::access::book_access(&state, &user, &book_id)
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

    // No-op guard, same reasoning as physical_copies::upsert.
    if is_update {
        let current = fetch_loan(&state, &id).await?.0;
        let tombstoned: bool =
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM deletion WHERE book_id = ?)")
                .bind(&id)
                .fetch_one(&state.db)
                .await?;
        if current.borrower == input.borrower.trim()
            && current.returned_at == input.returned_at
            && !tombstoned
        {
            return Ok(Json(current));
        }
    }

    let mut tx = state.db.begin().await?;
    if is_update {
        sqlx::query(
            "UPDATE loan SET borrower = ?, returned_at = ?, updated_at = datetime('now') \
             WHERE id = ?",
        )
        .bind(input.borrower.trim())
        .bind(&input.returned_at)
        .bind(&id)
        .execute(&mut *tx)
        .await?;
    } else {
        sqlx::query(
            "INSERT INTO loan (id, copy_id, borrower, loaned_at, returned_at) \
             VALUES (?, ?, ?, ?, ?)",
        )
        .bind(&id)
        .bind(&input.copy_id)
        .bind(input.borrower.trim())
        .bind(&input.loaned_at)
        .bind(&input.returned_at)
        .execute(&mut *tx)
        .await?;
    }
    sqlx::query("DELETE FROM deletion WHERE book_id = ? AND kind = 'loan'")
        .bind(&id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    fetch_loan(&state, &id).await
}

/// Delete — restricted to the loan's copy's book's owner or the master, same
/// as `physical_copies::delete`. Exists for completeness (removing exactly
/// one loan record); no app code path calls this today, since a copy delete
/// cascades its loans instead (see the module doc comment).
pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    let owner: Option<Option<String>> = sqlx::query_scalar(
        "SELECT b.owner_id FROM loan l \
         JOIN physical_copy pc ON pc.id = l.copy_id \
         JOIN book b ON b.id = pc.book_id \
         WHERE l.id = ?",
    )
    .bind(&id)
    .fetch_optional(&state.db)
    .await?;
    let Some(owner_id) = owner else {
        return Err(AppError::NotFound("loan not found".into()));
    };
    if !user.is_master && owner_id.as_deref() != Some(user.id.as_str()) {
        return Err(AppError::Forbidden(
            "only the book's owner may delete this loan".into(),
        ));
    }

    let mut tx = state.db.begin().await?;
    sqlx::query("INSERT OR REPLACE INTO deletion (book_id, owner_id, kind) VALUES (?, ?, 'loan')")
        .bind(&id)
        .bind(&owner_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM loan WHERE id = ?")
        .bind(&id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    Ok(Json(serde_json::json!({ "deleted": id })))
}

async fn fetch_loan(state: &AppState, id: &str) -> AppResult<Json<LoanDto>> {
    let loan =
        sqlx::query_as::<_, LoanDto>(&format!("SELECT {LOAN_COLUMNS} FROM loan WHERE id = ?"))
            .bind(id)
            .fetch_optional(&state.db)
            .await?
            .ok_or_else(|| AppError::NotFound("loan not found".into()))?;
    Ok(Json(loan))
}
