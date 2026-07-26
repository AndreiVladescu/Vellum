//! Permission resolution. Given a caller and a resource, decide whether they may
//! view or modify it, taking ownership, master status, and shares into account.
//!
//! **Compile-checked queries** (plan 5 #46): this module is the pilot for
//! `sqlx::query_*!`, verified against the schema at build time from the committed
//! `.sqlx/` data — a mistyped column here is a compile error rather than a
//! runtime 500 in the security-critical path. Regenerate with
//! `cargo sqlx prepare` after touching a query (CI checks it is current). Modules
//! whose SQL is composed with `format!` — the visibility predicate in `books.rs`,
//! the dynamic-table helpers — cannot use the macros, which is why the migration
//! is incremental rather than wholesale.

use crate::AppState;
use crate::auth::AuthUser;
use crate::error::AppResult;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum Access {
    None,
    Viewer,
    Editor,
}

impl Access {
    pub fn can_view(self) -> bool {
        self != Access::None
    }
    pub fn can_edit(self) -> bool {
        self == Access::Editor
    }
}

/// The caller's access to a single book. `None` also covers a missing book, so
/// callers can treat "no access" and "not found" identically (avoids leaking
/// which book ids exist).
pub async fn book_access(state: &AppState, user: &AuthUser, book_id: &str) -> AppResult<Access> {
    let owner: Option<Option<String>> =
        sqlx::query_scalar!("SELECT owner_id FROM book WHERE id = ?", book_id)
            .fetch_optional(&state.db)
            .await?;
    let Some(owner_id) = owner else {
        return Ok(Access::None); // no such book
    };

    if user.is_master || owner_id.as_deref() == Some(user.id.as_str()) {
        return Ok(Access::Editor);
    }

    // Best permission granted by any share covering this book.
    let permission: Option<String> = sqlx::query_scalar!(
        "SELECT s.permission FROM share s \
         WHERE s.grantee_id = ? AND ( \
            (s.scope = 'all'   AND s.owner_id = ?) OR \
            (s.scope = 'book'  AND s.scope_id = ?) OR \
            (s.scope = 'group' AND EXISTS ( \
                SELECT 1 FROM book_group_item gi \
                WHERE gi.group_id = s.scope_id AND gi.book_id = ?)) ) \
         ORDER BY (s.permission = 'editor') DESC LIMIT 1",
        user.id,
        owner_id,
        book_id,
        book_id,
    )
    .fetch_optional(&state.db)
    .await?;

    Ok(match permission.as_deref() {
        Some("editor") => Access::Editor,
        Some(_) => Access::Viewer,
        None => Access::None,
    })
}

/// The caller's access to a group. Owner/master may manage it (`Editor`); a
/// group- or all-scoped share grants `Viewer`.
pub async fn group_access(state: &AppState, user: &AuthUser, group_id: &str) -> AppResult<Access> {
    let owner: Option<String> =
        sqlx::query_scalar!("SELECT owner_id FROM book_group WHERE id = ?", group_id)
            .fetch_optional(&state.db)
            .await?;
    let Some(owner_id) = owner else {
        return Ok(Access::None);
    };

    if user.is_master || owner_id == user.id {
        return Ok(Access::Editor);
    }

    let shared = sqlx::query_scalar!(
        "SELECT EXISTS(SELECT 1 FROM share s WHERE s.grantee_id = ? AND ( \
            (s.scope = 'group' AND s.scope_id = ?) OR \
            (s.scope = 'all'   AND s.owner_id = ?) ))",
        user.id,
        group_id,
        owner_id,
    )
    .fetch_one(&state.db)
    .await?;

    // SQLite's EXISTS is an integer; the macro types it as such rather than
    // guessing a bool the way the runtime API let us.
    Ok(if shared != 0 {
        Access::Viewer
    } else {
        Access::None
    })
}

/// The caller's access to a physical copy. Unlike shelf/group, a copy has no
/// owner of its own — it belongs to exactly one book — so this is just
/// `book_access` on that book, keeping share semantics (viewer vs. editor,
/// book/group/all scope) identical for a book and its copies.
pub async fn copy_access(state: &AppState, user: &AuthUser, copy_id: &str) -> AppResult<Access> {
    let book_id: Option<String> =
        sqlx::query_scalar!("SELECT book_id FROM physical_copy WHERE id = ?", copy_id)
            .fetch_optional(&state.db)
            .await?;
    match book_id {
        Some(book_id) => book_access(state, user, &book_id).await,
        None => Ok(Access::None),
    }
}

/// The caller's access to a loan. Same reasoning as `copy_access`: a loan has
/// no owner of its own — it belongs to a copy, which belongs to a book — so
/// this joins through both to reach `book_access`.
pub async fn loan_access(state: &AppState, user: &AuthUser, loan_id: &str) -> AppResult<Access> {
    let book_id: Option<String> = sqlx::query_scalar!(
        "SELECT pc.book_id FROM loan l \
         JOIN physical_copy pc ON pc.id = l.copy_id \
         WHERE l.id = ?",
        loan_id,
    )
    .fetch_optional(&state.db)
    .await?;
    match book_id {
        Some(book_id) => book_access(state, user, &book_id).await,
        None => Ok(Access::None),
    }
}

/// The caller's access to a shelf. Owner/master may manage it (`Editor`); an
/// all-scoped share (the whole library) grants `Viewer` — unlike books and
/// groups, there is no shelf-scoped share type, so this reduces to just
/// ownership vs. an all-scope grant.
pub async fn shelf_access(state: &AppState, user: &AuthUser, shelf_id: &str) -> AppResult<Access> {
    let owner: Option<String> = sqlx::query_scalar("SELECT owner_id FROM shelf WHERE id = ?")
        .bind(shelf_id)
        .fetch_optional(&state.db)
        .await?;
    let Some(owner_id) = owner else {
        return Ok(Access::None);
    };

    if user.is_master || owner_id == user.id {
        return Ok(Access::Editor);
    }

    let shared: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM share s \
            WHERE s.grantee_id = ? AND s.scope = 'all' AND s.owner_id = ?)",
    )
    .bind(&user.id)
    .bind(&owner_id)
    .fetch_one(&state.db)
    .await?;

    Ok(if shared { Access::Viewer } else { Access::None })
}
