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
pub async fn visible_books(state: &AppState, user: &AuthUser) -> AppResult<Vec<BookDto>> {
    let books = sqlx::query_as::<_, BookDto>(&format!(
        "SELECT {BOOK_COLUMNS} FROM book b \
         WHERE b.owner_id = ? \
            OR ? = 1 \
            OR EXISTS ( \
                SELECT 1 FROM share s WHERE s.grantee_id = ? AND ( \
                    (s.scope = 'all'   AND s.owner_id = b.owner_id) OR \
                    (s.scope = 'book'  AND s.scope_id = b.id) OR \
                    (s.scope = 'group' AND EXISTS ( \
                        SELECT 1 FROM book_group_item gi \
                        WHERE gi.group_id = s.scope_id AND gi.book_id = b.id)) )) \
         ORDER BY b.title"
    ))
    .bind(&user.id)
    .bind(user.is_master)
    .bind(&user.id)
    .fetch_all(&state.db)
    .await?;
    Ok(books)
}

/// A book plus the two aggregates the console's table needs to render its
/// Author and file columns without a per-row `/detail` round-trip.
#[derive(Serialize)]
pub struct BookListItem {
    #[serde(flatten)]
    pub book: BookDto,
    pub authors: Vec<String>,
    pub file_count: i64,
}

pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Vec<BookListItem>>> {
    let books = visible_books(&state, &user).await?;

    // Two grouped scans, folded into lookup maps, so the response is assembled
    // in Rust rather than with a per-book query. Fine for a personal library.
    #[derive(sqlx::FromRow)]
    struct AuthorRow {
        book_id: String,
        name: String,
    }
    let author_rows = sqlx::query_as::<_, AuthorRow>(
        "SELECT ba.book_id, a.name FROM author a \
         JOIN book_author ba ON ba.author_id = a.id ORDER BY ba.book_id, ba.position",
    )
    .fetch_all(&state.db)
    .await?;
    let mut authors_by_book: std::collections::HashMap<String, Vec<String>> =
        std::collections::HashMap::new();
    for row in author_rows {
        authors_by_book
            .entry(row.book_id)
            .or_default()
            .push(row.name);
    }

    #[derive(sqlx::FromRow)]
    struct CountRow {
        book_id: String,
        n: i64,
    }
    let count_rows = sqlx::query_as::<_, CountRow>(
        "SELECT book_id, COUNT(*) AS n FROM book_file GROUP BY book_id",
    )
    .fetch_all(&state.db)
    .await?;
    let counts_by_book: std::collections::HashMap<String, i64> =
        count_rows.into_iter().map(|r| (r.book_id, r.n)).collect();

    let items = books
        .into_iter()
        .map(|book| {
            let authors = authors_by_book.get(&book.id).cloned().unwrap_or_default();
            let file_count = counts_by_book.get(&book.id).copied().unwrap_or(0);
            BookListItem {
                book,
                authors,
                file_count,
            }
        })
        .collect();
    Ok(Json(items))
}

pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(input): Json<BookInput>,
) -> AppResult<Json<BookDto>> {
    if input.title.trim().is_empty() {
        return Err(AppError::BadRequest("title is required".into()));
    }
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
    let owner: Option<Option<String>> =
        sqlx::query_scalar("SELECT owner_id FROM book WHERE id = ?")
            .bind(&id)
            .fetch_optional(&state.db)
            .await?;

    match owner {
        Some(_) => {
            if !book_access(&state, &user, &id).await?.can_edit() {
                return Err(AppError::Forbidden(
                    "you have read-only access to this book".into(),
                ));
            }
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
            .execute(&state.db)
            .await?;
        }
        None => {
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
            // Re-creating a book at a tombstoned id revives it — drop the
            // tombstone so it isn't deleted again on the next pull.
            sqlx::query("DELETE FROM deletion WHERE book_id = ?")
                .bind(&id)
                .execute(&state.db)
                .await?;
        }
    }
    fetch_book(&state, &id).await
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

    // Collect blob paths before the row (and its cascaded book_file rows) vanish,
    // so we can remove them from disk afterwards and not leak storage.
    let cover: Option<Option<String>> =
        sqlx::query_scalar("SELECT cover_path FROM book WHERE id = ?")
            .bind(&id)
            .fetch_optional(&state.db)
            .await?;
    let files: Vec<String> = sqlx::query_scalar("SELECT path FROM book_file WHERE book_id = ?")
        .bind(&id)
        .fetch_all(&state.db)
        .await?;

    // Record a tombstone so a client that pulls after this delete removes the
    // book locally instead of treating its absence as "nothing to do".
    sqlx::query("INSERT OR REPLACE INTO deletion (book_id, owner_id) VALUES (?, ?)")
        .bind(&id)
        .bind(&owner_id)
        .execute(&state.db)
        .await?;
    sqlx::query("DELETE FROM book WHERE id = ?")
        .bind(&id)
        .execute(&state.db)
        .await?;

    for rel in files.into_iter().chain(cover.flatten()) {
        let _ = tokio::fs::remove_file(state.data_dir.join(rel)).await;
    }
    Ok(Json(serde_json::json!({ "deleted": id })))
}

#[derive(Serialize, sqlx::FromRow)]
pub struct DeletionDto {
    pub book_id: String,
    pub deleted_at: String,
}

/// Every delete tombstone, so a client can propagate deletes on its next pull.
/// Returns all tombstones to any authenticated caller — this leaks only the
/// UUIDs of deleted books, which is acceptable on a personal server.
pub async fn deletions(
    State(state): State<AppState>,
    _user: AuthUser,
) -> AppResult<Json<Vec<DeletionDto>>> {
    let rows = sqlx::query_as::<_, DeletionDto>(
        "SELECT book_id, deleted_at FROM deletion ORDER BY deleted_at",
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
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
