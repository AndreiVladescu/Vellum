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
//! **Behind a reverse proxy that serves Vellum under a path prefix** (say
//! `https://host/vellum/`), the path a browser asks for and the path this
//! server sees can differ. The signature therefore never covers either raw
//! path: it covers the *canonical* path, `/api/...` relative to the API root,
//! with the configured prefix (`VELLUM_BASE_PATH`, opt-in) removed. Both ends
//! derive it from the same function ([`canonical`]), the server hands out the
//! finished public URL (so no client computes a path), and a proxy that strips
//! the prefix and one that does not verify identically. Nothing is read from
//! `X-Forwarded-*` headers, which any client can send. See docs/DEPLOYMENT.md.
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

/// The public path prefix Vellum is served under (`VELLUM_BASE_PATH`), or `""`.
///
/// Opt-in configuration, never inferred from a request: normalised to a leading
/// `/` and no trailing one, so `vellum`, `/vellum` and `/vellum/` are the same.
/// Empty (the default) changes nothing at all.
pub fn base_path() -> &'static str {
    static BASE: std::sync::LazyLock<String> = std::sync::LazyLock::new(|| {
        normalize_base(&std::env::var("VELLUM_BASE_PATH").unwrap_or_default())
    });
    &BASE
}

fn normalize_base(raw: &str) -> String {
    let trimmed = raw.trim().trim_matches('/');
    if trimmed.is_empty() {
        String::new()
    } else {
        format!("/{trimmed}")
    }
}

/// The path relative to the API root: `path` with `base` removed if (and only
/// if) it is there as whole segments.
///
/// This is what gets signed and verified, on both sides. A proxy that strips
/// its prefix delivers `/api/files/x`; one that forwards it delivers
/// `/vellum/api/files/x`; both canonicalise to `/api/files/x`. The prefix is
/// removed only at a segment boundary (`/vellumx/...` is left alone and then
/// fails [`classify`]), and only one copy of it, so no spelling of a path can
/// name a resource other than the one the signature was made for.
fn canonical<'a>(base: &str, path: &'a str) -> &'a str {
    if base.is_empty() {
        return path;
    }
    match path.strip_prefix(base) {
        Some(rest) if rest.starts_with('/') => rest,
        _ => path,
    }
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
    let key = key(state).await.ok()?;
    verify_with(
        &key,
        base_path(),
        path,
        query,
        chrono::Utc::now().timestamp(),
    )
}

/// [`verify`] with everything it depends on passed in, so the prefixed and
/// unprefixed setups can be tested side by side.
fn verify_with(key: &[u8], base: &str, path: &str, query: &str, now: i64) -> Option<String> {
    let path = canonical(base, path);
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
    if exp < now {
        return None;
    }
    let want = mac(key, u, path, exp);
    ct_eq(want.as_bytes(), sig.as_bytes()).then(|| u.to_string())
}

/// Signs one link: the signature is over the canonical path, and the result is
/// the public URL to hand to a browser (`base` + that path + the query). `None`
/// if the path is not one a link may point at.
fn sign_with(key: &[u8], base: &str, user_id: &str, path: &str, exp: i64) -> Option<String> {
    let path = canonical(base, path);
    classify(path)?;
    let sig = mac(key, user_id, path, exp);
    Some(format!("{base}{path}?u={user_id}&exp={exp}&sig={sig}"))
}

#[derive(Deserialize)]
pub struct LinksInput {
    pub paths: Vec<String>,
}

#[derive(Serialize)]
pub struct Link {
    pub path: String,
    /// Root-relative URL, ready to use as an `src`/`href`. It already carries
    /// the public path prefix when one is configured, so clients use it as is.
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
        let Some((kind, id)) = classify(canonical(base_path(), &path)) else {
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
        let Some(url) = sign_with(&key, base_path(), &user.id, &path, exp) else {
            continue;
        };
        links.push(Link {
            url,
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

    const KEY: &[u8] = b"test-signing-key";
    const NOW: i64 = 1_000;
    const EXP: i64 = NOW + 60;

    /// Splits a URL from `sign_with` into (path, query).
    fn split(url: &str) -> (&str, &str) {
        url.split_once('?').unwrap()
    }

    #[test]
    fn unprefixed_setup_signs_and_verifies_as_before() {
        let url = sign_with(KEY, "", "u1", "/api/files/f1", EXP).unwrap();
        let (path, query) = split(&url);
        assert_eq!(path, "/api/files/f1", "no prefix configured, none added");
        assert_eq!(
            verify_with(KEY, "", path, query, NOW).as_deref(),
            Some("u1")
        );
    }

    #[test]
    fn a_proxy_that_strips_the_prefix_still_verifies() {
        // The console asked for `/vellum/api/files/f1`; the server hands back a
        // URL under the prefix; the proxy strips it, so the server sees the
        // bare path. Same signature, same answer.
        let url = sign_with(KEY, "/vellum", "u1", "/api/files/f1", EXP).unwrap();
        let (public, query) = split(&url);
        assert_eq!(public, "/vellum/api/files/f1");
        let seen_by_server = public.strip_prefix("/vellum").unwrap();
        assert_eq!(
            verify_with(KEY, "/vellum", seen_by_server, query, NOW).as_deref(),
            Some("u1")
        );
    }

    #[test]
    fn a_proxy_that_keeps_the_prefix_verifies_too() {
        let url = sign_with(KEY, "/vellum", "u1", "/api/books/b1/cover", EXP).unwrap();
        let (public, query) = split(&url);
        assert_eq!(
            verify_with(KEY, "/vellum", public, query, NOW).as_deref(),
            Some("u1"),
            "the path as the proxy forwarded it, prefix and all"
        );
    }

    #[test]
    fn a_path_given_with_the_prefix_signs_the_same_resource() {
        let bare = sign_with(KEY, "/vellum", "u1", "/api/files/f1", EXP).unwrap();
        let prefixed = sign_with(KEY, "/vellum", "u1", "/vellum/api/files/f1", EXP).unwrap();
        assert_eq!(bare, prefixed);
    }

    #[test]
    fn a_signature_for_one_resource_never_opens_another() {
        let url = sign_with(KEY, "/vellum", "u1", "/api/files/f1", EXP).unwrap();
        let (_, query) = split(&url);
        for other in [
            "/api/files/f2",
            "/vellum/api/files/f2",
            "/api/books/f1/cover",
            "/vellum/vellum/api/files/f2",
            "/vellum/api/files/f1/extra",
            "/vellum/api/admin/snapshot",
        ] {
            assert_eq!(
                verify_with(KEY, "/vellum", other, query, NOW),
                None,
                "{other}"
            );
        }
        // And the same with no prefix configured.
        let url = sign_with(KEY, "", "u1", "/api/files/f1", EXP).unwrap();
        let (_, query) = split(&url);
        assert_eq!(verify_with(KEY, "", "/api/files/f2", query, NOW), None);
    }

    #[test]
    fn the_prefix_is_removed_only_as_whole_segments_and_only_once() {
        assert_eq!(canonical("/vellum", "/vellum/api/files/x"), "/api/files/x");
        assert_eq!(canonical("/vellum", "/api/files/x"), "/api/files/x");
        assert_eq!(
            canonical("/vellum", "/vellumx/api/files/x"),
            "/vellumx/api/files/x"
        );
        assert_eq!(canonical("/vellum", "/vellum"), "/vellum");
        assert_eq!(
            canonical("/vellum", "/vellum/vellum/api/files/x"),
            "/vellum/api/files/x",
            "one copy only; what is left is not an API path"
        );
        assert!(classify(canonical("/vellum", "/vellum/vellum/api/files/x")).is_none());
        assert_eq!(canonical("", "/vellum/api/files/x"), "/vellum/api/files/x");
    }

    #[test]
    fn a_prefix_that_was_not_configured_is_not_honoured() {
        // What `X-Forwarded-Prefix` trust would have allowed: a link made for a
        // prefixed deployment does not verify on one with none configured.
        let url = sign_with(KEY, "/vellum", "u1", "/api/files/f1", EXP).unwrap();
        let (public, query) = split(&url);
        assert_eq!(verify_with(KEY, "", public, query, NOW), None);
    }

    #[test]
    fn expired_wrong_user_and_wrong_key_are_refused() {
        let url = sign_with(KEY, "/vellum", "u1", "/api/files/f1", EXP).unwrap();
        let (public, query) = split(&url);
        assert_eq!(verify_with(KEY, "/vellum", public, query, EXP + 1), None);
        assert_eq!(
            verify_with(b"another key", "/vellum", public, query, NOW),
            None
        );
        let swapped = query.replace("u=u1", "u=u2");
        assert_eq!(verify_with(KEY, "/vellum", public, &swapped, NOW), None);
    }

    #[test]
    fn only_cover_and_file_paths_can_be_signed_under_a_prefix() {
        assert!(sign_with(KEY, "/vellum", "u1", "/api/admin/snapshot", EXP).is_none());
        assert!(sign_with(KEY, "/vellum", "u1", "/vellum/api/books/b1", EXP).is_none());
    }

    #[test]
    fn base_path_is_normalised() {
        assert_eq!(normalize_base(""), "");
        assert_eq!(normalize_base("/"), "");
        assert_eq!(normalize_base("vellum"), "/vellum");
        assert_eq!(normalize_base("/vellum/"), "/vellum");
        assert_eq!(normalize_base(" /a/b/ "), "/a/b");
    }
}
