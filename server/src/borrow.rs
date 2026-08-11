//! Borrow requests (plan 5 #49) — the last step of the lending workflow.
//!
//! Someone browsing a shared room can see the book they want on your shelf, and
//! until now had to leave the app and text you. This closes that loop: a request
//! the owner approves, which **creates the loan** the physical side already
//! models.
//!
//! Three decisions worth stating:
//!
//! - **Visibility is the gate.** You may request a book you can already see;
//!   that is exactly the RBAC that governs everything else, so there is no new
//!   surface to leak through. A book you can't see answers 404, not 403.
//! - **Approve is atomic.** The loan is created and the request closed in one
//!   transaction. A half-applied approval would mean either a loan nobody asked
//!   for or a request that looks decided with nothing to show for it.
//! - **Anonymous viewers get no button.** A public link has no account to hold a
//!   request, so the page says who to ask instead of pretending.

use axum::Json;
use axum::extract::{Path, Query, State};
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};

#[derive(Serialize, sqlx::FromRow)]
pub struct BorrowRequestDto {
    pub id: String,
    pub book_id: String,
    pub book_title: String,
    pub copy_id: Option<String>,
    pub requester_id: String,
    pub requester_email: String,
    pub owner_id: String,
    pub status: String,
    pub note: Option<String>,
    pub reply: Option<String>,
    pub created_at: String,
    pub decided_at: Option<String>,
    pub loan_id: Option<String>,
}

const SELECT: &str = "SELECT r.id, r.book_id, b.title AS book_title, r.copy_id, \
        r.requester_id, r.requester_email, r.owner_id, r.status, r.note, r.reply, \
        r.created_at, r.decided_at, r.loan_id \
    FROM borrow_request r JOIN book b ON b.id = r.book_id";

#[derive(Deserialize)]
pub struct CreateInput {
    pub book_id: String,
    #[serde(default)]
    pub copy_id: Option<String>,
    #[serde(default)]
    pub note: Option<String>,
}

#[derive(Deserialize)]
pub struct DecideInput {
    /// 'approved' | 'declined' | 'cancelled'
    pub status: String,
    #[serde(default)]
    pub reply: Option<String>,
    /// Approval only: when the book is due back (plan 5 #27's due dates).
    #[serde(default)]
    pub due_at: Option<String>,
}

#[derive(Deserialize)]
pub struct ListQuery {
    /// 'incoming' (default — requests to answer) or 'outgoing' (mine).
    pub direction: Option<String>,
    /// Filter by status; omit for everything.
    pub status: Option<String>,
}

/// `POST /api/borrow-requests`
pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(input): Json<CreateInput>,
) -> AppResult<Json<BorrowRequestDto>> {
    // Visibility is the gate, and 404 for anything else — the same rule as
    // everywhere, so this can't be used to probe which books exist.
    if !crate::access::book_access(&state, &user, &input.book_id)
        .await?
        .can_view()
    {
        return Err(AppError::NotFound("book not found".into()));
    }
    let owner: Option<String> = sqlx::query_scalar("SELECT owner_id FROM book WHERE id = ?")
        .bind(&input.book_id)
        .fetch_optional(&state.db)
        .await?
        .flatten();
    let owner = owner.ok_or_else(|| AppError::NotFound("book not found".into()))?;
    if owner == user.id {
        return Err(AppError::BadRequest(
            "this is your own book — just lend it".into(),
        ));
    }

    // Per requester, so one person hammering the button can't fill an owner's
    // inbox, and so the limit is theirs rather than the server's.
    if !state.search_limiter.check(&format!("borrow:{}", user.id)) {
        return Err(AppError::TooManyRequests(
            "too many borrow requests; try again later".into(),
        ));
    }

    let id = uuid::Uuid::new_v4().to_string();
    let note = input
        .note
        .as_deref()
        .map(str::trim)
        .filter(|n| !n.is_empty());
    let result = sqlx::query(
        "INSERT INTO borrow_request \
            (id, book_id, copy_id, requester_id, requester_email, owner_id, note) \
         VALUES (?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(&input.book_id)
    .bind(&input.copy_id)
    .bind(&user.id)
    .bind(&user.email)
    .bind(&owner)
    .bind(note)
    .execute(&state.db)
    .await;

    if let Err(e) = result {
        // The partial unique index: one live request per person per book.
        if e.to_string().contains("UNIQUE") {
            return Err(AppError::Conflict(
                "you already have a request pending for this book".into(),
            ));
        }
        return Err(e.into());
    }

    crate::audit::record(
        &state,
        Some(&user),
        "borrow.request",
        "book",
        &input.book_id,
        note,
    )
    .await;

    // The owner is the one who has to do something about this, and until now
    // nothing told them: the request sat in a screen they had no reason to
    // open.
    let title: String = sqlx::query_scalar("SELECT title FROM book WHERE id = ?")
        .bind(&input.book_id)
        .fetch_optional(&state.db)
        .await?
        .unwrap_or_else(|| "a book".to_string());
    crate::notifications::notify(
        &state,
        &owner,
        crate::notifications::Message {
            kind: "borrow.requested",
            title: format!("{} would like to borrow “{title}”", user.email),
            body: note.map(|n| format!("They said: “{n}”")),
            book_id: Some(&input.book_id),
        },
    )
    .await;
    fetch(&state, &id).await
}

/// `GET /api/borrow-requests` — what you have to answer, or what you asked for.
pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<ListQuery>,
) -> AppResult<Json<Vec<BorrowRequestDto>>> {
    let outgoing = q.direction.as_deref() == Some("outgoing");
    let mut sql = format!(
        "{SELECT} WHERE r.{} = ?",
        if outgoing { "requester_id" } else { "owner_id" }
    );
    let status = q
        .status
        .as_deref()
        .map(str::trim)
        .filter(|s| !s.is_empty())
        .map(str::to_string);
    if status.is_some() {
        sql.push_str(" AND r.status = ?");
    }
    sql.push_str(" ORDER BY r.created_at DESC");

    let mut query = sqlx::query_as::<_, BorrowRequestDto>(&sql).bind(&user.id);
    if let Some(status) = &status {
        query = query.bind(status.clone());
    }
    Ok(Json(query.fetch_all(&state.db).await?))
}

/// `POST /api/borrow-requests/{id}/decide`
///
/// The owner approves or declines; the requester may cancel their own. Approval
/// creates the loan in the **same transaction** that closes the request — see
/// the module comment for why that matters.
pub async fn decide(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(input): Json<DecideInput>,
) -> AppResult<Json<BorrowRequestDto>> {
    let row: Option<(String, String, String, String, Option<String>)> = sqlx::query_as(
        "SELECT owner_id, requester_id, status, book_id, copy_id \
         FROM borrow_request WHERE id = ?",
    )
    .bind(&id)
    .fetch_optional(&state.db)
    .await?;
    let (owner_id, requester_id, status, book_id, copy_id) =
        row.ok_or_else(|| AppError::NotFound("request not found".into()))?;

    if user.id != owner_id && user.id != requester_id && !user.is_master {
        return Err(AppError::NotFound("request not found".into()));
    }
    if status != "pending" {
        return Err(AppError::Conflict(format!(
            "this request was already {status}"
        )));
    }

    let decision = input.status.as_str();
    match decision {
        "approved" | "declined" => {
            if user.id != owner_id && !user.is_master {
                return Err(AppError::Forbidden(
                    "only the book's owner can answer this".into(),
                ));
            }
        }
        "cancelled" => {
            if user.id != requester_id && !user.is_master {
                return Err(AppError::Forbidden(
                    "only the requester can cancel this".into(),
                ));
            }
        }
        other => {
            return Err(AppError::BadRequest(format!("unknown decision '{other}'")));
        }
    }

    let reply = input
        .reply
        .as_deref()
        .map(str::trim)
        .filter(|r| !r.is_empty());
    let mut tx = state.db.begin().await?;
    let mut loan_id: Option<String> = None;

    if decision == "approved" {
        // Which copy to lend: the one asked for, else any copy of the book that
        // isn't already out. Approving a book with nothing free is refused
        // rather than silently double-lending a copy.
        let copy: Option<String> = match &copy_id {
            Some(explicit) => {
                sqlx::query_scalar("SELECT id FROM physical_copy WHERE id = ? AND book_id = ?")
                    .bind(explicit)
                    .bind(&book_id)
                    .fetch_optional(&mut *tx)
                    .await?
            }
            None => {
                sqlx::query_scalar(
                    "SELECT pc.id FROM physical_copy pc WHERE pc.book_id = ? \
                 AND NOT EXISTS (SELECT 1 FROM loan l \
                     WHERE l.copy_id = pc.id AND l.returned_at IS NULL) \
                 LIMIT 1",
                )
                .bind(&book_id)
                .fetch_optional(&mut *tx)
                .await?
            }
        };
        let copy = copy.ok_or_else(|| {
            AppError::BadRequest("no physical copy of this book is free to lend".into())
        })?;
        let out: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM loan WHERE copy_id = ? AND returned_at IS NULL)",
        )
        .bind(&copy)
        .fetch_one(&mut *tx)
        .await?;
        if out {
            return Err(AppError::Conflict("that copy is already lent out".into()));
        }

        let new_loan = uuid::Uuid::new_v4().to_string();
        // The borrower's name is their account's email — the owner can edit it
        // afterwards like any loan, but a request approved into an anonymous
        // loan would lose the one fact that matters.
        let borrower: String = sqlx::query_scalar("SELECT email FROM app_user WHERE id = ?")
            .bind(&requester_id)
            .fetch_one(&mut *tx)
            .await?;
        sqlx::query(
            "INSERT INTO loan (id, copy_id, borrower, loaned_at, due_at, borrower_contact) \
             VALUES (?, ?, ?, datetime('now'), ?, ?)",
        )
        .bind(&new_loan)
        .bind(&copy)
        .bind(&borrower)
        .bind(&input.due_at)
        .bind(&borrower)
        .execute(&mut *tx)
        .await?;
        loan_id = Some(new_loan);
    }

    sqlx::query(
        "UPDATE borrow_request SET status = ?, reply = ?, loan_id = ?, \
            decided_at = datetime('now') \
         WHERE id = ? AND status = 'pending'",
    )
    .bind(decision)
    .bind(reply)
    .bind(&loan_id)
    .bind(&id)
    .execute(&mut *tx)
    .await?;
    tx.commit().await?;

    crate::audit::record(
        &state,
        Some(&user),
        &format!("borrow.{decision}"),
        "book",
        &book_id,
        reply,
    )
    .await;

    // Whoever did *not* press the button is the one who needs telling: the
    // requester when the owner answers, the owner when the requester gives up.
    let title: String = sqlx::query_scalar("SELECT title FROM book WHERE id = ?")
        .bind(&book_id)
        .fetch_optional(&state.db)
        .await?
        .unwrap_or_else(|| "a book".to_string());
    let (recipient, headline) = match decision {
        "approved" => (
            &requester_id,
            format!("“{title}” is yours to borrow"),
        ),
        "declined" => (
            &requester_id,
            format!("Your request for “{title}” was declined"),
        ),
        // cancelled: the requester withdrew, so it is the owner who has one
        // fewer thing to answer.
        _ => (
            &owner_id,
            format!("{} no longer needs “{title}”", user.email),
        ),
    };
    crate::notifications::notify(
        &state,
        recipient,
        crate::notifications::Message {
            kind: &format!("borrow.{decision}"),
            title: headline,
            body: reply.map(|r| format!("They said: “{r}”")),
            book_id: Some(&book_id),
        },
    )
    .await;
    fetch(&state, &id).await
}

async fn fetch(state: &AppState, id: &str) -> AppResult<Json<BorrowRequestDto>> {
    let row = sqlx::query_as::<_, BorrowRequestDto>(&format!("{SELECT} WHERE r.id = ?"))
        .bind(id)
        .fetch_optional(&state.db)
        .await?
        .ok_or_else(|| AppError::NotFound("request not found".into()))?;
    Ok(Json(row))
}
