//! Send a book to an e-reader by email (plan 5 #53).
//!
//! The SMTP host in these tests does not exist, so every send *fails at the
//! relay* — which is exactly what makes them useful: everything before the
//! relay (authorisation, the file/book check, the size cap, the rate limit,
//! address resolution) has to be settled first, and a 502 rather than a 404 or
//! a 403 is the proof that it was.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::json;
use tower::ServiceExt;
use vellum_server::{AppState, RateLimiter, connect_db, router, test_mailer};

struct Harness {
    app: axum::Router,
    db: sqlx::SqlitePool,
    data_dir: std::path::PathBuf,
}

async fn app(with_mail: bool, send_quota: usize) -> Harness {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_send_{id}.db"));
    let data_dir = std::env::temp_dir().join(format!("vellum_send_data_{id}"));
    tokio::fs::create_dir_all(data_dir.join("files"))
        .await
        .unwrap();
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let router = router(AppState {
        db: db.clone(),
        public_base_url: "http://test.local".into(),
        data_dir: data_dir.clone(),
        http: reqwest::Client::new(),
        max_upload_bytes: 8 * 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
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
            send_quota,
            std::time::Duration::from_secs(60),
        )),
        // A host that cannot resolve: nothing leaves the machine, and the
        // handler still runs to completion.
        mailer: with_mail.then(|| test_mailer("smtp.invalid.example", "vellum@example.com")),
        index_text: false,
        audit: false,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    });
    Harness {
        app: router,
        db,
        data_dir,
    }
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

async fn register(app: &axum::Router, email: &str) -> String {
    let (_, body) = call(
        app,
        "POST",
        "/api/auth/register",
        None,
        Some(json!({
            "email": email,
            "password": "a long enough passphrase",
            "display_name": "Owner",
        })),
    )
    .await;
    body["token"].as_str().unwrap().to_string()
}

async fn add_member(app: &axum::Router, master: &str, email: &str) -> String {
    let (status, _) = call(
        app,
        "POST",
        "/api/users",
        Some(master),
        Some(json!({
            "email": email,
            "password": "another good passphrase",
            "display_name": "Member",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, login) = call(
        app,
        "POST",
        "/api/auth/login",
        None,
        Some(json!({ "email": email, "password": "another good passphrase" })),
    )
    .await;
    login["token"].as_str().unwrap().to_string()
}

/// A book owned by [token]'s user, with one EPUB of [size] bytes on disk.
async fn seed_book(h: &Harness, token: &str, title: &str, size: usize) -> (String, String) {
    let (status, _) = call(
        &h.app,
        "PUT",
        &format!("/api/books/{title}"),
        Some(token),
        Some(json!({ "title": title })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let file_id = uuid::Uuid::new_v4().to_string();
    let rel = format!("files/{file_id}.epub");
    tokio::fs::write(h.data_dir.join(&rel), vec![b'x'; size])
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO book_file (id, book_id, format, path, size_bytes, sha256) \
         VALUES (?, ?, 'epub', ?, ?, 'deadbeef')",
    )
    .bind(&file_id)
    .bind(title)
    .bind(&rel)
    .bind(size as i64)
    .execute(&h.db)
    .await
    .unwrap();
    (title.to_string(), file_id)
}

#[tokio::test]
async fn a_send_reaches_the_relay_and_reports_its_refusal() {
    let h = app(true, 100).await;
    let token = register(&h.app, "owner@lib.test").await;
    let (book, file) = seed_book(&h, &token, "Dune", 32).await;

    let (status, body) = call(
        &h.app,
        "POST",
        &format!("/api/books/{book}/send"),
        Some(&token),
        Some(json!({ "file_id": file, "to": "reader@kindle.com" })),
    )
    .await;

    // 502, not 500: everything this server controls succeeded, and the message
    // has to be actionable rather than swallowed as an internal error.
    assert_eq!(status, StatusCode::BAD_GATEWAY, "{body}");
    assert!(
        body["error"].as_str().unwrap().contains("approved"),
        "the error should name the two things a user can fix: {body}"
    );
}

#[tokio::test]
async fn a_server_without_mail_says_so_instead_of_failing() {
    let h = app(false, 100).await;
    let token = register(&h.app, "owner@lib.test").await;
    let (book, file) = seed_book(&h, &token, "Dune", 32).await;

    let (status, body) = call(
        &h.app,
        "POST",
        &format!("/api/books/{book}/send"),
        Some(&token),
        Some(json!({ "file_id": file, "to": "reader@kindle.com" })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(body["error"].as_str().unwrap().contains("outbound email"));
}

#[tokio::test]
async fn only_a_book_you_can_see_can_be_sent() {
    let h = app(true, 100).await;
    let master = register(&h.app, "owner@lib.test").await;
    let stranger = add_member(&h.app, &master, "member@lib.test").await;
    let (book, file) = seed_book(&h, &master, "Private", 32).await;

    let (status, _) = call(
        &h.app,
        "POST",
        &format!("/api/books/{book}/send"),
        Some(&stranger),
        Some(json!({ "file_id": file, "to": "reader@kindle.com" })),
    )
    .await;
    // 404, not 403: a 403 would confirm the book exists.
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn a_file_belonging_to_another_book_cannot_be_smuggled_out() {
    // Without the book_id check this would let a caller send any file they can
    // name through any book they happen to be allowed to see.
    let h = app(true, 100).await;
    let token = register(&h.app, "owner@lib.test").await;
    let (visible, _) = seed_book(&h, &token, "Visible", 32).await;
    let (_, other_file) = seed_book(&h, &token, "Other", 32).await;

    let (status, _) = call(
        &h.app,
        "POST",
        &format!("/api/books/{visible}/send"),
        Some(&token),
        Some(json!({ "file_id": other_file, "to": "reader@kindle.com" })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn a_file_over_the_cap_is_refused_with_a_number() {
    let h = app(true, 100).await;
    let token = register(&h.app, "owner@lib.test").await;
    // One byte over, so the test doesn't depend on the exact cap.
    let over = (vellum_server::MAX_ATTACHMENT_BYTES + 1) as usize;
    let (book, file) = seed_book(&h, &token, "Huge", over).await;

    let (status, body) = call(
        &h.app,
        "POST",
        &format!("/api/books/{book}/send"),
        Some(&token),
        Some(json!({ "file_id": file, "to": "reader@kindle.com" })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let error = body["error"].as_str().unwrap();
    assert!(error.contains("MB"), "the user needs a number: {error}");
}

#[tokio::test]
async fn sending_is_rate_limited_per_user() {
    let h = app(true, 2).await;
    let token = register(&h.app, "owner@lib.test").await;
    let (book, file) = seed_book(&h, &token, "Dune", 32).await;
    let body = json!({ "file_id": file, "to": "reader@kindle.com" });

    for _ in 0..2 {
        let (status, _) = call(
            &h.app,
            "POST",
            &format!("/api/books/{book}/send"),
            Some(&token),
            Some(body.clone()),
        )
        .await;
        assert_eq!(status, StatusCode::BAD_GATEWAY, "within quota");
    }
    let (status, _) = call(
        &h.app,
        "POST",
        &format!("/api/books/{book}/send"),
        Some(&token),
        Some(body),
    )
    .await;
    assert_eq!(status, StatusCode::TOO_MANY_REQUESTS);
}

#[tokio::test]
async fn a_malformed_address_is_refused_before_anything_is_read() {
    let h = app(true, 100).await;
    let token = register(&h.app, "owner@lib.test").await;
    let (book, file) = seed_book(&h, &token, "Dune", 32).await;

    for bad in ["nope", "a@b", "two@@at.com", "with space@x.com", "@x.com"] {
        let (status, _) = call(
            &h.app,
            "POST",
            &format!("/api/books/{book}/send"),
            Some(&token),
            Some(json!({ "file_id": file, "to": bad })),
        )
        .await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "should refuse {bad:?}");
    }
}

#[tokio::test]
async fn saved_targets_round_trip_and_can_be_sent_to_by_label() {
    let h = app(true, 100).await;
    let token = register(&h.app, "owner@lib.test").await;
    let (book, file) = seed_book(&h, &token, "Dune", 32).await;

    let (status, body) = call(
        &h.app,
        "PUT",
        "/api/send-targets",
        Some(&token),
        Some(json!([
            { "label": "My Kindle", "address": "reader@kindle.com" },
            { "label": "Kobo", "address": "reader@kobo.com" },
        ])),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");

    let (_, listed) = call(&h.app, "GET", "/api/send-targets", Some(&token), None).await;
    assert_eq!(listed.as_array().unwrap().len(), 2);
    assert_eq!(listed[0]["label"], "My Kindle");

    // Sending by label resolves to the saved address; case-insensitively, since
    // the label is a human name rather than a key.
    let (status, _) = call(
        &h.app,
        "POST",
        &format!("/api/books/{book}/send"),
        Some(&token),
        Some(json!({ "file_id": file, "label": "my kindle" })),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::BAD_GATEWAY,
        "resolved, then hit the relay"
    );

    let (status, _) = call(
        &h.app,
        "POST",
        &format!("/api/books/{book}/send"),
        Some(&token),
        Some(json!({ "file_id": file, "label": "Nonexistent" })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn saved_targets_are_per_user() {
    let h = app(true, 100).await;
    let master = register(&h.app, "owner@lib.test").await;
    let member = add_member(&h.app, &master, "member@lib.test").await;

    call(
        &h.app,
        "PUT",
        "/api/send-targets",
        Some(&master),
        Some(json!([{ "label": "Mine", "address": "owner@kindle.com" }])),
    )
    .await;

    let (_, theirs) = call(&h.app, "GET", "/api/send-targets", Some(&member), None).await;
    assert_eq!(theirs.as_array().unwrap().len(), 0);
}

#[tokio::test]
async fn a_saved_target_with_a_bad_address_is_refused() {
    let h = app(true, 100).await;
    let token = register(&h.app, "owner@lib.test").await;
    let (status, _) = call(
        &h.app,
        "PUT",
        "/api/send-targets",
        Some(&token),
        Some(json!([{ "label": "Broken", "address": "not-an-address" }])),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn send_to_device_is_advertised_only_when_mail_is_configured() {
    let with = app(true, 100).await;
    let (_, caps) = call(&with.app, "GET", "/api/capabilities", None, None).await;
    let features = caps["features"].as_array().unwrap();
    assert!(features.contains(&json!("mail")));
    assert!(features.contains(&json!("send_to_device")));

    let without = app(false, 100).await;
    let (_, caps) = call(&without.app, "GET", "/api/capabilities", None, None).await;
    let features = caps["features"].as_array().unwrap();
    assert!(!features.contains(&json!("send_to_device")));
}

#[tokio::test]
async fn anonymous_callers_are_rejected() {
    let h = app(true, 100).await;
    let token = register(&h.app, "owner@lib.test").await;
    let (book, file) = seed_book(&h, &token, "Dune", 32).await;

    let (status, _) = call(
        &h.app,
        "POST",
        &format!("/api/books/{book}/send"),
        None,
        Some(json!({ "file_id": file, "to": "reader@kindle.com" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[test]
fn an_attachment_is_named_so_the_recipient_can_convert_it() {
    // send-to-Kindle decides how to convert by the suffix, so a book delivered
    // as `Dune` rather than `Dune.epub` is silently dropped.
    assert_eq!(
        vellum_server::attachment_name("Dune", "EPUB"),
        "Dune.epub",
        "the extension must survive, lowercased"
    );
    assert_eq!(
        vellum_server::attachment_name("Gödel, Escher, Bach", "pdf"),
        "Gödel Escher Bach.pdf",
        "punctuation out, one space between words"
    );
    assert_eq!(vellum_server::attachment_name("///", "epub"), "book.epub");
}
