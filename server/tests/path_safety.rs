//! Ids arrive from the URL and end up in filesystem paths.
//!
//! `covers/{id}.jpg`, `copy-photos/{id}` and friends are all built by
//! interpolating a path parameter into a relative path. axum percent-decodes a
//! captured segment, so `..%2F..%2Fx` reaches the handler as `../../x` — and
//! ids are client-chosen on the sync endpoints (a `PUT /books/{id}` creates the
//! book under whatever id the caller picked). These pin that a hostile id can
//! never name a file outside the data directory.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;
use vellum_server::{AppState, EventBus, RateLimiter, connect_db, router};

struct Harness {
    app: axum::Router,
    data_dir: std::path::PathBuf,
}

async fn app() -> Harness {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_paths_{id}.db"));
    let data_dir = std::env::temp_dir().join(format!("vellum_paths_data_{id}"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let app = router(AppState {
        db,
        public_base_url: "http://test.local".into(),
        data_dir: data_dir.clone(),
        http: reqwest::Client::new(),
        max_upload_bytes: 16 * 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        enrich_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        basic_cache: std::sync::Arc::default(),
        public_limiter: std::sync::Arc::new(RateLimiter::new(
            1000,
            std::time::Duration::from_secs(60),
        )),
        search_limiter: std::sync::Arc::new(RateLimiter::new(
            1000,
            std::time::Duration::from_secs(60),
        )),
        send_limiter: std::sync::Arc::new(RateLimiter::new(
            1000,
            std::time::Duration::from_secs(60),
        )),
        events: EventBus::new(),
        mailer: None,
        index_text: false,
        audit: false,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    });
    Harness { app, data_dir }
}

async fn call(
    app: &axum::Router,
    method: &str,
    uri: &str,
    token: Option<&str>,
    body: Option<serde_json::Value>,
) -> (StatusCode, serde_json::Value) {
    let mut builder = Request::builder().method(method).uri(uri);
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
    let request = match body {
        Some(json) => builder
            .header("content-type", "application/json")
            .body(Body::from(json.to_string()))
            .unwrap(),
        None => builder.body(Body::empty()).unwrap(),
    };
    let res = app.clone().oneshot(request).await.unwrap();
    let status = res.status();
    let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
        .await
        .unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null),
    )
}

async fn master(app: &axum::Router) -> String {
    let (_, body) = call(
        app,
        "POST",
        "/api/auth/register",
        None,
        Some(serde_json::json!({
            "email": "master@lib.test",
            "password": "a long enough passphrase",
            "display_name": "M",
        })),
    )
    .await;
    body["token"].as_str().unwrap().to_string()
}

async fn put_bytes(
    app: &axum::Router,
    uri: &str,
    token: &str,
    content_type: &str,
    bytes: Vec<u8>,
) -> StatusCode {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(uri)
                .header("authorization", format!("Bearer {token}"))
                .header("content-type", content_type)
                .body(Body::from(bytes))
                .unwrap(),
        )
        .await
        .unwrap();
    res.status()
}

/// The smallest thing `sniff` will accept as a PNG.
fn png() -> Vec<u8> {
    let mut v = vec![0x89, b'P', b'N', b'G', 0x0d, 0x0a, 0x1a, 0x0a];
    v.extend_from_slice(&[0u8; 64]);
    v
}

/// `..%2F..%2Fescaped` as a book id, then a cover upload under it.
#[tokio::test]
async fn a_hostile_book_id_cannot_write_a_cover_outside_the_data_dir() {
    let h = app().await;
    let token = master(&h.app).await;

    let (status, _) = call(
        &h.app,
        "PUT",
        "/api/books/..%2F..%2Fescaped",
        Some(&token),
        Some(serde_json::json!({ "title": "Trouble" })),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::BAD_REQUEST,
        "an id that is not a plain identifier must be refused outright"
    );

    let status = put_bytes(
        &h.app,
        "/api/books/..%2F..%2Fescaped/cover",
        &token,
        "image/png",
        png(),
    )
    .await;
    assert_ne!(status, StatusCode::OK);

    let escaped = h.data_dir.join("../../escaped.jpg");
    assert!(
        !escaped.exists(),
        "wrote a cover outside the data directory: {}",
        escaped.display()
    );
}

/// The same shape one level deeper: a copy photo's bytes are stored at
/// `copy-photos/{id}`, and the id is chosen by whoever creates the row.
#[tokio::test]
async fn a_hostile_photo_id_cannot_write_an_image_outside_the_data_dir() {
    let h = app().await;
    let token = master(&h.app).await;

    let (_, book) = call(
        &h.app,
        "POST",
        "/api/books",
        Some(&token),
        Some(serde_json::json!({ "title": "Dune" })),
    )
    .await;
    let book = book["id"].as_str().unwrap().to_string();
    let (status, _) = call(
        &h.app,
        "PUT",
        "/api/copies/copy-1",
        Some(&token),
        Some(serde_json::json!({ "book_id": book })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (status, _) = call(
        &h.app,
        "PUT",
        "/api/copy-photos/..%2F..%2Fescaped-photo",
        Some(&token),
        Some(serde_json::json!({ "copy_id": "copy-1" })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    let status = put_bytes(
        &h.app,
        "/api/copy-photos/..%2F..%2Fescaped-photo/image",
        &token,
        "image/png",
        png(),
    )
    .await;
    assert_ne!(status, StatusCode::OK);

    let escaped = h.data_dir.join("../../escaped-photo");
    assert!(
        !escaped.exists(),
        "wrote a photo outside the data directory: {}",
        escaped.display()
    );
}

/// Ordinary ids — uuids, and the readable ones the app and console generate —
/// must keep working. A validator that rejected these would break every client.
#[tokio::test]
async fn ordinary_ids_are_still_accepted() {
    let h = app().await;
    let token = master(&h.app).await;

    for id in [
        uuid::Uuid::new_v4().to_string(),
        "book-1".to_string(),
        "A_book.2".to_string(),
    ] {
        let (status, _) = call(
            &h.app,
            "PUT",
            &format!("/api/books/{id}"),
            Some(&token),
            Some(serde_json::json!({ "title": "Fine" })),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "rejected a legitimate id: {id}");
    }
}
