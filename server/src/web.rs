//! The self-hosted web console and the public link landing page, plus the
//! book↔group membership endpoint the console needs to render tags. The console
//! is split into html/css/js, all embedded in the binary (no external assets,
//! no CDN) and served same-origin from `/assets/*`, so `fetch` to `/api/*` and
//! the stylesheet/script loads just work.

use axum::Json;
use axum::extract::State;
use axum::http::header;
use axum::response::{Html, IntoResponse};
use serde::Serialize;

use crate::AppState;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};

pub async fn console() -> Html<&'static str> {
    Html(include_str!("../web/console.html"))
}

/// The console's stylesheet and script are compiled into the binary, so they
/// change with every upgrade — and always at the same two URLs, with no hash in
/// the name to distinguish one version from the next.
///
/// Without a cache header the browser applies its own heuristic and may keep
/// serving the previous copy indefinitely. The symptom is upgrading the server,
/// seeing nothing change, and reasonably concluding the fix did not ship — a CSS
/// fix for the import dialog was reported that way. `no-cache` still allows
/// caching; it requires revalidation first, so an unchanged asset costs a 304
/// rather than a re-download.
const REVALIDATE: (header::HeaderName, &str) = (header::CACHE_CONTROL, "no-cache");

pub async fn console_css() -> impl IntoResponse {
    (
        [
            (header::CONTENT_TYPE, "text/css; charset=utf-8"),
            REVALIDATE,
        ],
        include_str!("../web/console.css"),
    )
}

pub async fn console_js() -> impl IntoResponse {
    (
        [
            (header::CONTENT_TYPE, "text/javascript; charset=utf-8"),
            REVALIDATE,
        ],
        include_str!("../web/console.js"),
    )
}

/// The page an emailed reset link opens (plan 5 #31). Served for any
/// `/reset/{token}`; the page reads the token from its own path rather than
/// taking it as a query parameter, which keeps it out of proxy logs and
/// browser-history entries the way `?token=` never could.
pub async fn reset_page() -> Html<&'static str> {
    Html(include_str!("../web/reset.html"))
}

/// Where an emailed invite link lands (plan 5 #31, stage 3).
pub async fn join_page() -> Html<&'static str> {
    Html(include_str!("../web/join.html"))
}

/// The browser reader (plan 5 #33), served for both `/read/{book_id}` (signed
/// in) and `/r/{token}` (a share link). One page for both, because the only
/// difference is where it fetches from and whether Download appears — and the
/// page works that out from its own path.
pub async fn read_page() -> Html<&'static str> {
    Html(include_str!("../web/read.html"))
}

pub async fn read_js() -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "text/javascript; charset=utf-8")],
        include_str!("../web/read.js"),
    )
}

/// The room viewer (plan 5 #48), for `/room/{id}` and `/pr/{token}` alike.
pub async fn room_page() -> Html<&'static str> {
    Html(include_str!("../web/room.html"))
}

pub async fn room_js() -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "text/javascript; charset=utf-8")],
        include_str!("../web/room.js"),
    )
}

pub async fn public_page() -> Html<&'static str> {
    Html(include_str!("../web/public.html"))
}

pub async fn favicon() -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "image/svg+xml")],
        include_str!("../web/favicon.svg"),
    )
}

pub async fn logo() -> impl IntoResponse {
    (
        [(header::CONTENT_TYPE, "image/svg+xml")],
        include_str!("../web/logo.svg"),
    )
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

#[derive(Serialize)]
pub struct ServerCert {
    /// The certificate in PEM form, ready to paste into the app's import dialog.
    pub pem: String,
    /// SHA-256 fingerprint (uppercase, colon-grouped) to eyeball against the
    /// value the server logged on startup and the one the app shows on import.
    pub fingerprint: String,
}

/// The active TLS certificate (public — presented in every handshake), so the
/// console can hand it to the user for import into the app instead of them
/// copying `cert.pem` off the server by hand. Requires a logged-in console user;
/// 404 when the server runs over plain HTTP (nothing to import).
pub async fn server_cert(
    State(state): State<AppState>,
    _user: AuthUser,
) -> AppResult<Json<ServerCert>> {
    let info = state
        .tls_cert
        .as_ref()
        .ok_or_else(|| AppError::NotFound("server is not using TLS".into()))?;
    let pem = tokio::fs::read_to_string(&info.cert_path)
        .await
        .map_err(|e| AppError::Internal(format!("reading certificate: {e}")))?;
    Ok(Json(ServerCert {
        // Only the CERTIFICATE blocks, so a private key can never leak even if
        // the configured cert file happens to also contain one.
        pem: certificates_only(&pem),
        fingerprint: info.fingerprint.clone(),
    }))
}

/// Keep only the `CERTIFICATE` PEM blocks from `pem`, dropping anything else.
fn certificates_only(pem: &str) -> String {
    const BEGIN: &str = "-----BEGIN CERTIFICATE-----";
    const END: &str = "-----END CERTIFICATE-----";
    let mut out = String::new();
    let mut rest = pem;
    while let Some(s) = rest.find(BEGIN) {
        let after = &rest[s..];
        let Some(e) = after.find(END) else { break };
        out.push_str(&after[..e + END.len()]);
        out.push('\n');
        rest = &after[e + END.len()..];
    }
    out
}

#[cfg(test)]
mod tests {
    use super::certificates_only;

    #[test]
    fn certificates_only_strips_a_private_key() {
        let pem = "-----BEGIN PRIVATE KEY-----\nSECRET\n-----END PRIVATE KEY-----\n\
                   -----BEGIN CERTIFICATE-----\nAAAA\n-----END CERTIFICATE-----\n";
        let out = certificates_only(pem);
        assert!(out.contains("BEGIN CERTIFICATE"));
        assert!(out.contains("AAAA"));
        assert!(
            !out.contains("PRIVATE KEY"),
            "the private key must be dropped"
        );
        assert!(!out.contains("SECRET"));
    }

    #[test]
    fn certificates_only_keeps_a_full_chain() {
        let pem = "-----BEGIN CERTIFICATE-----\nLEAF\n-----END CERTIFICATE-----\n\
                   -----BEGIN CERTIFICATE-----\nCA\n-----END CERTIFICATE-----\n";
        let out = certificates_only(pem);
        assert!(out.contains("LEAF") && out.contains("CA"));
    }
}
