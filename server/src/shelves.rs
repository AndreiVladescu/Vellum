//! Custom shelves (plan 5 #4): manual, explicitly-ordered book collections,
//! now synced like books rather than living only on one device. Mirrors
//! `books.rs`'s upsert/delta-pull/tombstone idioms so the two stay consistent.

use axum::Json;
use axum::extract::{Path, Query, State};
use serde::{Deserialize, Serialize};
use std::collections::HashMap;

use crate::AppState;
use crate::access::shelf_access;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};

#[derive(Serialize, sqlx::FromRow)]
pub struct ShelfRow {
    pub id: String,
    pub owner_id: String,
    pub name: String,
    pub sort_order: i64,
    pub updated_at: String,
    /// A shelf its owner keeps to themselves (migration 0029). It still syncs
    /// — it is theirs on every device they use — but no share can see it, so
    /// "books I mean to reread" stays out of other people's chip rows.
    pub personal: bool,
}

/// A shelf plus its membership in explicit order — the app's push sends the
/// same shape and the server replaces the whole list, so ordering never needs
/// a separate move/reorder endpoint.
#[derive(Serialize)]
pub struct ShelfDto {
    #[serde(flatten)]
    pub shelf: ShelfRow,
    pub book_ids: Vec<String>,
}

#[derive(Deserialize)]
pub struct ShelfInput {
    pub name: String,
    #[serde(default)]
    pub sort_order: i64,
    #[serde(default)]
    pub book_ids: Vec<String>,
    /// The pushing client's sync clock, same LWW convention as `BookInput`.
    #[serde(default)]
    pub updated_at: Option<String>,
    /// Defaults to public: a client that predates 0029 sends nothing, and its
    /// shelves are the shared kind, which is what they already were.
    #[serde(default)]
    pub personal: bool,
}

/// Shelves owned by the caller, plus every shelf shared with them via an
/// all-scope share (there is no shelf-scoped share type — see
/// `access::shelf_access`). `updated_since` narrows to a delta pull.
async fn visible_shelves(
    state: &AppState,
    user: &AuthUser,
    updated_since: Option<&str>,
) -> AppResult<Vec<ShelfRow>> {
    let filter = if updated_since.is_some() {
        " AND s.updated_at >= ?"
    } else {
        ""
    };
    let sql = format!(
        // A personal shelf is reachable by its owner (and the master, who
        // administers the server) but never through a share — that is the whole
        // distinction the flag exists to draw.
        "SELECT s.id, s.owner_id, s.name, s.sort_order, s.updated_at, s.personal FROM shelf s \
         WHERE ( s.owner_id = ? OR ? = 1 OR ( s.personal = 0 AND EXISTS ( \
            SELECT 1 FROM share sh WHERE sh.grantee_id = ? AND sh.scope = 'all' \
                AND sh.owner_id = s.owner_id) ) ) \
            {filter} \
         ORDER BY s.sort_order, s.name"
    );
    let mut query = sqlx::query_as::<_, ShelfRow>(&sql)
        .bind(&user.id)
        .bind(user.is_master)
        .bind(&user.id);
    if let Some(ts) = updated_since {
        query = query.bind(ts.to_string());
    }
    Ok(query.fetch_all(&state.db).await?)
}

/// Ordered book ids for exactly `shelf_ids`, one scan (mirrors
/// `books::author_map_for`'s chunked-IN-list reasoning).
const ID_CHUNK: usize = 900;

async fn membership_by_shelf(
    state: &AppState,
    shelf_ids: &[String],
) -> AppResult<HashMap<String, Vec<String>>> {
    let mut map: HashMap<String, Vec<String>> = HashMap::new();
    if shelf_ids.is_empty() {
        return Ok(map);
    }
    #[derive(sqlx::FromRow)]
    struct Row {
        shelf_id: String,
        book_id: String,
    }
    for chunk in shelf_ids.chunks(ID_CHUNK) {
        let placeholders = std::iter::repeat_n("?", chunk.len())
            .collect::<Vec<_>>()
            .join(",");
        let sql = format!(
            "SELECT shelf_id, book_id FROM shelf_book \
             WHERE shelf_id IN ({placeholders}) ORDER BY shelf_id, position"
        );
        let mut query = sqlx::query_as::<_, Row>(&sql);
        for id in chunk {
            query = query.bind(id);
        }
        for row in query.fetch_all(&state.db).await? {
            map.entry(row.shelf_id).or_default().push(row.book_id);
        }
    }
    Ok(map)
}

/// Query params: same `cursor`-presence convention as `books::list` — present
/// (even empty) selects the `{ server_now, shelves }` envelope and, if
/// non-empty, filters to shelves changed since it; absent returns a bare
/// array (there is no paged/console shape for shelves, so no `page` param).
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
    let shelves = visible_shelves(&state, &user, since).await?;
    let items = assemble_items(&state, shelves).await?;

    if q.cursor.is_some() {
        let server_now: String = sqlx::query_scalar("SELECT datetime('now')")
            .fetch_one(&state.db)
            .await?;
        Ok(Json(serde_json::json!({
            "server_now": server_now,
            "shelves": items,
        })))
    } else {
        Ok(Json(serde_json::to_value(items)?))
    }
}

async fn assemble_items(state: &AppState, shelves: Vec<ShelfRow>) -> AppResult<Vec<ShelfDto>> {
    let ids: Vec<String> = shelves.iter().map(|s| s.id.clone()).collect();
    let mut membership = membership_by_shelf(state, &ids).await?;
    Ok(shelves
        .into_iter()
        .map(|shelf| {
            let book_ids = membership.remove(&shelf.id).unwrap_or_default();
            ShelfDto { shelf, book_ids }
        })
        .collect())
}

/// Upsert a shelf at a caller-chosen id, same convention as `books::upsert`:
/// creates it (owned by the caller) if absent, otherwise requires edit access.
/// `book_ids` **replaces** the membership list wholesale (a push always sends
/// the full ordered shelf) — ids the server doesn't recognize as a book are
/// dropped rather than rejected, since `shelf_book.book_id` has a foreign key
/// and a stale/foreign id must not fail the whole shelf.
pub async fn upsert(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(input): Json<ShelfInput>,
) -> AppResult<Json<ShelfDto>> {
    crate::ids::check("shelf", &id)?;
    if input.name.trim().is_empty() {
        return Err(AppError::BadRequest("shelf name is required".into()));
    }
    let existing: Option<(String, String)> =
        sqlx::query_as("SELECT owner_id, updated_at FROM shelf WHERE id = ?")
            .bind(&id)
            .fetch_optional(&state.db)
            .await?;

    let is_update = match &existing {
        Some((_owner, stored_updated_at)) => {
            if !shelf_access(&state, &user, &id).await?.can_edit() {
                return Err(AppError::Forbidden(
                    "you have read-only access to this shelf".into(),
                ));
            }
            if let Some(incoming) = input.updated_at.as_deref()
                && incoming <= stored_updated_at.as_str()
            {
                return fetch_shelf(&state, &id).await;
            }
            true
        }
        None => false,
    };

    // No-op guard, same reasoning as books::upsert: skip the write (and the
    // updated_at churn) when the push wouldn't change anything, including
    // order — a scrambled shelf is exactly the failure mode a naive
    // "book set unchanged" check would miss.
    if is_update {
        let current = fetch_shelf(&state, &id).await?.0;
        let tombstoned: bool = sqlx::query_scalar(
            "SELECT EXISTS(SELECT 1 FROM deletion WHERE entity_id = ? AND kind = 'shelf')",
        )
        .bind(&id)
        .fetch_one(&state.db)
        .await?;
        if current.shelf.name == input.name.trim()
            && current.shelf.sort_order == input.sort_order
            && current.book_ids == input.book_ids
            && current.shelf.personal == input.personal
            && !tombstoned
        {
            return Ok(Json(current));
        }
    }

    let valid_book_ids = existing_book_ids(&state, &input.book_ids).await?;

    let mut tx = state.db.begin().await?;
    if is_update {
        sqlx::query(
            "UPDATE shelf SET name = ?, sort_order = ?, personal = ?, \
                updated_at = datetime('now') \
             WHERE id = ?",
        )
        .bind(input.name.trim())
        .bind(input.sort_order)
        .bind(input.personal)
        .bind(&id)
        .execute(&mut *tx)
        .await?;
    } else {
        sqlx::query(
            "INSERT INTO shelf (id, owner_id, name, sort_order, personal) \
             VALUES (?, ?, ?, ?, ?)",
        )
        .bind(&id)
        .bind(&user.id)
        .bind(input.name.trim())
        .bind(input.sort_order)
        .bind(input.personal)
            .execute(&mut *tx)
            .await?;
    }
    // Re-creating a shelf at a tombstoned id revives it, same as books::upsert.
    sqlx::query("DELETE FROM deletion WHERE entity_id = ? AND kind = 'shelf'")
        .bind(&id)
        .execute(&mut *tx)
        .await?;

    sqlx::query("DELETE FROM shelf_book WHERE shelf_id = ?")
        .bind(&id)
        .execute(&mut *tx)
        .await?;
    for (position, book_id) in valid_book_ids.iter().enumerate() {
        sqlx::query("INSERT INTO shelf_book (shelf_id, book_id, position) VALUES (?, ?, ?)")
            .bind(&id)
            .bind(book_id)
            .bind(position as i64)
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;

    crate::events::publish(&state, "shelf", &id, "upsert");
    fetch_shelf(&state, &id).await
}

/// Filters `ids` down to the ones that actually name a book on the server,
/// preserving order — the FK-safety net `upsert`'s doc comment promises.
async fn existing_book_ids(state: &AppState, ids: &[String]) -> AppResult<Vec<String>> {
    if ids.is_empty() {
        return Ok(Vec::new());
    }
    let placeholders = std::iter::repeat_n("?", ids.len())
        .collect::<Vec<_>>()
        .join(",");
    let sql = format!("SELECT id FROM book WHERE id IN ({placeholders})");
    let mut query = sqlx::query_scalar::<_, String>(&sql);
    for id in ids {
        query = query.bind(id);
    }
    let present: std::collections::HashSet<String> =
        query.fetch_all(&state.db).await?.into_iter().collect();
    Ok(ids
        .iter()
        .filter(|id| present.contains(*id))
        .cloned()
        .collect())
}

pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    let owner: Option<String> = sqlx::query_scalar("SELECT owner_id FROM shelf WHERE id = ?")
        .bind(&id)
        .fetch_optional(&state.db)
        .await?;
    let Some(owner_id) = owner else {
        return Err(AppError::NotFound("shelf not found".into()));
    };
    if !user.is_master && owner_id != user.id {
        return Err(AppError::Forbidden(
            "only the owner may delete this shelf".into(),
        ));
    }

    let mut tx = state.db.begin().await?;
    sqlx::query(
        "INSERT OR REPLACE INTO deletion (entity_id, owner_id, kind) VALUES (?, ?, 'shelf')",
    )
    .bind(&id)
    .bind(&owner_id)
    .execute(&mut *tx)
    .await?;
    sqlx::query("DELETE FROM shelf WHERE id = ?")
        .bind(&id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    crate::events::publish(&state, "shelf", &id, "delete");
    Ok(Json(serde_json::json!({ "deleted": id })))
}

async fn fetch_shelf(state: &AppState, id: &str) -> AppResult<Json<ShelfDto>> {
    let shelf = sqlx::query_as::<_, ShelfRow>(
        "SELECT id, owner_id, name, sort_order, updated_at, personal FROM shelf WHERE id = ?",
    )
    .bind(id)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::NotFound("shelf not found".into()))?;
    let book_ids = sqlx::query_scalar::<_, String>(
        "SELECT book_id FROM shelf_book WHERE shelf_id = ? ORDER BY position",
    )
    .bind(id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(ShelfDto { shelf, book_ids }))
}
