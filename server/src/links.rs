//! Short-lived signed links for covers and downloads (v1.6.2).
//!
//! A browser `<img src>` or `<a href>` cannot send an `Authorization` header,
//! and putting the session token in the URL leaks it into proxy logs and
//! history (docs/SECURITY_AUDIT.md, L1). A signed link is the middle road: a
//! URL good for *one resource*, for *one person*, for a *short while*.
//!
//! `?u=<user id>&exp=<unix seconds>&sig=<hex HMAC-SHA256>` where the MAC covers
//! the user id, the request path and the expiry, keyed by a server secret. There
//! is no row per link. What the signature does **not** do is grant access: the
//! `AuthUser` extractor only turns a valid link back into the signing user, and
//! the handler then runs its usual `book_access` check. So a share revoked after
//! the link was minted stops working on the next request.
//!
//! The key lives in `server_setting` (`link_signing_key`), created on first
//! use. Deleting that row (or `POST /api/links/rotate`) invalidates every link.

use axum::Json;
use axum::extract::State;
use rand_core::{OsRng, RngCore};
use serde::{Deserialize, Serialize};
use sha2::{Digest, Sha256};

use crate::AppState;
use crate::access::book_access;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};

const KEY_SETTING: &str = "link_signing_key";

/// Covers are shown in long-lived pages and re-requested as the user scrolls,
/// so they get hours; a download link is used once, straight away, so minutes.
pub const COVER_TTL_SECS: i64 = 6 * 3600;
pub const DOWNLOAD_TTL_SECS: i64 = 5 * 60;

const MAX_PATHS: usize = 500;

#[derive(Clone, Copy, PartialEq, Debug)]
enum Kind {
    Cover,
    File,
}

/// Which resource a path names, if it is one a link may point at. Anything
/// else (any other endpoint) can never be reached with a signature.
fn classify(path: &str) -> Option<(Kind, &str)> {
    let rest = path.strip_prefix("/api/")?;
    let ok = |id: &str| !id.is_empty() && !id.contains('/');
    if let Some(id) = rest
        .strip_prefix("books/")
        .and_then(|r| r.strip_suffix("/cover"))
        && ok(id)
    {
        return Some((Kind::Cover, id));
    }
    if let Some(id) = rest.strip_prefix("files/")
        && ok(id)
    {
        return Some((Kind::File, id));
    }
    None
}

fn hmac_sha256(key: &[u8], msg: &[u8]) -> [u8; 32] {
    const BLOCK: usize = 64;
    let mut k = [0u8; BLOCK];
    if key.len() > BLOCK {
        k[..32].copy_from_slice(&Sha256::digest(key));
    } else {
        k[..key.len()].copy_from_slice(key);
    }
    let mut inner = Sha256::new();
    inner.update(k.map(|b| b ^ 0x36));
    inner.update(msg);
    let inner = inner.finalize();
    let mut outer = Sha256::new();
    outer.update(k.map(|b| b ^ 0x5c));
    outer.update(inner);
    outer.finalize().into()
}

fn ct_eq(a: &[u8], b: &[u8]) -> bool {
    if a.len() != b.len() {
        return false;
    }
    a.iter().zip(b).fold(0u8, |acc, (x, y)| acc | (x ^ y)) == 0
}

fn mac(key: &[u8], user_id: &str, path: &str, exp: i64) -> String {
    let msg = format!("vellum-link-v1\n{user_id}\n{path}\n{exp}");
    hex::encode(hmac_sha256(key, msg.as_bytes()))
}

/// The signing key, created on first use. `INSERT OR IGNORE` then re-read, so
/// two first requests racing agree on one key.
async fn key(state: &AppState) -> AppResult<Vec<u8>> {
    let read = || async {
        sqlx::query_scalar::<_, String>("SELECT value FROM server_setting WHERE key = ?")
            .bind(KEY_SETTING)
            .fetch_optional(&state.db)
            .await
    };
    if let Some(v) = read().await? {
        return Ok(v.into_bytes());
    }
    let mut raw = [0u8; 32];
    OsRng.fill_bytes(&mut raw);
    sqlx::query(
        "INSERT OR IGNORE INTO server_setting (key, value, updated_at) \
         VALUES (?, ?, datetime('now'))",
    )
    .bind(KEY_SETTING)
    .bind(hex::encode(raw))
    .execute(&state.db)
    .await?;
    let v = read()
        .await?
        .ok_or_else(|| AppError::Internal("signing key missing".into()))?;
    Ok(v.into_bytes())
}

/// Checks a request's `u`/`exp`/`sig` query against its path. On success
/// returns the user id the link was minted for; the caller must still load that
/// user and check access. Any failure is the same "unauthorised" answer.
pub async fn verify(state: &AppState, path: &str, query: &str) -> Option<String> {
    classify(path)?;
    let (mut u, mut exp, mut sig) = (None, None, None);
    for pair in query.split('&') {
        match pair.split_once('=') {
            Some(("u", v)) => u = Some(v),
            Some(("exp", v)) => exp = Some(v),
            Some(("sig", v)) => sig = Some(v),
            _ => {}
        }
    }
    let (u, exp, sig) = (u?, exp?.parse::<i64>().ok()?, sig?);
    if exp < chrono::Utc::now().timestamp() {
        return None;
    }
    let key = key(state).await.ok()?;
    let want = mac(&key, u, path, exp);
    ct_eq(want.as_bytes(), sig.as_bytes()).then(|| u.to_string())
}

#[derive(Deserialize)]
pub struct LinksInput {
    pub paths: Vec<String>,
}

#[derive(Serialize)]
pub struct Link {
    pub path: String,
    /// Root-relative URL, ready to use as an `src`/`href`.
    pub url: String,
    pub expires_at: i64,
}

#[derive(Serialize)]
pub struct LinksOutput {
    pub links: Vec<Link>,
}

/// `POST /api/links {paths: ["/api/books/ID/cover", "/api/files/ID"]}`.
///
/// Paths the caller cannot view are left out of the answer rather than failing
/// the batch, so one revoked book does not blank a whole page of covers. Query
/// strings are not accepted: the signature binds the path only.
pub async fn create(
    State(state): State<AppState>,
    user: AuthUser,
    Json(input): Json<LinksInput>,
) -> AppResult<Json<LinksOutput>> {
    if input.paths.len() > MAX_PATHS {
        return Err(AppError::BadRequest(format!(
            "at most {MAX_PATHS} paths per request"
        )));
    }
    let key = key(&state).await?;
    let now = chrono::Utc::now().timestamp();
    let mut links = Vec::new();
    for path in input.paths {
        let Some((kind, id)) = classify(&path) else {
            return Err(AppError::BadRequest(format!(
                "cannot sign {path}: only cover and file paths"
            )));
        };
        let book_id = match kind {
            Kind::Cover => Some(id.to_string()),
            Kind::File => {
                sqlx::query_scalar::<_, String>("SELECT book_id FROM book_file WHERE id = ?")
                    .bind(id)
                    .fetch_optional(&state.db)
                    .await?
            }
        };
        let Some(book_id) = book_id else { continue };
        if !book_access(&state, &user, &book_id).await?.can_view() {
            continue;
        }
        let exp = now
            + match kind {
                Kind::Cover => COVER_TTL_SECS,
                Kind::File => DOWNLOAD_TTL_SECS,
            };
        let sig = mac(&key, &user.id, &path, exp);
        links.push(Link {
            url: format!("{path}?u={}&exp={exp}&sig={sig}", user.id),
            path,
            expires_at: exp,
        });
    }
    Ok(Json(LinksOutput { links }))
}

/// `POST /api/links/rotate`: master only. Every outstanding link stops working.
pub async fn rotate(
    State(state): State<AppState>,
    user: AuthUser,
) -> AppResult<Json<serde_json::Value>> {
    if !user.is_master {
        return Err(AppError::Forbidden("only the owner can rotate".into()));
    }
    sqlx::query("DELETE FROM server_setting WHERE key = ?")
        .bind(KEY_SETTING)
        .execute(&state.db)
        .await?;
    Ok(Json(serde_json::json!({ "rotated": true })))
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn hmac_matches_rfc4231_case_2() {
        let mac = hmac_sha256(b"Jefe", b"what do ya want for nothing?");
        assert_eq!(
            hex::encode(mac),
            "5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843"
        );
    }

    #[test]
    fn classify_only_cover_and_file_paths() {
        assert!(classify("/api/books/abc/cover").is_some());
        assert!(classify("/api/files/abc").is_some());
        assert!(classify("/api/books/abc").is_none());
        assert!(classify("/api/books/a/b/cover").is_none());
        assert!(classify("/api/files/").is_none());
        assert!(classify("/api/admin/snapshot").is_none());
    }
}
