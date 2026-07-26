//! Published physical room layouts (plan 5 #47).
//!
//! **A document store, not a synced table.** Everything else the server holds
//! is rows merged by last-write-wins. A room is a *composition*: two devices
//! that each moved half the books have no meaningful row-level merge, and LWW
//! would interleave two arrangements into a third nobody made. So a layout is
//! published whole, with a revision counter, and a stale publish is a **409**
//! the human resolves — the same reasoning that rejected field-level merge in
//! §J of the improvement plan.
//!
//! **The server does not interpret the document.** It checks that it parses and
//! fits under the size cap, then stores it verbatim. Any further validation
//! would be a second implementation of `docs/LAYOUT_DOC.md` to keep in step with
//! the app's.
//!
//! **The document carries no book metadata** — geometry only — which is what
//! makes the console's room view (#48) safe by construction rather than by
//! remembering to filter.

use axum::Json;
use axum::extract::{Path, State};
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};

/// 512 KiB. A large room is a few hundred placements — well under 100 KB — so
/// this only ever catches a bug or an abuse, and a room that genuinely exceeded
/// it would be one nobody could see on a screen.
const MAX_DOC_BYTES: usize = 512 * 1024;

#[derive(Serialize, sqlx::FromRow)]
pub struct LayoutSummary {
    pub id: String,
    pub name: String,
    pub revision: i64,
    pub published_at: String,
    pub owner_id: String,
    /// Whether the caller owns it, so a client can offer Publish rather than
    /// only Fetch without a second query.
    pub mine: bool,
}

#[derive(Serialize)]
pub struct LayoutDoc {
    pub id: String,
    pub name: String,
    pub revision: i64,
    pub published_at: String,
    pub owner_id: String,
    pub mine: bool,
    /// The `layout_doc` JSON, parsed back out so a client gets one object
    /// rather than a string containing an object.
    pub doc: serde_json::Value,
}

#[derive(Deserialize)]
pub struct PublishInput {
    pub name: String,
    /// The revision this publish started from. `0` (or absent) means "this is
    /// new"; anything else must equal the stored revision.
    #[serde(default)]
    pub base_revision: i64,
    pub doc: serde_json::Value,
}

/// The predicate for "layouts this caller may see": their own, or one shared
/// with them at `scope = 'layout'`. Binds, in order: `user.id`, `user.is_master`,
/// `user.id`.
///
/// Master sees everything, exactly as with books — a self-hosted server's owner
/// is already the person who can read the database.
fn visible_predicate() -> &'static str {
    "( l.owner_id = ? \
        OR ? = 1 \
        OR EXISTS ( \
            SELECT 1 FROM share s WHERE s.grantee_id = ? \
              AND s.scope = 'layout' AND s.scope_id = l.id ) )"
}

pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Vec<LayoutSummary>>> {
    let rows: Vec<(String, String, i64, String, String)> = sqlx::query_as(&format!(
        "SELECT l.id, l.name, l.revision, l.published_at, l.owner_id \
         FROM layout l WHERE {} ORDER BY l.name",
        visible_predicate()
    ))
    .bind(&user.id)
    .bind(user.is_master)
    .bind(&user.id)
    .fetch_all(&state.db)
    .await?;

    Ok(Json(
        rows.into_iter()
            .map(
                |(id, name, revision, published_at, owner_id)| LayoutSummary {
                    mine: owner_id == user.id,
                    id,
                    name,
                    revision,
                    published_at,
                    owner_id,
                },
            )
            .collect(),
    ))
}

pub async fn get(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<LayoutDoc>> {
    let row: Option<(String, String, i64, String, String, String)> = sqlx::query_as(&format!(
        "SELECT l.id, l.name, l.revision, l.published_at, l.owner_id, l.doc \
         FROM layout l WHERE l.id = ? AND {}",
        visible_predicate()
    ))
    .bind(&id)
    .bind(&user.id)
    .bind(user.is_master)
    .bind(&user.id)
    .fetch_optional(&state.db)
    .await?;

    // 404 rather than 403 for a layout the caller can't see — the same rule the
    // rest of the API follows, so this can't be used to probe which ids exist.
    let (id, name, revision, published_at, owner_id, doc) =
        row.ok_or_else(|| AppError::NotFound("layout not found".into()))?;

    Ok(Json(LayoutDoc {
        mine: owner_id == user.id,
        id,
        name,
        revision,
        published_at,
        owner_id,
        doc: serde_json::from_str(&doc).unwrap_or(serde_json::Value::Null),
    }))
}

/// `PUT /api/layouts/{id}` — publish, at a caller-chosen id (the environment's).
///
/// The id comes from the app so a device that published a room and a device
/// that fetched it agree without a mapping table.
pub async fn publish(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(input): Json<PublishInput>,
) -> AppResult<Json<LayoutSummary>> {
    if input.name.trim().is_empty() {
        return Err(AppError::BadRequest("name is required".into()));
    }
    let doc = serde_json::to_string(&input.doc)
        .map_err(|_| AppError::BadRequest("doc is not valid JSON".into()))?;
    if doc.len() > MAX_DOC_BYTES {
        return Err(AppError::BadRequest(format!(
            "layout is too large ({} KiB; the limit is {} KiB)",
            doc.len() / 1024,
            MAX_DOC_BYTES / 1024
        )));
    }
    // A bare `null`/number/string would store and hand back something no viewer
    // can render; the shape is the app's business but "is an object" is not.
    if !input.doc.is_object() {
        return Err(AppError::BadRequest("doc must be an object".into()));
    }

    let existing: Option<(String, i64)> =
        sqlx::query_as("SELECT owner_id, revision FROM layout WHERE id = ?")
            .bind(&id)
            .fetch_optional(&state.db)
            .await?;

    let revision = match existing {
        Some((owner_id, revision)) => {
            if !user.is_master && owner_id != user.id {
                // Someone else's room. 404, not 403 — see `get`.
                return Err(AppError::NotFound("layout not found".into()));
            }
            if input.base_revision != revision {
                return Err(AppError::Conflict(format!(
                    "this room was published from another device (revision {revision})"
                )));
            }
            // Guarded by the WHERE below as well, so two publishes racing on
            // the same base revision can't both win.
            let updated = sqlx::query(
                "UPDATE layout SET name = ?, doc = ?, revision = revision + 1, \
                    published_at = datetime('now') \
                 WHERE id = ? AND revision = ?",
            )
            .bind(input.name.trim())
            .bind(&doc)
            .bind(&id)
            .bind(revision)
            .execute(&state.db)
            .await?
            .rows_affected();
            if updated == 0 {
                return Err(AppError::Conflict(
                    "this room was published from another device".into(),
                ));
            }
            revision + 1
        }
        None => {
            sqlx::query(
                "INSERT INTO layout (id, owner_id, name, revision, doc) \
                 VALUES (?, ?, ?, 1, ?)",
            )
            .bind(&id)
            .bind(&user.id)
            .bind(input.name.trim())
            .bind(&doc)
            .execute(&state.db)
            .await?;
            1
        }
    };

    crate::audit::record(
        &state,
        Some(&user),
        "layout.publish",
        "layout",
        &id,
        Some(input.name.trim()),
    )
    .await;

    let published_at: String = sqlx::query_scalar("SELECT published_at FROM layout WHERE id = ?")
        .bind(&id)
        .fetch_one(&state.db)
        .await?;

    Ok(Json(LayoutSummary {
        id,
        name: input.name.trim().to_string(),
        revision,
        published_at,
        owner_id: user.id.clone(),
        mine: true,
    }))
}

/// Owner (or master) only. Shares of the layout go with it — a share pointing
/// at a room that no longer exists is a dead entry in someone's list.
pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    let owner: Option<String> = sqlx::query_scalar("SELECT owner_id FROM layout WHERE id = ?")
        .bind(&id)
        .fetch_optional(&state.db)
        .await?;
    let owner = owner.ok_or_else(|| AppError::NotFound("layout not found".into()))?;
    if !user.is_master && owner != user.id {
        return Err(AppError::NotFound("layout not found".into()));
    }

    let mut tx = state.db.begin().await?;
    sqlx::query("DELETE FROM share WHERE scope = 'layout' AND scope_id = ?")
        .bind(&id)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM layout WHERE id = ?")
        .bind(&id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    crate::audit::record(&state, Some(&user), "layout.delete", "layout", &id, None).await;
    Ok(Json(serde_json::json!({ "deleted": id })))
}

/// The owner of a layout, for the share-scope check in `shares::create`.
pub async fn owner_of(state: &AppState, layout_id: &str) -> AppResult<Option<String>> {
    Ok(
        sqlx::query_scalar("SELECT owner_id FROM layout WHERE id = ?")
            .bind(layout_id)
            .fetch_optional(&state.db)
            .await?,
    )
}
