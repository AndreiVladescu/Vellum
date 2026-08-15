use argon2::Argon2;
use argon2::password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use axum::Json;
use axum::extract::{FromRequestParts, Path, State};
use axum::http::HeaderMap;
use axum::http::header::AUTHORIZATION;
use axum::http::request::Parts;
use rand_core::{OsRng, RngCore};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::AppState;
use crate::error::{AppError, AppResult};

/// A precomputed Argon2 hash used only to spend the same verification time when
/// an email doesn't exist, so login/basic-auth timing can't confirm which
/// emails have accounts.
static DUMMY_HASH: std::sync::LazyLock<String> =
    std::sync::LazyLock::new(|| hash_password("timing-equalizer-dummy").unwrap());

/// Optional operator-set secret (`VELLUM_BOOTSTRAP_TOKEN`) that the very first
/// (master) registration must present. When unset, first-registration is open
/// as before; when set, it closes the "whoever hits the port first becomes
/// master" window on a freshly exposed instance. See docs/SECURITY_AUDIT.md (M3).
static BOOTSTRAP_TOKEN: std::sync::LazyLock<Option<String>> = std::sync::LazyLock::new(|| {
    std::env::var("VELLUM_BOOTSTRAP_TOKEN")
        .ok()
        .filter(|s| !s.is_empty())
});

/// Enforce the bootstrap token when one is configured. Compares the SHA-256 of
/// each side so the equality check runs over fixed-length hex (a timing leak
/// there reveals nothing about the secret).
fn require_bootstrap_token(provided: Option<&str>) -> AppResult<()> {
    let Some(expected) = &*BOOTSTRAP_TOKEN else {
        return Ok(());
    };
    match provided {
        Some(p) if sha256_hex(p) == sha256_hex(expected) => Ok(()),
        _ => Err(AppError::Forbidden(
            "registration requires the bootstrap token".into(),
        )),
    }
}

/// The authenticated caller, extracted from the `Authorization: Bearer <token>`
/// header. Any handler that takes an `AuthUser` argument requires a valid login.
#[derive(Debug, Clone, Serialize, sqlx::FromRow)]
pub struct AuthUser {
    pub id: String,
    pub email: String,
    pub display_name: String,
    pub is_master: bool,
}

impl FromRequestParts<AppState> for AuthUser {
    type Rejection = AppError;

    async fn from_request_parts(
        parts: &mut Parts,
        state: &AppState,
    ) -> Result<Self, Self::Rejection> {
        // Bearer for the app; Basic so OPDS e-readers (and file downloads) work.
        // The session token is *only* ever accepted from the Authorization
        // header — never a `?token=` query param, so it can't leak into
        // reverse-proxy access logs or browser history. The web console loads
        // authenticated blobs (covers, downloads) with an `Authorization: Bearer`
        // fetch into an object URL rather than a bare `<img src>`/`<a href>`.
        if let Some(header) = parts
            .headers
            .get(AUTHORIZATION)
            .and_then(|v| v.to_str().ok())
        {
            return if let Some(token) = header.strip_prefix("Bearer ") {
                user_from_token(state, token).await
            } else if let Some(encoded) = header.strip_prefix("Basic ") {
                user_from_basic(state, encoded).await
            } else {
                Err(AppError::Unauthorized(
                    "unsupported authorization scheme".into(),
                ))
            };
        }
        Err(AppError::Unauthorized("missing credentials".into()))
    }
}

/// The caller's IP for per-client rate limiting. Prefers the first hop of
/// `X-Forwarded-For` (DESIGN mandates a reverse proxy), falling back to the
/// direct socket address (present when the server runs with
/// `into_make_service_with_connect_info`), then a constant. Never fails, so it
/// composes with handlers and works in tests without connect info.
pub struct ClientKey(pub String);

impl<S: Sync> FromRequestParts<S> for ClientKey {
    type Rejection = std::convert::Infallible;

    async fn from_request_parts(parts: &mut Parts, _state: &S) -> Result<Self, Self::Rejection> {
        let forwarded = parts
            .headers
            .get("x-forwarded-for")
            .and_then(|v| v.to_str().ok())
            .and_then(|s| s.split(',').next())
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty());
        let ip = forwarded
            .or_else(|| {
                parts
                    .extensions
                    .get::<axum::extract::ConnectInfo<std::net::SocketAddr>>()
                    .map(|c| c.0.ip().to_string())
            })
            .unwrap_or_else(|| "unknown".to_string());
        Ok(ClientKey(ip))
    }
}

async fn user_from_token(state: &AppState, token: &str) -> AppResult<AuthUser> {
    let hash = sha256_hex(token);
    let user = sqlx::query_as::<_, AuthUser>(
        "SELECT u.id, u.email, u.display_name, u.is_master \
         FROM session s JOIN app_user u ON u.id = s.user_id \
         WHERE s.token_hash = ? AND s.expires_at > datetime('now')",
    )
    .bind(&hash)
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::Unauthorized("invalid or expired token".into()))?;

    // Sliding expiry: once a live session enters its final 15 days, push its
    // expiry back to 30 days out. The WHERE clause means at most one write per
    // request, and only inside the renewal window — a daily-use app never hits
    // the day-31 wall. Fire-and-forget: a failed renewal just retries next time.
    let _ = sqlx::query(
        "UPDATE session SET expires_at = datetime('now', '+30 days') \
         WHERE token_hash = ? AND expires_at < datetime('now', '+15 days')",
    )
    .bind(&hash)
    .execute(&state.db)
    .await;

    Ok(user)
}

async fn user_from_basic(state: &AppState, encoded: &str) -> AppResult<AuthUser> {
    use base64::Engine;
    let decoded = base64::engine::general_purpose::STANDARD
        .decode(encoded)
        .ok()
        .and_then(|b| String::from_utf8(b).ok())
        .ok_or_else(|| AppError::Unauthorized("malformed basic credentials".into()))?;
    let (email, password) = decoded
        .split_once(':')
        .ok_or_else(|| AppError::Unauthorized("malformed basic credentials".into()))?;

    // Bound work before Argon2, so an over-long Basic password isn't free CPU.
    check_password_length(password)?;
    let key = email.trim().to_lowercase();
    if !state.throttle.allowed(&key) {
        return Err(AppError::TooManyRequests(
            "too many failed attempts — try again later".into(),
        ));
    }

    let row = sqlx::query_as::<_, (String, String, String, bool, String)>(
        "SELECT id, email, display_name, is_master, password_hash \
         FROM app_user WHERE email = ?",
    )
    .bind(&key)
    .fetch_optional(&state.db)
    .await?;

    let Some((id, email, display_name, is_master, password_hash)) = row else {
        let _ = verify_password(password, &DUMMY_HASH); // equalize timing
        state.throttle.record_failure(&key);
        return Err(AppError::Unauthorized("invalid email or password".into()));
    };
    // Fast path: skip Argon2 when this exact password was verified recently.
    // Otherwise run the full verify and, on success, prime the cache.
    let ok = state.basic_cache.hit(&key, password) || {
        let verified = verify_password(password, &password_hash);
        if verified {
            state.basic_cache.store(&key, password);
        }
        verified
    };
    if !ok {
        state.throttle.record_failure(&key);
        state.basic_cache.forget(&key);
        return Err(AppError::Unauthorized("invalid email or password".into()));
    }
    state.throttle.clear(&key);
    Ok(AuthUser {
        id,
        email,
        display_name,
        is_master,
    })
}

/// How long a successful Basic-auth verification is trusted before Argon2 runs
/// again. Short enough that a (future) password change self-heals quickly.
const BASIC_CACHE_TTL: std::time::Duration = std::time::Duration::from_secs(300);

/// A random secret generated once per process, used to key the Basic-auth
/// cache's password fingerprints. It never leaves the process and is never
/// persisted, so a cached value can't be lifted (via a log, a partial leak, or
/// a swapped page) and cracked offline into the plaintext password.
static CACHE_KEY: std::sync::LazyLock<[u8; 32]> = std::sync::LazyLock::new(|| {
    let mut key = [0u8; 32];
    OsRng.fill_bytes(&mut key);
    key
});

/// A keyed fingerprint of `password` under [`CACHE_KEY`] — `sha256(key‖password)`.
/// Used only to recognise the *same* password within the process (not as a MAC),
/// so length-extension is irrelevant; the point is that without the secret key
/// the value is not precomputable, i.e. useless for offline cracking.
fn cache_fingerprint(password: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(*CACHE_KEY);
    hasher.update(password.as_bytes());
    hex::encode(hasher.finalize())
}

/// Caches recent successful Basic-auth verifications so an e-reader that sends
/// `Authorization: Basic` on *every* OPDS request doesn't cost an Argon2 verify
/// (~10²ms of CPU) each time — which is both slow and a free CPU-amplification
/// vector. Keyed by lowercase email → (keyed fingerprint of the password, when
/// verified). The stored fingerprint is salted by a per-process secret
/// ([`cache_fingerprint`]), so it can't be cracked offline if it ever leaks.
#[derive(Default)]
pub struct BasicAuthCache {
    inner: std::sync::Mutex<std::collections::HashMap<String, (String, std::time::Instant)>>,
}

impl BasicAuthCache {
    /// True when `email` was verified within the TTL with this exact password.
    /// Drops the entry lazily when it has expired, so the map can't outgrow the
    /// user count.
    fn hit(&self, email: &str, password: &str) -> bool {
        let mut map = self.inner.lock().unwrap();
        match map.get(email) {
            Some((fp, at)) if at.elapsed() < BASIC_CACHE_TTL => *fp == cache_fingerprint(password),
            Some(_) => {
                map.remove(email);
                false
            }
            None => false,
        }
    }

    fn store(&self, email: &str, password: &str) {
        self.inner.lock().unwrap().insert(
            email.to_string(),
            (cache_fingerprint(password), std::time::Instant::now()),
        );
    }

    fn forget(&self, email: &str) {
        self.inner.lock().unwrap().remove(email);
    }
}

/// Rejects non-master callers — used to guard administrative endpoints.
pub fn require_master(user: &AuthUser) -> AppResult<()> {
    if user.is_master {
        Ok(())
    } else {
        Err(AppError::Forbidden("master only".into()))
    }
}

pub fn hash_password(password: &str) -> AppResult<String> {
    let salt = SaltString::generate(&mut OsRng);
    Argon2::default()
        .hash_password(password.as_bytes(), &salt)
        .map(|h| h.to_string())
        .map_err(|e| AppError::Internal(e.to_string()))
}

pub(crate) fn verify_password(password: &str, hash: &str) -> bool {
    PasswordHash::new(hash)
        .map(|parsed| {
            Argon2::default()
                .verify_password(password.as_bytes(), &parsed)
                .is_ok()
        })
        .unwrap_or(false)
}

/// A fresh opaque session token (returned to the client once).
/// The invite-token minter (plan 5 #31 stage 3), same generator as sessions and
/// resets — one source of randomness, so all three have the same strength.
pub fn new_token_for_invite() -> String {
    new_token()
}

pub(crate) fn new_token() -> String {
    let mut bytes = [0u8; 32];
    OsRng.fill_bytes(&mut bytes);
    hex::encode(bytes)
}

pub fn sha256_hex(input: &str) -> String {
    let mut hasher = Sha256::new();
    hasher.update(input.as_bytes());
    hex::encode(hasher.finalize())
}

// ---- request / response bodies -------------------------------------------

#[derive(Deserialize)]
pub struct RegisterInput {
    pub email: String,
    pub display_name: String,
    pub password: String,
    /// Required only for the first registration and only when the operator set
    /// `VELLUM_BOOTSTRAP_TOKEN`; ignored otherwise (and by `create_user`).
    #[serde(default)]
    pub bootstrap_token: Option<String>,
}

#[derive(Deserialize)]
pub struct LoginInput {
    pub email: String,
    pub password: String,
}

#[derive(Serialize)]
pub struct AuthResponse {
    pub token: String,
    pub user: AuthUser,
}

#[derive(Serialize)]
pub struct RegistrationState {
    /// True only while the server has no master — the window in which
    /// [`register`] can succeed.
    pub open: bool,
    /// Whether that first registration must also present the operator's
    /// `VELLUM_BOOTSTRAP_TOKEN`, so a form can ask for it up front instead of
    /// being refused after the fact. Reported only while registration is open:
    /// a closed server says nothing about how its operator configured it.
    pub bootstrap_token_required: bool,
}

// ---- handlers -------------------------------------------------------------

/// `GET /api/auth/registration` — can a first account still be created here?
///
/// Exists so a client that has never had an account can *offer* the right form
/// instead of guessing: the console showed a login box on a server with nobody
/// to log in as, which is a dead end for anyone who doesn't know the app or
/// `curl` is the way in.
///
/// Unauthenticated, and deliberately unrevealing: it answers "open" only in the
/// state anyone can already detect by POSTing to [`register`] and reading the
/// error, and once a master exists the answer is a permanent "closed" that says
/// nothing about who the accounts belong to or how many there are.
pub async fn registration_state(
    State(state): State<AppState>,
) -> AppResult<Json<RegistrationState>> {
    let master_exists: bool =
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM app_user WHERE is_master = 1)")
            .fetch_one(&state.db)
            .await?;
    Ok(Json(RegistrationState {
        open: !master_exists,
        bootstrap_token_required: !master_exists && BOOTSTRAP_TOKEN.is_some(),
    }))
}

/// Bootstraps the library: the first account created becomes the master. Once a
/// master exists this is closed and the master provisions further accounts.
pub async fn register(
    State(state): State<AppState>,
    Json(input): Json<RegisterInput>,
) -> AppResult<Json<AuthResponse>> {
    validate_credentials(&input.email, &input.password)?;
    require_bootstrap_token(input.bootstrap_token.as_deref())?;

    // Check "is there a master yet?" and insert the first user in one
    // transaction, so two simultaneous first-registrations can't both win.
    let mut tx = crate::write_tx(&state.db).await?;
    let master_exists: bool =
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM app_user WHERE is_master = 1)")
            .fetch_one(&mut *tx)
            .await?;
    if master_exists {
        return Err(AppError::Forbidden(
            "registration is closed — ask the library owner to create your account".into(),
        ));
    }

    let user = insert_user(
        &mut *tx,
        &input.email,
        &input.display_name,
        &input.password,
        true,
    )
    .await?;
    tx.commit().await?;

    let token = issue_token(&state, &user.id).await?;
    Ok(Json(AuthResponse { token, user }))
}

pub async fn login(
    State(state): State<AppState>,
    client: ClientKey,
    Json(input): Json<LoginInput>,
) -> AppResult<Json<AuthResponse>> {
    // Bound work before Argon2 runs, even for a wrong password.
    check_password_length(&input.password)?;
    let key = input.email.trim().to_lowercase();
    // Throttle failed logins per email *and* per source IP, so a password spray
    // across many distinct emails from one host is also capped (the email-only
    // limiter wouldn't catch it). See docs/SECURITY_AUDIT.md (L4). Reuses the
    // existing failure limiter under a namespaced key — no new shared state.
    let ip_key = format!("ip:{}", client.0);
    if !state.throttle.allowed(&key) || !state.throttle.allowed(&ip_key) {
        return Err(AppError::TooManyRequests(
            "too many failed attempts — try again later".into(),
        ));
    }

    let row = sqlx::query_as::<_, (String, String, String, bool, String)>(
        "SELECT id, email, display_name, is_master, password_hash \
         FROM app_user WHERE email = ?",
    )
    .bind(&key)
    .fetch_optional(&state.db)
    .await?;

    let Some((id, email, display_name, is_master, password_hash)) = row else {
        let _ = verify_password(&input.password, &DUMMY_HASH); // equalize timing
        state.throttle.record_failure(&key);
        state.throttle.record_failure(&ip_key);
        return Err(AppError::Unauthorized("invalid email or password".into()));
    };
    if !verify_password(&input.password, &password_hash) {
        state.throttle.record_failure(&key);
        state.throttle.record_failure(&ip_key);
        return Err(AppError::Unauthorized("invalid email or password".into()));
    }
    state.throttle.clear(&key);
    state.throttle.clear(&ip_key);

    let user = AuthUser {
        id,
        email,
        display_name,
        is_master,
    };
    let token = issue_token(&state, &user.id).await?;
    Ok(Json(AuthResponse { token, user }))
}

pub async fn me(user: AuthUser) -> Json<AuthUser> {
    Json(user)
}

/// Invalidate the presented bearer session server-side (real logout). Succeeds
/// even if the token was already gone, so the client can always clear locally.
pub async fn logout(
    State(state): State<AppState>,
    headers: HeaderMap,
) -> AppResult<Json<serde_json::Value>> {
    let token = headers
        .get(AUTHORIZATION)
        .and_then(|v| v.to_str().ok())
        .and_then(|h| h.strip_prefix("Bearer "))
        .ok_or_else(|| AppError::Unauthorized("missing bearer token".into()))?;
    sqlx::query("DELETE FROM session WHERE token_hash = ?")
        .bind(sha256_hex(token))
        .execute(&state.db)
        .await?;
    Ok(Json(serde_json::json!({ "ok": true })))
}

/// Master-only: create a member account. Returns the new user (no token — they
/// log in themselves).
pub async fn create_user(
    State(state): State<AppState>,
    caller: AuthUser,
    Json(input): Json<RegisterInput>,
) -> AppResult<Json<AuthUser>> {
    require_master(&caller)?;
    validate_credentials(&input.email, &input.password)?;
    let user = insert_user(
        &state.db,
        &input.email,
        &input.display_name,
        &input.password,
        false,
    )
    .await?;
    crate::audit::record(
        &state,
        Some(&caller),
        "user.create",
        "user",
        &user.id,
        Some(&user.email),
    )
    .await;
    Ok(Json(user))
}

pub async fn list_users(
    State(state): State<AppState>,
    caller: AuthUser,
) -> AppResult<Json<Vec<AuthUser>>> {
    require_master(&caller)?;
    let users = sqlx::query_as::<_, AuthUser>(
        "SELECT id, email, display_name, is_master FROM app_user ORDER BY created_at",
    )
    .fetch_all(&state.db)
    .await?;
    Ok(Json(users))
}

/// Master-only: change whether an account is a master.
///
/// The library must never end up with **no** master — that is an account nobody
/// can administer, recoverable only by editing the database by hand. So a
/// demotion checks there is another one first, which also covers the obvious
/// mistake of demoting yourself.
pub async fn set_user_role(
    State(state): State<AppState>,
    caller: AuthUser,
    Path(id): Path<String>,
    Json(input): Json<RoleInput>,
) -> AppResult<Json<AuthUser>> {
    require_master(&caller)?;
    let target: Option<AuthUser> =
        sqlx::query_as("SELECT id, email, display_name, is_master FROM app_user WHERE id = ?")
            .bind(&id)
            .fetch_optional(&state.db)
            .await?;
    let target = target.ok_or_else(|| AppError::NotFound("no such user".into()))?;

    if target.is_master && !input.is_master {
        let others: i64 =
            sqlx::query_scalar("SELECT COUNT(*) FROM app_user WHERE is_master = 1 AND id != ?")
                .bind(&id)
                .fetch_one(&state.db)
                .await?;
        if others == 0 {
            return Err(AppError::BadRequest(
                "that is the only master — promote someone else first".into(),
            ));
        }
    }

    sqlx::query("UPDATE app_user SET is_master = ? WHERE id = ?")
        .bind(input.is_master)
        .bind(&id)
        .execute(&state.db)
        .await?;
    crate::audit::record(
        &state,
        Some(&caller),
        if input.is_master {
            "user.promote"
        } else {
            "user.demote"
        },
        "user",
        &id,
        Some(&target.email),
    )
    .await;

    Ok(Json(AuthUser {
        is_master: input.is_master,
        ..target
    }))
}

/// Master-only: remove an account.
///
/// Everything that account owns goes with it — `app_user`'s `ON DELETE CASCADE`
/// reaches its sessions, shares, invites, annotations, sittings, notes and
/// reading positions. The *books* stay: they belong to the library, and
/// `book.owner_id` is nullable precisely so removing a person does not delete
/// what they catalogued.
pub async fn delete_user(
    State(state): State<AppState>,
    caller: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    require_master(&caller)?;
    if id == caller.id {
        // Not a safety net so much as a sanity one: removing the account you
        // are authenticated as logs you out mid-request and, if you were the
        // last master, locks everyone out for good.
        return Err(AppError::BadRequest(
            "you cannot remove your own account".into(),
        ));
    }
    let target: Option<AuthUser> =
        sqlx::query_as("SELECT id, email, display_name, is_master FROM app_user WHERE id = ?")
            .bind(&id)
            .fetch_optional(&state.db)
            .await?;
    let target = target.ok_or_else(|| AppError::NotFound("no such user".into()))?;

    sqlx::query("DELETE FROM app_user WHERE id = ?")
        .bind(&id)
        .execute(&state.db)
        .await?;
    crate::audit::record(
        &state,
        Some(&caller),
        "user.delete",
        "user",
        &id,
        Some(&target.email),
    )
    .await;
    Ok(Json(serde_json::json!({ "ok": true })))
}

#[derive(Deserialize)]
pub struct RoleInput {
    pub is_master: bool,
}

// ---- helpers --------------------------------------------------------------

/// Upper bound on password length. Argon2 will happily hash a multi-megabyte
/// password; capping the length before hashing stops an unauthenticated caller
/// from spending the server's CPU on a giant password (the login/basic verify
/// paths hash whatever arrives, so the registration check alone can't protect
/// them). 128 bytes is far more than any real passphrase needs.
const MAX_PASSWORD_LEN: usize = 128;

/// Reject an over-long password before it reaches Argon2. Kept separate from
/// [`validate_credentials`] so the verify paths can call it without the
/// registration-time minimum-length / email checks.
pub(crate) fn check_password_length(password: &str) -> AppResult<()> {
    if password.len() > MAX_PASSWORD_LEN {
        return Err(AppError::BadRequest(format!(
            "password must be at most {MAX_PASSWORD_LEN} bytes"
        )));
    }
    Ok(())
}

fn validate_credentials(email: &str, password: &str) -> AppResult<()> {
    if !email.contains('@') {
        return Err(AppError::BadRequest("a valid email is required".into()));
    }
    if password.len() < 8 {
        return Err(AppError::BadRequest(
            "password must be at least 8 characters".into(),
        ));
    }
    check_password_length(password)
}

async fn insert_user<'e, E>(
    executor: E,
    email: &str,
    display_name: &str,
    password: &str,
    is_master: bool,
) -> AppResult<AuthUser>
where
    E: sqlx::Executor<'e, Database = sqlx::Sqlite>,
{
    let id = uuid::Uuid::new_v4().to_string();
    let email = email.trim().to_lowercase();
    let display_name = display_name.trim();
    let hash = hash_password(password)?;

    let result = sqlx::query(
        "INSERT INTO app_user (id, email, display_name, password_hash, is_master) \
         VALUES (?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(&email)
    .bind(display_name)
    .bind(&hash)
    .bind(is_master)
    .execute(executor)
    .await;

    if let Err(sqlx::Error::Database(e)) = &result
        && e.is_unique_violation()
    {
        return Err(AppError::Conflict(
            "that email is already registered".into(),
        ));
    }
    result?;

    Ok(AuthUser {
        id,
        email,
        display_name: display_name.to_string(),
        is_master,
    })
}

async fn issue_token(state: &AppState, user_id: &str) -> AppResult<String> {
    let token = new_token();
    sqlx::query(
        "INSERT INTO session (token_hash, user_id, expires_at) \
         VALUES (?, ?, datetime('now', '+30 days'))",
    )
    .bind(sha256_hex(&token))
    .bind(user_id)
    .execute(&state.db)
    .await?;
    Ok(token)
}

#[cfg(test)]
mod tests {
    use super::require_bootstrap_token;

    #[test]
    fn bootstrap_open_when_env_unset() {
        // VELLUM_BOOTSTRAP_TOKEN is unset in the test process, so first-time
        // registration stays open regardless of what the caller sends.
        assert!(require_bootstrap_token(None).is_ok());
        assert!(require_bootstrap_token(Some("anything")).is_ok());
    }
}

// ---- Password reset (plan 5 #31, stage 2) ----------------------------------

#[derive(Deserialize)]
pub struct ForgotInput {
    pub email: String,
}

/// `POST /api/auth/forgot` — start a password reset.
///
/// **Always answers the same thing.** Whether or not the address belongs to an
/// account, the response is "if that email exists, a link was sent". Anything
/// else turns this endpoint into an account-existence oracle, which is worse
/// than the inconvenience of an ambiguous message — and for a personal library
/// server, the account list is a list of people the owner knows.
///
/// Throttled per email *and* per source IP, reusing the login limiter, so the
/// endpoint can't be used to spray mail at one address or to enumerate many.
pub async fn forgot(
    State(state): State<AppState>,
    client: ClientKey,
    Json(input): Json<ForgotInput>,
) -> AppResult<Json<serde_json::Value>> {
    let email = input.email.trim().to_lowercase();
    let ip_key = format!("ip:{}", client.0);
    // Deliberately checked *before* looking anything up, so a throttled caller
    // can't tell a rate limit from a missing account either.
    if !state.throttle.allowed(&email) || !state.throttle.allowed(&ip_key) {
        return Err(AppError::TooManyRequests(
            "too many reset requests; try again later".into(),
        ));
    }
    state.throttle.record_failure(&email);
    state.throttle.record_failure(&ip_key);

    let ambiguous = Ok(Json(serde_json::json!({
        "status": "if that email exists, a link was sent"
    })));

    // No mailer means the feature is off; the app hides it via capabilities, so
    // reaching here at all is unusual. Still answer identically.
    let Some(mailer) = state.mailer.clone() else {
        return ambiguous;
    };

    let user: Option<(String, String)> =
        sqlx::query_as("SELECT id, display_name FROM app_user WHERE email = ?")
            .bind(&email)
            .fetch_optional(&state.db)
            .await?;
    let Some((user_id, display_name)) = user else {
        return ambiguous;
    };

    // One outstanding token per user: minting a new link silently invalidates
    // the old one, so a forwarded or leaked earlier email stops working.
    sqlx::query("DELETE FROM password_reset WHERE user_id = ?")
        .bind(&user_id)
        .execute(&state.db)
        .await?;

    let token = new_token();
    sqlx::query(
        "INSERT INTO password_reset (token_hash, user_id, expires_at) \
         VALUES (?, ?, datetime('now', '+1 hour'))",
    )
    .bind(sha256_hex(&token))
    .bind(&user_id)
    .execute(&state.db)
    .await?;

    let link = format!(
        "{}/reset/{token}",
        state.public_base_url.trim_end_matches('/')
    );
    let body = format!(
        "Hello {display_name},\n\n\
         Someone asked to reset the password for your Vellum account ({email}).\n\
         Open this link within the hour to choose a new one:\n\n\
         {link}\n\n\
         If it wasn't you, ignore this email — nothing has changed, and the link \n\
         expires on its own.\n"
    );
    // A send failure is logged inside the mailer and must not change the answer:
    // "we couldn't email you" would leak that the address exists.
    let _ = mailer
        .send(&email, "Reset your Vellum password", &body)
        .await;
    ambiguous
}

#[derive(Deserialize)]
pub struct ResetInput {
    pub token: String,
    pub password: String,
}

/// `POST /api/auth/reset` — redeem a reset token and set a new password.
///
/// Single-use and short-lived: the row is marked used inside the same
/// transaction that writes the new hash, so two racing redemptions can't both
/// succeed. Every existing session is dropped as well — a reset is what someone
/// does when they fear their account is compromised, and leaving the attacker's
/// session alive would defeat the point.
pub async fn reset(
    State(state): State<AppState>,
    Json(input): Json<ResetInput>,
) -> AppResult<Json<serde_json::Value>> {
    check_password_length(&input.password)?;
    let hash = sha256_hex(input.token.trim());

    let row: Option<(String,)> = sqlx::query_as(
        "SELECT user_id FROM password_reset \
         WHERE token_hash = ? AND used_at IS NULL AND expires_at > datetime('now')",
    )
    .bind(&hash)
    .fetch_optional(&state.db)
    .await?;
    let Some((user_id,)) = row else {
        // One message for expired, used, and never-existed: distinguishing them
        // tells a guesser which of their attempts was close.
        return Err(AppError::BadRequest(
            "this reset link is invalid or has expired".into(),
        ));
    };

    let password_hash = hash_password(&input.password)?;
    let mut tx = crate::write_tx(&state.db).await?;
    // Consuming the token is part of the same transaction as the password write,
    // so a crash can't leave a used token with the old password (or vice versa).
    let consumed = sqlx::query(
        "UPDATE password_reset SET used_at = datetime('now') \
         WHERE token_hash = ? AND used_at IS NULL",
    )
    .bind(&hash)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if consumed == 0 {
        return Err(AppError::BadRequest(
            "this reset link is invalid or has expired".into(),
        ));
    }
    sqlx::query("UPDATE app_user SET password_hash = ? WHERE id = ?")
        .bind(&password_hash)
        .bind(&user_id)
        .execute(&mut *tx)
        .await?;
    sqlx::query("DELETE FROM session WHERE user_id = ?")
        .bind(&user_id)
        .execute(&mut *tx)
        .await?;
    tx.commit().await?;

    tracing::info!(user_id, "password reset completed");
    Ok(Json(serde_json::json!({ "status": "password updated" })))
}

/// Creates the account behind a redeemed invite (plan 5 #31, stage 3).
///
/// Deliberately not reachable through the public registration path: the address
/// comes from the *invite*, not from the request, so a forwarded link can't be
/// used to open an account under someone else's email. Never master.
pub async fn create_invited_user(
    state: &AppState,
    email: &str,
    display_name: &str,
    password: &str,
    as_owner: bool,
) -> AppResult<String> {
    check_password_length(password)?;
    // `as_owner` comes from the *invitation*, never from the redeeming request
    // — the same reason the address does. A forwarded link must not be able to
    // promote whoever opens it.
    let user = insert_user(&state.db, email, display_name, password, as_owner).await?;
    Ok(user.id)
}
