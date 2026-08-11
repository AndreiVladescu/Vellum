//! One copy, one borrower — and the console's view of who has what.
//!
//! A loan is bookkeeping for a physical object, so the number of books that can
//! be out is the number of copies that exist. The borrow-request path always
//! checked that before approving, but the sync endpoint did not: a push (or a
//! direct `PUT`) could open a second loan on a copy that was already lent, and
//! then the library claimed two people were holding the same book. Migration
//! 0028 makes that impossible; these tests are about the rule holding at the
//! API, with an answer a person can act on rather than a constraint violation.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;
use vellum_server::{AppState, EventBus, RateLimiter, connect_db, router};

async fn app() -> axum::Router {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_loans_{id}.db"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    router(AppState {
        db,
        public_base_url: "http://test.local".into(),
        data_dir: std::env::temp_dir().join(format!("vellum_loans_data_{id}")),
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
    })
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

/// A book owned by `token` with one physical copy. Returns (book, copy).
async fn book_with_copy(app: &axum::Router, token: &str, title: &str) -> (String, String) {
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
    (book, copy)
}

async fn lend(
    app: &axum::Router,
    token: &str,
    copy: &str,
    borrower: &str,
    returned_at: Option<&str>,
) -> (String, StatusCode, serde_json::Value) {
    let id = uuid::Uuid::new_v4().to_string();
    let (status, body) = call(
        app,
        "PUT",
        &format!("/api/loans/{id}"),
        Some(token),
        Some(serde_json::json!({
            "copy_id": copy,
            "borrower": borrower,
            "loaned_at": "2026-01-01 09:00:00",
            "returned_at": returned_at,
        })),
    )
    .await;
    (id, status, body)
}

#[tokio::test]
async fn a_copy_that_is_out_cannot_be_lent_again() {
    let app = app().await;
    let owner = register(&app).await;
    let (_book, copy) = book_with_copy(&app, &owner, "Dune").await;

    let (_first, status, _) = lend(&app, &owner, &copy, "Alice", None).await;
    assert_eq!(status, StatusCode::OK, "the first lend is fine");

    let (_second, status, body) = lend(&app, &owner, &copy, "Bob", None).await;
    assert_eq!(
        status,
        StatusCode::CONFLICT,
        "the copy is in Alice's hands, so it cannot also be in Bob's"
    );
    // The message has to name who has it — "conflict" alone leaves the owner
    // with nothing to do about it.
    let message = body["error"].as_str().unwrap_or_default().to_string();
    assert!(
        message.contains("Alice"),
        "the refusal should say who has it, got: {message}"
    );
}

#[tokio::test]
async fn returning_it_frees_the_copy_for_the_next_borrower() {
    let app = app().await;
    let owner = register(&app).await;
    let (_book, copy) = book_with_copy(&app, &owner, "Dune").await;

    let (first, status, _) = lend(&app, &owner, &copy, "Alice", None).await;
    assert_eq!(status, StatusCode::OK);

    // The return is an update to the same loan — history is preserved, which is
    // the whole reason loans are their own table.
    let (status, _) = call(
        &app,
        "PUT",
        &format!("/api/loans/{first}"),
        Some(&owner),
        Some(serde_json::json!({
            "copy_id": copy,
            "borrower": "Alice",
            "loaned_at": "2026-01-01 09:00:00",
            "returned_at": "2026-02-01 09:00:00",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "marking it returned");

    let (_second, status, _) = lend(&app, &owner, &copy, "Bob", None).await;
    assert_eq!(status, StatusCode::OK, "the copy is back on the shelf");

    let (_, loans) = call(&app, "GET", "/api/loans", Some(&owner), None).await;
    assert_eq!(
        loans.as_array().unwrap().len(),
        2,
        "both loans are kept — the first is history, not a mistake"
    );
}

#[tokio::test]
async fn a_returning_loan_is_never_blocked_by_itself() {
    // The guard asks "is another loan open on this copy?", and the loan being
    // updated must not count as another. Getting this wrong would make a copy
    // impossible to return, which is worse than the bug it fixes.
    let app = app().await;
    let owner = register(&app).await;
    let (_book, copy) = book_with_copy(&app, &owner, "Dune").await;
    let (loan, _, _) = lend(&app, &owner, &copy, "Alice", None).await;

    // An ordinary edit that leaves the loan open: the due date moves.
    let (status, _) = call(
        &app,
        "PUT",
        &format!("/api/loans/{loan}"),
        Some(&owner),
        Some(serde_json::json!({
            "copy_id": copy,
            "borrower": "Alice",
            "loaned_at": "2026-01-01 09:00:00",
            "due_at": "2026-03-01 09:00:00",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "editing an open loan in place");
}

#[tokio::test]
async fn the_overview_shows_free_copies_and_who_has_the_rest() {
    let app = app().await;
    let owner = register(&app).await;
    let (_dune, lent) = book_with_copy(&app, &owner, "Dune").await;
    let (_solaris, free) = book_with_copy(&app, &owner, "Solaris").await;
    lend(&app, &owner, &lent, "Alice", None).await;

    let (status, rows) = call(&app, "GET", "/api/loans/overview", Some(&owner), None).await;
    assert_eq!(status, StatusCode::OK);
    let rows = rows.as_array().unwrap();
    assert_eq!(rows.len(), 2, "one row per copy, lent or not");

    let dune = rows
        .iter()
        .find(|r| r["copy_id"] == serde_json::json!(lent))
        .unwrap();
    assert_eq!(dune["book_title"], "Dune");
    assert_eq!(dune["borrower"], "Alice");
    assert_eq!(dune["can_edit"], true, "the owner may take it back");

    let solaris = rows
        .iter()
        .find(|r| r["copy_id"] == serde_json::json!(free))
        .unwrap();
    assert!(
        solaris["borrower"].is_null(),
        "a copy nobody has borrowed still has to appear — it is the one you can lend"
    );
}
