//! Gzip for JSON responses (performance round #7).
//!
//! A sync's lists are JSON, and JSON compresses well: the full book listing of
//! a 5,000-book library is 4.4 MB as sent and about 0.2 MB gzipped. The app's
//! HTTP client (dart:io) already asks for gzip and inflates it transparently, as
//! do browsers for the console, so this is all on this side.
//!
//! A small middleware rather than `tower-http`'s `CompressionLayer`, for the
//! same reason as `observability`'s request ids: one job, and this server keeps
//! its dependency surface small. `flate2` is already compiled in (via `lopdf`
//! and `png`). Only JSON is touched: covers and book files are already
//! compressed formats, and they stream with `Range` support that a rewritten
//! body would break.

use std::io::Write;

use axum::body::Body;
use axum::extract::Request;
use axum::http::{HeaderValue, header};
use axum::middleware::Next;
use axum::response::Response;
use flate2::Compression;
use flate2::write::GzEncoder;

/// Smaller bodies go as they are: gzip's own framing is ~20 bytes, and a tiny
/// body gains nothing worth the CPU.
const MIN_BYTES: usize = 1024;

/// JSON bodies are built in memory by `axum::Json` anyway; this only bounds a
/// pathological one.
const MAX_BYTES: usize = 256 * 1024 * 1024;

pub async fn gzip_json(request: Request, next: Next) -> Response {
    let wants_gzip = request
        .headers()
        .get(header::ACCEPT_ENCODING)
        .and_then(|v| v.to_str().ok())
        .is_some_and(accepts_gzip);
    let response = next.run(request).await;
    if !wants_gzip
        || !is_json(&response)
        || response.headers().contains_key(header::CONTENT_ENCODING)
    {
        return response;
    }

    let (mut parts, body) = response.into_parts();
    let Ok(bytes) = axum::body::to_bytes(body, MAX_BYTES).await else {
        // Not a body we can hold; there is nothing left to send either way.
        return Response::from_parts(parts, Body::empty());
    };
    // Tells a cache between us and the client that the encoding depends on
    // what was asked for.
    parts
        .headers
        .append(header::VARY, HeaderValue::from_static("accept-encoding"));
    if bytes.len() < MIN_BYTES {
        return Response::from_parts(parts, Body::from(bytes));
    }

    // Off the async workers: a few MB of deflate is milliseconds of CPU, and a
    // small server (a Raspberry Pi) has few cores to share with other requests.
    let compressed = tokio::task::spawn_blocking(move || {
        let mut encoder = GzEncoder::new(Vec::new(), Compression::fast());
        encoder.write_all(&bytes)?;
        encoder.finish()
    })
    .await;
    match compressed {
        Ok(Ok(gz)) => {
            parts.headers.remove(header::CONTENT_LENGTH);
            parts
                .headers
                .insert(header::CONTENT_ENCODING, HeaderValue::from_static("gzip"));
            Response::from_parts(parts, Body::from(gz))
        }
        // Compressing into memory doesn't fail in practice; if it ever did, the
        // body it started from is gone, so answer honestly.
        _ => {
            let mut failed = Response::new(Body::empty());
            *failed.status_mut() = axum::http::StatusCode::INTERNAL_SERVER_ERROR;
            failed
        }
    }
}

fn is_json(response: &Response) -> bool {
    response
        .headers()
        .get(header::CONTENT_TYPE)
        .and_then(|v| v.to_str().ok())
        .is_some_and(|ct| ct.starts_with("application/json"))
}

/// Whether an `Accept-Encoding` value allows gzip — listed, and not with `q=0`.
fn accepts_gzip(value: &str) -> bool {
    value.split(',').any(|item| {
        let mut parts = item.split(';').map(str::trim);
        let coding = parts.next().unwrap_or("");
        let refused = parts.any(|p| {
            p.strip_prefix("q=")
                .and_then(|q| q.parse::<f32>().ok())
                .is_some_and(|q| q == 0.0)
        });
        (coding.eq_ignore_ascii_case("gzip") || coding == "*") && !refused
    })
}

#[cfg(test)]
mod tests {
    use super::accepts_gzip;

    #[test]
    fn reads_accept_encoding() {
        assert!(accepts_gzip("gzip"));
        assert!(accepts_gzip("deflate, gzip;q=0.8, br"));
        assert!(accepts_gzip("GZIP"));
        assert!(accepts_gzip("*"));
        assert!(!accepts_gzip("identity"));
        assert!(!accepts_gzip("br, deflate"));
        assert!(!accepts_gzip("gzip;q=0"));
        assert!(!accepts_gzip("gzip; q=0.0"));
    }
}
