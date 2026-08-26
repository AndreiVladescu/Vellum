//! Server settings a person edits, as opposed to the environment that
//! configures the process (migration 0037).
//!
//! The line between the two: `VELLUM_SMTP_HOST` decides whether this server
//! *can* send mail and belongs to whoever deploys it; whether it sends loan
//! reminders, and what they say, belongs to whoever runs the library — and
//! restarting a server to reword an email would be absurd.
//!
//! Master-only, like every other thing on the console's settings screen.

use axum::Json;
use axum::extract::State;
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};

/// Whether due loans send reminders at all. Off until switched on: a server
/// that starts emailing the moment it learns how to is a server nobody
/// forgives.
pub const LOAN_REMINDERS: &str = "loan_reminders";

/// The three messages, as templates. See [`render`] for the placeholders.
pub const REMINDER_BEFORE_SUBJECT: &str = "loan_reminder_before_subject";
pub const REMINDER_BEFORE_BODY: &str = "loan_reminder_before_body";
pub const REMINDER_DUE_SUBJECT: &str = "loan_reminder_due_subject";
pub const REMINDER_DUE_BODY: &str = "loan_reminder_due_body";
pub const REMINDER_OVERDUE_SUBJECT: &str = "loan_reminder_overdue_subject";
pub const REMINDER_OVERDUE_BODY: &str = "loan_reminder_overdue_body";

/// How many days before the due date the first reminder goes.
pub const REMINDER_LEAD_DAYS: &str = "loan_reminder_lead_days";

/// What a setting says when nobody has said otherwise.
pub fn default_for(key: &str) -> &'static str {
    match key {
        LOAN_REMINDERS => "off",
        REMINDER_LEAD_DAYS => "3",
        REMINDER_BEFORE_SUBJECT => "\"{title}\" is due back on {due_date}",
        REMINDER_BEFORE_BODY => {
            "Hello {borrower},\n\n\
             You borrowed \"{title}\" on {loaned_date}. It is due back on \
             {due_date} — {days} days from now.\n\n\
             — {library}"
        }
        REMINDER_DUE_SUBJECT => "\"{title}\" is due back today",
        REMINDER_DUE_BODY => {
            "Hello {borrower},\n\n\
             \"{title}\", which you borrowed on {loaned_date}, is due back \
             today.\n\n\
             — {library}"
        }
        REMINDER_OVERDUE_SUBJECT => "\"{title}\" is overdue",
        REMINDER_OVERDUE_BODY => {
            "Hello {borrower},\n\n\
             \"{title}\" was due back on {due_date}. If you have already \
             returned it, ignore this.\n\n\
             — {library}"
        }
        _ => "",
    }
}

/// Fills `{title}`, `{borrower}`, `{due_date}`, `{loaned_date}`, `{days}` and
/// `{library}` in a template.
///
/// Deliberately not a template *language*: someone writing an email should not
/// be able to make the server loop, and a placeholder nobody filled is left
/// visible rather than blanked — a message reading "due back on {due_date}" is
/// a bug report, where one reading "due back on" is a mystery.
pub fn render(template: &str, values: &[(&str, &str)]) -> String {
    let mut out = template.to_string();
    for (key, value) in values {
        out = out.replace(&format!("{{{key}}}"), value);
    }
    out
}

pub async fn get(state: &AppState, key: &str) -> String {
    let stored: Option<String> =
        sqlx::query_scalar("SELECT value FROM server_setting WHERE key = ?")
            .bind(key)
            .fetch_optional(&state.db)
            .await
            .ok()
            .flatten();
    stored.unwrap_or_else(|| default_for(key).to_string())
}

#[derive(Serialize)]
pub struct SettingsDto {
    pub loan_reminders: bool,
    pub lead_days: i64,
    pub before_subject: String,
    pub before_body: String,
    pub due_subject: String,
    pub due_body: String,
    pub overdue_subject: String,
    pub overdue_body: String,
    /// Whether this server can send mail at all. The switch above is worth
    /// nothing without it, and a settings screen that does not say so invites
    /// someone to turn reminders on and wonder why nothing arrives.
    pub mail_configured: bool,
}

#[derive(Deserialize)]
pub struct SettingsInput {
    pub loan_reminders: Option<bool>,
    pub lead_days: Option<i64>,
    pub before_subject: Option<String>,
    pub before_body: Option<String>,
    pub due_subject: Option<String>,
    pub due_body: Option<String>,
    pub overdue_subject: Option<String>,
    pub overdue_body: Option<String>,
}

pub async fn list(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<SettingsDto>> {
    if !user.is_master {
        return Err(AppError::Forbidden(
            "only the owner can read settings".into(),
        ));
    }
    Ok(Json(SettingsDto {
        loan_reminders: get(&state, LOAN_REMINDERS).await == "on",
        lead_days: get(&state, REMINDER_LEAD_DAYS).await.parse().unwrap_or(3),
        before_subject: get(&state, REMINDER_BEFORE_SUBJECT).await,
        before_body: get(&state, REMINDER_BEFORE_BODY).await,
        due_subject: get(&state, REMINDER_DUE_SUBJECT).await,
        due_body: get(&state, REMINDER_DUE_BODY).await,
        overdue_subject: get(&state, REMINDER_OVERDUE_SUBJECT).await,
        overdue_body: get(&state, REMINDER_OVERDUE_BODY).await,
        mail_configured: crate::mail::is_enabled(&state.mailer),
    }))
}

pub async fn update(
    State(state): State<AppState>,
    user: AuthUser,
    Json(input): Json<SettingsInput>,
) -> AppResult<Json<SettingsDto>> {
    if !user.is_master {
        return Err(AppError::Forbidden(
            "only the owner can change settings".into(),
        ));
    }
    if let Some(days) = input.lead_days
        && !(0..=90).contains(&days)
    {
        return Err(AppError::BadRequest(
            "the lead time must be between 0 and 90 days".into(),
        ));
    }
    let pairs: Vec<(&str, String)> = [
        input
            .loan_reminders
            .map(|on| (LOAN_REMINDERS, if on { "on" } else { "off" }.to_string())),
        input
            .lead_days
            .map(|days| (REMINDER_LEAD_DAYS, days.to_string())),
        input.before_subject.map(|v| (REMINDER_BEFORE_SUBJECT, v)),
        input.before_body.map(|v| (REMINDER_BEFORE_BODY, v)),
        input.due_subject.map(|v| (REMINDER_DUE_SUBJECT, v)),
        input.due_body.map(|v| (REMINDER_DUE_BODY, v)),
        input.overdue_subject.map(|v| (REMINDER_OVERDUE_SUBJECT, v)),
        input.overdue_body.map(|v| (REMINDER_OVERDUE_BODY, v)),
    ]
    .into_iter()
    .flatten()
    .collect();

    for (key, value) in pairs {
        sqlx::query(
            "INSERT INTO server_setting (key, value, updated_at) \
             VALUES (?, ?, datetime('now')) \
             ON CONFLICT(key) DO UPDATE SET \
                value = excluded.value, updated_at = datetime('now')",
        )
        .bind(key)
        .bind(&value)
        .execute(&state.db)
        .await?;
    }
    list(State(state), user).await
}

#[derive(Serialize)]
pub struct SweepResult {
    pub sent: usize,
}

/// Sends whatever is due right now, rather than at the top of the hour.
pub async fn run_reminders(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<SweepResult>> {
    if !user.is_master {
        return Err(AppError::Forbidden(
            "only the owner can send reminders".into(),
        ));
    }
    Ok(Json(SweepResult {
        sent: crate::reminders::sweep(&state).await,
    }))
}
