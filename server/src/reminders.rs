//! Telling a borrower a book is due (8/25 request).
//!
//! **Why the server and not the app.** The app knows about loans too, but it is
//! only running when someone opens it, and a reminder that arrives three days
//! late is not a reminder. The server is the thing that is awake at nine in the
//! morning, and it is where the mailer already lives.
//!
//! **Three at most, each once.** A few days before the due date, on the day,
//! and one when it goes late — and then silence. A daily nag is how a feature
//! like this gets switched off for good, so each stage is recorded in
//! `loan_reminder` when it goes out and never sent twice (migration 0037).
//!
//! Nothing is sent unless three things are true: the server has a mailer, the
//! owner has switched reminders on, and this particular loan has not been
//! opted out of. Off is the default for all three.

use crate::AppState;
use crate::settings;

/// A loan the sweep might have something to say about.
#[derive(sqlx::FromRow)]
struct DueLoan {
    id: String,
    borrower: String,
    borrower_contact: Option<String>,
    due_at: String,
    loaned_at: String,
    title: String,
    /// Whose library it is — the name the message signs off with.
    owner_name: Option<String>,
}

/// Which reminder, if any, a loan is owed today.
///
/// Split out from the query so the decision is testable without a database:
/// dates are where this class of code goes wrong.
///
/// [days_until] is negative once the date has passed. The `before` stage is a
/// window rather than an exact day — a server that was off on the third day
/// before should still send it on the second, since the point is that the
/// reminder arrives, not that it arrives on a particular morning.
pub fn stage_for(days_until: i64, lead_days: i64) -> Option<&'static str> {
    if days_until > lead_days {
        return None;
    }
    if days_until > 0 {
        return Some("before");
    }
    if days_until == 0 {
        return Some("due");
    }
    Some("overdue")
}

/// Whole days from today to [due], by date rather than by hour: a book due
/// "tomorrow" is due tomorrow whether it was lent at nine or at midnight.
pub fn days_until(now: &str, due: &str) -> Option<i64> {
    let today = date_part(now)?;
    let then = date_part(due)?;
    Some(then.signed_duration_since(today).num_days())
}

fn date_part(timestamp: &str) -> Option<chrono::NaiveDate> {
    let head = timestamp.get(..10)?;
    chrono::NaiveDate::parse_from_str(head, "%Y-%m-%d").ok()
}

/// Sends what is owed. Returns how many messages went out, which is what the
/// tests and the manual "send now" both want to know.
pub async fn sweep(state: &AppState) -> usize {
    let Some(mailer) = state.mailer.as_ref() else {
        return 0;
    };
    if settings::get(state, settings::LOAN_REMINDERS).await != "on" {
        return 0;
    }
    let lead_days: i64 = settings::get(state, settings::REMINDER_LEAD_DAYS)
        .await
        .parse()
        .unwrap_or(3);

    // Live loans only, with a date and an address to write to. The `remind`
    // column is the per-loan opt-out.
    let loans: Vec<DueLoan> = match sqlx::query_as(
        "SELECT l.id, l.borrower, l.borrower_contact, l.due_at, l.loaned_at, \
                b.title, u.display_name AS owner_name \
         FROM loan l \
         JOIN physical_copy pc ON pc.id = l.copy_id \
         JOIN book b ON b.id = pc.book_id \
         LEFT JOIN app_user u ON u.id = b.owner_id \
         WHERE l.returned_at IS NULL \
           AND l.due_at IS NOT NULL \
           AND l.remind = 1 \
           AND l.borrower_contact IS NOT NULL \
           AND l.borrower_contact != ''",
    )
    .fetch_all(&state.db)
    .await
    {
        Ok(rows) => rows,
        Err(e) => {
            tracing::error!("loan reminders: could not list loans: {e}");
            return 0;
        }
    };

    let now: String = sqlx::query_scalar("SELECT datetime('now')")
        .fetch_one(&state.db)
        .await
        .unwrap_or_default();

    let mut sent = 0;
    for loan in loans {
        let Some(days) = days_until(&now, &loan.due_at) else {
            continue;
        };
        let Some(stage) = stage_for(days, lead_days) else {
            continue;
        };
        let already: Option<String> =
            sqlx::query_scalar("SELECT stage FROM loan_reminder WHERE loan_id = ? AND stage = ?")
                .bind(&loan.id)
                .bind(stage)
                .fetch_optional(&state.db)
                .await
                .ok()
                .flatten();
        if already.is_some() {
            continue;
        }

        let (subject_key, body_key) = match stage {
            "before" => (
                settings::REMINDER_BEFORE_SUBJECT,
                settings::REMINDER_BEFORE_BODY,
            ),
            "due" => (settings::REMINDER_DUE_SUBJECT, settings::REMINDER_DUE_BODY),
            _ => (
                settings::REMINDER_OVERDUE_SUBJECT,
                settings::REMINDER_OVERDUE_BODY,
            ),
        };
        let library = loan
            .owner_name
            .clone()
            .filter(|n| !n.trim().is_empty())
            .map(|n| format!("{n}'s library"))
            .unwrap_or_else(|| "your library".to_string());
        let values = [
            ("title", loan.title.as_str()),
            ("borrower", loan.borrower.as_str()),
            ("due_date", &loan.due_at[..10.min(loan.due_at.len())]),
            (
                "loaned_date",
                &loan.loaned_at[..10.min(loan.loaned_at.len())],
            ),
            ("days", &days.abs().to_string()),
            ("library", &library),
        ];
        let subject = settings::render(&settings::get(state, subject_key).await, &values);
        let body = settings::render(&settings::get(state, body_key).await, &values);
        let to = loan.borrower_contact.clone().unwrap_or_default();

        // Recorded *before* sending: a message that goes out and then fails to
        // record would be sent again on the next sweep, and a borrower emailed
        // twice an hour is worse than one not emailed at all. A message that is
        // recorded and then fails to send is one missed reminder, and the next
        // stage still comes.
        if let Err(e) =
            sqlx::query("INSERT INTO loan_reminder (loan_id, stage, sent_to) VALUES (?, ?, ?)")
                .bind(&loan.id)
                .bind(stage)
                .bind(&to)
                .execute(&state.db)
                .await
        {
            tracing::error!("loan reminders: could not record {stage}: {e}");
            continue;
        }
        match mailer.send(&to, &subject, &body).await {
            Ok(()) => {
                sent += 1;
                tracing::info!("loan reminders: sent '{stage}' for loan {}", loan.id);
            }
            // `AppError` says nothing useful in a log and deliberately does
            // not implement Display — the message it carries is for a client.
            Err(_) => tracing::error!(
                "loan reminders: sending '{stage}' for loan {} failed",
                loan.id
            ),
        }
    }
    sent
}

/// Sweeps every hour, and once shortly after boot.
///
/// Hourly rather than daily because "daily" needs a time of day to happen at,
/// and a server restarted every evening at six would send its reminders at six
/// — or, if the schedule were absolute, never. Each stage is sent once, so the
/// cost of sweeping often is a query.
///
/// The first sweep waits a minute: a server that has only just come up is
/// usually being watched, and an email storm from a mis-restored database is
/// better met while somebody is looking.
pub async fn run_reminder_worker(state: AppState) {
    tokio::time::sleep(std::time::Duration::from_secs(60)).await;
    loop {
        let sent = sweep(&state).await;
        if sent > 0 {
            tracing::info!("loan reminders: sent {sent} message(s)");
        }
        tokio::time::sleep(std::time::Duration::from_secs(3600)).await;
    }
}
