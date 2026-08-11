//! Borrow requests (plan 5 #49).
//!
//! The two properties that matter: you can only request what you can already
//! see (so this adds no new way to learn what exists), and an approval creates
//! the loan **atomically** — a request that looks decided with no loan behind it
//! is worse than no feature.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;
use vellum_server::{AppState, EventBus, RateLimiter, connect_db, router};

async fn app() -> (axum::Router, sqlx::SqlitePool) {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_borrow_{id}.db"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let router = router(AppState {
        db: db.clone(),
        public_base_url: "http://test.local".into(),
        data_dir: std::env::temp_dir().join(format!("vellum_borrow_data_{id}")),
        http: reqwest::Client::new(),
        max_upload_bytes: 8 * 1024 * 1024,
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
    (router, db)
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

async fn register(app: &axum::Router) -> String {
    let (_, body) = call(
        app,
        "POST",
        "/api/auth/register",
        None,
        Some(serde_json::json!({
            "email": "owner@lib.test",
            "password": "a long enough passphrase",
            "display_name": "Owner",
        })),
    )
    .await;
    body["token"].as_str().unwrap().to_string()
}

async fn member(app: &axum::Router, master: &str, email: &str) -> String {
    let (status, _) = call(
        app,
        "POST",
        "/api/users",
        Some(master),
        Some(serde_json::json!({
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
        Some(serde_json::json!({
            "email": email,
            "password": "another good passphrase",
        })),
    )
    .await;
    login["token"].as_str().unwrap().to_string()
}

/// A book owned by `token`, with one physical copy, shared with `email`.
async fn shared_book(
    app: &axum::Router,
    token: &str,
    title: &str,
    share_with: Option<&str>,
) -> (String, String) {
    let (_, created) = call(
        app,
        "POST",
        "/api/books",
        Some(token),
        Some(serde_json::json!({ "title": title })),
    )
    .await;
    let book = created["id"].as_str().unwrap().to_string();

    let copy = uuid::Uuid::new_v4().to_string();
    let (status, _) = call(
        app,
        "PUT",
        &format!("/api/copies/{copy}"),
        Some(token),
        Some(serde_json::json!({ "book_id": book })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "creating a copy");

    if let Some(email) = share_with {
        let (status, _) = call(
            app,
            "POST",
            "/api/shares",
            Some(token),
            Some(serde_json::json!({
                "grantee_email": email,
                "scope": "book",
                "scope_id": book,
                "permission": "viewer",
            })),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
    }
    (book, copy)
}

#[tokio::test]
async fn a_visible_book_can_be_requested_and_approving_lends_it() {
    let (app, _db) = app().await;
    let owner = register(&app).await;
    let other = member(&app, &owner, "reader@lib.test").await;
    let (book, copy) = shared_book(&app, &owner, "Dune", Some("reader@lib.test")).await;

    let (status, request) = call(
        &app,
        "POST",
        "/api/borrow-requests",
        Some(&other),
        Some(serde_json::json!({ "book_id": book, "note": "for the weekend" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(request["status"], "pending");
    assert_eq!(request["book_title"], "Dune");
    assert_eq!(request["requester_email"], "reader@lib.test");
    let id = request["id"].as_str().unwrap().to_string();

    // The owner sees it in their inbox; the requester in their outbox.
    let (_, incoming) = call(&app, "GET", "/api/borrow-requests", Some(&owner), None).await;
    assert_eq!(incoming.as_array().unwrap().len(), 1);
    let (_, outgoing) = call(
        &app,
        "GET",
        "/api/borrow-requests?direction=outgoing",
        Some(&other),
        None,
    )
    .await;
    assert_eq!(outgoing.as_array().unwrap().len(), 1);
    // ...and not in each other's.
    let (_, none) = call(
        &app,
        "GET",
        "/api/borrow-requests?direction=outgoing",
        Some(&owner),
        None,
    )
    .await;
    assert!(none.as_array().unwrap().is_empty());

    let (status, decided) = call(
        &app,
        "POST",
        &format!("/api/borrow-requests/{id}/decide"),
        Some(&owner),
        Some(serde_json::json!({ "status": "approved", "due_at": "2026-09-01" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(decided["status"], "approved");
    assert!(decided["loan_id"].is_string(), "an approval creates a loan");

    // And the loan is real, on the book's copy, due when the owner said.
    let (_, loans) = call(&app, "GET", "/api/loans", Some(&owner), None).await;
    let loan = loans.as_array().unwrap().first().expect("a loan");
    assert_eq!(loan["copy_id"], copy);
    assert_eq!(loan["borrower"], "reader@lib.test");
    assert_eq!(loan["due_at"], "2026-09-01");
    assert!(loan["returned_at"].is_null());
}

#[tokio::test]
async fn a_book_you_cannot_see_cannot_be_requested_or_probed() {
    let (app, _db) = app().await;
    let owner = register(&app).await;
    let other = member(&app, &owner, "reader@lib.test").await;
    let (book, _) = shared_book(&app, &owner, "Private", None).await;

    // 404, not 403 — a request endpoint must not become an existence oracle.
    let (status, _) = call(
        &app,
        "POST",
        "/api/borrow-requests",
        Some(&other),
        Some(serde_json::json!({ "book_id": book })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (status, _) = call(
        &app,
        "POST",
        "/api/borrow-requests",
        Some(&other),
        Some(serde_json::json!({ "book_id": "no-such-book" })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn you_cannot_request_your_own_book() {
    let (app, _db) = app().await;
    let owner = register(&app).await;
    let (book, _) = shared_book(&app, &owner, "Mine", None).await;
    let (status, body) = call(
        &app,
        "POST",
        "/api/borrow-requests",
        Some(&owner),
        Some(serde_json::json!({ "book_id": book })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(body["error"].as_str().unwrap().contains("just lend it"));
}

#[tokio::test]
async fn one_live_request_per_person_per_book() {
    // Without this, a refresh-happy requester becomes a queue of identical rows
    // in somebody's inbox.
    let (app, _db) = app().await;
    let owner = register(&app).await;
    let other = member(&app, &owner, "reader@lib.test").await;
    let (book, _) = shared_book(&app, &owner, "Dune", Some("reader@lib.test")).await;

    let ask = serde_json::json!({ "book_id": book });
    let (status, _) = call(
        &app,
        "POST",
        "/api/borrow-requests",
        Some(&other),
        Some(ask.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, body) = call(
        &app,
        "POST",
        "/api/borrow-requests",
        Some(&other),
        Some(ask.clone()),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert!(body["error"].as_str().unwrap().contains("already"));

    // Once it is decided, asking again is allowed — the constraint is on *live*
    // requests, not on ever having asked.
    let (_, list) = call(&app, "GET", "/api/borrow-requests", Some(&owner), None).await;
    let id = list.as_array().unwrap()[0]["id"]
        .as_str()
        .unwrap()
        .to_string();
    call(
        &app,
        "POST",
        &format!("/api/borrow-requests/{id}/decide"),
        Some(&owner),
        Some(serde_json::json!({ "status": "declined", "reply": "sorry" })),
    )
    .await;
    let (status, _) = call(
        &app,
        "POST",
        "/api/borrow-requests",
        Some(&other),
        Some(ask),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
}

#[tokio::test]
async fn a_decided_request_cannot_be_decided_again() {
    let (app, _db) = app().await;
    let owner = register(&app).await;
    let other = member(&app, &owner, "reader@lib.test").await;
    let (book, _) = shared_book(&app, &owner, "Dune", Some("reader@lib.test")).await;
    let (_, request) = call(
        &app,
        "POST",
        "/api/borrow-requests",
        Some(&other),
        Some(serde_json::json!({ "book_id": book })),
    )
    .await;
    let id = request["id"].as_str().unwrap().to_string();

    let (status, _) = call(
        &app,
        "POST",
        &format!("/api/borrow-requests/{id}/decide"),
        Some(&owner),
        Some(serde_json::json!({ "status": "declined", "reply": "not this one" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // A declined request must not be approvable afterwards — that would create
    // a loan for a request the requester was told was refused.
    let (status, body) = call(
        &app,
        "POST",
        &format!("/api/borrow-requests/{id}/decide"),
        Some(&owner),
        Some(serde_json::json!({ "status": "approved" })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert!(body["error"].as_str().unwrap().contains("declined"));

    let (_, loans) = call(&app, "GET", "/api/loans", Some(&owner), None).await;
    assert!(loans.as_array().unwrap().is_empty());
}

#[tokio::test]
async fn only_the_owner_answers_and_only_the_requester_cancels() {
    // Both parties are ordinary members here, not the master: the master can do
    // anything by design, so testing this rule against it would prove nothing.
    let (app, _db) = app().await;
    let master = register(&app).await;
    let owner = member(&app, &master, "lender@lib.test").await;
    let other = member(&app, &master, "reader@lib.test").await;
    let (book, _) = shared_book(&app, &owner, "Dune", Some("reader@lib.test")).await;
    let (_, request) = call(
        &app,
        "POST",
        "/api/borrow-requests",
        Some(&other),
        Some(serde_json::json!({ "book_id": book })),
    )
    .await;
    let id = request["id"].as_str().unwrap().to_string();

    // The requester cannot approve their own request into a loan.
    let (status, _) = call(
        &app,
        "POST",
        &format!("/api/borrow-requests/{id}/decide"),
        Some(&other),
        Some(serde_json::json!({ "status": "approved" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // The owner cannot cancel it on the requester's behalf.
    let (status, _) = call(
        &app,
        "POST",
        &format!("/api/borrow-requests/{id}/decide"),
        Some(&owner),
        Some(serde_json::json!({ "status": "cancelled" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // The requester can withdraw it.
    let (status, cancelled) = call(
        &app,
        "POST",
        &format!("/api/borrow-requests/{id}/decide"),
        Some(&other),
        Some(serde_json::json!({ "status": "cancelled" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(cancelled["status"], "cancelled");
}

#[tokio::test]
async fn a_stranger_cannot_see_or_touch_someone_elses_request() {
    let (app, _db) = app().await;
    let owner = register(&app).await;
    let other = member(&app, &owner, "reader@lib.test").await;
    let third = member(&app, &owner, "third@lib.test").await;
    let (book, _) = shared_book(&app, &owner, "Dune", Some("reader@lib.test")).await;
    let (_, request) = call(
        &app,
        "POST",
        "/api/borrow-requests",
        Some(&other),
        Some(serde_json::json!({ "book_id": book })),
    )
    .await;
    let id = request["id"].as_str().unwrap().to_string();

    let (status, _) = call(
        &app,
        "POST",
        &format!("/api/borrow-requests/{id}/decide"),
        Some(&third),
        Some(serde_json::json!({ "status": "approved" })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (_, theirs) = call(&app, "GET", "/api/borrow-requests", Some(&third), None).await;
    assert!(theirs.as_array().unwrap().is_empty());
}

#[tokio::test]
async fn approving_a_book_with_no_free_copy_is_refused_not_double_lent() {
    let (app, _db) = app().await;
    let owner = register(&app).await;
    let other = member(&app, &owner, "reader@lib.test").await;
    let (book, copy) = shared_book(&app, &owner, "Dune", Some("reader@lib.test")).await;

    // The only copy is already out.
    let loan = uuid::Uuid::new_v4().to_string();
    let (status, _) = call(
        &app,
        "PUT",
        &format!("/api/loans/{loan}"),
        Some(&owner),
        Some(serde_json::json!({
            "copy_id": copy,
            "borrower": "Someone else",
            "loaned_at": "2026-07-01 10:00:00",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (_, request) = call(
        &app,
        "POST",
        "/api/borrow-requests",
        Some(&other),
        Some(serde_json::json!({ "book_id": book })),
    )
    .await;
    let id = request["id"].as_str().unwrap().to_string();

    let (status, body) = call(
        &app,
        "POST",
        &format!("/api/borrow-requests/{id}/decide"),
        Some(&owner),
        Some(serde_json::json!({ "status": "approved" })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(body["error"].as_str().unwrap().contains("free to lend"));

    // The request is untouched, so the owner can free a copy and approve later.
    let (_, list) = call(&app, "GET", "/api/borrow-requests", Some(&owner), None).await;
    assert_eq!(list.as_array().unwrap()[0]["status"], "pending");
}

#[tokio::test]
async fn requests_can_be_filtered_by_status() {
    let (app, _db) = app().await;
    let owner = register(&app).await;
    let other = member(&app, &owner, "reader@lib.test").await;
    let (a, _) = shared_book(&app, &owner, "A", Some("reader@lib.test")).await;
    let (b, _) = shared_book(&app, &owner, "B", Some("reader@lib.test")).await;
    for book in [&a, &b] {
        call(
            &app,
            "POST",
            "/api/borrow-requests",
            Some(&other),
            Some(serde_json::json!({ "book_id": book })),
        )
        .await;
    }
    let (_, all) = call(&app, "GET", "/api/borrow-requests", Some(&owner), None).await;
    let first = all.as_array().unwrap()[0]["id"]
        .as_str()
        .unwrap()
        .to_string();
    call(
        &app,
        "POST",
        &format!("/api/borrow-requests/{first}/decide"),
        Some(&owner),
        Some(serde_json::json!({ "status": "approved" })),
    )
    .await;

    let (_, pending) = call(
        &app,
        "GET",
        "/api/borrow-requests?status=pending",
        Some(&owner),
        None,
    )
    .await;
    assert_eq!(pending.as_array().unwrap().len(), 1);
    assert_eq!(pending.as_array().unwrap()[0]["status"], "pending");
}

#[tokio::test]
async fn borrow_requests_are_advertised_as_a_capability() {
    let (app, _db) = app().await;
    let (_, caps) = call(&app, "GET", "/api/capabilities", None, None).await;
    assert!(
        caps["features"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f == "borrow_requests")
    );
}
