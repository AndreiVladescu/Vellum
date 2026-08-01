//! Vellum sync server as a library, so integration tests in `tests/` can build
//! the same router the binary serves. `main.rs` is a thin wrapper over this.

use std::path::PathBuf;

use axum::Router;
use axum::extract::{DefaultBodyLimit, Request};
use axum::handler::Handler;
use axum::http::HeaderValue;
use axum::http::header::{CONTENT_SECURITY_POLICY, X_CONTENT_TYPE_OPTIONS, X_FRAME_OPTIONS};
use axum::middleware::Next;
use axum::response::Response;
use axum::routing::{delete, get, post, put};
use sqlx::sqlite::{SqliteConnectOptions, SqlitePool, SqlitePoolOptions};

mod access;
mod admin;
mod audit;
mod auth;
mod blobs;
mod books;
mod borrow;
mod capabilities;
mod discover;
mod error;
mod events;
mod groups;
mod ids;
mod import_check;
mod layouts;
mod loans;
mod mail;
mod metadata;
mod observability;
mod opds;
mod personal;
mod physical_copies;
mod reader;
mod reading;
mod send;
mod shares;
mod shelves;
mod text_index;
mod throttle;
pub mod tls;
mod unpublish;
mod web;

pub use throttle::RateLimiter;

/// Re-exported so `main.rs` and the tests can build an `AppState`.
pub use events::EventBus;

/// Re-exported for `main.rs`: the content-search backlog queue and worker
/// (plan 5 #32).
/// Re-exported for `main.rs`: the one-shot move of pre-#9 blobs into the
/// content-addressed layout (plan 5 #9).
pub use blobs::backfill_content_addressed;

pub use text_index::{
    drain as drain_text_index, enqueue_missing as enqueue_missing_text,
    run_worker as run_text_worker,
};

/// Shared handler state: the database pool, the base URL used to build public
/// share links (`VELLUM_PUBLIC_URL`), and the directory holding cover/file
/// blobs (`VELLUM_DATA_DIR`).
#[derive(Clone)]
pub struct AppState {
    pub db: SqlitePool,
    pub public_base_url: String,
    pub data_dir: PathBuf,
    /// Shared client for outbound metadata lookups (Open Library, Google Books).
    pub http: reqwest::Client,
    /// Largest upload (book file) accepted, in bytes (`VELLUM_MAX_UPLOAD_MB`).
    pub max_upload_bytes: usize,
    /// In-memory failed-login limiter, shared across requests.
    pub throttle: std::sync::Arc<throttle::LoginThrottle>,
    /// Bounds concurrent PDF-cover shell-outs so many parallel uploads can't
    /// fork many `gs`/`mutool` processes at once.
    pub render_semaphore: std::sync::Arc<tokio::sync::Semaphore>,
    /// Short-lived cache of successful Basic-auth verifications, so per-request
    /// OPDS Basic auth doesn't cost an Argon2 verify every time.
    pub basic_cache: std::sync::Arc<auth::BasicAuthCache>,
    /// Per-IP limiter for the unauthenticated public-link endpoints.
    pub public_limiter: std::sync::Arc<throttle::RateLimiter>,
    /// Per-user limiter for outbound metadata search (shared Open Library /
    /// Google Books quota).
    pub search_limiter: std::sync::Arc<throttle::RateLimiter>,
    /// Per-user limiter for send-to-device email (plan 5 #53): outbound mail is
    /// a shared, quota'd resource, and a loop over a library would look like
    /// abuse from the relay's side.
    pub send_limiter: std::sync::Arc<throttle::RateLimiter>,
    /// Fan-out for live sync hints (plan 5 #8). Hints only — an event says
    /// *something changed*, and the client answers with the delta pull it
    /// would have run anyway, so this adds no second conflict model.
    pub events: events::EventBus,
    /// Outbound email, present only when SMTP is configured (plan 5 #31). The
    /// `Option` is the feature flag: everything that needs mail checks it and
    /// degrades rather than failing.
    pub mailer: Option<mail::Mailer>,
    /// Whether this server keeps an activity log (`VELLUM_AUDIT=1`, plan
    /// 5 #35). Off by default: a single-user server should not pay for a table
    /// it will never read.
    pub audit: bool,
    /// Whether this server extracts and indexes book *contents* for search
    /// (`VELLUM_INDEX_TEXT=1`, plan 5 #32). Off by default: the index is
    /// roughly the size of the text it holds, and an operator who only wants
    /// sync should not silently start paying for a search engine.
    pub index_text: bool,
    /// Wakes the text-index worker when something is queued, so an upload is
    /// searchable in moments rather than on the next slow poll.
    pub text_notify: std::sync::Arc<tokio::sync::Notify>,
    /// When TLS is on, the served certificate's path + SHA-256 fingerprint, so
    /// the web console can offer it for import into the app. `None` over plain
    /// HTTP (nothing to import).
    pub tls_cert: Option<TlsCertInfo>,
}

/// The active TLS leaf certificate, surfaced to the console's "import
/// certificate" affordance. The certificate is public (presented in every
/// handshake); the private key is never exposed.
#[derive(Clone)]
pub struct TlsCertInfo {
    pub cert_path: PathBuf,
    pub fingerprint: String,
}

/// Open (creating if missing) the SQLite database at `path` and run migrations.
pub async fn connect_db(path: &str) -> anyhow::Result<SqlitePool> {
    let options = SqliteConnectOptions::new()
        .filename(path)
        .create_if_missing(true)
        .foreign_keys(true)
        // WAL lets readers (the console's list, OPDS) run concurrently with a
        // writer (a streaming upload's INSERT); NORMAL sync is the standard WAL
        // pairing (durable except in a narrow power-loss window). A busy timeout
        // turns a transient lock into a short wait instead of a SQLITE_BUSY 500.
        .journal_mode(sqlx::sqlite::SqliteJournalMode::Wal)
        .synchronous(sqlx::sqlite::SqliteSynchronous::Normal)
        .busy_timeout(std::time::Duration::from_secs(5));
    let db = SqlitePoolOptions::new().connect_with(options).await?;
    sqlx::migrate!().run(&db).await?;
    // Drop already-expired sessions so the table doesn't grow without bound.
    sqlx::query("DELETE FROM session WHERE expires_at <= datetime('now')")
        .execute(&db)
        .await?;
    Ok(db)
}

/// Every `/api/*` route, built with paths relative to that prefix (`/books`,
/// not `/api/books`) so it can be `nest`ed under both `/api` (the permanent
/// alias — OPDS entries, the console, and existing public links all embed
/// this form, and it stays valid forever) and `/api/v1` (what new clients
/// should prefer; see `capabilities::get` for the version they're on). Same
/// handlers, zero duplication — this is the only place these routes exist.
fn api_routes(max_upload: usize) -> Router<AppState> {
    Router::new()
        .route("/capabilities", get(capabilities::get))
        // Live sync hints (plan 5 #8). Authenticated, and filtered per
        // subscriber — see `events::visible_to`.
        .route("/events", get(events::stream))
        .route("/memberships", get(web::memberships))
        // Operator dashboard numbers (plan 5 #37). Master-only — see the
        // handler; counts of other people's shares are not a member's business.
        .route("/admin/stats", get(observability::stats))
        // Integrity sweep and one-command backup (plan 5 #12), both master-only.
        .route("/admin/sweep", post(admin::sweep))
        .route("/admin/reindex", post(text_index::reindex))
        .route("/admin/audit", get(audit::list))
        // Content search (plan 5 #32). Under /api like everything else, and
        // named `search` rather than `books/search` because it searches inside
        // books rather than over their metadata — `/books?q=` is the other one.
        .route("/search", get(text_index::search))
        .route("/search/status", get(text_index::status))
        .route("/admin/snapshot", get(admin::snapshot))
        // The active TLS certificate (public), for the console's import affordance.
        .route("/cert", get(web::server_cert))
        // Accounts & sessions.
        .route("/auth/register", post(auth::register))
        .route("/auth/login", post(auth::login))
        .route("/auth/logout", post(auth::logout))
        // Password reset by email (plan 5 #31). Both are unauthenticated by
        // necessity — the caller can't log in — so both are throttled and
        // deliberately uninformative about which addresses exist.
        .route("/auth/forgot", post(auth::forgot))
        .route("/auth/reset", post(auth::reset))
        .route("/auth/me", get(auth::me))
        .route("/users", get(auth::list_users).post(auth::create_user))
        // Administering the people in a shared library (plan 6 #1). Master-only,
        // and console-only by design — this is a desk job, not something to
        // duplicate into the app.
        .route(
            "/users/{id}",
            put(auth::set_user_role).delete(auth::delete_user),
        )
        // Online metadata search + add a chosen result.
        // The duplicate check, shared by the console's importer and (in time)
        // the app's, so the two cannot disagree (next features #5).
        .route("/import/check", post(import_check::check))
        .route("/metadata/search", get(discover::search))
        .route("/metadata/analyze", post(discover::analyze))
        .route("/books/from-search", post(discover::add_from_search))
        .route("/books/{id}/enrich", post(discover::enrich))
        // Books (visibility-filtered by RBAC).
        .route("/deletions", get(books::deletions))
        .route("/books", get(books::list).post(books::create))
        // Batch metadata push (plan 5 #7): fewer round trips for a large
        // first sync. Shares books::upsert's exact per-book logic.
        .route("/books:batch", post(books::batch_upsert))
        .route(
            "/books/{id}",
            get(books::get)
                .put(books::upsert)
                .patch(books::update)
                .delete(books::delete),
        )
        // Cover images and book files (filesystem-backed blobs). The big upload
        // limit is scoped to just these two write handlers, so every other
        // endpoint — including unauthenticated ones like login — keeps axum's
        // small default and can't be used to buffer gigabytes of body in RAM.
        .route(
            "/books/{id}/cover",
            put(blobs::put_cover.layer(DefaultBodyLimit::max(32 * 1024 * 1024)))
                .get(blobs::get_cover),
        )
        .route(
            "/books/{id}/files",
            get(blobs::list_files)
                .post(blobs::upload_file.layer(DefaultBodyLimit::max(max_upload))),
        )
        .route("/books/{id}/read", get(reader::manifest))
        .route("/books/{id}/read/{index}", get(reader::unit))
        .route("/books/{id}/read/asset/{*name}", get(reader::asset))
        .route("/files/{file_id}", get(blobs::download_file))
        // Send a book to an e-reader by email (plan 5 #53). Gated on the `mail`
        // capability, rate-limited per user, and RBAC'd exactly like a read.
        .route("/books/{id}/send", post(send::send_book))
        .route(
            "/send-targets",
            get(send::list_targets).put(send::put_targets),
        )
        // Book groups.
        .route("/groups", get(groups::list).post(groups::create))
        .route("/groups/{id}", get(groups::get).delete(groups::delete))
        .route("/groups/{id}/books", post(groups::add_book))
        .route("/groups/{id}/books/{book_id}", delete(groups::remove_book))
        // Custom shelves (plan 5 #4) — cursor-pull list, id-chosen upsert (a
        // push always sends the whole ordered membership), delete.
        .route("/shelves", get(shelves::list))
        .route(
            "/shelves/{id}",
            put(shelves::upsert).delete(shelves::delete),
        )
        // Physical copies (plan 5 #4) — same cursor-pull/upsert/delete shape
        // as shelves, but no owner of its own (access derives from the book).
        .route("/copies", get(physical_copies::list))
        .route(
            "/copies/{id}",
            put(physical_copies::upsert).delete(physical_copies::delete),
        )
        // Loan history (plan 5 #4, last of the trio) — same shape again.
        // Personal data (annotations, sittings, private notes, profile) —
        // scoped to the caller, never to the library. See personal.rs.
        .route("/annotations", get(personal::list_annotations))
        .route(
            "/annotations/{id}",
            put(personal::upsert_annotation).delete(personal::delete_annotation),
        )
        .route(
            "/annotations/deletions",
            get(personal::list_annotation_deletions),
        )
        .route("/sessions", get(personal::list_sessions))
        .route("/sessions/{id}", put(personal::upsert_session))
        .route("/notes", get(personal::list_notes))
        .route("/notes/{book_id}", put(personal::upsert_note))
        .route(
            "/profile",
            get(personal::get_profile).put(personal::update_profile),
        )
        .route(
            "/profile/avatar",
            get(personal::get_avatar)
                // Stated explicitly so `put_avatar`'s own 4 MB check is the one
                // that fires. Without it axum's 2 MB default rejected a 3 MB
                // upload first, with "Failed to buffer the request body" — a
                // limit that disagreed with the documented one and an error
                // that named neither (plan 6 #3, finding P2).
                .put(personal::put_avatar.layer(DefaultBodyLimit::max(4 * 1024 * 1024)))
                .delete(personal::delete_avatar),
        )
        // Photos of a physical copy (plan 6 #4). Library data, not personal:
        // they hang off a copy and are visible to whoever the book is shared
        // with, like its covers.
        .route("/copy-photos", get(physical_copies::list_photos))
        .route(
            "/copy-photos/{id}",
            put(physical_copies::upsert_photo).delete(physical_copies::delete_photo),
        )
        .route(
            "/copy-photos/{id}/image",
            get(physical_copies::get_photo_image).put(
                physical_copies::put_photo_image.layer(DefaultBodyLimit::max(16 * 1024 * 1024)),
            ),
        )
        .route("/loans", get(loans::list))
        .route("/loans/{id}", put(loans::upsert).delete(loans::delete))
        // Optional cross-device reading position (plan 5 #5). Per-(book, user,
        // device) rows, so there is nothing to merge; DELETE un-publishes one
        // device's rows when the user turns the setting back off.
        .route(
            "/reading-progress",
            get(reading::list).delete(reading::forget_device),
        )
        .route("/reading-progress/{book_id}", put(reading::upsert))
        // Taking a resource back off the server (next features #8). Scoped to
        // the caller in every case — see `unpublish`.
        .route("/mine/{resource}", delete(unpublish::forget))
        // User-to-user shares.
        // Published room layouts (plan 5 #47). A document store: whole-document
        // publish with a revision, 409 on a stale base.
        // Borrow requests (plan 5 #49).
        .route("/borrow-requests", get(borrow::list).post(borrow::create))
        .route("/borrow-requests/{id}/decide", post(borrow::decide))
        .route("/layouts", get(layouts::list))
        .route("/layouts/{id}/books", get(layouts::books))
        .route(
            "/layouts/{id}",
            get(layouts::get)
                .put(layouts::publish)
                .delete(layouts::delete),
        )
        .route("/shares", get(shares::list).post(shares::create))
        .route("/shares/{id}", delete(shares::delete))
        // Emailed member invites (plan 5 #31, stage 3). Minting is master-only;
        // redeeming is necessarily unauthenticated — the invitee has no account.
        .route(
            "/invites",
            get(shares::list_invites).post(shares::create_invite),
        )
        .route(
            "/invites/{id}",
            axum::routing::delete(shares::revoke_invite),
        )
        .route("/invites/redeem", post(shares::redeem_invite))
        // Public per-book links (no account required to read).
        .route(
            "/share-links",
            get(shares::list_links).post(shares::create_link),
        )
        .route("/share-links/{id}", delete(shares::delete_link))
        // Reading in the browser (plan 5 #33). The public variants never
        // consume a share link's use — that counts downloads.
        // A published room, for anyone with the link (plan 5 #48). Never
        // consumes a use: there is nothing to download.
        .route("/public/{token}/room", get(shares::public_room))
        .route("/public/{token}/read", get(reader::public_manifest))
        .route("/public/{token}/read/{index}", get(reader::public_unit))
        .route(
            "/public/{token}/read/asset/{*name}",
            get(reader::public_asset),
        )
        .route("/public/{token}", get(shares::public_book))
        .route("/public/{token}/file", get(shares::public_file))
        // Book detail (metadata + authors + genres + files) for the console.
        .route("/books/{id}/detail", get(books::detail))
}

/// Reads the mail configuration from the environment (plan 5 #31). Re-exported
/// so `main.rs` can fail fast on a misconfiguration without depending on the
/// module layout.
pub fn build_mailer() -> anyhow::Result<Option<mail::Mailer>> {
    mail::Mailer::from_env()
}

/// The token-hashing function, so tests can seed a reset token the same way the
/// handler stores one (the plaintext is never returned by the API, by design).
pub fn sha256_hex_for_tests(input: &str) -> String {
    auth::sha256_hex(input)
}

/// A mailer for tests, built without touching the process environment.
/// The email attachment cap and the attachment-name rule, re-exported so the
/// integration tests can assert against the real values rather than copies.
pub use send::{MAX_ATTACHMENT_BYTES, attachment_name};

pub fn test_mailer(host: &str, from: &str) -> mail::Mailer {
    mail::for_testing(host, from)
}

/// Build the full application router.
/// The OPDS feeds, with the HTTP Basic challenge attached to *their* 401s only.
///
/// E-readers speak Basic auth and need `WWW-Authenticate` to know to ask for
/// credentials. Browsers react to the same header by popping their own native
/// credential dialog — which, when it was sent on every 401 in the server, sat
/// on top of the console from the moment the page loaded and reappeared on
/// every failed sign-in, leaving no way to log in through the console's own
/// form at all. So the challenge lives here, on the routes that want it, rather
/// than in `AppError::Unauthorized`.
fn opds_routes() -> Router<AppState> {
    Router::new()
        .route("/opds", get(opds::root))
        .route("/opds/all", get(opds::all))
        .route("/opds/recent", get(opds::recent))
        .route("/opds/authors", get(opds::authors))
        .route("/opds/authors/{name}", get(opds::by_author))
        .route("/opds/genres", get(opds::genres))
        .route("/opds/genres/{name}", get(opds::by_genre))
        .route("/opds/groups", get(opds::groups))
        .route("/opds/groups/{id}", get(opds::by_group))
        .route("/opds/search", get(opds::search))
        .route("/opds/search.xml", get(opds::search_description))
        .route("/opds/v2", get(opds::v2_root))
        .layer(axum::middleware::map_response(add_basic_challenge))
}

async fn add_basic_challenge(mut response: axum::response::Response) -> axum::response::Response {
    if response.status() == axum::http::StatusCode::UNAUTHORIZED {
        response.headers_mut().insert(
            axum::http::header::WWW_AUTHENTICATE,
            axum::http::HeaderValue::from_static("Basic realm=\"Vellum\""),
        );
    }
    response
}

pub fn router(state: AppState) -> Router {
    let api = api_routes(state.max_upload_bytes);
    Router::new()
        .route("/health", get(health))
        // Web admin console + public landing page.
        .route("/", get(web::console))
        .route("/assets/console.css", get(web::console_css))
        .route("/assets/console.js", get(web::console_js))
        .route("/assets/logo.svg", get(web::logo))
        .route("/favicon.svg", get(web::favicon))
        .route("/p/{token}", get(web::public_page))
        // The browser reader (plan 5 #33): the same page for a signed-in
        // reader and for a share link, which it tells apart from its own path.
        // The room viewer (plan 5 #48): /room/<id> signed in, /pr/<token> for a
        // public link. One page, told apart by its own path — the same shape
        // the browser reader uses.
        .route("/room/{layout_id}", get(web::room_page))
        .route("/pr/{token}", get(web::room_page))
        .route("/assets/room.js", get(web::room_js))
        .route("/read/{book_id}", get(web::read_page))
        .route("/r/{token}", get(web::read_page))
        .route("/assets/read.js", get(web::read_js))
        // Where the emailed password-reset link lands (plan 5 #31).
        .route("/reset/{token}", get(web::reset_page))
        .route("/join/{token}", get(web::join_page))
        // OPDS catalog for third-party e-readers (HTTP Basic auth) — not
        // versioned: readers have this exact URL saved, it never moves.
        // OPDS (plan 5 #34). `/opds` is a *navigation* feed; the acquisition
        // feeds hang off it and are paged. `/opds/all` is what the old flat
        // `/opds` was, so an existing client that bookmarked the root still
        // finds every book one hop away.
        .merge(opds_routes())
        .nest("/api", api.clone())
        .nest("/api/v1", api)
        .with_state(state)
        // Baseline security headers on every response (defence in depth for the
        // console/public pages and blob downloads). See docs/SECURITY_AUDIT.md (L3).
        .layer(axum::middleware::from_fn(security_headers))
        // Before any handler: a path segment must not be hiding a separator.
        // Ids from the URL end up in filesystem paths, and axum decodes a
        // captured segment — so `..%2F..%2Fx` used to arrive as `../../x`.
        .layer(axum::middleware::from_fn(ids::reject_smuggled_separators))
        // Outermost, so every response — including one rejected before any
        // handler runs — carries a request id (plan 5 #37).
        .layer(axum::middleware::from_fn(observability::request_id))
}

/// A restrictive Content-Security-Policy that still lets the self-hosted console
/// and public landing page work: everything loads from same-origin, images may
/// also be `data:` (inline placeholders) or `blob:` (the console fetches
/// authenticated covers with an `Authorization` header and shows them via an
/// object URL, so the token never rides the URL), and the pages' inline
/// `<style>`/`<script>` (no external/CDN assets) are permitted. `object-src` and
/// framing are denied outright.
const CSP: &str = "default-src 'self'; img-src 'self' data: blob:; \
    style-src 'self' 'unsafe-inline'; script-src 'self' 'unsafe-inline'; \
    object-src 'none'; base-uri 'none'; frame-ancestors 'none'";

/// Adds baseline hardening headers to every response: block MIME-sniffing,
/// forbid framing (clickjacking), and apply the CSP above.
async fn security_headers(req: Request, next: Next) -> Response {
    let mut res = next.run(req).await;
    let h = res.headers_mut();
    h.insert(X_CONTENT_TYPE_OPTIONS, HeaderValue::from_static("nosniff"));
    h.insert(X_FRAME_OPTIONS, HeaderValue::from_static("DENY"));
    h.insert(CONTENT_SECURITY_POLICY, HeaderValue::from_static(CSP));
    res
}

async fn health() -> &'static str {
    "ok"
}
