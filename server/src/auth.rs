use argon2::Argon2;
use argon2::password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use axum::Json;
use axum::extract::{FromRequestParts, State};
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

        // Fallback: a `?token=` query param, so browser <img> and <a download>
        // links to authenticated blobs (covers, file downloads) work. Scoped to
        // exactly those GETs, so a token leaked into a proxy log or browser
        // history can't be replayed against a mutating endpoint (e.g. a DELETE).
        if let Some(token) = query_token(parts.uri.query())
            && is_blob_get(&parts.method, parts.uri.path())
        {
            return user_from_token(state, token).await;
        }
        Err(AppError::Unauthorized("missing credentials".into()))
    }
}

/// Whether `?token=` is allowed here: only `GET`s for a book cover
/// (`/api/books/{id}/cover`) or a file download (`/api/files/...`).
fn is_blob_get(method: &axum::http::Method, path: &str) -> bool {
    method == axum::http::Method::GET
        && (path.starts_with("/api/files/")
            || (path.starts_with("/api/books/") && path.ends_with("/cover")))
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

/// Extracts a `token` value from a URL query string (tokens are hex, so no
/// percent-decoding is needed).
fn query_token(query: Option<&str>) -> Option<&str> {
    query?
        .split('&')
        .find_map(|pair| pair.strip_prefix("token="))
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

/// Caches recent successful Basic-auth verifications so an e-reader that sends
/// `Authorization: Basic` on *every* OPDS request doesn't cost an Argon2 verify
/// (~10²ms of CPU) each time — which is both slow and a free CPU-amplification
/// vector. Keyed by lowercase email → (sha256 of the password, when verified).
/// The threat here is repeated *hashing cost*, not storage, so a TTL-gated
/// SHA-256 of a high-entropy in-memory value is acceptable.
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
            Some((hash, at)) if at.elapsed() < BASIC_CACHE_TTL => *hash == sha256_hex(password),
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
            (sha256_hex(password), std::time::Instant::now()),
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

fn verify_password(password: &str, hash: &str) -> bool {
    PasswordHash::new(hash)
        .map(|parsed| {
            Argon2::default()
                .verify_password(password.as_bytes(), &parsed)
                .is_ok()
        })
        .unwrap_or(false)
}

/// A fresh opaque session token (returned to the client once).
fn new_token() -> String {
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

// ---- handlers -------------------------------------------------------------

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
    let mut tx = state.db.begin().await?;
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
fn check_password_length(password: &str) -> AppResult<()> {
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
