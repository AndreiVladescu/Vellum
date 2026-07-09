//! Book discovery: search the online metadata sources and add a chosen result
//! as a real book (the console's search flow; the app has its own client).

use axum::extract::{Path, Query, State};
use axum::Json;
use serde::Deserialize;

use crate::access::book_access;
use crate::auth::AuthUser;
use crate::books::{fetch_book, BookDto};
use crate::error::{AppError, AppResult};
use crate::metadata::{self, BookSearchResult};
use crate::AppState;

#[derive(Deserialize)]
pub struct SearchQuery {
    pub q: String,
}

/// Search Open Library / Google Books. Requires a logged-in user.
pub async fn search(
    State(state): State<AppState>,
    _user: AuthUser,
    Query(query): Query<SearchQuery>,
) -> AppResult<Json<Vec<BookSearchResult>>> {
    let q = query.q.trim();
    if q.is_empty() {
        return Ok(Json(Vec::new()));
    }
    Ok(Json(metadata::search(&state.http, q).await?))
}

/// Create a book from a chosen search result: fetch its description and cover,
/// then store it (owned by the caller) with its authors and a few genres.
pub async fn add_from_search(
    State(state): State<AppState>,
    user: AuthUser,
    Json(result): Json<BookSearchResult>,
) -> AppResult<Json<BookDto>> {
    if result.title.trim().is_empty() {
        return Err(AppError::BadRequest("title is required".into()));
    }
    let id = uuid::Uuid::new_v4().to_string();

    let description = match &result.description {
        Some(d) => Some(d.clone()),
        None => metadata::fetch_description(&state.http, &result.work_key)
            .await
            .unwrap_or(None),
    };

    let mut cover_path: Option<String> = None;
    if let Some(bytes) = metadata::download_cover(&state.http, &result).await {
        let rel = format!("covers/{id}.jpg");
        let full = state.data_dir.join(&rel);
        if let Some(parent) = full.parent() {
            let _ = tokio::fs::create_dir_all(parent).await;
        }
        if tokio::fs::write(&full, &bytes).await.is_ok() {
            cover_path = Some(rel);
        }
    }

    sqlx::query(
        "INSERT INTO book (id, title, subtitle, description, isbn, publisher, \
            published_year, page_count, cover_path, owner_id) \
         VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(result.title.trim())
    .bind(&result.subtitle)
    .bind(&description)
    .bind(&result.isbn)
    .bind(&result.publisher)
    .bind(result.first_publish_year)
    .bind(result.page_count)
    .bind(&cover_path)
    .bind(&user.id)
    .execute(&state.db)
    .await?;

    for (position, name) in result.authors.iter().enumerate() {
        let author_id = id_for_name(&state, "author", name).await?;
        sqlx::query(
            "INSERT OR IGNORE INTO book_author (book_id, author_id, position) VALUES (?, ?, ?)",
        )
        .bind(&id)
        .bind(&author_id)
        .bind(position as i64)
        .execute(&state.db)
        .await?;
    }

    // Open Library subjects are noisy; keep a few short, clean ones as genres.
    for name in result
        .subjects
        .iter()
        .filter(|s| s.len() <= 28 && !s.contains(':'))
        .take(3)
    {
        let genre_id = id_for_name(&state, "genre", name).await?;
        sqlx::query("INSERT OR IGNORE INTO book_genre (book_id, genre_id) VALUES (?, ?)")
            .bind(&id)
            .bind(&genre_id)
            .execute(&state.db)
            .await?;
    }

    Ok(Json(fetch_book(&state, &id).await?.0))
}

/// Fill a book's *empty* fields from an online metadata lookup, keyed on its
/// title (plus its first author, if it already has one, to disambiguate). Never
/// overwrites values the user set — every column uses COALESCE and authors /
/// genres are only added when the book has none. Used when a book is created by
/// title alone or gets a file uploaded, so the shelf fills itself in. A missing
/// match or a source error leaves the book untouched (returns it unchanged).
pub async fn enrich(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
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

    let book = fetch_book(&state, &id).await?.0;
    let author_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM book_author WHERE book_id = ?")
        .bind(&id)
        .fetch_one(&state.db)
        .await?;
    let genre_count: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM book_genre WHERE book_id = ?")
        .bind(&id)
        .fetch_one(&state.db)
        .await?;

    let need_author = author_count == 0;
    let need_genre = genre_count == 0;
    let need_desc = book.description.is_none();
    let need_cover = book.cover_path.is_none();
    // Nothing to fill — skip the network round-trip entirely.
    if !(need_author
        || need_genre
        || need_desc
        || need_cover
        || book.published_year.is_none()
        || book.publisher.is_none()
        || book.isbn.is_none()
        || book.page_count.is_none()
        || book.subtitle.is_none())
    {
        return Ok(Json(book));
    }

    let first_author: Option<String> = sqlx::query_scalar(
        "SELECT a.name FROM author a JOIN book_author ba ON ba.author_id = a.id \
         WHERE ba.book_id = ? ORDER BY ba.position LIMIT 1",
    )
    .bind(&id)
    .fetch_optional(&state.db)
    .await?;
    let mut query = book.title.clone();
    if let Some(author) = &first_author {
        query.push(' ');
        query.push_str(author);
    }

    let Some(top) = metadata::search(&state.http, &query)
        .await
        .unwrap_or_default()
        .into_iter()
        .next()
    else {
        return Ok(Json(book));
    };

    // Fetch the description separately (Open Library) only when we still need it.
    let description = if need_desc {
        match &top.description {
            Some(d) => Some(d.clone()),
            None => metadata::fetch_description(&state.http, &top.work_key)
                .await
                .unwrap_or(None),
        }
    } else {
        None
    };

    let mut cover_path: Option<String> = None;
    if need_cover
        && let Some(bytes) = metadata::download_cover(&state.http, &top).await
    {
        let rel = format!("covers/{id}.jpg");
        let full = state.data_dir.join(&rel);
        if let Some(parent) = full.parent() {
            let _ = tokio::fs::create_dir_all(parent).await;
        }
        if tokio::fs::write(&full, &bytes).await.is_ok() {
            cover_path = Some(rel);
        }
    }

    sqlx::query(
        "UPDATE book SET \
            subtitle = COALESCE(subtitle, ?), \
            description = COALESCE(description, ?), \
            isbn = COALESCE(isbn, ?), \
            publisher = COALESCE(publisher, ?), \
            published_year = COALESCE(published_year, ?), \
            page_count = COALESCE(page_count, ?), \
            cover_path = COALESCE(cover_path, ?), \
            updated_at = datetime('now') \
         WHERE id = ?",
    )
    .bind(&top.subtitle)
    .bind(&description)
    .bind(&top.isbn)
    .bind(&top.publisher)
    .bind(top.first_publish_year)
    .bind(top.page_count)
    .bind(&cover_path)
    .bind(&id)
    .execute(&state.db)
    .await?;

    if need_author {
        for (position, name) in top.authors.iter().enumerate() {
            let author_id = id_for_name(&state, "author", name).await?;
            sqlx::query(
                "INSERT OR IGNORE INTO book_author (book_id, author_id, position) VALUES (?, ?, ?)",
            )
            .bind(&id)
            .bind(&author_id)
            .bind(position as i64)
            .execute(&state.db)
            .await?;
        }
    }
    if need_genre {
        for name in top
            .subjects
            .iter()
            .filter(|s| s.len() <= 28 && !s.contains(':'))
            .take(3)
        {
            let genre_id = id_for_name(&state, "genre", name).await?;
            sqlx::query("INSERT OR IGNORE INTO book_genre (book_id, genre_id) VALUES (?, ?)")
                .bind(&id)
                .bind(&genre_id)
                .execute(&state.db)
                .await?;
        }
    }

    Ok(Json(fetch_book(&state, &id).await?.0))
}

/// Fill a book's empty fields from its uploaded file's *name*, following the
/// `Author(s) - Title-Publisher (Year)` download convention (see
/// [`metadata::parse_filename`]). Authors are added only when the book has none;
/// year/publisher fill only when empty; and the title is rewritten only while it
/// is still the raw file name (i.e. the user hasn't set one), which then lets the
/// online lookup search a clean title. Called from the file-upload handler.
pub async fn apply_filename_metadata(
    state: &AppState,
    book_id: &str,
    filename: &str,
) -> AppResult<()> {
    let stem = std::path::Path::new(filename)
        .file_stem()
        .and_then(|s| s.to_str())
        .unwrap_or(filename)
        .to_string();
    let parsed = metadata::parse_filename(&stem);

    let book = fetch_book(state, book_id).await?.0;
    // Only tidy the title if it's still verbatim the uploaded file name.
    let new_title = match &parsed.title {
        Some(t) if book.title == stem && *t != stem => Some(t.clone()),
        _ => None,
    };

    sqlx::query(
        "UPDATE book SET \
            title = COALESCE(?, title), \
            publisher = COALESCE(publisher, ?), \
            published_year = COALESCE(published_year, ?), \
            updated_at = datetime('now') \
         WHERE id = ?",
    )
    .bind(&new_title)
    .bind(&parsed.publisher)
    .bind(parsed.year)
    .bind(book_id)
    .execute(&state.db)
    .await?;

    if !parsed.authors.is_empty() {
        let author_count: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM book_author WHERE book_id = ?")
                .bind(book_id)
                .fetch_one(&state.db)
                .await?;
        if author_count == 0 {
            for (position, name) in parsed.authors.iter().enumerate() {
                let author_id = id_for_name(state, "author", name).await?;
                sqlx::query(
                    "INSERT OR IGNORE INTO book_author (book_id, author_id, position) \
                     VALUES (?, ?, ?)",
                )
                .bind(book_id)
                .bind(&author_id)
                .bind(position as i64)
                .execute(&state.db)
                .await?;
            }
        }
    }
    Ok(())
}

/// Get-or-create by name for the `author` / `genre` lookup tables. `table` is a
/// fixed literal from this module, never user input.
async fn id_for_name(state: &AppState, table: &str, name: &str) -> AppResult<String> {
    let name = name.trim();
    let existing: Option<String> =
        sqlx::query_scalar(&format!("SELECT id FROM {table} WHERE name = ?"))
            .bind(name)
            .fetch_optional(&state.db)
            .await?;
    if let Some(id) = existing {
        return Ok(id);
    }
    let id = uuid::Uuid::new_v4().to_string();
    sqlx::query(&format!("INSERT INTO {table} (id, name) VALUES (?, ?)"))
        .bind(&id)
        .bind(name)
        .execute(&state.db)
        .await?;
    Ok(id)
}
