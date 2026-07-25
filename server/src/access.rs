//! Permission resolution. Given a caller and a resource, decide whether they may
//! view or modify it, taking ownership, master status, and shares into account.

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
        sqlx::query_scalar("SELECT owner_id FROM book WHERE id = ?")
            .bind(book_id)
            .fetch_optional(&state.db)
            .await?;
    let Some(owner_id) = owner else {
        return Ok(Access::None); // no such book
    };

    if user.is_master || owner_id.as_deref() == Some(user.id.as_str()) {
        return Ok(Access::Editor);
    }

    // Best permission granted by any share covering this book.
    let permission: Option<String> = sqlx::query_scalar(
        "SELECT s.permission FROM share s \
         WHERE s.grantee_id = ? AND ( \
            (s.scope = 'all'   AND s.owner_id = ?) OR \
            (s.scope = 'book'  AND s.scope_id = ?) OR \
            (s.scope = 'group' AND EXISTS ( \
                SELECT 1 FROM book_group_item gi \
                WHERE gi.group_id = s.scope_id AND gi.book_id = ?)) ) \
         ORDER BY (s.permission = 'editor') DESC LIMIT 1",
    )
    .bind(&user.id)
    .bind(&owner_id)
    .bind(book_id)
    .bind(book_id)
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
    let owner: Option<String> = sqlx::query_scalar("SELECT owner_id FROM book_group WHERE id = ?")
        .bind(group_id)
        .fetch_optional(&state.db)
        .await?;
    let Some(owner_id) = owner else {
        return Ok(Access::None);
    };

    if user.is_master || owner_id == user.id {
        return Ok(Access::Editor);
    }

    let shared: bool = sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM share s WHERE s.grantee_id = ? AND ( \
            (s.scope = 'group' AND s.scope_id = ?) OR \
            (s.scope = 'all'   AND s.owner_id = ?) ))",
    )
    .bind(&user.id)
    .bind(group_id)
    .bind(&owner_id)
    .fetch_one(&state.db)
    .await?;

    Ok(if shared { Access::Viewer } else { Access::None })
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
