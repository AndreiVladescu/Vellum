//! The activity log (plan 5 #35).
//!
//! **Why.** With several members editing one library, "who deleted that book?"
//! currently has no answer. This is cheap insurance: a row per mutation, read
//! only by the master.
//!
//! **Opt-in and bounded.** `VELLUM_AUDIT=1` turns it on; a single-user server
//! should not pay for a table it will never read. Beyond [`MAX_ROWS`] the oldest
//! rows are trimmed, so an unattended server cannot grow a log until the disk
//! fills — a log that takes the server down is worse than no log.
//!
//! **What is *not* recorded.** Never a payload: a note is a title or an email,
//! never a description or a file's contents. An audit log that copies the books
//! into a table with different access control is a second, weaker library.
//!
//! **Never fails a request.** Every write here is best-effort. Losing an audit
//! row is a small loss; failing the delete the user asked for because its log
//! entry couldn't be written is a large one.

use axum::Json;
use axum::extract::{Query, State};
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};

/// How many rows to keep. Roughly a year of a busy shared library, and a few
/// megabytes at most.
pub const MAX_ROWS: i64 = 50_000;

/// Trim every this many writes rather than on each one — the sweep is a
/// `DELETE ... WHERE id <= ?`, cheap but not free.
const TRIM_EVERY: u64 = 256;

static WRITES: std::sync::atomic::AtomicU64 = std::sync::atomic::AtomicU64::new(0);

/// Records one action. A no-op unless the server opted in.
pub async fn record(
    state: &AppState,
    actor: Option<&AuthUser>,
    action: &str,
    target_kind: &str,
    target_id: &str,
    detail: Option<&str>,
) {
    if !state.audit {
        return;
    }
    let result = sqlx::query(
        "INSERT INTO audit (actor_id, actor_email, action, target_kind, target_id, detail) \
         VALUES (?, ?, ?, ?, ?, ?)",
    )
    .bind(actor.map(|a| a.id.as_str()))
    .bind(actor.map(|a| a.email.as_str()))
    .bind(action)
    .bind(target_kind)
    .bind(target_id)
    .bind(detail.map(truncate))
    .execute(&state.db)
    .await;
    if let Err(e) = result {
        // Logged, never propagated: see the module comment.
        tracing::warn!("audit: could not record {action}: {e}");
        return;
    }

    let count = WRITES.fetch_add(1, std::sync::atomic::Ordering::Relaxed);
    if count.is_multiple_of(TRIM_EVERY) {
        trim(state).await;
    }
}

/// A detail note is a label, not a document.
fn truncate(detail: &str) -> String {
    const MAX: usize = 200;
    if detail.chars().count() <= MAX {
        return detail.to_string();
    }
    let mut out: String = detail.chars().take(MAX).collect();
    out.push('…');
    out
}

async fn trim(state: &AppState) {
    let _ = sqlx::query("DELETE FROM audit WHERE id <= (SELECT MAX(id) - ? FROM audit)")
        .bind(MAX_ROWS)
        .execute(&state.db)
        .await;
}

#[derive(Serialize, sqlx::FromRow)]
pub struct AuditRow {
    pub id: i64,
    pub at: String,
    pub actor_id: Option<String>,
    pub actor_email: Option<String>,
    pub action: String,
    pub target_kind: Option<String>,
    pub target_id: Option<String>,
    pub detail: Option<String>,
}

#[derive(Deserialize)]
pub struct AuditQuery {
    /// Filter to one actor, for "what has this member been doing?".
    pub actor: Option<String>,
    /// Filter to one action prefix, e.g. `book.` or `book.delete`.
    pub action: Option<String>,
    pub limit: Option<i64>,
    pub before: Option<i64>,
}

/// `GET /api/admin/audit` — master only.
///
/// Master-only rather than "each member sees their own": the log's purpose is
/// accountability across members, and a member who could read only their own
/// rows would learn nothing while a member who could read everyone's would turn
/// the log into a surveillance tool the library owner never agreed to.
pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<AuditQuery>,
) -> AppResult<Json<serde_json::Value>> {
    if !user.is_master {
        return Err(AppError::Forbidden(
            "only the master account may read the activity log".into(),
        ));
    }
    if !state.audit {
        return Ok(Json(serde_json::json!({ "enabled": false, "rows": [] })));
    }

    let limit = q.limit.unwrap_or(100).clamp(1, 1000);
    let mut sql = "SELECT id, at, actor_id, actor_email, action, target_kind, target_id, detail \
                   FROM audit WHERE 1 = 1"
        .to_string();
    let mut binds: Vec<String> = Vec::new();
    if let Some(actor) = q.actor.as_deref().filter(|a| !a.is_empty()) {
        sql.push_str(" AND (actor_id = ? OR actor_email = ?)");
        binds.push(actor.to_string());
        binds.push(actor.to_string());
    }
    if let Some(action) = q.action.as_deref().filter(|a| !a.is_empty()) {
        sql.push_str(" AND action LIKE ?");
        binds.push(format!("{action}%"));
    }
    // Keyset paging on the autoincrement id: an offset would skip rows as the
    // trim runs underneath a reader.
    if let Some(before) = q.before {
        sql.push_str(" AND id < ?");
        binds.push(before.to_string());
    }
    sql.push_str(" ORDER BY id DESC LIMIT ?");

    let mut query = sqlx::query_as::<_, AuditRow>(sqlx::AssertSqlSafe(sql.as_str()));
    for bind in &binds {
        query = query.bind(bind.clone());
    }
    let rows = query.bind(limit).fetch_all(&state.db).await?;
    let next = rows.last().map(|r| r.id);

    Ok(Json(serde_json::json!({
        "enabled": true,
        "rows": rows,
        "next_before": if (rows.len() as i64) < limit { None } else { next },
    })))
}
