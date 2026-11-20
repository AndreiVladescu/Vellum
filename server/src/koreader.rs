//! KOReader progress sync (v1.6.3): the server speaks KOReader's own sync
//! protocol ("kosync"), so an e-reader running KOReader keeps its place in the
//! same per-device reading-position channel the Vellum app uses.
//!
//! Mounted under `/koreader`; KOReader's *Progress sync → Custom sync server*
//! takes that address. The protocol is the one KOReader's `kosync.koplugin`
//! speaks to `koreader-sync-server`:
//!
//! | request                           | answer                                  |
//! |-----------------------------------|-----------------------------------------|
//! | `GET  /healthcheck`               | `{"state":"OK"}`                        |
//! | `POST /users/create`              | refused — accounts come from the console |
//! | `GET  /users/auth`                | `{"authorized":"OK"}`                   |
//! | `PUT  /syncs/progress`            | `{"document", "timestamp"}`             |
//! | `GET  /syncs/progress/{document}` | the latest position, or `{}`            |
//!
//! ## Credentials
//!
//! Every request carries `x-auth-user` (here: the account's email) and
//! `x-auth-key`, the hex MD5 of what was typed as the password. That key must
//! come from an **app password made for KOReader** — never the account
//! password, which is Argon2-hashed and so could not be checked against an MD5
//! even if we wanted it on an e-reader. Migration 0042 explains what is stored
//! and why MD5 is harmless here. The key opens these routes and nothing else:
//! it is not a Basic credential, so it cannot reach OPDS or `/api` at all.
//!
//! ## Documents
//!
//! KOReader names a book by a partial MD5 of its file ([`partial_md5`]). Each
//! stored file's digest is computed on upload and cached, so `document`
//! resolves to the books holding that exact file. A document nothing matches
//! is recorded anyway and linked when the file arrives.
//!
//! ## Where it lands
//!
//! KOReader's report is kept verbatim (`koreader_progress`), because a GET has
//! to hand back its opaque `progress` — an EPUB xpointer or a PDF page — byte
//! for byte. It is also **mirrored** into `reading_progress` for every linked
//! book the caller can see, as device `koreader:<device_id>` labelled
//! "KOReader on <device>", so the app shows it like any other device. That row
//! is personal data keyed by the credential's `user_id`, never a book column —
//! the rule in CLAUDE.md.
//!
//! ## And back (migration 0045)
//!
//! A GET answers with KOReader's own latest report, verbatim — unless the app
//! password has "Send Vellum's position to KOReader" on and the Vellum app has
//! a strictly newer position in a book holding this file. Then that position
//! goes out in KOReader's form ([`progress_in_koreader_terms`]): a PDF's page,
//! or an EPUB chapter's **start**, `/body/DocFragment[N]`. Only the chapter:
//! the app's in-chapter scroll has no xpointer the server could vouch for, and
//! crengine sends an xpointer it cannot resolve to the first page of the book.
//! The `device` says "Vellum on <device>", so KOReader's prompt names it.

use std::io::{Read, Seek, SeekFrom};

use axum::Json;
use axum::Router;
use axum::body::Bytes;
use axum::extract::{FromRequestParts, Path, State};
use axum::http::StatusCode;
use axum::http::request::Parts;
use axum::response::{IntoResponse, Response};
use axum::routing::{get, post, put};
use md5::{Digest, Md5};
use serde_json::{Value, json};

use crate::AppState;
use crate::access::book_access;
use crate::auth::{AuthUser, sha256_hex};

// ---- the document digest ---------------------------------------------------

/// KOReader's `util.partialMD5`: the MD5 of up to 1 KiB read at each of the
/// offsets 0, 1 KiB, 4 KiB, 16 KiB, … 1 GiB, stopping at the first offset at or
/// past the end of the file.
///
/// The Lua loop runs `i = -1 .. 10` over `bit.lshift(1024, 2*i)`. LuaJIT masks
/// a shift count to five bits, so `i = -1` is a shift by 30, and `1024 << 30`
/// wraps to **0** in 32 bits — the first sample is the file's start, not
/// offset 256 as the arithmetic suggests. That quirk is the de facto format;
/// every reimplementation reproduces it, and so does this.
pub fn partial_md5<R: Read + Seek>(file: &mut R) -> std::io::Result<String> {
    const STEP: u64 = 1024;
    const SIZE: usize = 1024;
    let len = file.seek(SeekFrom::End(0))?;
    let mut md5 = Md5::new();
    let mut buf = [0u8; SIZE];
    for i in -1i32..=10 {
        let offset = if i < 0 { 0 } else { STEP << (2 * i) };
        // Lua's `file:read(n)` returns nil at end of file, which ends the loop.
        if offset >= len {
            break;
        }
        file.seek(SeekFrom::Start(offset))?;
        let mut filled = 0;
        while filled < SIZE {
            let n = file.read(&mut buf[filled..])?;
            if n == 0 {
                break;
            }
            filled += n;
        }
        md5.update(&buf[..filled]);
    }
    Ok(hex::encode(md5.finalize()))
}

/// [`partial_md5`] of a file on disk.
pub fn partial_md5_file(path: &std::path::Path) -> std::io::Result<String> {
    partial_md5(&mut std::fs::File::open(path)?)
}

/// Hex MD5 of a string — what KOReader sends as `x-auth-key`.
fn md5_hex(s: &str) -> String {
    hex::encode(Md5::digest(s.as_bytes()))
}

// ---- keys --------------------------------------------------------------------

/// What is stored for one key: `sha256(md5_hex)`. The MD5 is lowercased first
/// so a client that sends it in capitals still matches.
pub(crate) fn key_hash(md5_hex: &str) -> String {
    sha256_hex(&md5_hex.trim().to_ascii_lowercase())
}

/// The spellings of a freshly made secret a person is likely to type into
/// KOReader: as shown (`k3m9-x2qa-…`), without the dashes, or with spaces, in
/// lower or upper case. The MD5 is over the exact characters, so each is its
/// own key; anything else (a Crockford slip like `o` for `0`) is refused rather
/// than guessed at.
pub(crate) fn key_spellings(secret: &str) -> Vec<String> {
    let dashed = secret.to_ascii_lowercase();
    let mut out = Vec::with_capacity(6);
    for form in [
        dashed.clone(),
        dashed.replace('-', ""),
        dashed.replace('-', " "),
    ] {
        for cased in [form.clone(), form.to_ascii_uppercase()] {
            if !out.contains(&cased) {
                out.push(cased);
            }
        }
    }
    out
}

/// Record the KOReader keys for a new app password, inside its creating
/// transaction — the only moment the secret exists on the server.
pub(crate) async fn store_keys(
    tx: &mut sqlx::SqliteConnection,
    app_password_id: &str,
    secret: &str,
) -> Result<(), sqlx::Error> {
    for spelling in key_spellings(secret) {
        sqlx::query("INSERT INTO koreader_key (key_hash, app_password_id) VALUES (?, ?)")
            .bind(key_hash(&md5_hex(&spelling)))
            .bind(app_password_id)
            .execute(&mut *tx)
            .await?;
    }
    Ok(())
}

// ---- errors, in the protocol's own shape -------------------------------------

/// The reference server's error table (`config/errors.lua`): a numeric code
/// and a message, with its HTTP status. KOReader shows `message` to the reader.
#[derive(Debug)]
pub enum KoError {
    Unauthorized,
    Throttled,
    InvalidFields(&'static str),
    DocumentMissing,
    RegistrationDisabled,
    DocumentNotServable,
    Internal(String),
}

impl IntoResponse for KoError {
    fn into_response(self) -> Response {
        let (status, code, message) = match self {
            KoError::Unauthorized => (StatusCode::UNAUTHORIZED, 2001, "Unauthorized".to_string()),
            KoError::Throttled => (
                StatusCode::TOO_MANY_REQUESTS,
                2001,
                "Too many failed attempts — try again later.".into(),
            ),
            KoError::InvalidFields(m) => (StatusCode::FORBIDDEN, 2003, m.into()),
            KoError::DocumentMissing => (
                StatusCode::FORBIDDEN,
                2004,
                "Field 'document' not provided.".into(),
            ),
            KoError::RegistrationDisabled => (
                StatusCode::PAYMENT_REQUIRED, // 402, as the reference server uses
                2005,
                "Accounts are made in the Vellum console. Log in with your email \
                 and an app password made for KOReader."
                    .into(),
            ),
            KoError::DocumentNotServable => (
                StatusCode::FORBIDDEN,
                2007,
                "Field 'document' contains characters the read route cannot serve.".into(),
            ),
            KoError::Internal(m) => {
                tracing::error!("koreader: {m}");
                (
                    StatusCode::BAD_GATEWAY, // 502, the reference's 2000
                    2000,
                    "Unknown server error.".into(),
                )
            }
        };
        (status, Json(json!({ "code": code, "message": message }))).into_response()
    }
}

impl From<sqlx::Error> for KoError {
    fn from(e: sqlx::Error) -> Self {
        KoError::Internal(e.to_string())
    }
}

impl From<crate::error::AppError> for KoError {
    fn from(e: crate::error::AppError) -> Self {
        KoError::Internal(e.message())
    }
}

type KoResult<T> = Result<T, KoError>;

// ---- the authenticated caller ------------------------------------------------

/// A request carrying a valid KOReader key. The user comes from the key's app
/// password — `x-auth-user` only has to agree with it.
pub struct KoUser {
    pub user: AuthUser,
    /// The app password's "Send Vellum's position to KOReader" (migration
    /// 0045): whether a GET may answer with the app's position.
    pub send_position: bool,
}

impl FromRequestParts<AppState> for KoUser {
    type Rejection = KoError;

    async fn from_request_parts(parts: &mut Parts, state: &AppState) -> KoResult<Self> {
        let header = |name: &str| {
            parts
                .headers
                .get(name)
                .and_then(|v| v.to_str().ok())
                .map(str::trim)
                .filter(|v| !v.is_empty())
        };
        let (Some(email), Some(key)) = (header("x-auth-user"), header("x-auth-key")) else {
            return Err(KoError::Unauthorized);
        };
        let email = email.to_lowercase();
        // Its own throttle bucket: a KOReader with a stale key retrying in the
        // background must not lock its owner out of the console. Guessing gains
        // nothing anyway — a key is the MD5 of 120 random bits — so the limit
        // only bounds the lookups.
        let bucket = format!("koreader:{email}");
        if !state.throttle.allowed(&bucket) {
            return Err(KoError::Throttled);
        }
        let well_formed = key.len() == 32 && key.bytes().all(|b| b.is_ascii_hexdigit());
        let found: Option<(String, String, String, bool, String, bool)> = if well_formed {
            sqlx::query_as(
                "SELECT u.id, u.email, u.display_name, u.is_master, ap.id, \
                        ap.koreader_send_position \
                 FROM koreader_key k \
                 JOIN app_password ap ON ap.id = k.app_password_id \
                 JOIN app_user u ON u.id = ap.user_id \
                 WHERE k.key_hash = ? AND u.email = ?",
            )
            .bind(key_hash(key))
            .bind(&email)
            .fetch_optional(&state.db)
            .await?
        } else {
            None
        };
        let Some((id, email, display_name, is_master, app_password_id, send_position)) = found
        else {
            state.throttle.record_failure(&bucket);
            return Err(KoError::Unauthorized);
        };
        state.throttle.clear(&bucket);
        crate::app_passwords::touch(state, &app_password_id).await;
        Ok(KoUser {
            user: AuthUser {
                id,
                email,
                display_name,
                is_master,
            },
            send_position,
        })
    }
}

// ---- routes --------------------------------------------------------------------

/// The kosync routes, relative to their mount point (`/koreader`).
pub fn routes() -> Router<AppState> {
    Router::new()
        .route("/healthcheck", get(healthcheck))
        .route("/users/create", post(create_user))
        .route("/users/auth", get(authorize))
        .route("/syncs/progress", put(put_progress))
        .route("/syncs/progress/{document}", get(get_progress))
}

async fn healthcheck() -> Json<Value> {
    Json(json!({ "state": "OK" }))
}

/// Registration from an e-reader is refused: accounts are made in the console,
/// and the password KOReader would register with is exactly the kind of
/// credential an app password exists to keep off the device.
async fn create_user() -> KoError {
    KoError::RegistrationDisabled
}

async fn authorize(_user: KoUser) -> Json<Value> {
    Json(json!({ "authorized": "OK" }))
}

const MAX_DOCUMENT: usize = 128;
const MAX_PROGRESS: usize = 4096;
const MAX_DEVICE: usize = 128;

/// A document id the reference server would serve: non-empty `[A-Za-z0-9_]`.
fn check_document(document: Option<&str>) -> KoResult<&str> {
    let document = document
        .map(str::trim)
        .filter(|d| !d.is_empty())
        .ok_or(KoError::DocumentMissing)?;
    if document.len() > MAX_DOCUMENT
        || !document
            .bytes()
            .all(|b| b.is_ascii_alphanumeric() || b == b'_')
    {
        return Err(KoError::DocumentNotServable);
    }
    Ok(document)
}

/// One position as KOReader reported it.
#[derive(Debug, Clone, PartialEq)]
pub struct Reported {
    pub document: String,
    pub progress: String,
    pub percentage: f64,
    pub device: String,
    pub device_id: String,
    pub timestamp: i64,
}

/// Parses a `PUT /syncs/progress` body. By hand rather than through a typed
/// `Json<…>` so a malformed one answers in the protocol's error shape instead
/// of axum's, and so `progress` may be a number as well as a string — KOReader
/// sends `tostring(progress)`, but other kosync clients send a page as a number.
fn parse_report(body: &[u8], timestamp: i64) -> KoResult<Reported> {
    let value: Value =
        serde_json::from_slice(body).map_err(|_| KoError::InvalidFields("Invalid request"))?;
    let document = check_document(value.get("document").and_then(Value::as_str))?.to_string();

    let progress = match value.get("progress") {
        Some(Value::String(s)) => s.clone(),
        Some(Value::Number(n)) => n.to_string(),
        _ => return Err(KoError::InvalidFields("Invalid request")),
    };
    if progress.is_empty() || progress.len() > MAX_PROGRESS {
        return Err(KoError::InvalidFields("Invalid request"));
    }
    let percentage = match value.get("percentage") {
        Some(Value::Number(n)) => n.as_f64(),
        Some(Value::String(s)) => s.trim().parse::<f64>().ok(),
        _ => None,
    }
    .filter(|p| p.is_finite())
    .ok_or(KoError::InvalidFields("Invalid request"))?
    .clamp(0.0, 1.0);

    let text = |key: &str| {
        value
            .get(key)
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|s| !s.is_empty())
            .map(|s| s.chars().take(MAX_DEVICE).collect::<String>())
    };
    let device = text("device").ok_or(KoError::InvalidFields("Invalid request"))?;
    // Optional in the reference server; without one, the device name is the
    // best identity there is.
    let device_id = text("device_id").unwrap_or_else(|| device.clone());
    Ok(Reported {
        document,
        progress,
        percentage,
        device,
        device_id,
        timestamp,
    })
}

async fn put_progress(
    State(state): State<AppState>,
    KoUser { user, .. }: KoUser,
    body: Bytes,
) -> KoResult<Json<Value>> {
    let report = parse_report(&body, chrono::Utc::now().timestamp())?;
    sqlx::query(
        "INSERT INTO koreader_progress \
            (user_id, document, device_id, device, progress, percentage, timestamp) \
         VALUES (?, ?, ?, ?, ?, ?, ?) \
         ON CONFLICT(user_id, document, device_id) DO UPDATE SET \
            device = excluded.device, progress = excluded.progress, \
            percentage = excluded.percentage, timestamp = excluded.timestamp",
    )
    .bind(&user.id)
    .bind(&report.document)
    .bind(&report.device_id)
    .bind(&report.device)
    .bind(&report.progress)
    .bind(report.percentage)
    .bind(report.timestamp)
    .execute(&state.db)
    .await?;

    // Best effort beyond this point: KOReader's write is recorded, and a mirror
    // that fails now is redone by the device's next page turn.
    if let Err(e) = mirror(&state, &user, &report).await {
        tracing::warn!("koreader: mirroring into reading_progress failed: {e:?}");
    }
    Ok(Json(json!({
        "document": report.document,
        "timestamp": report.timestamp,
    })))
}

/// `GET /syncs/progress/{document}`: the newest position for this document,
/// in KOReader's terms.
///
/// Two candidates. KOReader's own latest report, across this person's devices,
/// is returned **verbatim** — the reference server's single last-writer-wins
/// slot; KOReader tells its own report from another device's by `device_id`.
/// And, when the app password allows it, the Vellum app's latest position in a
/// book holding this file ([`vellum_position`]), converted. The Vellum one wins
/// only when strictly newer; a tie goes to KOReader, whose position is the
/// precise one.
///
/// Nothing at all is `200 {}`, as the reference server answers and as
/// KOReader's plugin expects: it reads a body without `percentage` as "No
/// progress found", and any non-200 as "Something went wrong".
async fn get_progress(
    State(state): State<AppState>,
    KoUser {
        user,
        send_position,
    }: KoUser,
    Path(document): Path<String>,
) -> KoResult<Json<Value>> {
    let document = check_document(Some(&document))?;
    let row: Option<(String, String, f64, String, String, i64)> = sqlx::query_as(
        "SELECT document, progress, percentage, device, device_id, timestamp \
         FROM koreader_progress WHERE user_id = ? AND document = ? \
         ORDER BY timestamp DESC, rowid DESC LIMIT 1",
    )
    .bind(&user.id)
    .bind(document)
    .fetch_optional(&state.db)
    .await?;
    let reported = row.map(
        |(document, progress, percentage, device, device_id, timestamp)| Reported {
            document,
            progress,
            percentage,
            device,
            device_id,
            timestamp,
        },
    );
    let vellum = if send_position {
        vellum_position(&state, &user, document).await?
    } else {
        None
    };
    let newest = match (reported, vellum) {
        (Some(k), Some(v)) => Some(if v.timestamp > k.timestamp { v } else { k }),
        (k, v) => k.or(v),
    };
    Ok(Json(match newest {
        None => json!({}),
        Some(r) => json!({
            "document": r.document,
            "progress": r.progress,
            "percentage": r.percentage,
            "device": r.device,
            "device_id": r.device_id,
            "timestamp": r.timestamp,
        }),
    }))
}

// ---- out of the reading-position channel -------------------------------------

/// The `device_id` a Vellum position is sent to KOReader under. Prefixed, so
/// KOReader never takes it for its own (it ignores a body whose `device` and
/// `device_id` are both its own).
pub fn vellum_device_id(device_id: &str) -> String {
    format!("vellum:{device_id}")
}

/// What KOReader's `progress` is for the app's `(page, unit)` in a file of
/// `format`, or None when there is nothing safe to send.
///
/// - **PDF** (`unit = 'page'`): the 1-based page number as a string — what
///   KOReader's paging mode reports (`tostring(getTopPage())`) and reads back
///   (`GotoPage(tonumber(progress))`, which clamps to the document's pages).
/// - **EPUB** (`unit = 'chapter'`): `/body/DocFragment[N]`, the *start* of the
///   chapter. crengine's whole EPUB is `<body>` with one `<DocFragment>` per
///   spine item, so this is the coarsest xpointer it resolves, and valid in
///   every rendering of the book; going deeper (`…/body/p[1]`) would assume
///   markup the chapter may not have. The app's in-chapter scroll is dropped
///   for the same reason. `fragments` maps the app's chapter to its
///   `DocFragment` ([`crate::blobs::epub_docfragments`]); a chapter past the
///   end is clamped to the last, as the app's own reader does.
/// - A unit that does not match the format, or anything else: None.
pub fn progress_in_koreader_terms(
    format: &str,
    page: i64,
    unit: &str,
    fragments: Option<&[usize]>,
) -> Option<String> {
    match (format, unit) {
        ("pdf", "page") if page >= 1 => Some(page.to_string()),
        ("epub", "chapter") if page >= 1 => {
            let fragments = fragments.filter(|f| !f.is_empty())?;
            let index = usize::try_from(page).ok()?.min(fragments.len()) - 1;
            Some(format!("/body/DocFragment[{}]", fragments[index]))
        }
        _ => None,
    }
}

/// The unit the app counts a file of `format` in, when KOReader can be sent it.
fn app_unit(format: &str) -> Option<&'static str> {
    match format {
        "pdf" => Some("page"),
        "epub" => Some("chapter"),
        _ => None,
    }
}

/// The Vellum app's newest position in any book the caller can see that holds
/// this document's file, as a KOReader report — or None.
///
/// Only a position that can be sent safely counts: one an app install wrote
/// (never a mirrored `koreader:` row), with a percentage and a page in the unit
/// this file's format needs. A book holding both a PDF and an EPUB is skipped:
/// the app keeps one `page` per book and labels it `page` whenever a PDF is
/// present, even when the EPUB was the one being read, so the number cannot be
/// trusted to mean either.
async fn vellum_position(
    state: &AppState,
    user: &AuthUser,
    document: &str,
) -> KoResult<Option<Reported>> {
    let mut books = linked_books(state, document).await?;
    if books.is_empty() {
        // Maybe a file that predates the digest table, not yet indexed.
        index_missing(state, BACKFILL_ON_REQUEST).await;
        books = linked_books(state, document).await?;
    }
    // (report without its progress yet, format, blob path, app page)
    let mut best: Option<(Reported, String, String, i64)> = None;
    for (book_id, format, path) in books {
        let Some(unit) = app_unit(&format) else {
            continue;
        };
        if !book_access(state, user, &book_id).await?.can_view() {
            continue;
        }
        let both: bool = sqlx::query_scalar(
            "SELECT COUNT(DISTINCT format) = 2 FROM book_file \
             WHERE book_id = ? AND format IN ('pdf', 'epub')",
        )
        .bind(&book_id)
        .fetch_one(&state.db)
        .await?;
        if both {
            continue;
        }
        // `updated_at` is the writing device's clock, UTC; KOReader compares
        // the timestamp with its own last page turn, in Unix seconds.
        let row: Option<(String, Option<String>, f64, i64, i64)> = sqlx::query_as(
            "SELECT device_id, device_label, progress, page, \
                    CAST(strftime('%s', updated_at) AS INTEGER) AS ts \
             FROM reading_progress \
             WHERE book_id = ? AND user_id = ? AND device_id NOT LIKE 'koreader:%' \
               AND unit = ? AND page >= 1 AND progress IS NOT NULL \
               AND strftime('%s', updated_at) IS NOT NULL \
             ORDER BY ts DESC, device_id LIMIT 1",
        )
        .bind(&book_id)
        .bind(&user.id)
        .bind(unit)
        .fetch_optional(&state.db)
        .await?;
        let Some((device_id, label, percentage, page, timestamp)) = row else {
            continue;
        };
        if best
            .as_ref()
            .is_some_and(|(b, ..)| b.timestamp >= timestamp)
        {
            continue;
        }
        let label = label
            .map(|l| l.trim().to_string())
            .filter(|l| !l.is_empty())
            .unwrap_or_else(|| "another device".into());
        let report = Reported {
            document: document.to_string(),
            progress: String::new(), // converted below, for the winner only
            percentage: if percentage.is_finite() {
                percentage.clamp(0.0, 1.0)
            } else {
                0.0
            },
            device: format!("Vellum on {label}")
                .chars()
                .take(MAX_DEVICE)
                .collect(),
            device_id: vellum_device_id(&device_id),
            timestamp,
        };
        best = Some((report, format, path, page));
    }
    let Some((mut report, format, path, page)) = best else {
        return Ok(None);
    };
    let fragments = if format == "epub" {
        // An EPUB that cannot be read here gets nothing: an xpointer the server
        // cannot vouch for is worse than none.
        let Some(fragments) = docfragments(state, &path).await else {
            return Ok(None);
        };
        Some(fragments)
    } else {
        None
    };
    let unit = app_unit(&format).unwrap_or_default();
    let Some(progress) = progress_in_koreader_terms(&format, page, unit, fragments.as_deref())
    else {
        return Ok(None);
    };
    report.progress = progress;
    Ok(Some(report))
}

/// [`crate::blobs::epub_docfragments`] for a stored file, off the async
/// runtime. None when the file is missing on disk or is not a readable EPUB.
async fn docfragments(state: &AppState, rel: &str) -> Option<Vec<usize>> {
    let path = crate::blobs::blob_file_path(state, rel).ok()?;
    tokio::task::spawn_blocking(move || crate::blobs::epub_docfragments(&path))
        .await
        .ok()
        .flatten()
}

// ---- into the reading-position channel ---------------------------------------

/// What KOReader's opaque `progress` means in the app's terms: `(page, unit)`,
/// 1-based like the app's own column, or nothing when it cannot be read.
///
/// - A PDF (KOReader's *paging* mode) reports the page number itself.
/// - An EPUB (*rolling* mode) reports an xpointer such as
///   `/body/DocFragment[12]/body/div/p[3]/text().42`. `DocFragment[N]` is the
///   N-th spine item, 1-based. That is the app's chapter N too, unless the app
///   skipped a spine item before it — `fragments` (the app's chapters' fragment
///   indices, [`crate::blobs::epub_docfragments`]) says; without it, N. A
///   fragment the app has no chapter for maps to no page.
///
/// Anything else maps to no page, and the app still shows the percentage.
pub fn position_in_app_terms(
    format: &str,
    progress: &str,
    fragments: Option<&[usize]>,
) -> (Option<i64>, Option<&'static str>) {
    let progress = progress.trim();
    match format {
        "pdf" => match progress.parse::<i64>() {
            Ok(page) if page >= 1 => (Some(page), Some("page")),
            _ => (None, None),
        },
        "epub" => {
            let chapter = progress
                .strip_prefix("/body/DocFragment[")
                .and_then(|rest| rest.split_once(']'))
                .and_then(|(n, _)| n.parse::<i64>().ok())
                .filter(|n| *n >= 1)
                .and_then(|n| match fragments {
                    None => Some(n),
                    Some(f) => f
                        .iter()
                        .position(|&frag| i64::try_from(frag) == Ok(n))
                        .and_then(|i| i64::try_from(i + 1).ok()),
                });
            match chapter {
                Some(n) => (Some(n), Some("chapter")),
                None => (None, None),
            }
        }
        _ => (None, None),
    }
}

/// The `reading_progress.device_id` a KOReader device writes under — prefixed,
/// so it can never collide with an app install's id, nor be dropped when the
/// app turns its own position sync off (`reading::forget_device`).
pub fn mirror_device_id(device_id: &str) -> String {
    format!("koreader:{device_id}")
}

/// Write `report` into `reading_progress` for every book the caller can see
/// that holds the document's file. Returns how many rows were written.
async fn mirror(state: &AppState, user: &AuthUser, report: &Reported) -> KoResult<usize> {
    let mut books = linked_books(state, &report.document).await?;
    if books.is_empty() {
        // Maybe a file that predates the digest table, not yet indexed.
        index_missing(state, BACKFILL_ON_REQUEST).await;
        books = linked_books(state, &report.document).await?;
    }
    let mut written = 0;
    for (book_id, format, path) in books {
        if book_access(state, user, &book_id).await?.can_view() {
            write_mirror(state, &user.id, &book_id, &format, &path, report).await?;
            written += 1;
        }
    }
    Ok(written)
}

/// `(book_id, format, path)` of a file with this digest, one per book. (The
/// same file twice in one book has one format and one blob path anyway: the
/// store is content-addressed.)
async fn linked_books(state: &AppState, document: &str) -> KoResult<Vec<(String, String, String)>> {
    Ok(sqlx::query_as(
        "SELECT bf.book_id, MIN(bf.format), MIN(bf.path) FROM koreader_file_digest d \
         JOIN book_file bf ON bf.id = d.file_id \
         WHERE d.digest = ? GROUP BY bf.book_id ORDER BY bf.book_id",
    )
    .bind(document)
    .fetch_all(&state.db)
    .await?)
}

async fn write_mirror(
    state: &AppState,
    user_id: &str,
    book_id: &str,
    format: &str,
    path: &str,
    report: &Reported,
) -> KoResult<()> {
    let fragments = if format == "epub" {
        docfragments(state, path).await
    } else {
        None
    };
    let (page, unit) = position_in_app_terms(format, &report.progress, fragments.as_deref());
    sqlx::query(
        "INSERT INTO reading_progress \
            (book_id, user_id, device_id, device_label, progress, page, unit, scroll, \
             updated_at, synced_at) \
         VALUES (?, ?, ?, ?, ?, ?, ?, NULL, datetime(?, 'unixepoch'), datetime('now')) \
         ON CONFLICT(book_id, user_id, device_id) DO UPDATE SET \
            device_label = excluded.device_label, progress = excluded.progress, \
            page = excluded.page, unit = excluded.unit, scroll = NULL, \
            updated_at = excluded.updated_at, synced_at = datetime('now')",
    )
    .bind(book_id)
    .bind(user_id)
    .bind(mirror_device_id(&report.device_id))
    .bind(format!("KOReader on {}", report.device))
    .bind(report.percentage)
    .bind(page)
    .bind(unit)
    .bind(report.timestamp)
    .execute(&state.db)
    .await?;
    Ok(())
}

// ---- digests of stored files ---------------------------------------------------

/// How many unindexed files a kosync request may digest before answering.
/// KOReader gives a progress call only a few seconds; the startup backfill and
/// the upload hook do the bulk, this only catches stragglers.
const BACKFILL_ON_REQUEST: i64 = 200;

/// Digest one stored file and link any KOReader positions already waiting for
/// it. Called after an upload; a failure only means the lazy path does it later.
pub(crate) async fn index_file(state: &AppState, file_id: &str, path: std::path::PathBuf) {
    let Ok(Ok(digest)) = tokio::task::spawn_blocking(move || partial_md5_file(&path)).await else {
        return;
    };
    if store_digest(state, file_id, &digest).await.is_ok() {
        let _ = link_waiting(state, file_id, &digest).await;
    }
}

async fn store_digest(state: &AppState, file_id: &str, digest: &str) -> Result<(), sqlx::Error> {
    // The file may have been deleted while it was being read; the foreign key
    // then refuses the row, which is the right outcome.
    sqlx::query(
        "INSERT INTO koreader_file_digest (file_id, digest) VALUES (?, ?) \
         ON CONFLICT(file_id) DO UPDATE SET digest = excluded.digest",
    )
    .bind(file_id)
    .bind(digest)
    .execute(&state.db)
    .await?;
    Ok(())
}

/// Positions recorded before this file existed here, now given a book. Each is
/// checked against *its* owner's access, never the uploader's: uploading a
/// file must not publish someone's reading into a book they cannot see.
async fn link_waiting(state: &AppState, file_id: &str, digest: &str) -> KoResult<()> {
    let target: Option<(String, String, String)> =
        sqlx::query_as("SELECT book_id, format, path FROM book_file WHERE id = ?")
            .bind(file_id)
            .fetch_optional(&state.db)
            .await?;
    let Some((book_id, format, path)) = target else {
        return Ok(());
    };
    let waiting: Vec<(String, String, f64, String, String, i64)> = sqlx::query_as(
        "SELECT user_id, progress, percentage, device, device_id, timestamp \
         FROM koreader_progress WHERE document = ?",
    )
    .bind(digest)
    .fetch_all(&state.db)
    .await?;
    for (user_id, progress, percentage, device, device_id, ts) in waiting {
        let user: AuthUser =
            sqlx::query_as("SELECT id, email, display_name, is_master FROM app_user WHERE id = ?")
                .bind(&user_id)
                .fetch_one(&state.db)
                .await?;
        if !book_access(state, &user, &book_id).await?.can_view() {
            continue;
        }
        let report = Reported {
            document: digest.to_string(),
            progress,
            percentage,
            device,
            device_id,
            timestamp: ts,
        };
        write_mirror(state, &user.id, &book_id, &format, &path, &report).await?;
    }
    Ok(())
}

/// Digest up to `limit` stored files that have none yet (`limit < 0`: all).
/// Returns how many were indexed. Files missing on disk are skipped and stay
/// unindexed, so a restored blob is picked up later.
pub async fn index_missing(state: &AppState, limit: i64) -> u64 {
    let rows: Vec<(String, String)> = match sqlx::query_as(
        "SELECT bf.id, bf.path FROM book_file bf \
         LEFT JOIN koreader_file_digest d ON d.file_id = bf.id \
         WHERE d.file_id IS NULL AND bf.format NOT IN ('m4b', 'm4a', 'mp3') \
         ORDER BY bf.added_at LIMIT ?",
    )
    .bind(limit)
    .fetch_all(&state.db)
    .await
    {
        Ok(rows) => rows,
        Err(e) => {
            tracing::warn!("koreader: listing unindexed files failed: {e}");
            return 0;
        }
    };
    let mut indexed = 0;
    for (file_id, rel) in rows {
        let Ok(path) = crate::blobs::blob_file_path(state, &rel) else {
            continue;
        };
        let Ok(Ok(digest)) = tokio::task::spawn_blocking(move || partial_md5_file(&path)).await
        else {
            continue;
        };
        if store_digest(state, &file_id, &digest).await.is_ok() {
            let _ = link_waiting(state, &file_id, &digest).await;
            indexed += 1;
        }
    }
    indexed
}

/// Forget everything KOReader recorded for `user`: the verbatim reports and
/// their mirrored rows. Behind `DELETE /api/mine/koreader`.
pub(crate) async fn forget(state: &AppState, user_id: &str) -> Result<u64, sqlx::Error> {
    let reports = sqlx::query("DELETE FROM koreader_progress WHERE user_id = ?")
        .bind(user_id)
        .execute(&state.db)
        .await?
        .rows_affected();
    sqlx::query("DELETE FROM reading_progress WHERE user_id = ? AND device_id LIKE 'koreader:%'")
        .bind(user_id)
        .execute(&state.db)
        .await?;
    Ok(reports)
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::io::Cursor;

    /// Deterministic, non-repeating-at-sample-offsets content.
    fn content(n: usize) -> Vec<u8> {
        (0..n).map(|j| ((j * 31 + 7) % 251) as u8).collect()
    }

    /// Vectors from a line-by-line Python port of `util.partialMD5` that models
    /// LuaJIT's 32-bit `bit.lshift` explicitly (not from this code). Sizes sit
    /// on the boundaries that matter: empty, under/at/over the first sample,
    /// a sample landing exactly on the end (1 MiB), and one byte past it.
    #[test]
    fn partial_md5_matches_the_reference_algorithm() {
        for (size, expected) in [
            (0, "d41d8cd98f00b204e9800998ecf8427e"),
            (1, "89e74e640b8c46257a29de0616794d5d"),
            (1023, "184b34b08bbb6b06f914e59a579c2a7b"),
            (1024, "5121b74d11d0ad611a246b4137993844"),
            (1025, "35b02546e34868e7b75dab8c43d47c36"),
            (4096, "8ff2b3ad1b7689199548d9ce054ade39"),
            (5000, "e9b23960f33568cd50442e8f305853c3"),
            (300_000, "3d87fe2dd28ddc7895ae5e290bfa539e"),
            (1_048_576, "3d87fe2dd28ddc7895ae5e290bfa539e"),
            (1_048_577, "786211a95054ac0cec32c0535d32846b"),
            (3_000_000, "951d6ad62a386c5d5e49f4c898e5c6c2"),
        ] {
            let got = partial_md5(&mut Cursor::new(content(size))).unwrap();
            assert_eq!(got, expected, "size {size}");
        }
    }

    #[test]
    fn a_small_file_is_just_its_md5() {
        // Under 1 KiB, the one sample is the whole file.
        assert_eq!(
            partial_md5(&mut Cursor::new(b"hello".to_vec())).unwrap(),
            "5d41402abc4b2a76b9719d911017c592"
        );
    }

    #[test]
    fn the_first_sample_is_offset_zero_not_256() {
        // Changing byte 0 must change the digest (LuaJIT's wrapped shift).
        let base = content(10_000);
        let mut at0 = base.clone();
        at0[0] ^= 1;
        let mut at3000 = base.clone();
        at3000[3000] ^= 1; // between the 1 KiB sample's end (2 KiB) and 4 KiB
        let d = |v: &Vec<u8>| partial_md5(&mut Cursor::new(v.clone())).unwrap();
        assert_ne!(d(&base), d(&at0));
        assert_eq!(d(&base), d(&at3000), "unsampled bytes do not count");
    }

    #[test]
    fn keys_cover_the_ways_a_secret_is_typed_and_nothing_else() {
        let secret = "k3m9-x2qa-0011-abcd-efgh-jkmn";
        let spellings = key_spellings(secret);
        for typed in [
            "k3m9-x2qa-0011-abcd-efgh-jkmn",
            "k3m9x2qa0011abcdefghjkmn",
            "k3m9 x2qa 0011 abcd efgh jkmn",
            "K3M9-X2QA-0011-ABCD-EFGH-JKMN",
            "K3M9X2QA0011ABCDEFGHJKMN",
        ] {
            assert!(spellings.iter().any(|s| s == typed), "{typed}");
        }
        assert_eq!(spellings.len(), 6);
        // Known MD5s of the two common spellings (computed independently).
        assert_eq!(
            md5_hex("k3m9-x2qa-0011-abcd-efgh-jkmn"),
            "4c6a40fac27ee6daa03c560e65e67bdc"
        );
        assert_eq!(
            md5_hex("k3m9x2qa0011abcdefghjkmn"),
            "fa6f09168f456224f7839aafb0fd46ba"
        );
        // The stored value is neither the secret nor its MD5.
        let stored = key_hash(&md5_hex(secret));
        assert_ne!(stored, md5_hex(secret));
        assert_eq!(stored, key_hash(&md5_hex(secret).to_uppercase()));
    }

    #[test]
    fn progress_converts_into_the_apps_units() {
        assert_eq!(
            position_in_app_terms("pdf", "214", None),
            (Some(214), Some("page"))
        );
        assert_eq!(
            position_in_app_terms("pdf", " 7 ", None),
            (Some(7), Some("page"))
        );
        assert_eq!(position_in_app_terms("pdf", "0", None), (None, None));
        assert_eq!(
            position_in_app_terms("pdf", "/body/DocFragment[3]", None),
            (None, None)
        );
        assert_eq!(
            position_in_app_terms(
                "epub",
                "/body/DocFragment[12]/body/div/p[3]/text().42",
                None
            ),
            (Some(12), Some("chapter"))
        );
        assert_eq!(
            position_in_app_terms("epub", "/body/DocFragment[1].0", None),
            (Some(1), Some("chapter"))
        );
        assert_eq!(
            position_in_app_terms("epub", "#_doc_fragment_3", None),
            (None, None)
        );
        assert_eq!(position_in_app_terms("epub", "42", None), (None, None));
        assert_eq!(position_in_app_terms("cbz", "4", None), (None, None));

        // The app skipped spine item 2 (its file is missing): fragments 1, 3, 4
        // are its chapters 1, 2, 3, and fragment 2 is no chapter of the app's.
        let skipped: &[usize] = &[1, 3, 4];
        let at = |xp: &str| position_in_app_terms("epub", xp, Some(skipped)).0;
        assert_eq!(at("/body/DocFragment[1]/body/p[2]/text().4"), Some(1));
        assert_eq!(at("/body/DocFragment[2]/body/p[1]"), None);
        assert_eq!(at("/body/DocFragment[3]"), Some(2));
        assert_eq!(at("/body/DocFragment[4].0"), Some(3));
        assert_eq!(at("/body/DocFragment[5]"), None);
    }

    #[test]
    fn the_apps_position_converts_into_koreaders() {
        let identity: &[usize] = &[1, 2, 3, 4];
        let to = |format, page, unit, f| progress_in_koreader_terms(format, page, unit, f);
        assert_eq!(to("pdf", 214, "page", None).as_deref(), Some("214"));
        assert_eq!(to("pdf", 0, "page", None), None);
        assert_eq!(to("pdf", 3, "chapter", None), None, "units must match");
        assert_eq!(
            to("epub", 1, "chapter", Some(identity)).as_deref(),
            Some("/body/DocFragment[1]"),
            "the first spine item"
        );
        assert_eq!(
            to("epub", 4, "chapter", Some(identity)).as_deref(),
            Some("/body/DocFragment[4]"),
            "the last"
        );
        assert_eq!(
            to("epub", 9, "chapter", Some(identity)).as_deref(),
            Some("/body/DocFragment[4]"),
            "past the end is clamped, as the app's reader does"
        );
        assert_eq!(
            to("epub", 2, "chapter", Some(&[1, 3, 4])).as_deref(),
            Some("/body/DocFragment[3]"),
            "a spine item the app skipped still has its DocFragment"
        );
        assert_eq!(to("epub", 2, "chapter", None), None, "no map, no guess");
        assert_eq!(to("epub", 2, "chapter", Some(&[])), None);
        assert_eq!(to("epub", 0, "chapter", Some(identity)), None);
        assert_eq!(to("epub", 2, "page", Some(identity)), None);
        assert_eq!(to("cbz", 2, "page", None), None);

        // What is sent reads back as the same chapter (a KOReader that syncs
        // straight back before turning a page reports our xpointer).
        for page in 1..=3 {
            let xp = to("epub", page, "chapter", Some(&[1, 3, 4])).unwrap();
            assert_eq!(
                position_in_app_terms("epub", &xp, Some(&[1, 3, 4])),
                (Some(page), Some("chapter"))
            );
        }
    }

    #[test]
    fn a_report_is_validated_like_the_reference_server_does() {
        let ok = parse_report(
            br#"{"document":"0123abcd","progress":"/body/DocFragment[2]","percentage":0.43,
                "device":"Kobo Libra 2","device_id":"ABC123"}"#,
            100,
        )
        .unwrap();
        assert_eq!(ok.percentage, 0.43);
        assert_eq!(ok.device_id, "ABC123");
        assert_eq!(ok.timestamp, 100);

        // A page as a number, no device_id: both accepted.
        let num = parse_report(
            br#"{"document":"d","progress":12,"percentage":1.5,"device":"Kindle"}"#,
            1,
        )
        .unwrap();
        assert_eq!(num.progress, "12");
        assert_eq!(num.percentage, 1.0, "clamped");
        assert_eq!(num.device_id, "Kindle");

        let code = |body: &[u8]| match parse_report(body, 0) {
            Err(KoError::InvalidFields(_)) => 2003,
            Err(KoError::DocumentMissing) => 2004,
            Err(KoError::DocumentNotServable) => 2007,
            other => panic!("unexpected {other:?}"),
        };
        assert_eq!(code(b"not json"), 2003);
        assert_eq!(
            code(br#"{"progress":"1","percentage":0.1,"device":"x"}"#),
            2004
        );
        assert_eq!(
            code(br#"{"document":"a:b","progress":"1","percentage":0.1,"device":"x"}"#),
            2007
        );
        assert_eq!(
            code(br#"{"document":"a","percentage":0.1,"device":"x"}"#),
            2003
        );
        assert_eq!(
            code(br#"{"document":"a","progress":"1","device":"x"}"#),
            2003
        );
        assert_eq!(
            code(br#"{"document":"a","progress":"1","percentage":0.1}"#),
            2003
        );
    }
}
