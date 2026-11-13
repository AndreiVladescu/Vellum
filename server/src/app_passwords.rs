//! App passwords (v1.6.2): per-device secrets for OPDS e-readers.
//!
//! An e-reader speaks HTTP Basic and stores whatever it is given, often in the
//! clear, on a device that gets lent, lost and left on trains. Typing the
//! account password into one hands that device everything the account can do:
//! the console, people, shares, the backup. An app password is the narrower
//! thing it actually needs.
//!
//! - **Scope.** Accepted only where a route opts in with [`AppPasswordScope`]:
//!   the OPDS feeds, covers and book downloads, all GETs. Everywhere else —
//!   admin endpoints, writes, *these* endpoints — answers 403, so a leaked app
//!   password can read the library its owner can read and nothing more. It can
//!   never mint, list or revoke app passwords, so it cannot entrench itself.
//! - **Per device, revocable.** Each has a label and its own row; revoking one
//!   deletes the row and the next request from that device is refused.
//! - **Shown once.** Only the SHA-256 is stored (migration 0039 explains why a
//!   fast hash is right here), so after creation nothing can show it again.
//!
//! The account password keeps working on the same routes: e-readers already set
//! up with it must not break on upgrade. App passwords are the recommended way,
//! and docs/DEPLOYMENT.md says so.

use axum::Json;
use axum::extract::{Path, State};
use rand_core::{OsRng, RngCore};
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::auth::{AuthUser, sha256_hex};
use crate::error::{AppError, AppResult};

/// Marker a route layer puts on the requests an app password may authenticate
/// (`axum::Extension(AppPasswordScope)` — see `lib.rs`). The [`AuthUser`]
/// extractor refuses an app password on any request without it, so the scope
/// is deny-by-default: a new route is closed to app passwords until someone
/// decides otherwise, in the route table where it is visible.
///
/// An extension can only be set by the server's own layers, never by a client.
#[derive(Clone, Copy, Debug)]
pub struct AppPasswordScope;

/// Crockford's base32, lowercase: digits and letters without `i`, `l`, `o` and
/// `u`, so nothing on a Kindle keyboard can be mistaken for something else.
/// 32 symbols, so a random byte masked to five bits picks one without bias.
const ALPHABET: &[u8; 32] = b"0123456789abcdefghjkmnpqrstvwxyz";

/// 24 symbols × 5 bits = 120 bits of entropy.
const SECRET_LEN: usize = 24;
const GROUP: usize = 4;

/// How many a person may hold. Generous for devices, small enough that a
/// script looping on "create" cannot grow the table without bound.
const MAX_PER_USER: i64 = 50;
const MAX_LABEL_CHARS: usize = 80;

/// A fresh secret, formatted for reading off a screen and typing on an
/// e-reader: six groups of four, `k3m9-x2qa-…`.
fn generate() -> String {
    let mut bytes = [0u8; SECRET_LEN];
    OsRng.fill_bytes(&mut bytes);
    let mut out = String::with_capacity(SECRET_LEN + SECRET_LEN / GROUP);
    for (i, b) in bytes.iter().enumerate() {
        if i > 0 && i % GROUP == 0 {
            out.push('-');
        }
        out.push(ALPHABET[(b & 31) as usize] as char);
    }
    out
}

/// The canonical form of something that might be an app password, or `None`
/// when it cannot be one (so the caller goes on to treat it as an account
/// password).
///
/// Forgiving about what a person typing on an e-reader gets wrong: case, the
/// dashes, spaces, and the letters Crockford folds onto digits (`o` → `0`,
/// `i`/`l` → `1`). The hash is always taken over this form, so `K3M9 X2QA …`
/// and `k3m9-x2qa-…` are the same secret.
pub(crate) fn normalize(candidate: &str) -> Option<String> {
    let mut out = String::with_capacity(SECRET_LEN);
    for c in candidate.chars() {
        let c = match c.to_ascii_lowercase() {
            '-' | ' ' => continue,
            'o' => '0',
            'i' | 'l' => '1',
            c => c,
        };
        if !c.is_ascii() || !ALPHABET.contains(&(c as u8)) {
            return None;
        }
        out.push(c);
        if out.len() > SECRET_LEN {
            return None;
        }
    }
    (out.len() == SECRET_LEN).then_some(out)
}

fn hash(normalized: &str) -> String {
    sha256_hex(normalized)
}

/// Is `password` one of `user_id`'s app passwords? Returns its row id.
///
/// Also stamps `last_used_at`, but only when the stored one is more than a
/// minute old: the staleness is read in the same SELECT, so the common case —
/// an e-reader fetching a page of covers — is a read and nothing else, rather
/// than a write per request queueing behind the server's single writer.
pub(crate) async fn verify(
    state: &AppState,
    user_id: &str,
    password: &str,
) -> AppResult<Option<String>> {
    let Some(normalized) = normalize(password) else {
        return Ok(None);
    };
    let row: Option<(String, bool)> = sqlx::query_as(
        "SELECT id, (last_used_at IS NULL OR last_used_at < datetime('now', '-60 seconds')) \
         FROM app_password WHERE secret_hash = ? AND user_id = ?",
    )
    .bind(hash(&normalized))
    .bind(user_id)
    .fetch_optional(&state.db)
    .await?;
    let Some((id, stale)) = row else {
        return Ok(None);
    };
    if stale {
        // Best effort: a failed stamp must not fail the request it describes.
        let _ = sqlx::query(
            "UPDATE app_password SET last_used_at = datetime('now') \
             WHERE id = ? AND (last_used_at IS NULL \
                               OR last_used_at < datetime('now', '-60 seconds'))",
        )
        .bind(&id)
        .execute(&state.db)
        .await;
    }
    Ok(Some(id))
}

// ---- endpoints -------------------------------------------------------------
//
// All three take a plain `AuthUser` and are *not* in the app-password scope,
// so only a real sign-in (a console session, or the account password) can
// manage them. Each is scoped to the caller: there is no admin view of other
// people's devices, because the owner of the server has no need to know which
// e-readers a member uses.

#[derive(Serialize, sqlx::FromRow)]
pub struct AppPasswordDto {
    pub id: String,
    pub label: String,
    pub prefix: String,
    pub created_at: String,
    pub last_used_at: Option<String>,
}

/// The one response that carries the secret. Never stored, never logged.
#[derive(Serialize)]
pub struct CreatedAppPassword {
    #[serde(flatten)]
    pub app_password: AppPasswordDto,
    pub password: String,
}

#[derive(Deserialize)]
pub struct CreateInput {
    pub label: String,
}

/// `GET /api/app-passwords` — the caller's, newest first, without secrets.
pub async fn list(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<Vec<AppPasswordDto>>> {
    let rows = sqlx::query_as::<_, AppPasswordDto>(
        "SELECT id, label, prefix, created_at, last_used_at FROM app_password \
         WHERE user_id = ? ORDER BY created_at DESC, id",
    )
    .bind(&user.id)
    .fetch_all(&state.db)
    .await?;
    Ok(Json(rows))
}

/// `POST /api/app-passwords` — mint one. The response is the only time the
/// secret exists outside the device it is typed into.
pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(input): Json<CreateInput>,
) -> AppResult<Json<CreatedAppPassword>> {
    let label = input.label.trim();
    if label.is_empty() {
        return Err(AppError::BadRequest(
            "give it a name, so you can tell which device it is".into(),
        ));
    }
    if label.chars().count() > MAX_LABEL_CHARS {
        return Err(AppError::BadRequest(format!(
            "a name can be at most {MAX_LABEL_CHARS} characters"
        )));
    }

    let secret = generate();
    let normalized = normalize(&secret).expect("a generated secret is canonical");
    let id = uuid::Uuid::new_v4().to_string();

    // Count and insert under one write lock, so two racing creates cannot both
    // slip under the limit.
    let mut tx = crate::write_tx(&state.db).await?;
    let held: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM app_password WHERE user_id = ?")
        .bind(&user.id)
        .fetch_one(&mut *tx)
        .await?;
    if held >= MAX_PER_USER {
        return Err(AppError::BadRequest(format!(
            "you already have {MAX_PER_USER} app passwords — revoke one you no longer use"
        )));
    }
    sqlx::query(
        "INSERT INTO app_password (id, user_id, label, prefix, secret_hash) \
         VALUES (?, ?, ?, ?, ?)",
    )
    .bind(&id)
    .bind(&user.id)
    .bind(label)
    .bind(&secret[..GROUP])
    .bind(hash(&normalized))
    .execute(&mut *tx)
    .await?;
    let row = sqlx::query_as::<_, AppPasswordDto>(
        "SELECT id, label, prefix, created_at, last_used_at FROM app_password WHERE id = ?",
    )
    .bind(&id)
    .fetch_one(&mut *tx)
    .await?;
    tx.commit().await?;

    crate::audit::record(
        &state,
        Some(&user),
        "app_password.create",
        "app_password",
        &id,
        Some(label),
    )
    .await;
    Ok(Json(CreatedAppPassword {
        app_password: row,
        password: secret,
    }))
}

/// `DELETE /api/app-passwords/{id}` — revoke one of the caller's. Takes effect
/// on the device's next request. Someone else's id answers 404, the same as
/// one that never existed, so ids cannot be probed.
pub async fn revoke(
    State(state): State<AppState>,
    user: AuthUser,
    Path(id): Path<String>,
) -> AppResult<Json<serde_json::Value>> {
    let label: Option<String> =
        sqlx::query_scalar("DELETE FROM app_password WHERE id = ? AND user_id = ? RETURNING label")
            .bind(&id)
            .bind(&user.id)
            .fetch_optional(&state.db)
            .await?;
    let Some(label) = label else {
        return Err(AppError::NotFound("no such app password".into()));
    };
    crate::audit::record(
        &state,
        Some(&user),
        "app_password.revoke",
        "app_password",
        &id,
        Some(&label),
    )
    .await;
    Ok(Json(serde_json::json!({ "ok": true })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn a_generated_secret_is_six_groups_of_four_from_the_alphabet() {
        let s = generate();
        let groups: Vec<&str> = s.split('-').collect();
        assert_eq!(groups.len(), 6, "{s}");
        for g in &groups {
            assert_eq!(g.len(), 4, "{s}");
            assert!(g.bytes().all(|b| ALPHABET.contains(&b)), "{s}");
        }
        assert_eq!(normalize(&s).as_deref(), Some(s.replace('-', "").as_str()));
    }

    #[test]
    fn secrets_do_not_repeat() {
        let a: std::collections::HashSet<String> = (0..200).map(|_| generate()).collect();
        assert_eq!(a.len(), 200);
    }

    #[test]
    fn typing_slips_normalize_to_the_same_secret() {
        let s = "k3m9-x2qa-0011-abcd-efgh-jkmn";
        let canonical = normalize(s).unwrap();
        for typed in [
            "K3M9-X2QA-0011-ABCD-EFGH-JKMN",
            "k3m9 x2qa 0011 abcd efgh jkmn",
            "k3m9x2qa0011abcdefghjkmn",
            "k3m9-x2qa-o0il-abcd-efgh-jkmn",
        ] {
            assert_eq!(
                normalize(typed).as_deref(),
                Some(canonical.as_str()),
                "{typed}"
            );
            assert_eq!(hash(&normalize(typed).unwrap()), hash(&canonical));
        }
    }

    #[test]
    fn ordinary_passwords_are_not_mistaken_for_one() {
        for not_one in [
            "",
            "a long enough passphrase",
            "k3m9-x2qa-0011-abcd-efgh",        // too short
            "k3m9-x2qa-0011-abcd-efgh-jkmn-p", // too long
            "k3m9-x2qa-0011-abcd-efgh-jkmu",   // `u` is not in the alphabet
            "k3m9-x2qa-0011-abcd-efgh-jkm!",
            "k3m9-x2qa-0011-abcd-efgh-jkmé",
        ] {
            assert_eq!(normalize(not_one), None, "{not_one}");
        }
    }

    #[test]
    fn the_stored_hash_is_not_the_secret_and_is_stable() {
        let n = normalize(&generate()).unwrap();
        let h = hash(&n);
        assert_eq!(h.len(), 64);
        assert!(!h.contains(&n));
        assert_eq!(h, hash(&n));
    }
}
