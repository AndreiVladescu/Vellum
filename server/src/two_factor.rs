//! Two-factor sign-in (v1.6.2): a code from an authenticator app on top of the
//! password, for the console and the app alike. The arithmetic is in
//! `totp.rs`; the tables are migration 0040, which also explains why the secret
//! is stored readable.
//!
//! ## What it covers, and what it deliberately does not
//!
//! - **Password sign-in** (`POST /api/auth/login`) on a two-factor account
//!   answers 401 with `two_factor_required` and a short-lived challenge, not a
//!   session. `POST /api/auth/login/2fa` with the challenge and a code (or a
//!   recovery code) completes it. A 401 rather than a 200 so a client that has
//!   never heard of two-factor shows the message — which says what to do —
//!   instead of failing to parse a session that is not there.
//! - **The account password over HTTP Basic** is refused for a two-factor
//!   account, everywhere: otherwise the password alone would still open every
//!   route through the back door, and the second factor would be decoration.
//! - **App passwords are not subject to it**, on purpose. They exist for
//!   e-readers, which cannot show a code prompt; each is a random 120-bit
//!   secret minted from a signed-in session (so, after two-factor), limited to
//!   reading OPDS, covers and downloads, and revocable one by one. That is
//!   their point, and docs/DEPLOYMENT.md says so.
//! - **Existing sessions stay valid** when it is turned on. A session is
//!   already past sign-in; the second factor guards the next one.
//! - **A password reset does not clear it.** The reset link arrives by email,
//!   and an attacker who can read someone's mail should not be able to remove
//!   their second factor by asking for one. A person who lost their phone *and*
//!   their recovery codes asks an owner, who can clear it from People
//!   (`DELETE /api/users/{id}/2fa`) — an owner of a personal library knows the
//!   person asking. A sole owner in that position needs the database
//!   (docs/DEPLOYMENT.md has the one-line `sqlite3` command).
//!
//! ## Throttling
//!
//! Wrong codes count against the login throttle under `totp:<email>` (and the
//! caller's IP), with the same limit as wrong passwords. Its own key, because a
//! *correct* password clears the password key — if wrong codes lived there, an
//! attacker who has the password could reset their budget by signing in again.
//! Each challenge also dies after [`MAX_CHALLENGE_FAILURES`] wrong codes.

use axum::Json;
use axum::extract::{Path, State};
use axum::http::StatusCode;
use axum::response::{IntoResponse, Response};
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::auth::{self, AuthUser, ClientKey, sha256_hex};
use crate::error::{AppError, AppResult};
use crate::totp;

/// What an authenticator app files the account under.
const ISSUER: &str = "Vellum";
/// How long a password stays "right" waiting for its code.
const CHALLENGE_MINUTES: i64 = 5;
const MAX_CHALLENGE_FAILURES: i64 = 5;

/// Throttle key for wrong second factors (see the module docs for why it is
/// not the password's).
fn code_key(email: &str) -> String {
    format!("totp:{email}")
}

/// Whether sign-in for `user_id` needs a second factor.
pub(crate) async fn is_enabled(state: &AppState, user_id: &str) -> AppResult<bool> {
    Ok(sqlx::query_scalar(
        "SELECT EXISTS(SELECT 1 FROM user_totp WHERE user_id = ? AND enabled_at IS NOT NULL)",
    )
    .bind(user_id)
    .fetch_one(&state.db)
    .await?)
}

/// Which kind of second factor was accepted.
#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub(crate) enum Factor {
    Totp,
    Recovery,
}

/// Accepts a code from the authenticator or an unused recovery code, consuming
/// it: a TOTP code moves `last_step` forward (so it cannot be used again inside
/// its window), a recovery code is marked used. Both writes are conditional
/// UPDATEs, so two requests racing with the same code cannot both pass.
///
/// `Ok(None)` for a wrong, replayed or malformed code; the caller throttles.
pub(crate) async fn consume_code(
    state: &AppState,
    user_id: &str,
    typed: &str,
) -> AppResult<Option<Factor>> {
    if let Some(code) = totp::parse_code(typed) {
        let row: Option<(String, i64)> = sqlx::query_as(
            "SELECT secret, last_step FROM user_totp \
             WHERE user_id = ? AND enabled_at IS NOT NULL",
        )
        .bind(user_id)
        .fetch_optional(&state.db)
        .await?;
        let Some((secret, last_step)) = row else {
            return Ok(None);
        };
        let secret = decode_secret(&secret)?;
        let now = totp::step_at(totp::now_unix());
        let Some(step) = totp::matching_step(&secret, code, now, last_step.max(0) as u64) else {
            return Ok(None);
        };
        let moved =
            sqlx::query("UPDATE user_totp SET last_step = ? WHERE user_id = ? AND last_step < ?")
                .bind(step as i64)
                .bind(user_id)
                .bind(step as i64)
                .execute(&state.db)
                .await?
                .rows_affected();
        return Ok((moved == 1).then_some(Factor::Totp));
    }
    let Some(normalized) = totp::normalize_recovery_code(typed) else {
        return Ok(None);
    };
    let used = sqlx::query(
        "UPDATE totp_recovery_code SET used_at = datetime('now') \
         WHERE user_id = ? AND code_hash = ? AND used_at IS NULL",
    )
    .bind(user_id)
    .bind(sha256_hex(&normalized))
    .execute(&state.db)
    .await?
    .rows_affected();
    Ok((used == 1).then_some(Factor::Recovery))
}

fn decode_secret(stored: &str) -> AppResult<Vec<u8>> {
    totp::base32_decode(stored).ok_or_else(|| AppError::Internal("unreadable TOTP secret".into()))
}

async fn recovery_codes_left(state: &AppState, user_id: &str) -> AppResult<i64> {
    Ok(sqlx::query_scalar(
        "SELECT COUNT(*) FROM totp_recovery_code WHERE user_id = ? AND used_at IS NULL",
    )
    .bind(user_id)
    .fetch_one(&state.db)
    .await?)
}

/// Replaces `user_id`'s recovery codes with a fresh set and returns them — the
/// only time they exist in readable form.
async fn replace_recovery_codes(
    conn: &mut sqlx::SqliteConnection,
    user_id: &str,
) -> AppResult<Vec<String>> {
    sqlx::query("DELETE FROM totp_recovery_code WHERE user_id = ?")
        .bind(user_id)
        .execute(&mut *conn)
        .await?;
    let codes: Vec<String> = (0..totp::RECOVERY_CODES)
        .map(|_| totp::new_recovery_code())
        .collect();
    for code in &codes {
        let normalized =
            totp::normalize_recovery_code(code).expect("a generated recovery code is canonical");
        sqlx::query("INSERT INTO totp_recovery_code (user_id, code_hash) VALUES (?, ?)")
            .bind(user_id)
            .bind(sha256_hex(&normalized))
            .execute(&mut *conn)
            .await?;
    }
    Ok(codes)
}

// ---- sign-in -----------------------------------------------------------------

/// Called by `auth::login` once the password is right on a two-factor account:
/// mints the challenge and builds the 401 that carries it.
pub(crate) async fn challenge_response(state: &AppState, user_id: &str) -> AppResult<Response> {
    // Housekeeping first, so abandoned challenges cannot pile up.
    sqlx::query("DELETE FROM login_challenge WHERE expires_at <= datetime('now')")
        .execute(&state.db)
        .await?;
    let token = auth::new_token();
    sqlx::query(
        "INSERT INTO login_challenge (token_hash, user_id, expires_at) \
         VALUES (?, ?, datetime('now', ?))",
    )
    .bind(sha256_hex(&token))
    .bind(user_id)
    .bind(format!("+{CHALLENGE_MINUTES} minutes"))
    .execute(&state.db)
    .await?;
    let body = serde_json::json!({
        // Written for a client that does not know this response: it is shown
        // as the sign-in error, so it has to say what to do.
        "error": "this account uses two-factor sign-in — enter the code from your \
                  authenticator app (if this app has nowhere to type it, update it)",
        "two_factor_required": true,
        "challenge": token,
    });
    Ok((StatusCode::UNAUTHORIZED, Json(body)).into_response())
}

#[derive(Deserialize)]
pub struct SecondFactorInput {
    pub challenge: String,
    pub code: String,
}

#[derive(Serialize)]
pub struct SecondFactorResponse {
    #[serde(flatten)]
    pub auth: auth::AuthResponse,
    /// Present only when a recovery code was used, so the client can warn
    /// that they are running out.
    #[serde(skip_serializing_if = "Option::is_none")]
    pub recovery_codes_left: Option<i64>,
}

/// `POST /api/auth/login/2fa` — finish a sign-in that `login` answered with a
/// challenge.
pub async fn login_second_factor(
    State(state): State<AppState>,
    client: ClientKey,
    Json(input): Json<SecondFactorInput>,
) -> AppResult<Json<SecondFactorResponse>> {
    let expired = || {
        AppError::Unauthorized("this sign-in has expired — start again with your password".into())
    };
    let challenge_hash = sha256_hex(input.challenge.trim());
    let row: Option<(String, String, String, bool)> = sqlx::query_as(
        "SELECT u.id, u.email, u.display_name, u.is_master \
         FROM login_challenge c JOIN app_user u ON u.id = c.user_id \
         WHERE c.token_hash = ? AND c.expires_at > datetime('now')",
    )
    .bind(&challenge_hash)
    .fetch_optional(&state.db)
    .await?;
    let Some((id, email, display_name, is_master)) = row else {
        return Err(expired());
    };

    let key = code_key(&email);
    let ip_key = format!("ip:{}", client.0);
    if !state.throttle.allowed(&key) || !state.throttle.allowed(&ip_key) {
        return Err(AppError::TooManyRequests(
            "too many failed attempts — try again later".into(),
        ));
    }
    // Bound what a code can be before it reaches anything.
    if input.code.len() > 64 {
        return Err(AppError::BadRequest("that is not a code".into()));
    }

    let Some(factor) = consume_code(&state, &id, &input.code).await? else {
        state.throttle.record_failure(&key);
        state.throttle.record_failure(&ip_key);
        let failures: Option<i64> = sqlx::query_scalar(
            "UPDATE login_challenge SET failures = failures + 1 \
             WHERE token_hash = ? RETURNING failures",
        )
        .bind(&challenge_hash)
        .fetch_optional(&state.db)
        .await?;
        if failures.unwrap_or(MAX_CHALLENGE_FAILURES) >= MAX_CHALLENGE_FAILURES {
            sqlx::query("DELETE FROM login_challenge WHERE token_hash = ?")
                .bind(&challenge_hash)
                .execute(&state.db)
                .await?;
            return Err(AppError::Unauthorized(
                "too many wrong codes — start again with your password".into(),
            ));
        }
        return Err(AppError::Unauthorized(
            "that code is not right — check it, or use a recovery code".into(),
        ));
    };

    // Single use: whichever request deletes the challenge is the one that
    // signs in.
    let gone = sqlx::query("DELETE FROM login_challenge WHERE token_hash = ?")
        .bind(&challenge_hash)
        .execute(&state.db)
        .await?
        .rows_affected();
    if gone == 0 {
        return Err(expired());
    }
    state.throttle.clear(&key);
    state.throttle.clear(&ip_key);

    let user = AuthUser {
        id,
        email,
        display_name,
        is_master,
    };
    let recovery_codes_left = if factor == Factor::Recovery {
        crate::audit::record(
            &state,
            Some(&user),
            "user.2fa_recovery_used",
            "user",
            &user.id,
            Some(&user.email),
        )
        .await;
        Some(recovery_codes_left(&state, &user.id).await?)
    } else {
        None
    };
    let token = auth::issue_token(&state, &user.id).await?;
    Ok(Json(SecondFactorResponse {
        auth: auth::AuthResponse { token, user },
        recovery_codes_left,
    }))
}

// ---- managing one's own -------------------------------------------------------

#[derive(Serialize)]
pub struct Status {
    pub enabled: bool,
    pub enabled_at: Option<String>,
    pub recovery_codes_left: i64,
}

/// `GET /api/auth/2fa` — is it on, and how many recovery codes are left.
pub async fn status(State(state): State<AppState>, user: AuthUser) -> AppResult<Json<Status>> {
    let enabled_at: Option<Option<String>> =
        sqlx::query_scalar("SELECT enabled_at FROM user_totp WHERE user_id = ?")
            .bind(&user.id)
            .fetch_optional(&state.db)
            .await?;
    let enabled_at = enabled_at.flatten();
    Ok(Json(Status {
        enabled: enabled_at.is_some(),
        enabled_at,
        recovery_codes_left: recovery_codes_left(&state, &user.id).await?,
    }))
}

/// Proof that the person at this session is the account's owner, not someone
/// who found it open: the password, or a current code (or recovery code). Asked
/// before anything that changes how the account signs in, so a stolen session
/// can neither turn two-factor off nor enrol a phone of its own and lock the
/// owner out.
#[derive(Deserialize, Default)]
pub struct Reauth {
    #[serde(default)]
    pub password: Option<String>,
    #[serde(default)]
    pub code: Option<String>,
}

async fn require_reauth(
    state: &AppState,
    user: &AuthUser,
    proof: &Reauth,
    allow_code: bool,
) -> AppResult<()> {
    let password = proof.password.as_deref().filter(|p| !p.is_empty());
    let code = proof
        .code
        .as_deref()
        .filter(|c| allow_code && !c.trim().is_empty());
    if password.is_none() && code.is_none() {
        return Err(AppError::BadRequest(if allow_code {
            "confirm it's you: your password, or a code from your authenticator".into()
        } else {
            "confirm it's you with your password".into()
        }));
    }
    let key = code_key(&user.email);
    if !state.throttle.allowed(&key) || !state.throttle.allowed(&user.email) {
        return Err(AppError::TooManyRequests(
            "too many failed attempts — try again later".into(),
        ));
    }
    if let Some(password) = password {
        auth::check_password_length(password)?;
        let hash: String = sqlx::query_scalar("SELECT password_hash FROM app_user WHERE id = ?")
            .bind(&user.id)
            .fetch_one(&state.db)
            .await?;
        if auth::verify_password(password, &hash) {
            return Ok(());
        }
        state.throttle.record_failure(&user.email);
        return Err(AppError::Forbidden("that password is not right".into()));
    }
    let code = code.expect("one of the two is present");
    if code.len() <= 64 && consume_code(state, &user.id, code).await?.is_some() {
        return Ok(());
    }
    state.throttle.record_failure(&key);
    Err(AppError::Forbidden("that code is not right".into()))
}

#[derive(Serialize)]
pub struct Setup {
    /// For typing in by hand, in groups of four.
    pub secret: String,
    pub otpauth_uri: String,
    /// The URI as a QR code, a bare `<svg>` element.
    pub qr_svg: String,
}

/// `POST /api/auth/2fa/setup` `{password}` — start enrolment: a new secret,
/// shown as a QR code and as text. Nothing changes for sign-in until a code
/// from it is confirmed; asking again replaces a pending secret.
pub async fn setup(
    State(state): State<AppState>,
    user: AuthUser,
    Json(proof): Json<Reauth>,
) -> AppResult<Json<Setup>> {
    if is_enabled(&state, &user.id).await? {
        return Err(AppError::Conflict(
            "two-factor sign-in is already on — turn it off first to move it to a new device"
                .into(),
        ));
    }
    // The password, never a code: there is no code yet.
    require_reauth(&state, &user, &proof, false).await?;
    let secret = totp::base32_encode(&totp::new_secret());
    sqlx::query(
        "INSERT INTO user_totp (user_id, secret) VALUES (?, ?) \
         ON CONFLICT (user_id) DO UPDATE SET secret = excluded.secret, last_step = 0 \
         WHERE user_totp.enabled_at IS NULL",
    )
    .bind(&user.id)
    .bind(&secret)
    .execute(&state.db)
    .await?;
    let uri = totp::otpauth_uri(ISSUER, &user.email, &secret);
    let grouped = secret
        .as_bytes()
        .chunks(4)
        .map(|c| std::str::from_utf8(c).expect("base32 is ASCII"))
        .collect::<Vec<_>>()
        .join(" ");
    Ok(Json(Setup {
        secret: grouped,
        qr_svg: totp::qr_svg(&uri),
        otpauth_uri: uri,
    }))
}

#[derive(Deserialize)]
pub struct EnableInput {
    pub code: String,
}

#[derive(Serialize)]
pub struct RecoveryCodes {
    pub recovery_codes: Vec<String>,
}

/// `POST /api/auth/2fa/enable` `{code}` — confirm enrolment with a code from
/// the new secret. Turns it on and returns the recovery codes, once.
pub async fn enable(
    State(state): State<AppState>,
    user: AuthUser,
    Json(input): Json<EnableInput>,
) -> AppResult<Json<RecoveryCodes>> {
    let row: Option<(String, Option<String>)> =
        sqlx::query_as("SELECT secret, enabled_at FROM user_totp WHERE user_id = ?")
            .bind(&user.id)
            .fetch_optional(&state.db)
            .await?;
    let Some((secret, enabled_at)) = row else {
        return Err(AppError::BadRequest("start setting it up first".into()));
    };
    if enabled_at.is_some() {
        return Err(AppError::Conflict(
            "two-factor sign-in is already on".into(),
        ));
    }
    let key = code_key(&user.email);
    if !state.throttle.allowed(&key) {
        return Err(AppError::TooManyRequests(
            "too many failed attempts — try again later".into(),
        ));
    }
    let secret_bytes = decode_secret(&secret)?;
    let step = totp::parse_code(&input.code).and_then(|code| {
        totp::matching_step(&secret_bytes, code, totp::step_at(totp::now_unix()), 0)
    });
    let Some(step) = step else {
        state.throttle.record_failure(&key);
        return Err(AppError::BadRequest(
            "that code doesn't match — check the phone's clock is right, and try the next one"
                .into(),
        ));
    };

    let mut tx = crate::write_tx(&state.db).await?;
    // Only a still-pending row, and only the secret this code was checked
    // against: a setup racing in between must not be confirmed by accident.
    let turned_on = sqlx::query(
        "UPDATE user_totp SET enabled_at = datetime('now'), last_step = ? \
         WHERE user_id = ? AND secret = ? AND enabled_at IS NULL",
    )
    .bind(step as i64)
    .bind(&user.id)
    .bind(&secret)
    .execute(&mut *tx)
    .await?
    .rows_affected();
    if turned_on == 0 {
        return Err(AppError::Conflict(
            "set-up changed meanwhile — start again".into(),
        ));
    }
    let codes = replace_recovery_codes(&mut tx, &user.id).await?;
    tx.commit().await?;
    state.throttle.clear(&key);

    crate::audit::record(
        &state,
        Some(&user),
        "user.2fa_enable",
        "user",
        &user.id,
        Some(&user.email),
    )
    .await;
    Ok(Json(RecoveryCodes {
        recovery_codes: codes,
    }))
}

/// `POST /api/auth/2fa/recovery-codes` `{password | code}` — a new set,
/// invalidating every old one.
pub async fn regenerate_recovery_codes(
    State(state): State<AppState>,
    user: AuthUser,
    Json(proof): Json<Reauth>,
) -> AppResult<Json<RecoveryCodes>> {
    if !is_enabled(&state, &user.id).await? {
        return Err(AppError::BadRequest("two-factor sign-in is not on".into()));
    }
    require_reauth(&state, &user, &proof, true).await?;
    let mut tx = crate::write_tx(&state.db).await?;
    let codes = replace_recovery_codes(&mut tx, &user.id).await?;
    tx.commit().await?;
    crate::audit::record(
        &state,
        Some(&user),
        "user.2fa_recovery_regenerate",
        "user",
        &user.id,
        Some(&user.email),
    )
    .await;
    Ok(Json(RecoveryCodes {
        recovery_codes: codes,
    }))
}

/// `POST /api/auth/2fa/disable` `{password | code}` — turn it off.
pub async fn disable(
    State(state): State<AppState>,
    user: AuthUser,
    Json(proof): Json<Reauth>,
) -> AppResult<Json<serde_json::Value>> {
    if !is_enabled(&state, &user.id).await? {
        return Err(AppError::BadRequest("two-factor sign-in is not on".into()));
    }
    require_reauth(&state, &user, &proof, true).await?;
    clear(&state, &user.id).await?;
    crate::audit::record(
        &state,
        Some(&user),
        "user.2fa_disable",
        "user",
        &user.id,
        Some(&user.email),
    )
    .await;
    Ok(Json(serde_json::json!({ "ok": true })))
}

/// Everything two-factor for one account: the secret, the recovery codes, and
/// any sign-in waiting on a code.
async fn clear(state: &AppState, user_id: &str) -> AppResult<()> {
    let mut tx = crate::write_tx(&state.db).await?;
    for sql in [
        "DELETE FROM user_totp WHERE user_id = ?",
        "DELETE FROM totp_recovery_code WHERE user_id = ?",
        "DELETE FROM login_challenge WHERE user_id = ?",
    ] {
        sqlx::query(sql).bind(user_id).execute(&mut *tx).await?;
    }
    tx.commit().await?;
    Ok(())
}

/// `DELETE /api/users/{id}/2fa` — master only: clear someone else's, for the
/// person who lost both their phone and their recovery codes. Never one's own:
/// that is `disable`, which asks for proof — otherwise an owner's stolen
/// session could strip the owner's second factor with no password at all.
pub async fn admin_clear(
    State(state): State<AppState>,
    caller: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    auth::require_master(&caller)?;
    if id == caller.id {
        return Err(AppError::BadRequest(
            "turn off your own from your account's security page".into(),
        ));
    }
    let email: Option<String> = sqlx::query_scalar("SELECT email FROM app_user WHERE id = ?")
        .bind(&id)
        .fetch_optional(&state.db)
        .await?;
    let Some(email) = email else {
        return Err(AppError::NotFound("no such user".into()));
    };
    clear(&state, &id).await?;
    crate::audit::record(
        &state,
        Some(&caller),
        "user.2fa_clear",
        "user",
        &id,
        Some(&email),
    )
    .await;
    Ok(Json(serde_json::json!({ "ok": true })))
}
