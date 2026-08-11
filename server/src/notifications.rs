//! Telling people what happened (migration 0030).
//!
//! Lending is a conversation, and the server has always held only its state:
//! a request was pending, then it was approved. Whoever pressed the button knew
//! that; the other person found out by opening the right screen and noticing.
//!
//! Three decisions worth stating:
//!
//! - **Addressed to an account, so it is per-user data.** Keyed by `user_id`
//!   taken from the token, never visible to anyone else, and never on the book
//!   row — the same rule as reading progress and annotations.
//! - **Best-effort at the edges.** [`notify`] logs and moves on rather than
//!   failing its caller: an approved loan that could not be announced is still
//!   an approved loan, and rolling one back because an email bounced would be
//!   losing the thing to protect the message about it.
//! - **Email only when a mailer is configured**, and only as a second copy of
//!   what is already in the list. A server with no SMTP is not a degraded
//!   server; it is the ordinary case.

use axum::Json;
use axum::extract::{Path, Query, State};
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};

#[derive(Serialize, sqlx::FromRow)]
pub struct NotificationDto {
    pub id: String,
    pub kind: String,
    pub title: String,
    pub body: Option<String>,
    pub book_id: Option<String>,
    pub created_at: String,
    pub read_at: Option<String>,
}

/// What one notification says, before it belongs to anyone.
pub struct Message<'a> {
    pub kind: &'a str,
    pub title: String,
    pub body: Option<String>,
    pub book_id: Option<&'a str>,
}

/// Records [message] for `user_id`, and emails it if the server has a mailer.
///
/// Best-effort by design: every failure is logged and swallowed, because every
/// caller is in the middle of doing the thing being announced. See the module
/// comment.
pub async fn notify(state: &AppState, user_id: &str, message: Message<'_>) {
    let id = uuid::Uuid::new_v4().to_string();
    let stored = sqlx::query(
        "INSERT INTO notification (id, user_id, kind, title, body, book_id) \
         VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(user_id)
    .bind(message.kind)
    .bind(&message.title)
    .bind(&message.body)
    .bind(message.book_id)
    .execute(&state.db)
    .await;
    if let Err(e) = stored {
        tracing::warn!(error = %e, user = %user_id, "could not record a notification");
        return;
    }

    let Some(mailer) = state.mailer.clone() else {
        return;
    };
    let address: Result<Option<String>, _> =
        sqlx::query_scalar("SELECT email FROM app_user WHERE id = ?")
            .bind(user_id)
            .fetch_optional(&state.db)
            .await;
    let Ok(Some(address)) = address else {
        return;
    };
    // The body already reads as a sentence to a person — the list and the email
    // say the same thing, so there is one wording to get right.
    let text = match &message.body {
        Some(body) => format!("{}\n\n{}", message.title, body),
        None => message.title.clone(),
    };
    let subject = message.title.clone();
    // Detached: SMTP can be slow, and the caller is answering a request.
    tokio::spawn(async move {
        // `AppError` is a response type, not a `Display` error — debug is
        // what there is, and this line is for the operator's log.
        if let Err(e) = mailer.send(&address, &subject, &text).await {
            tracing::warn!(error = ?e, "could not email a notification");
        }
    });
}

#[derive(Deserialize)]
pub struct ListQuery {
    /// `unread=1` for just the ones not yet seen; omit for everything.
    pub unread: Option<String>,
    /// How many to return, newest first. Bounded so a long-lived account
    /// cannot make the app fetch thousands of rows to draw a badge.
    pub limit: Option<i64>,
}

/// `GET /api/notifications`
pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<ListQuery>,
) -> AppResult<Json<serde_json::Value>> {
    let unread_only = matches!(q.unread.as_deref(), Some("1" | "true"));
    let limit = q.limit.unwrap_or(50).clamp(1, 200);
    let sql = format!(
        "SELECT id, kind, title, body, book_id, created_at, read_at \
         FROM notification WHERE user_id = ? {} \
         ORDER BY created_at DESC, id DESC LIMIT ?",
        if unread_only { "AND read_at IS NULL" } else { "" }
    );
    let items = sqlx::query_as::<_, NotificationDto>(&sql)
        .bind(&user.id)
        .bind(limit)
        .fetch_all(&state.db)
        .await?;

    // The unread count is always the whole truth, not the count within the
    // page — a badge saying "50" when there are 200 would be a lie the limit
    // invented.
    let unread: i64 = sqlx::query_scalar(
        "SELECT COUNT(*) FROM notification WHERE user_id = ? AND read_at IS NULL",
    )
    .bind(&user.id)
    .fetch_one(&state.db)
    .await?;

    Ok(Json(serde_json::json!({
        "unread": unread,
        "notifications": items,
    })))
}

/// `POST /api/notifications/{id}/read` — idempotent; reading twice is not an
/// error, and a missing id is a 404 rather than a silent success.
pub async fn mark_read(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    crate::ids::check("notification", &id)?;
    let affected = sqlx::query(
        "UPDATE notification SET read_at = COALESCE(read_at, datetime('now')) \
         WHERE id = ? AND user_id = ?",
    )
    .bind(&id)
    .bind(&user.id)
    .execute(&state.db)
    .await?
    .rows_affected();
    if affected == 0 {
        // Someone else's notification is not found, not forbidden — the same
        // rule as everywhere, so this cannot be used to learn what exists.
        return Err(AppError::NotFound("notification not found".into()));
    }
    Ok(Json(serde_json::json!({ "read": id })))
}

/// `POST /api/notifications/read-all`
pub async fn mark_all_read(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<serde_json::Value>> {
    let affected = sqlx::query(
        "UPDATE notification SET read_at = datetime('now') \
         WHERE user_id = ? AND read_at IS NULL",
    )
    .bind(&user.id)
    .execute(&state.db)
    .await?
    .rows_affected();
    Ok(Json(serde_json::json!({ "read": affected })))
}
