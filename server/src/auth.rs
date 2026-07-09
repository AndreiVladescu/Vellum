use argon2::password_hash::{PasswordHash, PasswordHasher, PasswordVerifier, SaltString};
use argon2::Argon2;
use rand_core::{OsRng, RngCore};
use axum::extract::{FromRequestParts, State};
use axum::http::header::AUTHORIZATION;
use axum::http::request::Parts;
use axum::http::HeaderMap;
use axum::Json;
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::error::{AppError, AppResult};
use crate::AppState;

/// A precomputed Argon2 hash used only to spend the same verification time when
/// an email doesn't exist, so login/basic-auth timing can't confirm which
/// emails have accounts.
static DUMMY_HASH: std::sync::LazyLock<String> =
    std::sync::LazyLock::new(|| hash_password("timing-equalizer-dummy").unwrap());

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
        if let Some(header) = parts.headers.get(AUTHORIZATION).and_then(|v| v.to_str().ok()) {
            return if let Some(token) = header.strip_prefix("Bearer ") {
                user_from_token(state, token).await
            } else if let Some(encoded) = header.strip_prefix("Basic ") {
                user_from_basic(state, encoded).await
            } else {
                Err(AppError::Unauthorized("unsupported authorization scheme".into()))
            };
        }

        // Fallback: a `?token=` query param, so browser <img> and <a download>
        // links to authenticated blobs (covers, file downloads) work.
        if let Some(token) = query_token(parts.uri.query()) {
            return user_from_token(state, token).await;
        }
        Err(AppError::Unauthorized("missing credentials".into()))
    }
}

/// Extracts a `token` value from a URL query string (tokens are hex, so no
/// percent-decoding is needed).
fn query_token(query: Option<&str>) -> Option<&str> {
    query?.split('&').find_map(|pair| pair.strip_prefix("token="))
}

async fn user_from_token(state: &AppState, token: &str) -> AppResult<AuthUser> {
    sqlx::query_as::<_, AuthUser>(
        "SELECT u.id, u.email, u.display_name, u.is_master \
         FROM session s JOIN app_user u ON u.id = s.user_id \
         WHERE s.token_hash = ? AND s.expires_at > datetime('now')",
    )
    .bind(sha256_hex(token))
    .fetch_optional(&state.db)
    .await?
    .ok_or_else(|| AppError::Unauthorized("invalid or expired token".into()))
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
    if !verify_password(password, &password_hash) {
        state.throttle.record_failure(&key);
        return Err(AppError::Unauthorized("invalid email or password".into()));
    }
    state.throttle.clear(&key);
    Ok(AuthUser { id, email, display_name, is_master })
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

    let master_exists: bool =
        sqlx::query_scalar("SELECT EXISTS(SELECT 1 FROM app_user WHERE is_master = 1)")
            .fetch_one(&state.db)
            .await?;
    if master_exists {
        return Err(AppError::Forbidden(
            "registration is closed — ask the library owner to create your account".into(),
        ));
    }

    let user = insert_user(&state, &input.email, &input.display_name, &input.password, true).await?;
    let token = issue_token(&state, &user.id).await?;
    Ok(Json(AuthResponse { token, user }))
}

pub async fn login(
    State(state): State<AppState>,
    Json(input): Json<LoginInput>,
) -> AppResult<Json<AuthResponse>> {
    let key = input.email.trim().to_lowercase();
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
        let _ = verify_password(&input.password, &DUMMY_HASH); // equalize timing
        state.throttle.record_failure(&key);
        return Err(AppError::Unauthorized("invalid email or password".into()));
    };
    if !verify_password(&input.password, &password_hash) {
        state.throttle.record_failure(&key);
        return Err(AppError::Unauthorized("invalid email or password".into()));
    }
    state.throttle.clear(&key);

    let user = AuthUser { id, email, display_name, is_master };
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
    let user =
        insert_user(&state, &input.email, &input.display_name, &input.password, false).await?;
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

fn validate_credentials(email: &str, password: &str) -> AppResult<()> {
    if !email.contains('@') {
        return Err(AppError::BadRequest("a valid email is required".into()));
    }
    if password.len() < 8 {
        return Err(AppError::BadRequest(
            "password must be at least 8 characters".into(),
        ));
    }
    Ok(())
}

async fn insert_user(
    state: &AppState,
    email: &str,
    display_name: &str,
    password: &str,
    is_master: bool,
) -> AppResult<AuthUser> {
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
    .execute(&state.db)
    .await;

    if let Err(sqlx::Error::Database(e)) = &result
        && e.is_unique_violation()
    {
        return Err(AppError::Conflict("that email is already registered".into()));
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
