//! The shared duplicate check (next features #5).
//!
//! The reason it is server-side at all: the console and the app both import
//! catalogues, and two implementations would disagree about what counts as a
//! duplicate — so the same CSV would build a different library depending on
//! which one you used. These pin the three rules and, just as importantly, that
//! a collision in someone *else's* books is not reported.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::json;
use tower::ServiceExt;
use vellum_server::{AppState, EventBus, RateLimiter, connect_db, router};

async fn app() -> axum::Router {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_impchk_{id}.db"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    router(AppState {
        db,
        public_base_url: "http://test.local".into(),
        data_dir: std::env::temp_dir().join(format!("vellum_impchk_data_{id}")),
        http: reqwest::Client::new(),
        max_upload_bytes: 16 * 1024 * 1024,
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

async fn register(app: &axum::Router, email: &str) -> String {
    let (_, body) = call(
        app,
        "POST",
        "/api/auth/register",
        None,
        Some(json!({
            "email": email,
            "password": "a long enough passphrase",
            "display_name": "Someone",
        })),
    )
    .await;
    body["token"].as_str().unwrap().to_string()
}

async fn add_member(app: &axum::Router, master: &str, email: &str) -> String {
    call(
        app,
        "POST",
        "/api/users",
        Some(master),
        Some(json!({
            "email": email,
            "display_name": "Member",
            "password": "a long enough passphrase",
        })),
    )
    .await;
    let (_, body) = call(
        app,
        "POST",
        "/api/auth/login",
        None,
        Some(json!({ "email": email, "password": "a long enough passphrase" })),
    )
    .await;
    body["token"].as_str().unwrap().to_string()
}

async fn check(
    app: &axum::Router,
    token: &str,
    candidates: serde_json::Value,
) -> serde_json::Value {
    let (status, body) = call(
        app,
        "POST",
        "/api/import/check",
        Some(token),
        Some(json!({ "candidates": candidates })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body
}

#[tokio::test]
async fn an_equal_isbn_is_reported_as_certain() {
    let app = app().await;
    let token = register(&app, "master@lib.test").await;
    call(
        &app,
        "POST",
        "/api/books",
        Some(&token),
        Some(json!({ "title": "Dune", "isbn": "978-0-441-01359-3" })),
    )
    .await;

    // Written the other way round, and with the hyphens gone.
    let body = check(
        &app,
        &token,
        json!([{ "key": "row-1", "title": "Something Else", "isbn": "9780441013593" }]),
    )
    .await;
    let v = &body[0];
    assert_eq!(v["reason"], "same_isbn");
    assert_eq!(v["certain"], true);
    assert_eq!(v["title"], "Dune");
}

#[tokio::test]
async fn a_similar_title_is_a_suggestion_and_a_different_book_is_not_flagged() {
    let app = app().await;
    let token = register(&app, "master@lib.test").await;
    call(
        &app,
        "PUT",
        "/api/books/lhod",
        Some(&token),
        Some(json!({ "title": "The Left Hand of Darkness", "authors": ["Ursula K. Le Guin"] })),
    )
    .await;

    let body = check(
        &app,
        &token,
        json!([
            { "key": "same", "title": "left hand of darkness",
              "authors": ["ursula k le guin"] },
            { "key": "sequel", "title": "The Dispossessed",
              "authors": ["Ursula K. Le Guin"] },
        ]),
    )
    .await;

    assert_eq!(body[0]["reason"], "similar_title");
    assert_eq!(
        body[0]["certain"], false,
        "a title match is a suggestion, never a certainty"
    );
    assert!(
        body[1]["reason"].is_null(),
        "a different book by the same author is not a duplicate: {}",
        body[1]
    );
}

#[tokio::test]
async fn a_title_match_needs_the_authors_to_agree() {
    let app = app().await;
    let token = register(&app, "master@lib.test").await;
    call(
        &app,
        "PUT",
        "/api/books/poems",
        Some(&token),
        Some(json!({ "title": "Selected Poems", "authors": ["Emily Dickinson"] })),
    )
    .await;

    let body = check(
        &app,
        &token,
        json!([{ "key": "other", "title": "Selected Poems", "authors": ["W. B. Yeats"] }]),
    )
    .await;
    assert!(
        body[0]["reason"].is_null(),
        "two different poets' Selected Poems are two books: {}",
        body[0]
    );
}

#[tokio::test]
async fn a_fresh_row_collides_with_nothing() {
    let app = app().await;
    let token = register(&app, "master@lib.test").await;
    let body = check(
        &app,
        &token,
        json!([{ "key": "new", "title": "Piranesi", "authors": ["Susanna Clarke"] }]),
    )
    .await;
    assert!(body[0]["reason"].is_null());
    assert_eq!(
        body[0]["key"], "new",
        "the key is echoed back for lining up"
    );
}

#[tokio::test]
async fn a_collision_in_a_book_you_cannot_see_is_not_reported() {
    // The privacy half: telling a member their import matches a book they have
    // no access to would leak both its existence and its title.
    let app = app().await;
    let master = register(&app, "master@lib.test").await;
    let member = add_member(&app, &master, "member@lib.test").await;
    call(
        &app,
        "POST",
        "/api/books",
        Some(&master),
        Some(json!({ "title": "A Private Diary", "isbn": "9780441013593" })),
    )
    .await;

    let body = check(
        &app,
        &member,
        json!([{ "key": "row", "title": "Anything", "isbn": "9780441013593" }]),
    )
    .await;
    assert!(
        body[0]["reason"].is_null(),
        "leaked a book the caller cannot see: {}",
        body[0]
    );
}
