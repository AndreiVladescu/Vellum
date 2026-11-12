//! The self-hosted web console and the public link landing page, plus the
//! book↔group membership endpoint the console needs to render tags. The console
//! is split into html/css and a folder of ES modules, all embedded in the binary
//! (no external assets, no CDN) and served same-origin from `/assets/*`, so
//! `fetch` to `/api/*` and the stylesheet/module loads just work.

use axum::Json;
use axum::extract::{Path, State};
use axum::http::{StatusCode, header};
use axum::response::{Html, IntoResponse, Response};
use serde::Serialize;

use crate::AppState;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};

/// Every one of this module's embedded pages and scripts is compiled into the
/// binary and served at one fixed, hash-less URL — so without a cache header
/// the browser, or a CDN in front of it, may keep serving a previous copy
/// indefinitely. The symptom is upgrading the server, seeing nothing change,
/// and reasonably concluding the fix did not ship — this has now been the
/// reported cause twice on the browser side alone.
///
/// `no-store` rather than `no-cache`: `no-cache` still permits a cache to
/// *store* the response and serve it after revalidating, which relies on the
/// cache actually honouring that — and a CDN sitting in front of this server
/// (Cloudflare, reported in the wild) may cache a `.js`/`.css` response by
/// file extension regardless, since nothing here hands it a validator to
/// revalidate against in the first place. `no-store` forbids storing the
/// response at all, which nothing gets to reinterpret. The cost is a full
/// re-fetch instead of an occasional 304 — irrelevant at this file size.
const REVALIDATE: (header::HeaderName, &str) = (header::CACHE_CONTROL, "no-store");

pub async fn console() -> impl IntoResponse {
    ([REVALIDATE], Html(include_str!("../web/console.html")))
}

pub async fn console_css() -> impl IntoResponse {
    (
        [
            (header::CONTENT_TYPE, "text/css; charset=utf-8"),
            REVALIDATE,
        ],
        include_str!("../web/console.css"),
    )
}

/// The console's script, one ES module per page or concern (`web/console/`),
/// served at `/assets/console/<name>`. Every file is listed here by name and
/// embedded at compile time, so the binary still carries the whole console and
/// nothing is read from disk at run time.
///
/// An explicit table rather than a directory lookup is also what keeps the
/// route safe: a request names an entry in this list or gets a 404, so there is
/// no path to normalise, no `..` to reject, and `package.json` (there for Node,
/// see the file) or anything else in the folder is never served by accident.
/// `tests/console_assets.rs` fails if a `.js` file in the folder is missing from
/// this list — the symptom otherwise is a console that 404s one import and
/// stops, in production only.
const CONSOLE_MODULES: &[(&str, &str)] = &[
    ("actions.js", include_str!("../web/console/actions.js")),
    ("activity.js", include_str!("../web/console/activity.js")),
    ("add_book.js", include_str!("../web/console/add_book.js")),
    ("api.js", include_str!("../web/console/api.js")),
    ("books.js", include_str!("../web/console/books.js")),
    ("boot.js", include_str!("../web/console/boot.js")),
    ("bulk.js", include_str!("../web/console/bulk.js")),
    ("cert.js", include_str!("../web/console/cert.js")),
    ("detail.js", include_str!("../web/console/detail.js")),
    ("dialogs.js", include_str!("../web/console/dialogs.js")),
    ("dom.js", include_str!("../web/console/dom.js")),
    ("export.js", include_str!("../web/console/export.js")),
    ("first_run.js", include_str!("../web/console/first_run.js")),
    ("import.js", include_str!("../web/console/import.js")),
    ("links.js", include_str!("../web/console/links.js")),
    ("loans.js", include_str!("../web/console/loans.js")),
    ("mail.js", include_str!("../web/console/mail.js")),
    ("main.js", include_str!("../web/console/main.js")),
    ("menus.js", include_str!("../web/console/menus.js")),
    ("overview.js", include_str!("../web/console/overview.js")),
    ("pages.js", include_str!("../web/console/pages.js")),
    ("people.js", include_str!("../web/console/people.js")),
    ("reminders.js", include_str!("../web/console/reminders.js")),
    ("requests.js", include_str!("../web/console/requests.js")),
    ("rooms.js", include_str!("../web/console/rooms.js")),
    ("router.js", include_str!("../web/console/router.js")),
    ("search.js", include_str!("../web/console/search.js")),
    ("session.js", include_str!("../web/console/session.js")),
    ("shares.js", include_str!("../web/console/shares.js")),
    ("state.js", include_str!("../web/console/state.js")),
    ("stats.js", include_str!("../web/console/stats.js")),
    ("table.js", include_str!("../web/console/table.js")),
    ("tags.js", include_str!("../web/console/tags.js")),
    ("uploads.js", include_str!("../web/console/uploads.js")),
    ("views.js", include_str!("../web/console/views.js")),
];

pub async fn console_module(Path(name): Path<String>) -> Response {
    match CONSOLE_MODULES.iter().find(|(n, _)| *n == name) {
        Some((_, source)) => (
            [
                (header::CONTENT_TYPE, "text/javascript; charset=utf-8"),
                REVALIDATE,
            ],
            *source,
        )
            .into_response(),
        None => StatusCode::NOT_FOUND.into_response(),
    }
}

/// The page an emailed reset link opens (plan 5 #31). Served for any
/// `/reset/{token}`; the page reads the token from its own path rather than
/// taking it as a query parameter, which keeps it out of proxy logs and
/// browser-history entries the way `?token=` never could.
pub async fn reset_page() -> impl IntoResponse {
    ([REVALIDATE], Html(include_str!("../web/reset.html")))
}

/// Where an emailed invite link lands (plan 5 #31, stage 3).
pub async fn join_page() -> impl IntoResponse {
    ([REVALIDATE], Html(include_str!("../web/join.html")))
}

/// The browser reader (plan 5 #33), served for both `/read/{book_id}` (signed
/// in) and `/r/{token}` (a share link). One page for both, because the only
/// difference is where it fetches from and whether Download appears — and the
/// page works that out from its own path.
pub async fn read_page() -> impl IntoResponse {
    ([REVALIDATE], Html(include_str!("../web/read.html")))
}

pub async fn read_js() -> impl IntoResponse {
    (
        [
            (header::CONTENT_TYPE, "text/javascript; charset=utf-8"),
            REVALIDATE,
        ],
        include_str!("../web/read.js"),
    )
}

/// The room viewer (plan 5 #48), for `/room/{id}` and `/pr/{token}` alike.
pub async fn room_page() -> impl IntoResponse {
    ([REVALIDATE], Html(include_str!("../web/room.html")))
}

pub async fn room_js() -> impl IntoResponse {
    (
        [
            (header::CONTENT_TYPE, "text/javascript; charset=utf-8"),
            REVALIDATE,
        ],
        include_str!("../web/room.js"),
    )
}

pub async fn public_page() -> impl IntoResponse {
    ([REVALIDATE], Html(include_str!("../web/public.html")))
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
