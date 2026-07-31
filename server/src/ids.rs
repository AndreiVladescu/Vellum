//! One rule for every client-chosen id.
//!
//! **Why this exists.** Sync is id-driven: `PUT /books/{id}` creates the book
//! under whatever id the caller picked, and the same is true of shelves,
//! copies, loans, annotations and copy photos. Several of those ids then become
//! filesystem paths — `covers/{id}.jpg`, `copy-photos/{id}` — and axum
//! percent-decodes a captured path segment, so `..%2F..%2Fx` arrives at the
//! handler as `../../x`. That was enough for any account with edit rights to
//! write a file anywhere the server process could write: create a book with
//! that id, then upload its cover.
//!
//! The fix is a whitelist rather than a blacklist, applied at the boundary.
//! Every id this project generates is a UUID; the console and older imports
//! also produce readable ones like `book-1`, so letters, digits, `.`, `-` and
//! `_` are all allowed. Nothing else is, `.`/`..` are refused by name, and the
//! length is bounded so an id can't be used to build a pathological filename.
//!
//! Reads are validated too, not just writes: `GET /copy-photos/{id}/image`
//! builds the same path, and a traversal there reads a file rather than writing
//! one.

use axum::response::IntoResponse;

use crate::error::{AppError, AppResult};

/// The longest id we accept. A UUID is 36; the slack is for prefixed ids
/// (`copy-<uuid>`) without leaving room for a 4 KB path.
const MAX_ID: usize = 128;

/// True when `id` is safe to use as a primary key and as a single path segment.
pub fn is_valid(id: &str) -> bool {
    !id.is_empty()
        && id.len() <= MAX_ID
        && id != "."
        && id != ".."
        && id
            .chars()
            .all(|c| c.is_ascii_alphanumeric() || c == '-' || c == '_' || c == '.')
}

/// [`is_valid`] as a request guard. `what` names the thing in the error, so a
/// client sees "invalid book id" rather than a bare 400.
pub fn check(what: &str, id: &str) -> AppResult<()> {
    if is_valid(id) {
        Ok(())
    } else {
        Err(AppError::BadRequest(format!("invalid {what} id")))
    }
}

/// The global half of the fix: refuse a request whose URL path hides a
/// separator inside a segment.
///
/// [`check`] is applied per handler, but a handler that forgets it is one route
/// away from the bug coming back — and every route here takes an id. This runs
/// before any of them and rejects the transformation itself: a `%2F`, `%5C` or
/// `%00` that only becomes path-significant *after* axum decodes the segment,
/// and a segment that decodes to `.` or `..`.
///
/// Checking the raw path means wildcard routes (`/read/asset/{*name}`) are
/// unaffected: their separators are real ones in the URL, not smuggled ones.
pub async fn reject_smuggled_separators(
    req: axum::extract::Request,
    next: axum::middleware::Next,
) -> axum::response::Response {
    for segment in req.uri().path().split('/') {
        let decoded = decode(segment);
        if decoded == ".."
            || decoded == "."
            || decoded.contains('/')
            || decoded.contains('\\')
            || decoded.contains('\0')
        {
            return AppError::BadRequest("invalid path".into()).into_response();
        }
    }
    next.run(req).await
}

/// Percent-decoding, only as far as this check needs: bytes that don't form a
/// valid escape are left alone, and invalid UTF-8 is replaced rather than
/// rejected — a segment we can't decode cleanly still gets its separators seen.
fn decode(segment: &str) -> String {
    let bytes = segment.as_bytes();
    let mut out = Vec::with_capacity(bytes.len());
    let mut i = 0;
    while i < bytes.len() {
        if bytes[i] == b'%' && i + 2 < bytes.len() {
            let hex = std::str::from_utf8(&bytes[i + 1..i + 3])
                .ok()
                .and_then(|h| u8::from_str_radix(h, 16).ok());
            if let Some(byte) = hex {
                out.push(byte);
                i += 3;
                continue;
            }
        }
        out.push(bytes[i]);
        i += 1;
    }
    String::from_utf8_lossy(&out).into_owned()
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn decoding_sees_the_separator_a_client_tried_to_hide() {
        assert_eq!(decode("..%2F..%2Fetc"), "../../etc");
        assert_eq!(decode("%2e%2e"), "..");
        assert_eq!(decode("plain-id"), "plain-id");
        // A stray percent is not an escape, and must not eat the rest.
        assert_eq!(decode("100%"), "100%");
        assert_eq!(decode("%zz"), "%zz");
    }

    #[test]
    fn accepts_what_the_clients_actually_generate() {
        assert!(is_valid("550e8400-e29b-41d4-a716-446655440000"));
        assert!(is_valid("book-1"));
        assert!(is_valid("A_book.2"));
        assert!(is_valid("7"));
    }

    #[test]
    fn refuses_anything_that_could_leave_its_directory() {
        for hostile in [
            "",
            ".",
            "..",
            "../../etc/passwd",
            "../escaped",
            "a/b",
            "a\\b",
            "a\0b",
            "a b",
            "réal",
            "%2e%2e",
        ] {
            assert!(!is_valid(hostile), "accepted {hostile:?}");
        }
        assert!(!is_valid(&"a".repeat(MAX_ID + 1)));
    }
}
