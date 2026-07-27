//! Send a book to an e-reader by email (plan 5 #53).
//!
//! OPDS (#34) covers readers that can browse a catalogue, but the most common
//! e-reader path is still an email address: Amazon's send-to-Kindle, Kobo's and
//! Pocketbook's equivalents all work this way. Once #31's mailer exists the
//! server can do in one click what the user otherwise does by downloading the
//! file and forwarding it by hand.
//!
//! Three things shape this module:
//!
//! - **It reuses the book's RBAC exactly.** Sending is a read of a book plus an
//!   outbound email; a caller who cannot see the book gets the same 404 they
//!   would get from any other read, never a hint that it exists.
//! - **The size cap is enforced here, not discovered at the relay.** Kindle's
//!   documented limit is 50 MB per message and base64 inflates an attachment by
//!   about a third, so a 40 MB book is already over. Failing fast with a number
//!   the user can act on beats a rejected message minutes later.
//! - **It is rate-limited like metadata search**, for the same reason: it spends
//!   a shared, quota'd external resource, and a loop over a library would look
//!   like abuse from the relay's side.

use axum::Json;
use axum::extract::{Path as AxPath, State};
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::access::book_access;
use crate::auth::AuthUser;
use crate::blobs::blob_file_path;
use crate::error::{AppError, AppResult};

/// The largest attachment we will hand to the relay, *after* base64.
///
/// 25 MB of file becomes roughly 34 MB on the wire, comfortably inside the
/// 50 MB most services accept while leaving room for headers and for relays
/// with a tighter limit.
pub const MAX_ATTACHMENT_BYTES: i64 = 25 * 1024 * 1024;

/// One saved destination ("My Kindle").
#[derive(Serialize, Deserialize, Clone, Debug)]
pub struct SendTarget {
    pub label: String,
    pub address: String,
}

#[derive(Deserialize)]
pub struct SendRequest {
    pub file_id: String,
    /// Where to send it. Either a literal address or, when absent, [`label`]
    /// picks one of the caller's saved targets.
    pub to: Option<String>,
    pub label: Option<String>,
}

#[derive(Serialize)]
pub struct SendResponse {
    pub sent_to: String,
    pub filename: String,
    pub size_bytes: i64,
}

/// `POST /api/books/{id}/send`
pub async fn send_book(
    State(state): State<AppState>,
    user: AuthUser,
    AxPath(book_id): AxPath<String>,
    Json(req): Json<SendRequest>,
) -> AppResult<Json<SendResponse>> {
    let Some(mailer) = state.mailer.clone() else {
        // The capability handshake already hides the action, so reaching here
        // means a stale client or a direct call — say why rather than 500.
        return Err(AppError::BadRequest(
            "this server has no outbound email configured".into(),
        ));
    };

    // Same 404-not-403 rule as every other book read: no existence oracle.
    if !book_access(&state, &user, &book_id).await?.can_view() {
        return Err(AppError::NotFound("book not found".into()));
    }

    // Rate-limited per user, like metadata search. `check` records the attempt
    // as it tests it, so a send that then fails still costs a slot — which is
    // right: the expensive part is the attempt, not the outcome.
    if !state.send_limiter.check(&user.id) {
        return Err(AppError::TooManyRequests(
            "too many books sent just now — try again in a few minutes".into(),
        ));
    }

    let to = resolve_destination(&state, &user.id, &req).await?;
    validate_address(&to)?;

    let row: Option<(String, String, String, i64)> =
        sqlx::query_as("SELECT book_id, format, path, size_bytes FROM book_file WHERE id = ?")
            .bind(&req.file_id)
            .fetch_optional(&state.db)
            .await?;
    let (file_book_id, format, rel, size) =
        row.ok_or_else(|| AppError::NotFound("file not found".into()))?;
    // A file id from another book would otherwise let a caller send any file
    // they can name through a book they *can* see.
    if file_book_id != book_id {
        return Err(AppError::NotFound("file not found".into()));
    }
    if size > MAX_ATTACHMENT_BYTES {
        return Err(AppError::BadRequest(format!(
            "that file is {} MB; the limit for email is {} MB",
            size / (1024 * 1024),
            MAX_ATTACHMENT_BYTES / (1024 * 1024)
        )));
    }

    let title: String = sqlx::query_scalar("SELECT title FROM book WHERE id = ?")
        .bind(&book_id)
        .fetch_optional(&state.db)
        .await?
        .unwrap_or_else(|| "Your book".to_string());

    let path = blob_file_path(&state, &rel)?;
    let bytes = tokio::fs::read(&path)
        .await
        .map_err(|_| AppError::NotFound("that file is missing on the server".into()))?;

    let filename = attachment_name(&title, &format);
    mailer
        .send_with_attachment(
            &to,
            // Amazon's convention: the subject is ignored for delivery but
            // shows up in the device's history, so name the book.
            &title,
            &format!("{title}\n\nSent from your Vellum library."),
            &filename,
            content_type_for(&format),
            bytes,
        )
        .await?;

    tracing::info!(book = %book_id, "sent a book by email");
    Ok(Json(SendResponse {
        sent_to: to,
        filename,
        size_bytes: size,
    }))
}

/// `GET /api/send-targets` — the caller's saved destinations.
pub async fn list_targets(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Vec<SendTarget>>> {
    Ok(Json(load_targets(&state, &user.id).await?))
}

/// `PUT /api/send-targets` — replaces the whole list.
///
/// Whole-list replacement rather than add/remove endpoints: it is a handful of
/// rows edited as one form, and two endpoints would need an id per target for
/// no benefit.
pub async fn put_targets(
    State(state): State<AppState>,
    user: AuthUser,
    Json(targets): Json<Vec<SendTarget>>,
) -> AppResult<Json<Vec<SendTarget>>> {
    if targets.len() > 20 {
        return Err(AppError::BadRequest("too many saved addresses".into()));
    }
    let cleaned: Vec<SendTarget> = targets
        .into_iter()
        .map(|t| SendTarget {
            label: t.label.trim().to_string(),
            address: t.address.trim().to_string(),
        })
        .filter(|t| !t.address.is_empty())
        .collect();
    for target in &cleaned {
        validate_address(&target.address)?;
    }
    let encoded = serde_json::to_string(&cleaned)?;
    sqlx::query("UPDATE app_user SET send_targets = ? WHERE id = ?")
        .bind(&encoded)
        .bind(&user.id)
        .execute(&state.db)
        .await?;
    Ok(Json(cleaned))
}

async fn load_targets(state: &AppState, user_id: &str) -> AppResult<Vec<SendTarget>> {
    let raw: Option<String> = sqlx::query_scalar("SELECT send_targets FROM app_user WHERE id = ?")
        .bind(user_id)
        .fetch_optional(&state.db)
        .await?;
    let raw = raw.unwrap_or_else(|| "[]".to_string());
    // A hand-edited or truncated blob must not lock the user out of the
    // feature; an unreadable list is an empty one.
    Ok(serde_json::from_str(&raw).unwrap_or_default())
}

async fn resolve_destination(
    state: &AppState,
    user_id: &str,
    req: &SendRequest,
) -> AppResult<String> {
    if let Some(to) = req.to.as_ref().map(|t| t.trim()).filter(|t| !t.is_empty()) {
        return Ok(to.to_string());
    }
    let Some(label) = req
        .label
        .as_ref()
        .map(|l| l.trim())
        .filter(|l| !l.is_empty())
    else {
        return Err(AppError::BadRequest(
            "give an address, or the label of a saved one".into(),
        ));
    };
    let targets = load_targets(state, user_id).await?;
    targets
        .into_iter()
        .find(|t| t.label.eq_ignore_ascii_case(label))
        .map(|t| t.address)
        .ok_or_else(|| AppError::NotFound(format!("no saved address called \"{label}\"")))
}

/// A deliberately loose check: exactly one `@`, something either side, no
/// whitespace, and a dot in the domain. The relay is the real authority, and
/// over-strict local validation rejects addresses that work.
fn validate_address(address: &str) -> AppResult<()> {
    let bad = address.is_empty()
        || address.chars().any(char::is_whitespace)
        || address.matches('@').count() != 1
        || address.starts_with('@')
        || address.ends_with('@');
    if bad {
        return Err(AppError::BadRequest(
            "that does not look like an email address".into(),
        ));
    }
    let domain = address.split('@').nth(1).unwrap_or_default();
    if !domain.contains('.') || domain.starts_with('.') || domain.ends_with('.') {
        return Err(AppError::BadRequest(
            "that does not look like an email address".into(),
        ));
    }
    Ok(())
}

fn content_type_for(format: &str) -> &'static str {
    match format.to_ascii_lowercase().as_str() {
        "epub" => "application/epub+zip",
        "pdf" => "application/pdf",
        _ => "application/octet-stream",
    }
}

/// A filename the receiving service will accept: the title, stripped to
/// characters that survive every mail client, plus the real extension.
///
/// The extension matters more than it looks — send-to-Kindle decides how to
/// convert by the file's suffix, so a book delivered as `Dune` rather than
/// `Dune.epub` is silently dropped.
pub fn attachment_name(title: &str, format: &str) -> String {
    let mut stem: String = title
        .chars()
        .map(|c| {
            if c.is_alphanumeric() || c == ' ' || c == '-' || c == '_' {
                c
            } else {
                ' '
            }
        })
        .collect();
    stem = stem.split_whitespace().collect::<Vec<_>>().join(" ");
    if stem.is_empty() {
        stem = "book".to_string();
    }
    stem.truncate(80);
    format!("{}.{}", stem.trim(), format.to_ascii_lowercase())
}
