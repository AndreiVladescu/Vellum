use axum::Json;
use axum::extract::{Path, State};
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::access::book_access;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};

#[derive(Debug, Serialize, sqlx::FromRow)]
pub struct BookDto {
    pub id: String,
    pub title: String,
    pub subtitle: Option<String>,
    pub description: Option<String>,
    pub isbn: Option<String>,
    pub publisher: Option<String>,
    pub published_year: Option<i64>,
    pub page_count: Option<i64>,
    pub cover_path: Option<String>,
    pub spine_style: Option<String>,
    pub owner_id: Option<String>,
    pub created_at: String,
    pub updated_at: String,
}

const BOOK_COLUMNS: &str = "id, title, subtitle, description, isbn, publisher, \
    published_year, page_count, cover_path, spine_style, owner_id, created_at, updated_at";

#[derive(Deserialize)]
pub struct BookInput {
    pub title: String,
    pub subtitle: Option<String>,
    pub description: Option<String>,
    pub isbn: Option<String>,
    pub publisher: Option<String>,
    pub published_year: Option<i64>,
    pub page_count: Option<i64>,
    pub cover_path: Option<String>,
    pub spine_style: Option<String>,
    /// The pushing client's sync clock as `"YYYY-MM-DD HH:MM:SS"` UTC (the same
    /// fixed-width form SQLite's `datetime('now')` produces, so lexical order is
    /// chronological). When present, [`upsert`] only overwrites an existing row
    /// if this is strictly newer than the stored `updated_at`. Absent for older
    /// clients, which keeps the always-overwrite behavior.
    #[serde(default)]
    pub updated_at: Option<String>,
    /// Author names in cover order. When present, [`upsert`] replaces the book's
    /// author joins with these (get-or-create by name). `None` (older clients)
    /// leaves existing joins untouched.
    #[serde(default)]
    pub authors: Option<Vec<String>>,
    /// Genre names. Same replace-or-leave semantics as [`authors`].
    #[serde(default)]
    pub genres: Option<Vec<String>>,
}

/// Partial update: every field optional; omitted fields are left unchanged.
#[derive(Deserialize)]
pub struct BookUpdate {
    pub title: Option<String>,
    pub subtitle: Option<String>,
    pub description: Option<String>,
    pub isbn: Option<String>,
    pub publisher: Option<String>,
    pub published_year: Option<i64>,
    pub page_count: Option<i64>,
    pub cover_path: Option<String>,
    pub spine_style: Option<String>,
}

/// Every book the caller can see: the ones they own, plus everything reachable
/// through a share (whole-library, group, or single-book), plus everything if
/// they are the master. Shared by the JSON list and the OPDS feed.
///
/// `updated_since` (for the app's delta pull) narrows to rows touched at or
/// after a cursor. `>=` rather than `>`: SQLite timestamps are second-resolution,
/// so `>` could skip a row edited in the very second the cursor was minted; the
/// small overlap is deduped by the client's per-row last-write-wins compare.
pub async fn visible_books(
    state: &AppState,
    user: &AuthUser,
    updated_since: Option<&str>,
) -> AppResult<Vec<BookDto>> {
    let filter = if updated_since.is_some() {
        " AND b.updated_at >= ?"
    } else {
        ""
    };
    let sql = format!(
        "SELECT {BOOK_COLUMNS} FROM book b WHERE {} {filter} ORDER BY b.title, b.id",
        access_predicate()
    );
    let mut query = sqlx::query_as::<_, BookDto>(&sql)
        .bind(&user.id)
        .bind(user.is_master)
        .bind(&user.id);
    if let Some(ts) = updated_since {
        query = query.bind(ts.to_string());
    }
    Ok(query.fetch_all(&state.db).await?)
}

/// The share/ownership predicate `visible_books` and `visible_books_page`
/// both filter on, factored out so the two can't drift apart. Binds (in
/// order): `user.id`, `user.is_master`, `user.id`. Wrapped in parens so a
/// caller ANDing another condition onto it doesn't just AND the last OR-term.
/// `pub(crate)`: `physical_copies::visible_copies` reuses it verbatim (joined
/// on `book b`), since a copy's visibility is exactly its book's.
pub(crate) fn access_predicate() -> &'static str {
    "( b.owner_id = ? \
        OR ? = 1 \
        OR EXISTS ( \
            SELECT 1 FROM share s WHERE s.grantee_id = ? AND ( \
                (s.scope = 'all'   AND s.owner_id = b.owner_id) OR \
                (s.scope = 'book'  AND s.scope_id = b.id) OR \
                (s.scope = 'group' AND EXISTS ( \
                    SELECT 1 FROM book_group_item gi \
                    WHERE gi.group_id = s.scope_id AND gi.book_id = b.id)) )) )"
}

/// A page of visible books (stable `title, id` order) plus the total count of
/// visible books under the same predicate — the console's paged fetch (§3).
/// Unlike `visible_books`, never used for the app's delta pull: paging must
/// never apply there, or a pull would silently stop short of its window.
pub async fn visible_books_page(
    state: &AppState,
    user: &AuthUser,
    limit: i64,
    offset: i64,
) -> AppResult<(Vec<BookDto>, i64)> {
    let sql = format!(
        "SELECT {BOOK_COLUMNS} FROM book b WHERE {} ORDER BY b.title, b.id LIMIT ? OFFSET ?",
        access_predicate()
    );
    let items = sqlx::query_as::<_, BookDto>(&sql)
        .bind(&user.id)
        .bind(user.is_master)
        .bind(&user.id)
        .bind(limit)
        .bind(offset)
        .fetch_all(&state.db)
        .await?;

    let count_sql = format!("SELECT COUNT(*) FROM book b WHERE {}", access_predicate());
    let total: i64 = sqlx::query_scalar(&count_sql)
        .bind(&user.id)
        .bind(user.is_master)
        .bind(&user.id)
        .fetch_one(&state.db)
        .await?;

    Ok((items, total))
}

/// All authors in the library, grouped by book id in cover order, from one
/// scan. Shared by the books list and the OPDS feed so neither does a per-book
/// author query (the OPDS N+1).
pub async fn author_map(
    state: &AppState,
) -> AppResult<std::collections::HashMap<String, Vec<String>>> {
    #[derive(sqlx::FromRow)]
    struct Row {
        book_id: String,
        name: String,
    }
    let rows = sqlx::query_as::<_, Row>(
        "SELECT ba.book_id, a.name FROM author a \
         JOIN book_author ba ON ba.author_id = a.id ORDER BY ba.book_id, ba.position",
    )
    .fetch_all(&state.db)
    .await?;
    let mut map: std::collections::HashMap<String, Vec<String>> = std::collections::HashMap::new();
    for row in rows {
        map.entry(row.book_id).or_default().push(row.name);
    }
    Ok(map)
}

/// All book files, grouped by book id as `(file_id, format)` in added order,
/// from one scan.
pub async fn files_map(
    state: &AppState,
) -> AppResult<std::collections::HashMap<String, Vec<(String, String)>>> {
    let rows: Vec<(String, String, String)> =
        sqlx::query_as("SELECT book_id, id, format FROM book_file ORDER BY book_id, added_at")
            .fetch_all(&state.db)
            .await?;
    let mut map: std::collections::HashMap<String, Vec<(String, String)>> =
        std::collections::HashMap::new();
    for (book_id, id, format) in rows {
        map.entry(book_id).or_default().push((id, format));
    }
    Ok(map)
}

/// SQLite's default `SQLITE_MAX_VARIABLE_NUMBER` is 999 (raised in newer
/// builds, but this repo doesn't assume that) — chunk `IN (?,?,…)` lists to
/// stay under it with room for a query's other binds.
const ID_CHUNK: usize = 900;

fn in_placeholders(n: usize) -> String {
    std::iter::repeat_n("?", n).collect::<Vec<_>>().join(",")
}

/// Authors for exactly `ids`, grouped by book id in cover order — `list`'s
/// scoped counterpart to `author_map` (§3: a one-book delta pull shouldn't
/// scan every author join in the library). A TEMP TABLE join would also work
/// but needs a transaction to survive across statements on a pooled
/// connection; a chunked `IN` list needs neither and reads no differently.
pub async fn author_map_for(
    state: &AppState,
    ids: &[String],
) -> AppResult<std::collections::HashMap<String, Vec<String>>> {
    let mut map: std::collections::HashMap<String, Vec<String>> = std::collections::HashMap::new();
    if ids.is_empty() {
        return Ok(map);
    }
    #[derive(sqlx::FromRow)]
    struct Row {
        book_id: String,
        name: String,
    }
    for chunk in ids.chunks(ID_CHUNK) {
        let sql = format!(
            "SELECT ba.book_id, a.name FROM author a \
             JOIN book_author ba ON ba.author_id = a.id \
             WHERE ba.book_id IN ({}) ORDER BY ba.book_id, ba.position",
            in_placeholders(chunk.len())
        );
        let mut query = sqlx::query_as::<_, Row>(&sql);
        for id in chunk {
            query = query.bind(id);
        }
        for row in query.fetch_all(&state.db).await? {
            map.entry(row.book_id).or_default().push(row.name);
        }
    }
    Ok(map)
}

/// Genres for exactly `ids`, grouped by book id — scoped counterpart to a
/// full genre scan, same reasoning as `author_map_for`.
pub async fn genre_map_for(
    state: &AppState,
    ids: &[String],
) -> AppResult<std::collections::HashMap<String, Vec<String>>> {
    let mut map: std::collections::HashMap<String, Vec<String>> = std::collections::HashMap::new();
    if ids.is_empty() {
        return Ok(map);
    }
    #[derive(sqlx::FromRow)]
    struct Row {
        book_id: String,
        name: String,
    }
    for chunk in ids.chunks(ID_CHUNK) {
        let sql = format!(
            "SELECT bg.book_id, g.name FROM genre g \
             JOIN book_genre bg ON bg.genre_id = g.id \
             WHERE bg.book_id IN ({}) ORDER BY bg.book_id, g.name",
            in_placeholders(chunk.len())
        );
        let mut query = sqlx::query_as::<_, Row>(&sql);
        for id in chunk {
            query = query.bind(id);
        }
        for row in query.fetch_all(&state.db).await? {
            map.entry(row.book_id).or_default().push(row.name);
        }
    }
    Ok(map)
}

/// Files for exactly `ids`, grouped by book id — scoped counterpart to a full
/// file scan, same reasoning as `author_map_for`.
pub async fn files_full_map_for(
    state: &AppState,
    ids: &[String],
) -> AppResult<std::collections::HashMap<String, Vec<crate::blobs::FileDto>>> {
    let mut map: std::collections::HashMap<String, Vec<crate::blobs::FileDto>> =
        std::collections::HashMap::new();
    if ids.is_empty() {
        return Ok(map);
    }
    for chunk in ids.chunks(ID_CHUNK) {
        let sql = format!(
            "SELECT id, book_id, format, path, size_bytes, sha256, added_at \
             FROM book_file WHERE book_id IN ({}) ORDER BY book_id, added_at",
            in_placeholders(chunk.len())
        );
        let mut query = sqlx::query_as::<_, crate::blobs::FileDto>(&sql);
        for id in chunk {
            query = query.bind(id);
        }
        for f in query.fetch_all(&state.db).await? {
            map.entry(f.book_id.clone()).or_default().push(f);
        }
    }
    Ok(map)
}

/// A book plus the aggregates a client needs without a per-row round-trip: the
/// console renders Author/file columns from these, and the app's pull reads
/// `files` instead of a `GET .../files` per book.
#[derive(Serialize)]
pub struct BookListItem {
    #[serde(flatten)]
    pub book: BookDto,
    pub authors: Vec<String>,
    pub genres: Vec<String>,
    pub files: Vec<crate::blobs::FileDto>,
    /// Retained for the console; now just `files.len()`, no separate scan.
    pub file_count: i64,
}

/// Query params for the books list.
///
/// `cursor`'s **presence** (even empty) is what selects the `{ server_now,
/// books }` envelope for the app's delta pull, and a non-empty value further
/// filters to rows changed since it; an empty cursor is the app's *first*
/// sync — still the envelope shape, still unbounded. Whenever `cursor` is
/// present at all, `page`/`limit` are ignored: a delta pull must never
/// silently stop short of its window.
///
/// `page` (1-based) requests the paged `{ items, total, next }` shape instead
/// of today's bare array — gated behind this explicit param so existing
/// console clients keep working until moved over (§3), then the flag drops.
/// `limit` overrides the default page size, clamped to `MAX_PAGE_SIZE`.
#[derive(Deserialize)]
pub struct ListQuery {
    pub cursor: Option<String>,
    pub page: Option<u32>,
    pub limit: Option<u32>,
}

const DEFAULT_PAGE_SIZE: i64 = 200;
const MAX_PAGE_SIZE: i64 = 2000;

pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
    axum::extract::Query(q): axum::extract::Query<ListQuery>,
) -> AppResult<Json<serde_json::Value>> {
    // Gate on `q.cursor.is_some()` alone, once, up front — not on whether the
    // cursor is non-empty. An empty `?cursor=` still means "delta-pull
    // envelope, unbounded"; letting `page` apply to it would silently
    // truncate a client's first sync.
    if let Some(cursor) = &q.cursor {
        let since = cursor.trim();
        let since = if since.is_empty() { None } else { Some(since) };
        let books = visible_books(&state, &user, since).await?;
        let items = assemble_items(&state, books).await?;
        let server_now: String = sqlx::query_scalar("SELECT datetime('now')")
            .fetch_one(&state.db)
            .await?;
        return Ok(Json(serde_json::json!({
            "server_now": server_now,
            "books": items,
        })));
    }

    if let Some(page) = q.page {
        let limit = (q.limit.unwrap_or(DEFAULT_PAGE_SIZE as u32) as i64).clamp(1, MAX_PAGE_SIZE);
        let page = page.max(1) as i64;
        let offset = (page - 1) * limit;
        let (books, total) = visible_books_page(&state, &user, limit, offset).await?;
        let next = if offset + (books.len() as i64) < total {
            Some(page + 1)
        } else {
            None
        };
        let items = assemble_items(&state, books).await?;
        return Ok(Json(serde_json::json!({
            "items": items,
            "total": total,
            "next": next,
        })));
    }

    // Neither cursor nor page: today's unbounded bare array, kept for console
    // clients until they're moved onto `?page=1`.
    let books = visible_books(&state, &user, None).await?;
    let items = assemble_items(&state, books).await?;
    Ok(Json(serde_json::to_value(items)?))
}

/// Assembles `BookListItem`s for exactly `books`, scoping the authors/genres/
/// files aggregation to their ids (§3) instead of scanning the whole library
/// regardless of how few books the caller actually asked for.
async fn assemble_items(state: &AppState, books: Vec<BookDto>) -> AppResult<Vec<BookListItem>> {
    let ids: Vec<String> = books.iter().map(|b| b.id.clone()).collect();
    let authors_by_book = author_map_for(state, &ids).await?;
    let genres_by_book = genre_map_for(state, &ids).await?;
    let mut files_by_book = files_full_map_for(state, &ids).await?;

    Ok(books
        .into_iter()
        .map(|book| {
            let authors = authors_by_book.get(&book.id).cloned().unwrap_or_default();
            let genres = genres_by_book.get(&book.id).cloned().unwrap_or_default();
            let files = files_by_book.remove(&book.id).unwrap_or_default();
            let file_count = files.len() as i64;
            BookListItem {
                book,
                authors,
                genres,
                files,
                file_count,
            }
        })
        .collect())
}

pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(input): Json<BookInput>,
) -> AppResult<Json<BookDto>> {
    if input.title.trim().is_empty() {
        return Err(AppError::BadRequest("title is required".into()));
    }
    validate_cover_path(input.cover_path.as_deref())?;
    let id = uuid::Uuid::new_v4().to_string();
    sqlx::query(
        "INSERT INTO book (id, title, subtitle, description, isbn, publisher, \
            published_year, page_count, cover_path, spine_style, owner_id) \
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(input.title.trim())
    .bind(&input.subtitle)
    .bind(&input.description)
    .bind(&input.isbn)
    .bind(&input.publisher)
    .bind(input.published_year)
    .bind(input.page_count)
    .bind(&input.cover_path)
    .bind(&input.spine_style)
    .bind(&user.id)
    .execute(&state.db)
    .await?;
    fetch_book(&state, &id).await
}

/// Upsert a book at a caller-chosen id — the app pushes local books this way so
/// ids stay consistent across push and pull. Creates it (owned by the caller)
/// if absent, otherwise updates it (requires editor access). `cover_path` and
/// `spine_style` are preserved when omitted, since covers sync separately.
pub async fn upsert(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(input): Json<BookInput>,
) -> AppResult<Json<BookDto>> {
    if input.title.trim().is_empty() {
        return Err(AppError::BadRequest("title is required".into()));
    }
    validate_cover_path(input.cover_path.as_deref())?;
    let existing: Option<(Option<String>, String)> =
        sqlx::query_as("SELECT owner_id, updated_at FROM book WHERE id = ?")
            .bind(&id)
            .fetch_optional(&state.db)
            .await?;

    let is_update = match &existing {
        Some((_owner, stored_updated_at)) => {
            if !book_access(&state, &user, &id).await?.can_edit() {
                return Err(AppError::Forbidden(
                    "you have read-only access to this book".into(),
                ));
            }
            // Last-write-wins guard: when the client sends its sync clock, only
            // overwrite if it is strictly newer than what we hold. A stale push
            // (e.g. after a console edit) then leaves the remote edit intact.
            // Both timestamps are fixed-width UTC, so a byte compare suffices.
            if let Some(incoming) = input.updated_at.as_deref()
                && incoming <= stored_updated_at.as_str()
            {
                return fetch_book(&state, &id).await;
            }
            true
        }
        None => false,
    };

    // No-op guard: if an update wouldn't change the stored row or its joins,
    // skip the write so `updated_at` (and thus every client's pull cursor) isn't
    // churned by a redundant push — notably the first post-upgrade sweep, which
    // re-pushes every book once. New books (INSERT path) always write.
    if is_update {
        let current = fetch_book(&state, &id).await?.0;
        let meta_same = current.title == input.title.trim()
            && current.subtitle == input.subtitle
            && current.description == input.description
            && current.isbn == input.isbn
            && current.publisher == input.publisher
            && current.published_year == input.published_year
            && current.page_count == input.page_count
            // cover_path / spine_style only overwrite when provided (COALESCE).
            && input
                .cover_path
                .as_ref()
                .is_none_or(|c| current.cover_path.as_ref() == Some(c))
            && input
                .spine_style
                .as_ref()
                .is_none_or(|s| current.spine_style.as_ref() == Some(s));
        let authors_same = match &input.authors {
            None => true,
            Some(a) => book_author_names(&state, &id).await? == normalize_names(a),
        };
        let genres_same = match &input.genres {
            None => true,
            Some(g) => {
                let mut want = normalize_names(g);
                want.sort();
                want.dedup();
                book_genre_names(&state, &id).await? == want
            }
        };
        // A live tombstone for this id (a crashed delete) must still be cleared,
        // so it isn't a no-op even when the data matches — fall through to write.
        let tombstoned: bool =
            sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM deletion WHERE book_id = ?)")
                .bind(&id)
                .fetch_one(&state.db)
                .await?;
        if meta_same && authors_same && genres_same && !tombstoned {
            return Ok(Json(current));
        }
    }

    // Metadata write and author/genre join replacement share one transaction so
    // a book never lands with half its relations, or with the tombstone of a
    // revived id still live.
    let mut tx = state.db.begin().await?;
    if is_update {
        sqlx::query(
            "UPDATE book SET title = ?, subtitle = ?, description = ?, isbn = ?, \
                publisher = ?, published_year = ?, page_count = ?, \
                cover_path = COALESCE(?, cover_path), \
                spine_style = COALESCE(?, spine_style), \
                updated_at = datetime('now') \
             WHERE id = ?",
        )
        .bind(input.title.trim())
        .bind(&input.subtitle)
        .bind(&input.description)
        .bind(&input.isbn)
        .bind(&input.publisher)
        .bind(input.published_year)
        .bind(input.page_count)
        .bind(&input.cover_path)
        .bind(&input.spine_style)
        .bind(&id)
        .execute(&mut *tx)
        .await?;
    } else {
        sqlx::query(
            "INSERT INTO book (id, title, subtitle, description, isbn, publisher, \
                published_year, page_count, cover_path, spine_style, owner_id) \
             VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
        )
        .bind(&id)
        .bind(input.title.trim())
        .bind(&input.subtitle)
        .bind(&input.description)
        .bind(&input.isbn)
        .bind(&input.publisher)
        .bind(input.published_year)
        .bind(input.page_count)
        .bind(&input.cover_path)
        .bind(&input.spine_style)
        .bind(&user.id)
        .execute(&mut *tx)
        .await?;
    }
    // Re-creating a book at a tombstoned id revives it — drop the tombstone so
    // it isn't deleted again on the next pull. Cleared on both branches so a
    // revived-then-updated id can't leave a stale tombstone behind.
    sqlx::query("DELETE FROM deletion WHERE book_id = ?")
        .bind(&id)
        .execute(&mut *tx)
        .await?;

    // Authors / genres: replace the joins when the push carried them, else leave
    // whatever is there (an old client, or a metadata-only edit).
    if let Some(authors) = &input.authors {
        sqlx::query("DELETE FROM book_author WHERE book_id = ?")
            .bind(&id)
            .execute(&mut *tx)
            .await?;
        let mut position: i64 = 0;
        for name in authors {
            let name = name.trim();
            if name.is_empty() {
                continue;
            }
            let author_id = id_for_name_tx(&mut tx, "author", name).await?;
            sqlx::query(
                "INSERT OR IGNORE INTO book_author (book_id, author_id, position) \
                 VALUES (?, ?, ?)",
            )
            .bind(&id)
            .bind(&author_id)
            .bind(position)
            .execute(&mut *tx)
            .await?;
            position += 1;
        }
        // Drop author names no book references any more (re-tagging can orphan
        // the old one), so the unique-name table doesn't grow forever.
        sqlx::query("DELETE FROM author WHERE id NOT IN (SELECT author_id FROM book_author)")
            .execute(&mut *tx)
            .await?;
    }
    if let Some(genres) = &input.genres {
        sqlx::query("DELETE FROM book_genre WHERE book_id = ?")
            .bind(&id)
            .execute(&mut *tx)
            .await?;
        for name in genres {
            let name = name.trim();
            if name.is_empty() {
                continue;
            }
            let genre_id = id_for_name_tx(&mut tx, "genre", name).await?;
            sqlx::query("INSERT OR IGNORE INTO book_genre (book_id, genre_id) VALUES (?, ?)")
                .bind(&id)
                .bind(&genre_id)
                .execute(&mut *tx)
                .await?;
        }
        sqlx::query("DELETE FROM genre WHERE id NOT IN (SELECT genre_id FROM book_genre)")
            .execute(&mut *tx)
            .await?;
    }
    tx.commit().await?;
    fetch_book(&state, &id).await
}

/// Trim each name and drop the blanks — the same normalization the join
/// replacement applies, so the no-op guard compares like with like.
fn normalize_names(names: &[String]) -> Vec<String> {
    names
        .iter()
        .map(|s| s.trim().to_string())
        .filter(|s| !s.is_empty())
        .collect()
}

/// A book's author names in cover order.
async fn book_author_names(state: &AppState, id: &str) -> AppResult<Vec<String>> {
    Ok(sqlx::query_scalar(
        "SELECT a.name FROM author a JOIN book_author ba ON ba.author_id = a.id \
         WHERE ba.book_id = ? ORDER BY ba.position",
    )
    .bind(id)
    .fetch_all(&state.db)
    .await?)
}

/// A book's genre names, sorted by name (the order the joins are compared in).
async fn book_genre_names(state: &AppState, id: &str) -> AppResult<Vec<String>> {
    Ok(sqlx::query_scalar(
        "SELECT g.name FROM genre g JOIN book_genre bg ON bg.genre_id = g.id \
         WHERE bg.book_id = ? ORDER BY g.name",
    )
    .bind(id)
    .fetch_all(&state.db)
    .await?)
}

/// Get-or-create a name-keyed row (author / genre) inside a transaction and
/// return its id. `table` is always a fixed literal, never user input.
async fn id_for_name_tx(
    conn: &mut sqlx::SqliteConnection,
    table: &str,
    name: &str,
) -> AppResult<String> {
    let existing: Option<String> =
        sqlx::query_scalar(&format!("SELECT id FROM {table} WHERE name = ?"))
            .bind(name)
            .fetch_optional(&mut *conn)
            .await?;
    if let Some(id) = existing {
        return Ok(id);
    }
    let id = uuid::Uuid::new_v4().to_string();
    sqlx::query(&format!(
        "INSERT INTO {table} (id, name) VALUES (?, ?) ON CONFLICT(name) DO NOTHING"
    ))
    .bind(&id)
    .bind(name)
    .execute(&mut *conn)
    .await?;
    // A concurrent insert may have won the race; re-read to get the real id.
    let id: String = sqlx::query_scalar(&format!("SELECT id FROM {table} WHERE name = ?"))
        .bind(name)
        .fetch_one(&mut *conn)
        .await?;
    Ok(id)
}

/// Full detail for the console's book view: metadata + authors + genres + files.
#[derive(Serialize)]
pub struct BookDetail {
    #[serde(flatten)]
    pub book: BookDto,
    pub authors: Vec<String>,
    pub genres: Vec<String>,
    pub files: Vec<crate::blobs::FileDto>,
}

pub async fn detail(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<BookDetail>> {
    if !book_access(&state, &user, &id).await?.can_view() {
        return Err(AppError::NotFound("book not found".into()));
    }
    let book = fetch_book(&state, &id).await?.0;
    let authors: Vec<String> = sqlx::query_scalar(
        "SELECT a.name FROM author a JOIN book_author ba ON ba.author_id = a.id \
         WHERE ba.book_id = ? ORDER BY ba.position",
    )
    .bind(&id)
    .fetch_all(&state.db)
    .await?;
    let genres: Vec<String> = sqlx::query_scalar(
        "SELECT g.name FROM genre g JOIN book_genre bg ON bg.genre_id = g.id \
         WHERE bg.book_id = ? ORDER BY g.name",
    )
    .bind(&id)
    .fetch_all(&state.db)
    .await?;
    let files = sqlx::query_as::<_, crate::blobs::FileDto>(
        "SELECT id, book_id, format, path, size_bytes, sha256, added_at \
         FROM book_file WHERE book_id = ? ORDER BY added_at",
    )
    .bind(&id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(BookDetail {
        book,
        authors,
        genres,
        files,
    }))
}

pub async fn get(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<BookDto>> {
    if !book_access(&state, &user, &id).await?.can_view() {
        return Err(AppError::NotFound("book not found".into()));
    }
    fetch_book(&state, &id).await
}

/// Partial update — requires editor (or owner/master) access. Omitted fields
/// are left unchanged; fields cannot be nulled out through this endpoint.
pub async fn update(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
    Json(input): Json<BookUpdate>,
) -> AppResult<Json<BookDto>> {
    let access = book_access(&state, &user, &id).await?;
    if !access.can_view() {
        return Err(AppError::NotFound("book not found".into()));
    }
    if !access.can_edit() {
        return Err(AppError::Forbidden(
            "you have read-only access to this book".into(),
        ));
    }
    validate_cover_path(input.cover_path.as_deref())?;
    sqlx::query(
        "UPDATE book SET \
            title = COALESCE(?, title), \
            subtitle = COALESCE(?, subtitle), \
            description = COALESCE(?, description), \
            isbn = COALESCE(?, isbn), \
            publisher = COALESCE(?, publisher), \
            published_year = COALESCE(?, published_year), \
            page_count = COALESCE(?, page_count), \
            cover_path = COALESCE(?, cover_path), \
            spine_style = COALESCE(?, spine_style), \
            updated_at = datetime('now') \
         WHERE id = ?",
    )
    .bind(input.title.and_then(nullable))
    .bind(&input.subtitle)
    .bind(&input.description)
    .bind(&input.isbn)
    .bind(&input.publisher)
    .bind(input.published_year)
    .bind(input.page_count)
    .bind(&input.cover_path)
    .bind(&input.spine_style)
    .bind(&id)
    .execute(&state.db)
    .await?;
    fetch_book(&state, &id).await
}

/// Delete — restricted to the book's owner or the master.
pub async fn delete(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    let owner: Option<Option<String>> =
        sqlx::query_scalar("SELECT owner_id FROM book WHERE id = ?")
            .bind(&id)
            .fetch_optional(&state.db)
            .await?;
    let Some(owner_id) = owner else {
        return Err(AppError::NotFound("book not found".into()));
    };
    if !user.is_master && owner_id.as_deref() != Some(user.id.as_str()) {
        return Err(AppError::Forbidden(
            "only the owner may delete this book".into(),
        ));
    }

    // Path collection, tombstone, and row delete run in one transaction so a
    // crash can't leave a live book *and* its tombstone — a state that makes
    // clients delete-then-re-download the book (and its blobs) on the next pull.
    let mut tx = state.db.begin().await?;

    // Collect blob paths before the row (and its cascaded book_file rows) vanish,
    // so we can remove them from disk afterwards and not leak storage.
    let cover: Option<Option<String>> =
        sqlx::query_scalar("SELECT cover_path FROM book WHERE id = ?")
            .bind(&id)
            .fetch_optional(&mut *tx)
            .await?;
    let files: Vec<String> = sqlx::query_scalar("SELECT path FROM book_file WHERE book_id = ?")
        .bind(&id)
        .fetch_all(&mut *tx)
        .await?;

    // Record a tombstone so a client that pulls after this delete removes the
    // book locally instead of treating its absence as "nothing to do".
    sqlx::query("INSERT OR REPLACE INTO deletion (book_id, owner_id) VALUES (?, ?)")
        .bind(&id)
        .bind(&owner_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM book WHERE id = ?")
        .bind(&id)
        .execute(&mut *tx)
        .await?;
    // The cascade removed this book's join rows; sweep any author/genre name
    // left with no book referencing it so the tables don't grow forever.
    sqlx::query("DELETE FROM author WHERE id NOT IN (SELECT author_id FROM book_author)")
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM genre WHERE id NOT IN (SELECT genre_id FROM book_genre)")
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    // Blob removal is best-effort and stays after the commit: a failed unlink
    // only leaks a file, it must not roll back the (committed) delete.
    for rel in files.into_iter().chain(cover.flatten()) {
        let _ = tokio::fs::remove_file(state.data_dir.join(rel)).await;
    }
    Ok(Json(serde_json::json!({ "deleted": id })))
}

#[derive(Serialize, sqlx::FromRow)]
pub struct DeletionDto {
    pub book_id: String,
    pub deleted_at: String,
    /// 'book', 'shelf', ... (plan 5 #4). Purely additive: an old client reads
    /// only `book_id`/`deleted_at` and looks the id up in its own `books`
    /// table, so a non-book tombstone is a harmless no-op there.
    pub kind: String,
}

#[derive(Deserialize)]
pub struct DeletionsQuery {
    /// Delta-pull marker: only tombstones at or after this timestamp. `>=` for
    /// the same second-resolution reason as [`visible_books`]; re-applying a
    /// delete is idempotent, so the overlap is harmless.
    pub since: Option<String>,
    /// Restrict to one kind ('book', 'shelf', ...). Absent returns every kind
    /// — what an old client that's never heard of `kind` still gets.
    pub kind: Option<String>,
}

/// Every delete tombstone, so a client can propagate deletes on its next pull.
/// Returns all tombstones to any authenticated caller — this leaks only the
/// UUIDs of deleted rows, which is acceptable on a personal server.
pub async fn deletions(
    State(state): State<AppState>,
    _user: AuthUser,
    axum::extract::Query(q): axum::extract::Query<DeletionsQuery>,
) -> AppResult<Json<Vec<DeletionDto>>> {
    let since = q.since.as_deref().map(str::trim).filter(|s| !s.is_empty());
    let kind = q.kind.as_deref().map(str::trim).filter(|k| !k.is_empty());
    let mut conditions = Vec::new();
    if since.is_some() {
        conditions.push("deleted_at >= ?");
    }
    if kind.is_some() {
        conditions.push("kind = ?");
    }
    let filter = if conditions.is_empty() {
        String::new()
    } else {
        format!("WHERE {}", conditions.join(" AND "))
    };
    let sql =
        format!("SELECT book_id, deleted_at, kind FROM deletion {filter} ORDER BY deleted_at");
    let mut query = sqlx::query_as::<_, DeletionDto>(&sql);
    if let Some(ts) = since {
        query = query.bind(ts.to_string());
    }
    if let Some(k) = kind {
        query = query.bind(k.to_string());
    }
    Ok(Json(query.fetch_all(&state.db).await?))
}

pub(crate) async fn fetch_book(state: &AppState, id: &str) -> AppResult<Json<BookDto>> {
    let book =
        sqlx::query_as::<_, BookDto>(&format!("SELECT {BOOK_COLUMNS} FROM book WHERE id = ?"))
            .bind(id)
            .fetch_optional(&state.db)
            .await?
            .ok_or_else(|| AppError::NotFound("book not found".into()))?;
    Ok(Json(book))
}

/// Treat an empty/blank string as "leave unchanged" for COALESCE updates.
fn nullable(value: String) -> Option<String> {
    let trimmed = value.trim();
    if trimmed.is_empty() {
        None
    } else {
        Some(trimmed.to_string())
    }
}

/// Reject a client-supplied `cover_path` that could escape the blob store.
///
/// Covers are set server-side (upload, or the PDF/EPUB first-page render); a
/// legitimate client only ever sends `None`. When a value *is* present we accept
/// only the server's own shape — a single `covers/<name>` segment with no path
/// separators or `..` — so a crafted `../../vellum.db` can't be stored and then
/// streamed straight back by [`crate::blobs::get_cover`] as an arbitrary-file
/// read. See docs/SECURITY_AUDIT.md (H1).
fn validate_cover_path(cover_path: Option<&str>) -> AppResult<()> {
    let Some(p) = cover_path else {
        return Ok(());
    };
    let safe = p.strip_prefix("covers/").is_some_and(|name| {
        !name.is_empty()
            && !name.contains('/')
            && !name.contains('\\')
            && !name.contains("..")
            && !name.contains('\0')
    });
    if safe {
        Ok(())
    } else {
        Err(AppError::BadRequest("invalid cover_path".into()))
    }
}

#[cfg(test)]
mod tests {
    use super::validate_cover_path;

    #[test]
    fn cover_path_validation_blocks_traversal() {
        // Omitted or server-shaped values are fine.
        assert!(validate_cover_path(None).is_ok());
        assert!(validate_cover_path(Some("covers/9e1c-uuid.jpg")).is_ok());
        // Anything that could escape the covers/ dir is rejected.
        assert!(validate_cover_path(Some("../vellum.db")).is_err());
        assert!(validate_cover_path(Some("covers/../../etc/passwd")).is_err());
        assert!(validate_cover_path(Some("/etc/passwd")).is_err());
        assert!(validate_cover_path(Some("files/x.pdf")).is_err());
        assert!(validate_cover_path(Some("covers/")).is_err());
    }
}
