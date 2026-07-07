//! The self-hosted web console and the public link landing page, plus the
//! book↔group membership endpoint the console needs to render tags. The HTML is
//! embedded in the binary (no external assets, no CDN) and served same-origin,
//! so `fetch` to `/api/*` just works.

use axum::extract::State;
use axum::response::Html;
use axum::Json;
use serde::Serialize;

use crate::auth::AuthUser;
use crate::error::AppResult;
use crate::AppState;

pub async fn console() -> Html<&'static str> {
    Html(include_str!("../web/console.html"))
}

pub async fn public_page() -> Html<&'static str> {
    Html(include_str!("../web/public.html"))
}

#[derive(Serialize, sqlx::FromRow)]
pub struct Membership {
    pub group_id: String,
    pub book_id: String,
}

/// Every group↔book membership among the books the caller can see. The console
/// joins these against the group and book lists to show each book's tags.
pub async fn memberships(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Vec<Membership>>> {
    let rows = sqlx::query_as::<_, Membership>(
        "SELECT gi.group_id, gi.book_id FROM book_group_item gi \
         WHERE EXISTS ( \
            SELECT 1 FROM book b WHERE b.id = gi.book_id AND ( \
                b.owner_id = ? OR ? = 1 OR EXISTS ( \
                    SELECT 1 FROM share s WHERE s.grantee_id = ? AND ( \
                        (s.scope = 'all'   AND s.owner_id = b.owner_id) OR \
                        (s.scope = 'book'  AND s.scope_id = b.id) OR \
                        (s.scope = 'group' AND s.scope_id = gi.group_id)))))",
    )
    .bind(&user.id)
    .bind(user.is_master)
    .bind(&user.id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}
