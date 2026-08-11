//! Live sync hints over SSE (plan 5 #8).
//!
//! The property that matters most is the one that isn't obvious from the
//! feature description: the stream must never mention a book the subscriber
//! cannot see. Fan-out is global, so without a per-subscriber filter this
//! endpoint would be an existence oracle over the whole library — the same hole
//! #46's RBAC matrix found in `books.rs`.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use futures_util::StreamExt;
use tower::ServiceExt;
use vellum_server::{AppState, EventBus, RateLimiter, connect_db, router};

async fn app() -> axum::Router {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_events_{id}.db"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    router(AppState {
        db,
        public_base_url: "http://test.local".into(),
        data_dir: std::env::temp_dir().join(format!("vellum_events_data_{id}")),
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

async fn register(app: &axum::Router, email: &str) -> String {
    let (_, body) = call(
        app,
        "POST",
        "/api/auth/register",
        None,
        Some(serde_json::json!({
            "email": email,
            "password": "a long enough passphrase",
            "display_name": "Owner",
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
        Some(serde_json::json!({
            "email": email,
            "password": "another good passphrase",
            "display_name": "Member",
        })),
    )
    .await;
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

/// Opens the stream and collects whatever arrives within [window].
///
/// Time-boxed rather than "read N events": the assertions below are as much
/// about what does *not* arrive as what does, and a read that blocks forever
/// waiting for a suppressed event is a hang rather than a failure.
async fn listen(
    app: &axum::Router,
    token: &str,
    window: std::time::Duration,
    trigger: impl std::future::Future<Output = ()>,
) -> String {
    let request = Request::builder()
        .method("GET")
        .uri("/api/events")
        .header("authorization", format!("Bearer {token}"))
        .body(Body::empty())
        .unwrap();
    let res = app.clone().oneshot(request).await.unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    assert_eq!(
        res.headers()
            .get("content-type")
            .and_then(|v| v.to_str().ok())
            .unwrap_or_default()
            .split(';')
            .next()
            .unwrap_or_default(),
        "text/event-stream"
    );

    let mut stream = res.into_body().into_data_stream();
    // Collected into a shared buffer rather than returned by the read future:
    // an SSE stream never ends, so the read is always cut short by the timeout,
    // and a future that only yields its result on completion would throw away
    // everything it had read. That mistake makes the negative assertions below
    // pass for the wrong reason, which is worse than failing.
    let seen = std::sync::Arc::new(std::sync::Mutex::new(String::new()));
    let sink = seen.clone();
    let collect = async move {
        while let Some(Ok(chunk)) = stream.next().await {
            sink.lock()
                .unwrap()
                .push_str(&String::from_utf8_lossy(&chunk));
        }
    };
    tokio::join!(
        async {
            let _ = tokio::time::timeout(window, collect).await;
        },
        async {
            // The subscription is live as soon as the handler runs; give it a
            // beat before the mutation so the event can't be published into an
            // empty channel.
            tokio::time::sleep(std::time::Duration::from_millis(50)).await;
            trigger.await;
        }
    );
    let collected = seen.lock().unwrap();
    collected.clone()
}

#[tokio::test]
async fn a_subscriber_hears_about_a_book_it_can_see() {
    let app = app().await;
    let token = register(&app, "owner@lib.test").await;

    let app2 = app.clone();
    let token2 = token.clone();
    let seen = listen(
        &app,
        &token,
        std::time::Duration::from_millis(600),
        async move {
            call(
                &app2,
                "PUT",
                "/api/books/dune",
                Some(&token2),
                Some(serde_json::json!({ "title": "Dune" })),
            )
            .await;
        },
    )
    .await;

    assert!(seen.contains("event: book"), "no book event in: {seen:?}");
    assert!(seen.contains("dune"), "the id should be there: {seen:?}");
    assert!(seen.contains("upsert"));
}

#[tokio::test]
async fn a_subscriber_never_hears_about_a_book_it_cannot_see() {
    // The whole reason the filter exists: fan-out is global.
    let app = app().await;
    let master = register(&app, "owner@lib.test").await;
    let stranger = add_member(&app, &master, "member@lib.test").await;

    let app2 = app.clone();
    let seen = listen(
        &app,
        &stranger,
        std::time::Duration::from_millis(600),
        async move {
            call(
                &app2,
                "PUT",
                "/api/books/secret",
                Some(&master),
                Some(serde_json::json!({ "title": "Private" })),
            )
            .await;
        },
    )
    .await;

    assert!(
        !seen.contains("secret"),
        "an invisible book leaked into the stream: {seen:?}"
    );
}

#[tokio::test]
async fn the_stream_needs_authentication() {
    let app = app().await;
    let request = Request::builder()
        .method("GET")
        .uri("/api/events")
        .body(Body::empty())
        .unwrap();
    let res = app.oneshot(request).await.unwrap();
    assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn live_events_is_advertised() {
    let app = app().await;
    let (_, caps) = call(&app, "GET", "/api/capabilities", None, None).await;
    assert!(
        caps["features"]
            .as_array()
            .unwrap()
            .contains(&serde_json::json!("live_events"))
    );
}

#[tokio::test]
async fn publishing_with_nobody_listening_is_harmless() {
    // A mutation must never fail because no client happened to be subscribed.
    let app = app().await;
    let token = register(&app, "owner@lib.test").await;
    let (status, _) = call(
        &app,
        "PUT",
        "/api/books/alone",
        Some(&token),
        Some(serde_json::json!({ "title": "Alone" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
}

#[tokio::test]
async fn a_deletion_reaches_subscribers() {
    // Deletes are announced to everyone: the row is gone, so there is nothing
    // left to check against, and the id alone is not actionable — the client's
    // answer is a delta pull, and `/api/deletions` is already scoped.
    let app = app().await;
    let token = register(&app, "owner@lib.test").await;
    call(
        &app,
        "PUT",
        "/api/books/goner",
        Some(&token),
        Some(serde_json::json!({ "title": "Goner" })),
    )
    .await;

    let app2 = app.clone();
    let token2 = token.clone();
    let seen = listen(
        &app,
        &token,
        std::time::Duration::from_millis(600),
        async move {
            call(&app2, "DELETE", "/api/books/goner", Some(&token2), None).await;
        },
    )
    .await;

    assert!(seen.contains("delete"), "no delete event in: {seen:?}");
    assert!(seen.contains("goner"));
}
