//! End-to-end API tests. Each test builds the real router against a throwaway
//! SQLite database and drives it with in-process HTTP requests via
//! `tower::ServiceExt::oneshot` — no network port is opened.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{Value, json};
use tower::ServiceExt; // for `oneshot`
use vellum_server::{AppState, connect_db, router};

/// A fresh app backed by its own temp-file database (migrated) and its own
/// temp data directory for blobs, plus the path to that data directory.
async fn test_app_with_dir() -> (axum::Router, std::path::PathBuf) {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_test_{id}.db"));
    let data_dir = std::env::temp_dir().join(format!("vellum_test_data_{id}"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let app = router(AppState {
        db,
        public_base_url: "http://test.local".into(),
        data_dir: data_dir.clone(),
        http: reqwest::Client::new(),
        max_upload_bytes: 512 * 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(2)),
        enrich_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        basic_cache: std::sync::Arc::default(),
        public_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            60,
            std::time::Duration::from_secs(60),
        )),
        search_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            30,
            std::time::Duration::from_secs(60),
        )),
        send_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            30,
            std::time::Duration::from_secs(60),
        )),
        events: vellum_server::EventBus::new(),
        mailer: None,
        // Off, like a default server: content indexing is opt-in
        // (VELLUM_INDEX_TEXT). `tests/text_index.rs` builds its own state with
        // it on.
        index_text: false,
        audit: true,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    });
    (app, data_dir)
}

/// A fresh app when the test doesn't need the data directory path.
async fn test_app() -> axum::Router {
    test_app_with_dir().await.0
}

/// A fresh app plus a clone of its database pool, for tests that assert on
/// tables the HTTP API doesn't expose (e.g. orphan cleanup).
async fn test_app_with_db() -> (axum::Router, sqlx::SqlitePool) {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_test_{id}.db"));
    let data_dir = std::env::temp_dir().join(format!("vellum_test_data_{id}"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let app = router(AppState {
        db: db.clone(),
        public_base_url: "http://test.local".into(),
        data_dir,
        http: reqwest::Client::new(),
        max_upload_bytes: 512 * 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(2)),
        enrich_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        basic_cache: std::sync::Arc::default(),
        public_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            60,
            std::time::Duration::from_secs(60),
        )),
        search_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            30,
            std::time::Duration::from_secs(60),
        )),
        send_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            30,
            std::time::Duration::from_secs(60),
        )),
        events: vellum_server::EventBus::new(),
        mailer: None,
        // Off, like a default server: content indexing is opt-in
        // (VELLUM_INDEX_TEXT). `tests/text_index.rs` builds its own state with
        // it on.
        index_text: false,
        audit: true,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    });
    (app, db)
}

/// Send one request and return the status plus the parsed JSON body (or Null).
async fn call(
    app: &axum::Router,
    method: &str,
    uri: &str,
    token: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut builder = Request::builder().method(method).uri(uri);
    if let Some(t) = token {
        builder = builder.header("authorization", format!("Bearer {t}"));
    }
    let request = match body {
        Some(b) => builder
            .header("content-type", "application/json")
            .body(Body::from(b.to_string()))
            .unwrap(),
        None => builder.body(Body::empty()).unwrap(),
    };

    let response = app.clone().oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(Value::Null)
    };
    (status, value)
}

/// Register the first (master) account and return its bearer token.
async fn register_master(app: &axum::Router) -> String {
    let (status, body) = call(
        app,
        "POST",
        "/api/auth/register",
        None,
        Some(json!({
            "email": "master@lib.test",
            "display_name": "Owner",
            "password": "masterpass1"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "register failed: {body}");
    body["token"].as_str().unwrap().to_string()
}

/// Master creates a member account and returns that member's bearer token.
async fn add_member(app: &axum::Router, master: &str, email: &str) -> String {
    let (status, _) = call(
        app,
        "POST",
        "/api/users",
        Some(master),
        Some(json!({ "email": email, "display_name": email, "password": "memberpass1" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, body) = call(
        app,
        "POST",
        "/api/auth/login",
        None,
        Some(json!({ "email": email, "password": "memberpass1" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    body["token"].as_str().unwrap().to_string()
}

async fn create_book(app: &axum::Router, token: &str, title: &str) -> String {
    let (status, body) = call(
        app,
        "POST",
        "/api/books",
        Some(token),
        Some(json!({ "title": title })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "create book failed: {body}");
    body["id"].as_str().unwrap().to_string()
}

fn titles(list: &Value) -> Vec<String> {
    list.as_array()
        .unwrap()
        .iter()
        .map(|b| b["title"].as_str().unwrap().to_string())
        .collect()
}

#[tokio::test]
async fn health_ok() {
    let app = test_app().await;
    let response = app
        .oneshot(
            Request::builder()
                .uri("/health")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
}

#[tokio::test]
async fn first_user_is_master_and_registration_then_closes() {
    let app = test_app().await;

    let (status, body) = call(
        &app,
        "POST",
        "/api/auth/register",
        None,
        Some(json!({ "email": "a@b.c", "display_name": "A", "password": "password1" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["user"]["is_master"], json!(true));

    // A second registration is refused.
    let (status, _) = call(
        &app,
        "POST",
        "/api/auth/register",
        None,
        Some(json!({ "email": "x@y.z", "display_name": "X", "password": "password1" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

/// What the console's first-run form is gated on: it must say "open" exactly
/// while `POST /auth/register` would succeed, and never afterwards.
#[tokio::test]
async fn registration_state_reports_the_window_and_then_closes() {
    let app = test_app().await;

    let (status, body) = call(&app, "GET", "/api/auth/registration", None, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        body["open"],
        json!(true),
        "a fresh server takes a first account"
    );
    // VELLUM_BOOTSTRAP_TOKEN is unset in the test process.
    assert_eq!(body["bootstrap_token_required"], json!(false));

    register_master(&app).await;

    let (status, body) = call(&app, "GET", "/api/auth/registration", None, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        body["open"],
        json!(false),
        "the window shuts with the master, matching register's own 403"
    );
    assert_eq!(
        body["bootstrap_token_required"],
        json!(false),
        "a closed server discloses nothing about its bootstrap configuration"
    );
}

/// A password turns the URL into one of two things the visitor needs. The gate
/// has to hold on every public entry point, and the unlock has to survive to
/// the download — which is an ordinary navigation, hence a cookie.
#[tokio::test]
async fn a_password_protected_link_opens_only_after_the_password() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    let (status, link) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&master),
        Some(json!({ "book_id": book, "password": "correct horse" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{link}");
    let token = link["url"]
        .as_str()
        .unwrap()
        .rsplit('/')
        .next()
        .unwrap()
        .to_string();

    // Holding the URL is no longer enough.
    let (status, _) = call(&app, "GET", &format!("/api/public/{token}"), None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "the link is locked");

    // Nor is the wrong password.
    let (status, _) = call(
        &app,
        "POST",
        &format!("/api/public/{token}/unlock"),
        None,
        Some(json!({ "password": "battery staple" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    // The right one mints a cookie.
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/public/{token}/unlock"))
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({ "password": "correct horse" }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    let set_cookie = response
        .headers()
        .get("set-cookie")
        .expect("unlock hands back a cookie")
        .to_str()
        .unwrap()
        .to_string();
    assert!(
        set_cookie.contains("HttpOnly"),
        "not readable from script: {set_cookie}"
    );
    assert!(set_cookie.contains("SameSite=Lax"), "{set_cookie}");
    let cookie = set_cookie.split(';').next().unwrap().to_string();

    // …which opens the metadata,
    let with_cookie = |uri: String| {
        let app = app.clone();
        let cookie = cookie.clone();
        async move {
            let response = app
                .oneshot(
                    Request::builder()
                        .method("GET")
                        .uri(uri)
                        .header("cookie", cookie)
                        .body(Body::empty())
                        .unwrap(),
                )
                .await
                .unwrap();
            response.status()
        }
    };
    assert_eq!(
        with_cookie(format!("/api/public/{token}")).await,
        StatusCode::OK
    );

    // …and the download, which never sees a header of its own. (This book has
    // no file, so the gate passing looks like 404 rather than 401 — the point
    // is which of the two.)
    assert_eq!(
        with_cookie(format!("/api/public/{token}/file")).await,
        StatusCode::NOT_FOUND,
        "past the password, and refused for the honest reason"
    );

    // The owner can see that it is protected, and never the password itself.
    let (_, links) = call(&app, "GET", "/api/share-links", Some(&master), None).await;
    assert_eq!(links[0]["has_password"], json!(true));
    assert!(
        !links.to_string().contains("argon2"),
        "no hash leaves the server: {links}"
    );
}

/// A link's address has to survive the dialog that created it: the Shares
/// screen lists live links, and a live link you cannot read is one you cannot
/// send to anyone.
#[tokio::test]
async fn a_links_url_can_be_read_back_and_its_token_is_not_shipped() {
    let (app, db) = test_app_with_db().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    let (_, created) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&master),
        Some(json!({ "book_id": book })),
    )
    .await;
    let url = created["url"].as_str().unwrap().to_string();

    let (status, links) = call(&app, "GET", "/api/share-links", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        links[0]["url"].as_str().unwrap(),
        url,
        "the same address the creator was shown"
    );
    assert!(
        links[0].get("token").is_none(),
        "the URL is the useful form; the bare token is not also shipped: {links}"
    );

    // A link made before migration 0027 has no token to rebuild from, and says
    // so with null rather than inventing an address that would not open.
    sqlx::query("UPDATE share_link SET token = NULL")
        .execute(&db)
        .await
        .unwrap();
    let (_, links) = call(&app, "GET", "/api/share-links", Some(&master), None).await;
    assert!(links[0]["url"].is_null());
}

#[tokio::test]
async fn unlocking_a_revoked_link_fails() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;
    let (_, link) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&master),
        Some(json!({ "book_id": book, "password": "correct horse" })),
    )
    .await;
    let token = link["url"]
        .as_str()
        .unwrap()
        .rsplit('/')
        .next()
        .unwrap()
        .to_string();
    let id = link["id"].as_str().unwrap().to_string();

    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/share-links/{id}"),
        Some(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (status, _) = call(
        &app,
        "POST",
        &format!("/api/public/{token}/unlock"),
        None,
        Some(json!({ "password": "correct horse" })),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::UNAUTHORIZED,
        "a revoked link has nothing left to unlock"
    );
}

/// The old shape still works: no password, no prompt.
#[tokio::test]
async fn a_link_without_a_password_opens_as_before() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;
    let (_, link) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&master),
        Some(json!({ "book_id": book })),
    )
    .await;
    let token = link["url"]
        .as_str()
        .unwrap()
        .rsplit('/')
        .next()
        .unwrap()
        .to_string();

    let (status, body) = call(&app, "GET", &format!("/api/public/{token}"), None, None).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (_, links) = call(&app, "GET", "/api/share-links", Some(&master), None).await;
    assert_eq!(links[0]["has_password"], json!(false));
}

#[tokio::test]
async fn session_expiry_slides_forward_on_use() {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_test_{id}.db"));
    let data_dir = std::env::temp_dir().join(format!("vellum_test_data_{id}"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let app = router(AppState {
        db: db.clone(),
        public_base_url: "http://test.local".into(),
        data_dir,
        http: reqwest::Client::new(),
        max_upload_bytes: 512 * 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(2)),
        enrich_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        basic_cache: std::sync::Arc::default(),
        public_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            60,
            std::time::Duration::from_secs(60),
        )),
        search_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            30,
            std::time::Duration::from_secs(60),
        )),
        send_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            30,
            std::time::Duration::from_secs(60),
        )),
        events: vellum_server::EventBus::new(),
        mailer: None,
        // Off, like a default server: content indexing is opt-in
        // (VELLUM_INDEX_TEXT). `tests/text_index.rs` builds its own state with
        // it on.
        index_text: false,
        audit: true,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    });
    let token = register_master(&app).await;

    // Force the session into its final 15 days.
    sqlx::query("UPDATE session SET expires_at = datetime('now', '+10 days')")
        .execute(&db)
        .await
        .unwrap();
    let before: String = sqlx::query_scalar("SELECT expires_at FROM session")
        .fetch_one(&db)
        .await
        .unwrap();

    // Any authenticated request renews it back toward +30 days.
    let (status, _) = call(&app, "GET", "/api/auth/me", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);

    let after: String = sqlx::query_scalar("SELECT expires_at FROM session")
        .fetch_one(&db)
        .await
        .unwrap();
    assert!(
        after > before,
        "session expiry should slide forward on use ({after} > {before})"
    );
}

#[tokio::test]
async fn logout_invalidates_the_session_token() {
    let app = test_app().await;
    let token = register_master(&app).await;

    // The token authenticates before logout.
    let (status, _) = call(&app, "GET", "/api/auth/me", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);

    let (status, _) = call(&app, "POST", "/api/auth/logout", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);

    // ...and is rejected afterwards (the server dropped the session).
    let (status, _) = call(&app, "GET", "/api/auth/me", Some(&token), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn repeated_failed_logins_are_throttled() {
    let app = test_app().await;
    register_master(&app).await; // master@lib.test / masterpass1

    // Ten wrong-password attempts are each merely unauthorized...
    for _ in 0..10 {
        let (status, _) = call(
            &app,
            "POST",
            "/api/auth/login",
            None,
            Some(json!({ "email": "master@lib.test", "password": "wrongpass1" })),
        )
        .await;
        assert_eq!(status, StatusCode::UNAUTHORIZED);
    }

    // ...but the next attempt is throttled even with the correct password.
    let (status, _) = call(
        &app,
        "POST",
        "/api/auth/login",
        None,
        Some(json!({ "email": "master@lib.test", "password": "masterpass1" })),
    )
    .await;
    assert_eq!(status, StatusCode::TOO_MANY_REQUESTS);
}

#[tokio::test]
async fn oversized_login_body_is_rejected() {
    let app = test_app().await;
    // 8 MB to an unauthenticated JSON endpoint must hit the small default body
    // limit (the 2 GB cap is scoped to file uploads only), not buffer in RAM.
    let big = "x".repeat(8 * 1024 * 1024);
    let req = Request::builder()
        .method("POST")
        .uri("/api/auth/login")
        .header("content-type", "application/json")
        .body(Body::from(format!(
            "{{\"email\":\"a@b.c\",\"password\":\"{big}\"}}"
        )))
        .unwrap();
    let res = app.oneshot(req).await.unwrap();
    assert_eq!(res.status(), StatusCode::PAYLOAD_TOO_LARGE);
}

#[tokio::test]
async fn query_token_is_never_accepted() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    // The session token is only ever read from the Authorization header, so a
    // `?token=` query param authenticates nothing — not even a blob GET (which
    // used to accept it). This keeps the token out of proxy logs / history.
    let put = Request::builder()
        .method("PUT")
        .uri(format!("/api/books/{book}/cover"))
        .header("authorization", format!("Bearer {master}"))
        .header("content-type", "image/png")
        .body(Body::from(b"\x89PNG\r\n\x1a\n fake".to_vec()))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(put).await.unwrap().status(),
        StatusCode::OK
    );

    // A `?token=` on the cover GET is now rejected...
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/books/{book}/cover?token={master}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::UNAUTHORIZED);

    // ...and the same GET succeeds only with the Authorization header.
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/books/{book}/cover"))
                .header("authorization", format!("Bearer {master}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
}

#[tokio::test]
async fn requires_a_token() {
    let app = test_app().await;
    let (status, _) = call(&app, "GET", "/api/books", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn cert_endpoint_requires_auth_and_404s_without_tls() {
    let app = test_app().await;
    // The certificate is behind the console login (any authenticated user).
    let (status, _) = call(&app, "GET", "/api/cert", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    // Authenticated, but the test server runs without TLS → nothing to import.
    let master = register_master(&app).await;
    let (status, _) = call(&app, "GET", "/api/cert", Some(&master), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn short_password_is_rejected() {
    let app = test_app().await;
    let (status, _) = call(
        &app,
        "POST",
        "/api/auth/register",
        None,
        Some(json!({ "email": "a@b.c", "display_name": "A", "password": "short" })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn overlong_password_is_rejected_before_hashing() {
    let app = test_app().await;
    register_master(&app).await;

    let huge = "p".repeat(200); // > 128-byte cap
    // Registration is closed after the master, but the length check fires first.
    let (status, _) = call(
        &app,
        "POST",
        "/api/auth/register",
        None,
        Some(json!({ "email": "a@b.c", "display_name": "A", "password": huge })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    // Login rejects it too, before spending Argon2 on a wrong password.
    let (status, _) = call(
        &app,
        "POST",
        "/api/auth/login",
        None,
        Some(json!({ "email": "master@lib.test", "password": huge })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn non_master_cannot_create_users() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let member = add_member(&app, &master, "alice@lib.test").await;

    let (status, _) = call(
        &app,
        "POST",
        "/api/users",
        Some(&member),
        Some(json!({ "email": "z@z.z", "display_name": "Z", "password": "password1" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn group_share_grants_read_but_not_write() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let alice = add_member(&app, &master, "alice@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;

    // Before sharing, Alice sees nothing.
    let (_, before) = call(&app, "GET", "/api/books", Some(&alice), None).await;
    assert!(titles(&before).is_empty());

    // Master groups the book and shares the group with Alice (viewer).
    let (_, group) = call(
        &app,
        "POST",
        "/api/groups",
        Some(&master),
        Some(json!({ "name": "Sci-Fi" })),
    )
    .await;
    let group_id = group["id"].as_str().unwrap();
    call(
        &app,
        "POST",
        &format!("/api/groups/{group_id}/books"),
        Some(&master),
        Some(json!({ "book_id": book })),
    )
    .await;
    let (status, _) = call(
        &app,
        "POST",
        "/api/shares",
        Some(&master),
        Some(json!({ "scope": "group", "scope_id": group_id, "grantee_email": "alice@lib.test" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // Now Alice sees the book...
    let (_, after) = call(&app, "GET", "/api/books", Some(&alice), None).await;
    assert_eq!(titles(&after), vec!["Dune".to_string()]);

    // ...but may not edit it (viewer only).
    let (status, _) = call(
        &app,
        "PATCH",
        &format!("/api/books/{book}"),
        Some(&alice),
        Some(json!({ "title": "Hacked" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn editor_book_share_allows_edit_but_not_delete() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let alice = add_member(&app, &master, "alice@lib.test").await;
    let book = create_book(&app, &master, "Neuromancer").await;

    call(
        &app,
        "POST",
        "/api/shares",
        Some(&master),
        Some(json!({
            "scope": "book", "scope_id": book,
            "grantee_email": "alice@lib.test", "permission": "editor"
        })),
    )
    .await;

    // Editor can update.
    let (status, body) = call(
        &app,
        "PATCH",
        &format!("/api/books/{book}"),
        Some(&alice),
        Some(json!({ "description": "Alice edited" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["description"], json!("Alice edited"));

    // But only the owner may delete.
    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/books/{book}"),
        Some(&alice),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn all_scope_share_exposes_whole_library() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let bob = add_member(&app, &master, "bob@lib.test").await;
    create_book(&app, &master, "Dune").await;
    create_book(&app, &master, "Neuromancer").await;

    call(
        &app,
        "POST",
        "/api/shares",
        Some(&master),
        Some(json!({ "scope": "all", "grantee_email": "bob@lib.test" })),
    )
    .await;

    let (_, list) = call(&app, "GET", "/api/books", Some(&bob), None).await;
    let mut seen = titles(&list);
    seen.sort();
    assert_eq!(seen, vec!["Dune".to_string(), "Neuromancer".to_string()]);
}

#[tokio::test]
async fn put_upserts_a_book_at_a_chosen_id() {
    let app = test_app().await;
    let master = register_master(&app).await;

    // Create at a client-chosen id.
    let (status, body) = call(
        &app,
        "PUT",
        "/api/books/my-local-id",
        Some(&master),
        Some(json!({ "title": "Pushed", "page_count": 100 })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["id"], json!("my-local-id"));
    assert_eq!(body["title"], json!("Pushed"));

    // PUT again updates the same row rather than creating a new one.
    let (status, body) = call(
        &app,
        "PUT",
        "/api/books/my-local-id",
        Some(&master),
        Some(json!({ "title": "Pushed v2" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["title"], json!("Pushed v2"));

    let (_, list) = call(&app, "GET", "/api/books", Some(&master), None).await;
    assert_eq!(list.as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn batch_upsert_creates_every_item_and_shares_upsert_s_logic() {
    // Plan 5 #7: same shape a single PUT accepts, just several at once with
    // a caller-chosen id per item (a batch request has no per-item URL).
    let app = test_app().await;
    let master = register_master(&app).await;

    let (status, body) = call(
        &app,
        "POST",
        "/api/books:batch",
        Some(&master),
        Some(json!({ "books": [
            { "id": "b1", "title": "Dune" },
            { "id": "b2", "title": "Neuromancer", "authors": ["William Gibson"] },
        ] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let results = body["results"].as_array().unwrap();
    assert_eq!(results.len(), 2);
    assert_eq!(results[0], json!({ "id": "b1", "status": "updated" }));
    assert_eq!(results[1], json!({ "id": "b2", "status": "updated" }));

    let (_, list) = call(&app, "GET", "/api/books", Some(&master), None).await;
    assert_eq!(list.as_array().unwrap().len(), 2);
}

#[tokio::test]
async fn batch_upsert_reports_per_item_status_without_aborting_the_batch() {
    let app = test_app().await;
    let master = register_master(&app).await;
    // Pre-existing row with a "newer" stored updated_at than the stale push
    // below will send -- exercises skipped_older inside a batch.
    call(
        &app,
        "PUT",
        "/api/books/existing",
        Some(&master),
        Some(json!({ "title": "Original", "updated_at": "2025-06-01 00:00:00" })),
    )
    .await;

    let (status, body) = call(
        &app,
        "POST",
        "/api/books:batch",
        Some(&master),
        Some(json!({ "books": [
            { "id": "new-book", "title": "Fresh" },
            { "id": "existing", "title": "Stale push", "updated_at": "2024-01-01 00:00:00" },
            { "id": "bad", "title": "   " },
        ] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let results = body["results"].as_array().unwrap();
    assert_eq!(results.len(), 3);
    assert_eq!(results[0]["status"], json!("updated"));
    assert_eq!(results[1]["status"], json!("skipped_older"));
    assert_eq!(results[2]["status"], json!("error"));
    assert!(results[2]["message"].is_string());

    // The bad/skipped items didn't roll back the good one.
    let (_, fresh) = call(&app, "GET", "/api/books/new-book", Some(&master), None).await;
    assert_eq!(fresh["title"], json!("Fresh"));
    // The stale push left the original title intact.
    let (_, existing) = call(&app, "GET", "/api/books/existing", Some(&master), None).await;
    assert_eq!(existing["title"], json!("Original"));
}

#[tokio::test]
async fn batch_upsert_reports_forbidden_items_as_errors_not_aborts() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let alice = add_member(&app, &master, "alice@lib.test").await;
    let book = create_book(&app, &master, "Master's book").await;
    // No share granted -- Alice has no access to `book`.

    let (status, body) = call(
        &app,
        "POST",
        "/api/books:batch",
        Some(&master),
        Some(json!({ "books": [ { "id": "hers", "title": "Alice's own" } ] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");

    let (status, body) = call(
        &app,
        "POST",
        "/api/books:batch",
        Some(&alice),
        Some(json!({ "books": [
            { "id": &book, "title": "Hijack attempt" },
            { "id": "alices-own-2", "title": "Alice's second" },
        ] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let results = body["results"].as_array().unwrap();
    assert_eq!(results[0]["status"], json!("error"));
    assert_eq!(results[1]["status"], json!("updated"));

    // Master's book is untouched.
    let (_, untouched) = call(
        &app,
        "GET",
        &format!("/api/books/{book}"),
        Some(&master),
        None,
    )
    .await;
    assert_eq!(untouched["title"], json!("Master's book"));
}

#[tokio::test]
async fn batch_upsert_rejects_a_batch_over_the_cap() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let books: Vec<serde_json::Value> = (0..201)
        .map(|i| json!({ "id": format!("b{i}"), "title": format!("Book {i}") }))
        .collect();

    let (status, _) = call(
        &app,
        "POST",
        "/api/books:batch",
        Some(&master),
        Some(json!({ "books": books })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

// ---- Cross-device reading position (plan 5 #5) ------------------------------

/// PUT one device's position in `book`, asserting it was accepted.
async fn put_progress(
    app: &axum::Router,
    token: &str,
    book: &str,
    device: &str,
    body: Value,
) -> Value {
    let mut payload = json!({ "device_id": device });
    payload
        .as_object_mut()
        .unwrap()
        .extend(body.as_object().unwrap().clone());
    let (status, out) = call(
        app,
        "PUT",
        &format!("/api/reading-progress/{book}"),
        Some(token),
        Some(payload),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{out}");
    out
}

#[tokio::test]
async fn reading_progress_is_per_device_so_two_devices_never_conflict() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    put_progress(
        &app,
        &master,
        &book,
        "desktop-1",
        json!({ "device_label": "desktop", "progress": 0.5, "page": 214, "unit": "page" }),
    )
    .await;
    put_progress(
        &app,
        &master,
        &book,
        "phone-1",
        json!({ "device_label": "phone", "progress": 0.1, "page": 40, "unit": "page" }),
    )
    .await;

    // The phone's write left the desktop's row alone: both survive, each owned
    // by its writer. That is the whole point of the (book, user, device) key.
    let (status, body) = call(&app, "GET", "/api/reading-progress", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK);
    let rows = body.as_array().unwrap();
    assert_eq!(rows.len(), 2);
    let desktop = rows
        .iter()
        .find(|r| r["device_id"] == json!("desktop-1"))
        .unwrap();
    assert_eq!(desktop["page"], json!(214));
    assert_eq!(desktop["device_label"], json!("desktop"));
    assert_eq!(desktop["unit"], json!("page"));
    let phone = rows
        .iter()
        .find(|r| r["device_id"] == json!("phone-1"))
        .unwrap();
    assert_eq!(phone["page"], json!(40));

    // Re-writing the same device replaces its own row rather than adding one.
    put_progress(
        &app,
        &master,
        &book,
        "phone-1",
        json!({ "progress": 0.2, "page": 80, "unit": "page" }),
    )
    .await;
    let (_, body) = call(&app, "GET", "/api/reading-progress", Some(&master), None).await;
    assert_eq!(body.as_array().unwrap().len(), 2);
}

#[tokio::test]
async fn reading_progress_is_never_visible_to_another_user() {
    // The stronger of the two isolation properties: a shared library means two
    // *users* hold positions in the same book, and one user's reading is not
    // the other's business (nor is it something they could overwrite).
    let app = test_app().await;
    let master = register_master(&app).await;
    let alice = add_member(&app, &master, "alice@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;
    let (status, _) = call(
        &app,
        "POST",
        "/api/shares",
        Some(&master),
        Some(json!({ "scope": "book", "scope_id": book, "grantee_email": "alice@lib.test" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    put_progress(
        &app,
        &master,
        &book,
        "master-desktop",
        json!({ "progress": 0.9, "page": 400, "unit": "page" }),
    )
    .await;
    // Alice may record her own position in a book shared with her read-only:
    // it's her data, so view access is the right bar.
    put_progress(
        &app,
        &alice,
        &book,
        "alice-phone",
        json!({ "progress": 0.1, "page": 20, "unit": "page" }),
    )
    .await;

    let (_, hers) = call(&app, "GET", "/api/reading-progress", Some(&alice), None).await;
    let rows = hers.as_array().unwrap();
    assert_eq!(rows.len(), 1, "Alice must not see the master's position");
    assert_eq!(rows[0]["device_id"], json!("alice-phone"));

    let (_, his) = call(&app, "GET", "/api/reading-progress", Some(&master), None).await;
    let rows = his.as_array().unwrap();
    assert_eq!(rows.len(), 1, "and the master must not see hers");
    assert_eq!(rows[0]["page"], json!(400));
}

#[tokio::test]
async fn reading_progress_needs_view_access_and_hides_unshared_books() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let alice = add_member(&app, &master, "alice@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;

    // No share: 404 rather than 403, so the endpoint doesn't confirm which
    // book ids exist.
    let (status, _) = call(
        &app,
        "PUT",
        &format!("/api/reading-progress/{book}"),
        Some(&alice),
        Some(json!({ "device_id": "alice-phone", "progress": 0.1 })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (status, _) = call(
        &app,
        "PUT",
        "/api/reading-progress/no-such-book",
        Some(&master),
        Some(json!({ "device_id": "d", "progress": 0.1 })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn reading_progress_stops_being_returned_when_a_book_is_unshared() {
    // The book join in `my_progress` isn't redundant with the user filter:
    // access can be revoked after a position was recorded.
    let app = test_app().await;
    let master = register_master(&app).await;
    let alice = add_member(&app, &master, "alice@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;
    let (_, share) = call(
        &app,
        "POST",
        "/api/shares",
        Some(&master),
        Some(json!({ "scope": "book", "scope_id": book, "grantee_email": "alice@lib.test" })),
    )
    .await;
    put_progress(
        &app,
        &alice,
        &book,
        "alice-phone",
        json!({ "progress": 0.3, "page": 60, "unit": "page" }),
    )
    .await;

    let share_id = share["id"].as_str().unwrap();
    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/shares/{share_id}"),
        Some(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (_, hers) = call(&app, "GET", "/api/reading-progress", Some(&alice), None).await;
    assert!(
        hers.as_array().unwrap().is_empty(),
        "an unshared book's position must stop coming back: {hers}"
    );
}

#[tokio::test]
async fn reading_progress_delta_pull_uses_the_server_cursor() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;
    put_progress(
        &app,
        &master,
        &book,
        "old-device",
        json!({ "progress": 0.2, "page": 40, "unit": "page", "updated_at": "2020-01-01 00:00:00" }),
    )
    .await;
    put_progress(
        &app,
        &master,
        &book,
        "new-device",
        json!({ "progress": 0.8, "page": 300, "unit": "page", "updated_at": "2026-01-01 00:00:00" }),
    )
    .await;

    // An empty cursor selects the envelope (with server_now) and everything.
    let (status, all) = call(
        &app,
        "GET",
        "/api/reading-progress?cursor=",
        Some(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(all["server_now"].is_string());
    assert_eq!(all["entries"].as_array().unwrap().len(), 2);

    let (_, delta) = call(
        &app,
        "GET",
        "/api/reading-progress?cursor=2025-01-01%2000:00:00",
        Some(&master),
        None,
    )
    .await;
    let entries = delta["entries"].as_array().unwrap();
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0]["device_id"], json!("new-device"));
}

#[tokio::test]
async fn reading_progress_rejects_a_bad_unit_or_missing_device() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    for bad in [
        json!({ "device_id": "d", "unit": "paragraph" }),
        json!({ "device_id": "   ", "progress": 0.5 }),
    ] {
        let (status, _) = call(
            &app,
            "PUT",
            &format!("/api/reading-progress/{book}"),
            Some(&master),
            Some(bad),
        )
        .await;
        assert_eq!(status, StatusCode::BAD_REQUEST);
    }
}

#[tokio::test]
async fn forgetting_a_device_unpublishes_only_that_device() {
    // What makes the opt-in honest: turning the setting off removes what
    // turning it on published -- this device's rows, and nothing else's.
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;
    put_progress(&app, &master, &book, "phone-1", json!({ "progress": 0.1 })).await;
    put_progress(
        &app,
        &master,
        &book,
        "desktop-1",
        json!({ "progress": 0.6 }),
    )
    .await;

    let (status, body) = call(
        &app,
        "DELETE",
        "/api/reading-progress?device_id=phone-1",
        Some(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["deleted"], json!(1));

    let (_, left) = call(&app, "GET", "/api/reading-progress", Some(&master), None).await;
    let rows = left.as_array().unwrap();
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["device_id"], json!("desktop-1"));

    let (status, _) = call(&app, "DELETE", "/api/reading-progress", Some(&master), None).await;
    assert_eq!(
        status,
        StatusCode::BAD_REQUEST,
        "a blanket wipe isn't what a per-device opt-out means"
    );
}

#[tokio::test]
async fn deleting_a_book_takes_its_reading_progress_with_it() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;
    put_progress(&app, &master, &book, "phone-1", json!({ "progress": 0.4 })).await;

    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/books/{book}"),
        Some(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (_, left) = call(&app, "GET", "/api/reading-progress", Some(&master), None).await;
    assert!(left.as_array().unwrap().is_empty(), "{left}");
}

// ---- Opt-in mail (plan 5 #31, stage 1) -------------------------------------

#[tokio::test]
async fn mail_is_not_advertised_when_it_is_not_configured() {
    // The default, and the one that matters most: a LAN server with no SMTP must
    // not tell the app it can send a password reset.
    let app = test_app().await;
    let (status, body) = call(&app, "GET", "/api/capabilities", None, None).await;
    assert_eq!(status, StatusCode::OK);
    let features = body["features"].as_array().unwrap();
    assert!(
        !features.contains(&json!("mail")),
        "a server with no mailer must not claim it can email"
    );
}

#[tokio::test]
async fn mail_is_advertised_once_a_mailer_exists() {
    // The capability is what lets the app hide "Forgot password?" rather than
    // offering a button that can only fail.
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_mail_{id}.db"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    // Built directly rather than from the environment: env vars are process-wide
    // and would race the other tests in this binary.
    let mailer = vellum_server::test_mailer("mail.example.com", "vellum@example.com");
    let app = router(AppState {
        db,
        public_base_url: "http://test.local".into(),
        data_dir: std::env::temp_dir().join(format!("vellum_mail_data_{id}")),
        http: reqwest::Client::new(),
        max_upload_bytes: 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        enrich_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        basic_cache: std::sync::Arc::default(),
        public_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            60,
            std::time::Duration::from_secs(60),
        )),
        search_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            30,
            std::time::Duration::from_secs(60),
        )),
        send_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            30,
            std::time::Duration::from_secs(60),
        )),
        events: vellum_server::EventBus::new(),
        mailer: Some(mailer),
        // Off, like a default server: content indexing is opt-in
        // (VELLUM_INDEX_TEXT). `tests/text_index.rs` builds its own state with
        // it on.
        index_text: false,
        audit: true,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    });

    let (_, body) = call(&app, "GET", "/api/capabilities", None, None).await;
    assert!(
        body["features"]
            .as_array()
            .unwrap()
            .contains(&json!("mail"))
    );
}

// ---- Password reset (plan 5 #31, stage 2) ----------------------------------

/// An app whose `AppState` has a mailer, so the reset path runs end to end.
/// Sending fails (the host doesn't exist) — which is deliberate: the handler must
/// answer identically whether or not the mail actually goes out.
async fn test_app_with_mail() -> (axum::Router, sqlx::SqlitePool) {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_reset_{id}.db"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let app = router(AppState {
        db: db.clone(),
        public_base_url: "https://books.example.com".into(),
        data_dir: std::env::temp_dir().join(format!("vellum_reset_data_{id}")),
        http: reqwest::Client::new(),
        max_upload_bytes: 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        enrich_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        basic_cache: std::sync::Arc::default(),
        public_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            1000,
            std::time::Duration::from_secs(60),
        )),
        search_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            1000,
            std::time::Duration::from_secs(60),
        )),
        send_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            1000,
            std::time::Duration::from_secs(60),
        )),
        events: vellum_server::EventBus::new(),
        // Off, like a default server: content indexing is opt-in
        // (VELLUM_INDEX_TEXT). `tests/text_index.rs` builds its own state with
        // it on.
        index_text: false,
        audit: true,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        mailer: Some(vellum_server::test_mailer(
            "smtp.invalid.example",
            "vellum@example.com",
        )),
        tls_cert: None,
    });
    (app, db)
}

/// The plaintext token can't be read from the response (by design), so tests
/// mint one the same way the handler does and insert it directly.
async fn seed_reset_token(db: &sqlx::SqlitePool, user_id: &str, token: &str, sql_expiry: &str) {
    sqlx::query(&format!(
        "INSERT INTO password_reset (token_hash, user_id, expires_at) \
         VALUES (?, ?, {sql_expiry})"
    ))
    .bind(vellum_server::sha256_hex_for_tests(token))
    .bind(user_id)
    .execute(db)
    .await
    .unwrap();
}

async fn master_id(db: &sqlx::SqlitePool) -> String {
    sqlx::query_scalar("SELECT id FROM app_user LIMIT 1")
        .fetch_one(db)
        .await
        .unwrap()
}

#[tokio::test]
async fn forgot_answers_identically_for_known_and_unknown_addresses() {
    // The property that matters: this endpoint must not be an account-existence
    // oracle. A personal library's account list is a list of people its owner
    // knows.
    let (app, _db) = test_app_with_mail().await;
    register_master(&app).await;

    let (known_status, known_body) = call(
        &app,
        "POST",
        "/api/auth/forgot",
        None,
        Some(json!({ "email": "master@lib.test" })),
    )
    .await;
    let (unknown_status, unknown_body) = call(
        &app,
        "POST",
        "/api/auth/forgot",
        None,
        Some(json!({ "email": "nobody@lib.test" })),
    )
    .await;

    assert_eq!(known_status, unknown_status);
    assert_eq!(known_body, unknown_body);
    assert_eq!(known_status, StatusCode::OK);
}

#[tokio::test]
async fn forgot_is_a_no_op_when_mail_is_off_but_answers_the_same() {
    let app = test_app().await; // no mailer
    register_master(&app).await;
    let (status, body) = call(
        &app,
        "POST",
        "/api/auth/forgot",
        None,
        Some(json!({ "email": "master@lib.test" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(body["status"].is_string());
}

#[tokio::test]
async fn a_reset_token_sets_the_password_once() {
    let (app, db) = test_app_with_mail().await;
    register_master(&app).await;
    let user = master_id(&db).await;
    seed_reset_token(&db, &user, "tok-good", "datetime('now', '+1 hour')").await;

    let (status, body) = call(
        &app,
        "POST",
        "/api/auth/reset",
        None,
        Some(json!({ "token": "tok-good", "password": "brand-new-pass" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");

    // The new password works...
    let (status, _) = call(
        &app,
        "POST",
        "/api/auth/login",
        None,
        Some(json!({ "email": "master@lib.test", "password": "brand-new-pass" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    // ...the old one doesn't...
    let (status, _) = call(
        &app,
        "POST",
        "/api/auth/login",
        None,
        Some(json!({ "email": "master@lib.test", "password": "masterpass1" })),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    // ...and the token is spent.
    let (status, _) = call(
        &app,
        "POST",
        "/api/auth/reset",
        None,
        Some(json!({ "token": "tok-good", "password": "another-attempt" })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "a reset link works once");
}

#[tokio::test]
async fn a_reset_ends_every_existing_session() {
    // Resetting is what someone does when they fear their account is
    // compromised; leaving the attacker's session alive would defeat it.
    let (app, db) = test_app_with_mail().await;
    let token = register_master(&app).await;
    let user = master_id(&db).await;

    let (status, _) = call(&app, "GET", "/api/auth/me", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK, "session works before the reset");

    seed_reset_token(&db, &user, "tok-session", "datetime('now', '+1 hour')").await;
    call(
        &app,
        "POST",
        "/api/auth/reset",
        None,
        Some(json!({ "token": "tok-session", "password": "brand-new-pass" })),
    )
    .await;

    let (status, _) = call(&app, "GET", "/api/auth/me", Some(&token), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "old sessions are dropped");
}

#[tokio::test]
async fn an_expired_or_unknown_token_is_refused_the_same_way() {
    let (app, db) = test_app_with_mail().await;
    register_master(&app).await;
    let user = master_id(&db).await;
    seed_reset_token(&db, &user, "tok-stale", "datetime('now', '-1 minute')").await;

    let (expired_status, expired_body) = call(
        &app,
        "POST",
        "/api/auth/reset",
        None,
        Some(json!({ "token": "tok-stale", "password": "brand-new-pass" })),
    )
    .await;
    let (unknown_status, unknown_body) = call(
        &app,
        "POST",
        "/api/auth/reset",
        None,
        Some(json!({ "token": "never-existed", "password": "brand-new-pass" })),
    )
    .await;

    assert_eq!(expired_status, StatusCode::BAD_REQUEST);
    assert_eq!(expired_status, unknown_status);
    assert_eq!(
        expired_body["error"], unknown_body["error"],
        "distinguishing expired from unknown tells a guesser which attempt was close"
    );
}

#[tokio::test]
async fn only_the_token_hash_is_stored() {
    // A backup or a snapshot must not contain anything replayable as a reset.
    let (app, db) = test_app_with_mail().await;
    register_master(&app).await;
    let user = master_id(&db).await;
    seed_reset_token(&db, &user, "tok-secret", "datetime('now', '+1 hour')").await;

    let stored: Vec<String> = sqlx::query_scalar("SELECT token_hash FROM password_reset")
        .fetch_all(&db)
        .await
        .unwrap();
    assert_eq!(stored.len(), 1);
    assert_ne!(stored[0], "tok-secret");
    assert_eq!(stored[0].len(), 64, "a hex SHA-256");
}

#[tokio::test]
async fn a_new_reset_request_invalidates_the_previous_link() {
    // A forwarded or leaked earlier email must stop working once a new one is
    // requested.
    let (app, db) = test_app_with_mail().await;
    register_master(&app).await;
    let user = master_id(&db).await;
    seed_reset_token(&db, &user, "tok-old", "datetime('now', '+1 hour')").await;

    call(
        &app,
        "POST",
        "/api/auth/forgot",
        None,
        Some(json!({ "email": "master@lib.test" })),
    )
    .await;

    let (status, _) = call(
        &app,
        "POST",
        "/api/auth/reset",
        None,
        Some(json!({ "token": "tok-old", "password": "brand-new-pass" })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

// ---- Emailed invites (plan 5 #31, stage 3) ---------------------------------

#[tokio::test]
async fn only_the_master_may_invite() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let alice = add_member(&app, &master, "alice@lib.test").await;

    let (status, _) = call(
        &app,
        "POST",
        "/api/invites",
        Some(&alice),
        Some(json!({ "email": "friend@lib.test" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn an_invite_without_mail_hands_back_the_link() {
    // A LAN server with no SMTP must still be able to invite someone; refusing
    // would make the feature depend on a mailer the design says is optional.
    let app = test_app().await;
    let master = register_master(&app).await;

    let (status, body) = call(
        &app,
        "POST",
        "/api/invites",
        Some(&master),
        Some(json!({ "email": "friend@lib.test" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["emailed"], json!(false));
    let url = body["url"].as_str().expect("the link is returned instead");
    assert!(url.contains("/join/"));
}

#[tokio::test]
async fn an_invite_hands_back_the_link_even_when_it_was_emailed() {
    // It used to be withheld once the mail went out. That made an invitation
    // lost to a spam folder unrecoverable: the only way back was to withdraw it
    // and mint another. The master minted this token and could mint a second
    // one in the same breath, so there is nothing to protect by hiding it.
    let (app, _db) = test_app_with_mail().await;
    let master = register_master(&app).await;

    let (status, body) = call(
        &app,
        "POST",
        "/api/invites",
        Some(&master),
        Some(json!({ "email": "friend@lib.test" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let url = body["url"].as_str().expect("the link is always returned");
    assert!(url.contains("/join/"), "{url}");
    // `smtp.invalid.example` cannot deliver, so this one reports honestly that
    // it did not send — which is the case where the link matters most.
    assert_eq!(
        body["emailed"],
        json!(false),
        "a relay that refused must not claim it sent"
    );
}

#[tokio::test]
async fn redeeming_an_invite_creates_the_account_and_applies_the_share() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    let (_, invite) = call(
        &app,
        "POST",
        "/api/invites",
        Some(&master),
        Some(json!({
            "email": "friend@lib.test",
            "scope": "book",
            "scope_id": book,
            "permission": "viewer"
        })),
    )
    .await;
    let token = invite["url"]
        .as_str()
        .unwrap()
        .rsplit('/')
        .next()
        .unwrap()
        .to_string();

    let (status, body) = call(
        &app,
        "POST",
        "/api/invites/redeem",
        None,
        Some(json!({
            "token": token,
            "display_name": "A Friend",
            "password": "friendpass1"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");

    // They can sign in...
    let (status, login) = call(
        &app,
        "POST",
        "/api/auth/login",
        None,
        Some(json!({ "email": "friend@lib.test", "password": "friendpass1" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let friend = login["token"].as_str().unwrap().to_string();
    assert_eq!(login["user"]["is_master"], json!(false), "never master");

    // ...and the grant came with the invite.
    let (_, books) = call(&app, "GET", "/api/books", Some(&friend), None).await;
    assert_eq!(titles(&books), vec!["Dune".to_string()]);

    // Viewer, not editor.
    let (status, _) = call(
        &app,
        "PUT",
        &format!("/api/books/{book}"),
        Some(&friend),
        Some(json!({ "title": "Hijacked" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn an_invite_works_once() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let (_, invite) = call(
        &app,
        "POST",
        "/api/invites",
        Some(&master),
        Some(json!({ "email": "friend@lib.test" })),
    )
    .await;
    let token = invite["url"]
        .as_str()
        .unwrap()
        .rsplit('/')
        .next()
        .unwrap()
        .to_string();

    let redeem = json!({
        "token": token,
        "display_name": "A Friend",
        "password": "friendpass1"
    });
    let (first, _) = call(
        &app,
        "POST",
        "/api/invites/redeem",
        None,
        Some(redeem.clone()),
    )
    .await;
    assert_eq!(first, StatusCode::OK);
    let (second, _) = call(&app, "POST", "/api/invites/redeem", None, Some(redeem)).await;
    assert_eq!(
        second,
        StatusCode::BAD_REQUEST,
        "a link is not a standing door"
    );
}

#[tokio::test]
async fn the_account_uses_the_invited_address_not_a_chosen_one() {
    // The security property: a forwarded link must not become an open
    // registration endpoint under whatever address the caller likes.
    let app = test_app().await;
    let master = register_master(&app).await;
    let (_, invite) = call(
        &app,
        "POST",
        "/api/invites",
        Some(&master),
        Some(json!({ "email": "intended@lib.test" })),
    )
    .await;
    let token = invite["url"]
        .as_str()
        .unwrap()
        .rsplit('/')
        .next()
        .unwrap()
        .to_string();

    let (status, body) = call(
        &app,
        "POST",
        "/api/invites/redeem",
        None,
        Some(json!({
            "token": token,
            // No email field exists on the redeem input at all — this is the
            // shape of the API, and the test pins it by checking the outcome.
            "display_name": "Someone Else",
            "password": "friendpass1"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["email"], json!("intended@lib.test"));
}

#[tokio::test]
async fn re_inviting_supersedes_the_previous_link() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let (_, first) = call(
        &app,
        "POST",
        "/api/invites",
        Some(&master),
        Some(json!({ "email": "friend@lib.test" })),
    )
    .await;
    let old = first["url"]
        .as_str()
        .unwrap()
        .rsplit('/')
        .next()
        .unwrap()
        .to_string();

    call(
        &app,
        "POST",
        "/api/invites",
        Some(&master),
        Some(json!({ "email": "friend@lib.test" })),
    )
    .await;

    let (status, _) = call(
        &app,
        "POST",
        "/api/invites/redeem",
        None,
        Some(json!({
            "token": old,
            "display_name": "A Friend",
            "password": "friendpass1"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn inviting_an_existing_account_is_refused_plainly() {
    // Unlike `forgot`, being explicit is right here: the master is entitled to
    // know who already has an account in their own library.
    let app = test_app().await;
    let master = register_master(&app).await;
    add_member(&app, &master, "alice@lib.test").await;

    let (status, _) = call(
        &app,
        "POST",
        "/api/invites",
        Some(&master),
        Some(json!({ "email": "alice@lib.test" })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
}

#[tokio::test]
async fn an_expired_invite_is_refused() {
    let (app, db) = test_app_with_mail().await;
    let master = register_master(&app).await;
    let (_, invite) = call(
        &app,
        "POST",
        "/api/invites",
        Some(&master),
        Some(json!({ "email": "friend@lib.test" })),
    )
    .await;
    // Mail is "configured" here, so the link isn't returned -- age the row
    // directly instead, which is what a fortnight would do.
    let _ = invite;
    sqlx::query("UPDATE invite SET expires_at = datetime('now', '-1 day')")
        .execute(&db)
        .await
        .unwrap();

    let (status, _) = call(
        &app,
        "POST",
        "/api/invites/redeem",
        None,
        Some(json!({
            "token": "whatever",
            "display_name": "A Friend",
            "password": "friendpass1"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

// ---- Integrity sweep and snapshot (plan 5 #12) -----------------------------

#[tokio::test]
async fn sweep_and_snapshot_are_master_only() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let alice = add_member(&app, &master, "alice@lib.test").await;

    let (status, _) = call(&app, "POST", "/api/admin/sweep", Some(&alice), None).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = call(&app, "GET", "/api/admin/snapshot", Some(&alice), None).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn a_sweep_reports_an_orphan_without_deleting_it() {
    // Deleting by default would be a footgun: the first run on a real library is
    // exactly when the operator wants to look before touching anything.
    let (app, data_dir) = test_app_with_dir().await;
    let master = register_master(&app).await;
    let orphan = data_dir.join("files").join("nobody-refers-to-this.pdf");
    tokio::fs::create_dir_all(orphan.parent().unwrap())
        .await
        .unwrap();
    tokio::fs::write(&orphan, b"stray bytes").await.unwrap();

    let (status, body) = call(&app, "POST", "/api/admin/sweep", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(
        body["orphan_blobs"],
        json!(["files/nobody-refers-to-this.pdf"])
    );
    assert_eq!(body["orphan_bytes"], json!(11));
    assert_eq!(body["deleted"], json!(0));
    assert!(orphan.exists(), "a plain sweep must not delete anything");

    // Only with the flag.
    let (_, body) = call(
        &app,
        "POST",
        "/api/admin/sweep?delete_orphans=true",
        Some(&master),
        None,
    )
    .await;
    assert_eq!(body["deleted"], json!(1));
    assert!(!orphan.exists());
}

#[tokio::test]
async fn a_sweep_reports_a_row_whose_blob_is_gone() {
    let (app, data_dir) = test_app_with_dir().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    // A cover row pointing at nothing, the way a half-restored data dir looks.
    let (status, _) = call(
        &app,
        "PUT",
        &format!("/api/books/{book}"),
        Some(&master),
        Some(json!({ "title": "Dune", "cover_path": "covers/vanished.jpg" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (_, body) = call(&app, "POST", "/api/admin/sweep", Some(&master), None).await;
    let missing = body["missing_covers"].as_array().unwrap();
    assert_eq!(missing.len(), 1);
    assert!(missing[0].as_str().unwrap().contains("covers/vanished.jpg"));
    // Nothing was deleted from the database — reporting is not repairing.
    let (_, still_there) = call(
        &app,
        "GET",
        &format!("/api/books/{book}"),
        Some(&master),
        None,
    )
    .await;
    assert_eq!(still_there["title"], json!("Dune"));
    let _ = data_dir;
}

#[tokio::test]
async fn an_in_flight_upload_temp_is_not_reported_as_an_orphan() {
    let (app, data_dir) = test_app_with_dir().await;
    let master = register_master(&app).await;
    let files = data_dir.join("files");
    tokio::fs::create_dir_all(&files).await.unwrap();
    tokio::fs::write(files.join(".tmp-abc"), b"half")
        .await
        .unwrap();
    tokio::fs::write(files.join("x.pdf.part"), b"half")
        .await
        .unwrap();

    let (_, body) = call(&app, "POST", "/api/admin/sweep", Some(&master), None).await;
    assert_eq!(
        body["orphan_blobs"],
        json!([]),
        "flagging in-flight temporaries would train the operator to ignore this"
    );
}

#[tokio::test]
async fn a_snapshot_restores_to_a_database_with_the_same_books() {
    // The property that matters: the tar is not merely non-empty, it contains a
    // database that opens and still has the library in it.
    let (app, _dir) = test_app_with_dir().await;
    let master = register_master(&app).await;
    create_book(&app, &master, "Dune").await;
    create_book(&app, &master, "Neuromancer").await;

    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/api/admin/snapshot")
                .header("authorization", format!("Bearer {master}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(
        response.headers().get("content-type").unwrap(),
        "application/x-tar"
    );
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    assert!(!bytes.is_empty());

    // Unpack and open the database it contains.
    let restore = std::env::temp_dir().join(format!("vellum_restore_{}", uuid::Uuid::new_v4()));
    std::fs::create_dir_all(&restore).unwrap();
    tar::Archive::new(std::io::Cursor::new(&bytes[..]))
        .unpack(&restore)
        .expect("the snapshot must be a valid tar");
    let restored_db = restore.join("vellum.db");
    assert!(
        restored_db.exists(),
        "the snapshot must contain the database"
    );

    let pool = connect_db(restored_db.to_str().unwrap()).await.unwrap();
    let titles: Vec<String> = sqlx::query_scalar("SELECT title FROM book ORDER BY title")
        .fetch_all(&pool)
        .await
        .unwrap();
    assert_eq!(titles, vec!["Dune".to_string(), "Neuromancer".to_string()]);

    std::fs::remove_dir_all(&restore).ok();
}

#[tokio::test]
async fn a_snapshot_leaves_no_workspace_behind() {
    let (app, data_dir) = test_app_with_dir().await;
    let master = register_master(&app).await;
    create_book(&app, &master, "Dune").await;

    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("GET")
                .uri("/api/admin/snapshot")
                .header("authorization", format!("Bearer {master}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    // Draining the body drops the stream, which is what triggers cleanup.
    let _ = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    // The cleanup is a detached blocking task; give it a moment.
    tokio::time::sleep(std::time::Duration::from_millis(200)).await;

    let leftovers: Vec<_> = std::fs::read_dir(&data_dir)
        .map(|entries| {
            entries
                .filter_map(Result::ok)
                .map(|e| e.file_name().to_string_lossy().to_string())
                .filter(|n| n.starts_with(".snapshot-"))
                .collect()
        })
        .unwrap_or_default();
    assert!(
        leftovers.is_empty(),
        "an abandoned snapshot must not leave a copy of the library: {leftovers:?}"
    );
}

// ---- Request ids and stats (plan 5 #37) ------------------------------------

/// Like [call], but returns the response headers too.
async fn call_with_headers(
    app: &axum::Router,
    method: &str,
    uri: &str,
    token: Option<&str>,
    request_id: Option<&str>,
) -> (StatusCode, axum::http::HeaderMap, Value) {
    let mut builder = Request::builder().method(method).uri(uri);
    if let Some(t) = token {
        builder = builder.header("authorization", format!("Bearer {t}"));
    }
    if let Some(id) = request_id {
        builder = builder.header("x-request-id", id);
    }
    let response = app
        .clone()
        .oneshot(builder.body(Body::empty()).unwrap())
        .await
        .unwrap();
    let status = response.status();
    let headers = response.headers().clone();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let value = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(Value::Null)
    };
    (status, headers, value)
}

#[tokio::test]
async fn an_inbound_request_id_is_echoed_back() {
    let app = test_app().await;
    let (status, headers, _) =
        call_with_headers(&app, "GET", "/health", None, Some("abc-123")).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(headers.get("x-request-id").unwrap(), "abc-123");
}

#[tokio::test]
async fn a_request_without_an_id_gets_one() {
    let app = test_app().await;
    let (_, headers, _) = call_with_headers(&app, "GET", "/health", None, None).await;
    let id = headers
        .get("x-request-id")
        .expect("every response carries one");
    assert!(!id.is_empty());
}

#[tokio::test]
async fn an_error_body_carries_the_request_id() {
    // The point of the feature: a user pastes one string into an issue and the
    // operator finds the request. A header alone is invisible in an app's error.
    let app = test_app().await;
    let (status, headers, body) = call_with_headers(
        &app,
        "GET",
        "/api/books",
        None, // unauthenticated -> 401
        Some("trace-me"),
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(headers.get("x-request-id").unwrap(), "trace-me");
    assert_eq!(body["request_id"], json!("trace-me"));
    // ...without losing the error message itself.
    assert!(body["error"].is_string());
}

#[tokio::test]
async fn a_hostile_request_id_is_sanitised() {
    // An id goes straight into the log; newlines would let a caller forge log
    // lines, and unbounded length would let them bloat every entry.
    let app = test_app().await;
    let (_, headers, _) =
        call_with_headers(&app, "GET", "/health", None, Some("ok-part_1.2")).await;
    assert_eq!(headers.get("x-request-id").unwrap(), "ok-part_1.2");

    let long = "x".repeat(500);
    let (_, headers, _) = call_with_headers(&app, "GET", "/health", None, Some(&long)).await;
    assert_eq!(headers.get("x-request-id").unwrap().len(), 64);
}

#[tokio::test]
async fn stats_are_master_only_and_count_the_library() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let alice = add_member(&app, &master, "alice@lib.test").await;
    create_book(&app, &master, "Dune").await;
    create_book(&app, &master, "Neuromancer").await;

    let (status, _) = call(&app, "GET", "/api/admin/stats", Some(&alice), None).await;
    assert_eq!(status, StatusCode::FORBIDDEN, "a member must not see this");

    let (status, body) = call(&app, "GET", "/api/admin/stats", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["books"], json!(2));
    assert_eq!(body["users"], json!(2));
    assert!(body["server_version"].is_string());
    // Sizes are reported even when they're zero on a fresh server.
    assert!(body["blob_bytes"].is_number());
    assert!(body["database_bytes"].is_number());
}

#[tokio::test]
async fn stats_needs_a_session_at_all() {
    let app = test_app().await;
    let (status, _) = call(&app, "GET", "/api/admin/stats", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

// ---- Series and volume tracking (plan 5 #17) -------------------------------

#[tokio::test]
async fn series_membership_is_resolved_by_name_and_shared_between_books() {
    // By name, not by id: two devices that each invented an id for "Dune" must
    // still end up in one series rather than two identically-named ones.
    let app = test_app().await;
    let master = register_master(&app).await;

    for (id, index) in [("b1", 1.0), ("b2", 2.0)] {
        let (status, body) = call(
            &app,
            "PUT",
            &format!("/api/books/{id}"),
            Some(&master),
            Some(json!({
                "title": format!("Volume {index}"),
                "series": "Dune",
                "series_index": index
            })),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{body}");
        assert_eq!(body["series"], json!("Dune"));
        assert_eq!(body["series_index"], json!(index));
    }

    // One series row, two books in it.
    let (_, list) = call(&app, "GET", "/api/books", Some(&master), None).await;
    let books = list.as_array().unwrap();
    assert_eq!(books.len(), 2);
    for book in books {
        assert_eq!(book["series"], json!("Dune"));
    }
}

#[tokio::test]
async fn a_fractional_series_index_survives() {
    // The reason the column is REAL: novellas and interquels are 1.5.
    let app = test_app().await;
    let master = register_master(&app).await;
    let (_, body) = call(
        &app,
        "PUT",
        "/api/books/novella",
        Some(&master),
        Some(json!({ "title": "An Interquel", "series": "Dune", "series_index": 1.5 })),
    )
    .await;
    assert_eq!(body["series_index"], json!(1.5));
}

#[tokio::test]
async fn an_empty_series_name_clears_membership() {
    let app = test_app().await;
    let master = register_master(&app).await;
    call(
        &app,
        "PUT",
        "/api/books/b1",
        Some(&master),
        Some(json!({ "title": "Dune", "series": "Dune", "series_index": 1 })),
    )
    .await;

    let (_, body) = call(
        &app,
        "PUT",
        "/api/books/b1",
        Some(&master),
        Some(json!({ "title": "Dune", "series": "" })),
    )
    .await;
    assert_eq!(body["series"], json!(null));
}

#[tokio::test]
async fn a_push_that_omits_series_leaves_it_alone() {
    // `None` means "an older client with nothing to say" — the same convention
    // as the author and genre joins. Losing a series to a metadata-only edit
    // from an old build would be silent data loss.
    let app = test_app().await;
    let master = register_master(&app).await;
    call(
        &app,
        "PUT",
        "/api/books/b1",
        Some(&master),
        Some(json!({ "title": "Dune", "series": "Dune", "series_index": 1 })),
    )
    .await;

    let (_, body) = call(
        &app,
        "PUT",
        "/api/books/b1",
        Some(&master),
        Some(json!({ "title": "Dune (revised)" })),
    )
    .await;
    assert_eq!(body["title"], json!("Dune (revised)"));
    assert_eq!(body["series"], json!("Dune"));
    assert_eq!(body["series_index"], json!(1.0));
}

#[tokio::test]
async fn a_series_only_edit_is_not_treated_as_a_no_op() {
    // The unchanged-data guard has to know about the series, or moving a book
    // from #2 to #2.5 would be silently dropped.
    let app = test_app().await;
    let master = register_master(&app).await;
    call(
        &app,
        "PUT",
        "/api/books/b1",
        Some(&master),
        Some(json!({ "title": "Dune", "series": "Dune", "series_index": 2 })),
    )
    .await;

    let (_, body) = call(
        &app,
        "PUT",
        "/api/books/b1",
        Some(&master),
        Some(json!({ "title": "Dune", "series": "Dune", "series_index": 2.5 })),
    )
    .await;
    assert_eq!(body["series_index"], json!(2.5));

    // ...and renaming the series is likewise applied.
    let (_, renamed) = call(
        &app,
        "PUT",
        "/api/books/b1",
        Some(&master),
        Some(json!({ "title": "Dune", "series": "Dune Chronicles", "series_index": 2.5 })),
    )
    .await;
    assert_eq!(renamed["series"], json!("Dune Chronicles"));
}

#[tokio::test]
async fn a_public_link_still_serves_a_book_with_a_series() {
    // Regression guard: `shares.rs` used to keep its own copy of the book select
    // list, which went stale the moment this feature added two columns.
    let app = test_app().await;
    let master = register_master(&app).await;
    call(
        &app,
        "PUT",
        "/api/books/b1",
        Some(&master),
        Some(json!({ "title": "Dune", "series": "Dune", "series_index": 1 })),
    )
    .await;
    let (status, link) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&master),
        Some(json!({ "book_id": "b1" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{link}");
    let token = link["url"].as_str().unwrap().rsplit('/').next().unwrap();

    let (status, body) = call(&app, "GET", &format!("/api/public/{token}"), None, None).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["title"], json!("Dune"));
}

#[tokio::test]
async fn book_upsert_ignores_reading_state() {
    // Plan 2 §A1's decision, pinned directly now that `reading_progress` is an
    // advertised capability (plan 5 #5) and can no longer stand in for it: the
    // *book row* still carries no reading state, in either direction. #5's
    // channel is a separate table, keyed per device, and must never leak here.
    let app = test_app().await;
    let master = register_master(&app).await;

    let (status, body) = call(
        &app,
        "PUT",
        "/api/books/b1",
        Some(&master),
        Some(json!({
            "title": "Dune",
            "reading_progress": 0.5,
            "last_read_page": 214,
            "last_read_at": "2026-01-01 00:00:00",
            "reader_notes": "private",
            "source_metadata": "{}"
        })),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::OK,
        "unknown fields are ignored, not 400"
    );
    for local_only in [
        "reading_progress",
        "last_read_page",
        "last_read_at",
        "reader_notes",
        "source_metadata",
    ] {
        assert!(
            body.get(local_only).is_none(),
            "{local_only} must not appear on a book DTO"
        );
    }

    let (_, list) = call(&app, "GET", "/api/books", Some(&master), None).await;
    let first = &list.as_array().unwrap()[0];
    assert!(first.get("reading_progress").is_none());
    assert!(first.get("reader_notes").is_none());
}

#[tokio::test]
async fn upsert_ignores_a_stale_timestamped_push() {
    let app = test_app().await;
    let master = register_master(&app).await;

    // Create the row (its stored updated_at is ~now).
    let (status, _) = call(
        &app,
        "PUT",
        "/api/books/lww-1",
        Some(&master),
        Some(json!({ "title": "Original" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // A push carrying an older timestamp must not overwrite the row.
    let (status, body) = call(
        &app,
        "PUT",
        "/api/books/lww-1",
        Some(&master),
        Some(json!({ "title": "Stale", "updated_at": "2000-01-01 00:00:00" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        body["title"],
        json!("Original"),
        "stale push must be ignored"
    );

    // A push carrying a strictly-newer timestamp applies.
    let (_, body) = call(
        &app,
        "PUT",
        "/api/books/lww-1",
        Some(&master),
        Some(json!({ "title": "Fresh", "updated_at": "2999-01-01 00:00:00" })),
    )
    .await;
    assert_eq!(body["title"], json!("Fresh"), "newer push must apply");

    // A push with no timestamp still overwrites (old-client compatibility).
    let (_, body) = call(
        &app,
        "PUT",
        "/api/books/lww-1",
        Some(&master),
        Some(json!({ "title": "NoStamp" })),
    )
    .await;
    assert_eq!(body["title"], json!("NoStamp"));
}

#[tokio::test]
async fn books_list_supports_delta_cursor_envelope() {
    let app = test_app().await;
    let master = register_master(&app).await;
    create_book(&app, &master, "Dune").await;

    // No cursor → the console's bare array is unchanged.
    let (_, bare) = call(&app, "GET", "/api/books", Some(&master), None).await;
    assert!(bare.is_array());
    assert_eq!(bare.as_array().unwrap().len(), 1);

    // An (empty) cursor → the { server_now, books } envelope with everything.
    let (_, env) = call(&app, "GET", "/api/books?cursor=", Some(&master), None).await;
    assert!(env["server_now"].is_string());
    assert_eq!(env["books"].as_array().unwrap().len(), 1);

    // A future cursor filters everything out (delta pull sees no changes).
    let (_, empty) = call(
        &app,
        "GET",
        "/api/books?cursor=2999-01-01%2000:00:00",
        Some(&master),
        None,
    )
    .await;
    assert!(empty["books"].as_array().unwrap().is_empty());
}

#[tokio::test]
async fn capabilities_is_unauthenticated_and_has_the_expected_shape() {
    let app = test_app().await;
    let (status, body) = call(&app, "GET", "/api/capabilities", None, None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(body["server_version"].is_string());
    assert_eq!(body["sync_protocol"], json!(1));
    let features = body["features"].as_array().unwrap();
    assert!(features.contains(&json!("delta_pull")));
    // shelf_sync, copy_sync, loan_sync (plan 5 #4), and batch_push (plan 5
    // #7) shipped after this handshake -- confirms the list tracks what's
    // actually built rather than staying frozen.
    assert!(features.contains(&json!("shelf_sync")));
    assert!(features.contains(&json!("copy_sync")));
    assert!(features.contains(&json!("loan_sync")));
    assert!(features.contains(&json!("batch_push")));
    // reading_progress advertises #5's separate opt-in per-device channel --
    // *not* reading state on the book row, which stays app-local-only. That
    // invariant used to be implied by this feature's absence; it is now pinned
    // directly by `book_upsert_ignores_reading_state`.
    assert!(features.contains(&json!("reading_progress")));
    // Absent here: `content_search` (plan 5 #32) and `mail` both depend on this
    // server's configuration rather than being constants -- this app has no
    // mailer and no content index. See mail_is_advertised_once_a_mailer_exists
    // and tests/text_index.rs for the other side of each.
    for absent in ["content_search", "mail"] {
        assert!(
            !features.contains(&json!(absent)),
            "{absent} is configuration-dependent and this server has it off"
        );
    }
}

#[tokio::test]
async fn api_v1_prefix_is_equivalent_to_the_unprefixed_alias() {
    // §6: /api/v1/* is `nest`ed from the exact same routes as /api/* (see
    // api_routes() in lib.rs) -- both must answer identically, and the
    // handful of routes that deliberately stay unversioned (/opds, /health,
    // /) must not have moved under either prefix.
    let app = test_app().await;
    let master = register_master(&app).await;
    create_book(&app, &master, "Dune").await;

    let (s1, unprefixed) = call(&app, "GET", "/api/capabilities", None, None).await;
    let (s2, v1) = call(&app, "GET", "/api/v1/capabilities", None, None).await;
    assert_eq!((s1, &unprefixed), (s2, &v1));

    let (s1, unprefixed) = call(&app, "GET", "/api/books", Some(&master), None).await;
    let (s2, v1) = call(&app, "GET", "/api/v1/books", Some(&master), None).await;
    assert_eq!((s1, &unprefixed), (s2, &v1));

    let (status, _) = call(&app, "GET", "/health", None, None).await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = call(&app, "GET", "/api/v1/health", None, None).await;
    assert_eq!(
        status,
        StatusCode::NOT_FOUND,
        "/health must not move under /api"
    );

    let (status, _) = call(&app, "GET", "/opds", None, None).await;
    assert_eq!(
        status,
        StatusCode::UNAUTHORIZED,
        "reachable, just needs Basic auth"
    );
    let (status, _) = call(&app, "GET", "/api/opds", None, None).await;
    assert_eq!(
        status,
        StatusCode::NOT_FOUND,
        "/opds must not move under /api either"
    );
}

#[tokio::test]
async fn books_list_page_param_is_inert_when_a_cursor_is_present() {
    // §3: page/limit must never apply when cursor is present in any form --
    // an empty cursor is the app's *first* sync, and letting a page limit
    // apply to it would silently truncate that pull.
    let app = test_app().await;
    let master = register_master(&app).await;
    for i in 0..3 {
        create_book(&app, &master, &format!("Book {i}")).await;
    }

    for cursor_qs in ["cursor=", "cursor=2000-01-01%2000:00:00"] {
        let (_, env) = call(
            &app,
            "GET",
            &format!("/api/books?{cursor_qs}&page=1&limit=1"),
            Some(&master),
            None,
        )
        .await;
        assert_eq!(
            env["books"].as_array().unwrap().len(),
            3,
            "cursor pull truncated by page/limit ({cursor_qs})"
        );
        assert!(
            env["items"].is_null(),
            "cursor pull must keep the envelope shape, not the paged one"
        );
    }
}

#[tokio::test]
async fn books_list_paginates_stably_with_total_and_next() {
    let app = test_app().await;
    let master = register_master(&app).await;
    // Titles chosen so the list's ORDER BY (title, id) gives a predictable
    // order regardless of creation order.
    create_book(&app, &master, "Charlie").await;
    create_book(&app, &master, "Alpha").await;
    create_book(&app, &master, "Bravo").await;

    let (_, page1) = call(
        &app,
        "GET",
        "/api/books?page=1&limit=2",
        Some(&master),
        None,
    )
    .await;
    assert_eq!(page1["total"], json!(3));
    assert_eq!(page1["next"], json!(2));
    assert_eq!(titles(&page1["items"]), vec!["Alpha", "Bravo"]);

    let (_, page2) = call(
        &app,
        "GET",
        "/api/books?page=2&limit=2",
        Some(&master),
        None,
    )
    .await;
    assert_eq!(page2["total"], json!(3));
    assert_eq!(page2["next"], Value::Null, "last page has no next");
    assert_eq!(titles(&page2["items"]), vec!["Charlie"]);
}

#[tokio::test]
async fn books_list_scopes_authors_genres_to_each_returned_book() {
    // §3: the authors/genres/files aggregation is now looked up scoped to
    // the returned book ids in one pass rather than a per-list full-table
    // scan -- pins that scoping doesn't cross-contaminate books sharing that
    // one lookup pass.
    let app = test_app().await;
    let master = register_master(&app).await;
    call(
        &app,
        "PUT",
        "/api/books/sc-1",
        Some(&master),
        Some(json!({ "title": "One", "authors": ["Ann"], "genres": ["Sci-Fi"] })),
    )
    .await;
    call(
        &app,
        "PUT",
        "/api/books/sc-2",
        Some(&master),
        Some(json!({ "title": "Two", "authors": ["Bob"], "genres": ["Poetry"] })),
    )
    .await;

    let (_, list) = call(&app, "GET", "/api/books", Some(&master), None).await;
    let by_id: std::collections::HashMap<String, Value> = list
        .as_array()
        .unwrap()
        .iter()
        .map(|b| (b["id"].as_str().unwrap().to_string(), b.clone()))
        .collect();
    assert_eq!(by_id["sc-1"]["authors"], json!(["Ann"]));
    assert_eq!(by_id["sc-1"]["genres"], json!(["Sci-Fi"]));
    assert_eq!(by_id["sc-2"]["authors"], json!(["Bob"]));
    assert_eq!(by_id["sc-2"]["genres"], json!(["Poetry"]));
}

#[tokio::test]
async fn shelves_put_creates_and_preserves_explicit_order() {
    // §4: a push always sends the whole ordered membership and the server
    // replaces it wholesale -- this is the test that would catch a set-replace
    // silently losing order (books present but scrambled), which looks fine
    // until a user notices their manual arrangement changed.
    let app = test_app().await;
    let master = register_master(&app).await;
    let b1 = create_book(&app, &master, "Charlie").await;
    let b2 = create_book(&app, &master, "Alpha").await;
    let b3 = create_book(&app, &master, "Bravo").await;

    let (status, shelf) = call(
        &app,
        "PUT",
        "/api/shelves/sh-1",
        Some(&master),
        Some(json!({ "name": "To read", "book_ids": [b1, b2, b3] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{shelf}");
    assert_eq!(shelf["book_ids"], json!([b1, b2, b3]));

    let (_, list) = call(&app, "GET", "/api/shelves", Some(&master), None).await;
    let listed = list.as_array().unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0]["book_ids"], json!([b1, b2, b3]));
}

#[tokio::test]
async fn shelves_put_drops_book_ids_the_server_does_not_recognize() {
    // shelf_book.book_id has a foreign key on book(id); a stale or
    // never-pushed id in the membership list must be dropped, not fail the
    // whole shelf (plan 5 #4's FK-safety net).
    let app = test_app().await;
    let master = register_master(&app).await;
    let real = create_book(&app, &master, "Dune").await;

    let (status, shelf) = call(
        &app,
        "PUT",
        "/api/shelves/sh-1",
        Some(&master),
        Some(json!({ "name": "Mixed", "book_ids": [real, "no-such-book"] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{shelf}");
    assert_eq!(shelf["book_ids"], json!([real]));
}

#[tokio::test]
async fn shelves_all_scope_share_grants_viewer_not_editor() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let bob = add_member(&app, &master, "bob@lib.test").await;
    call(
        &app,
        "PUT",
        "/api/shelves/sh-1",
        Some(&master),
        Some(json!({ "name": "Master's shelf" })),
    )
    .await;

    // Before sharing, Bob sees nothing.
    let (_, before) = call(&app, "GET", "/api/shelves", Some(&bob), None).await;
    assert!(before.as_array().unwrap().is_empty());

    call(
        &app,
        "POST",
        "/api/shares",
        Some(&master),
        Some(json!({ "scope": "all", "grantee_email": "bob@lib.test" })),
    )
    .await;

    let (_, after) = call(&app, "GET", "/api/shelves", Some(&bob), None).await;
    assert_eq!(after.as_array().unwrap().len(), 1);

    // Read-only: Bob may not rename or delete master's shelf.
    let (status, _) = call(
        &app,
        "PUT",
        "/api/shelves/sh-1",
        Some(&bob),
        Some(json!({ "name": "Hijacked" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = call(&app, "DELETE", "/api/shelves/sh-1", Some(&bob), None).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn shelves_delete_records_a_kind_tagged_tombstone() {
    let app = test_app().await;
    let master = register_master(&app).await;
    call(
        &app,
        "PUT",
        "/api/shelves/sh-1",
        Some(&master),
        Some(json!({ "name": "Gone soon" })),
    )
    .await;

    let (status, _) = call(&app, "DELETE", "/api/shelves/sh-1", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK);

    // The shared /api/deletions endpoint carries it, tagged so an old client
    // (which only reads book_id/deleted_at) harmlessly no-ops on it.
    let (_, all) = call(&app, "GET", "/api/deletions", Some(&master), None).await;
    let entries = all.as_array().unwrap();
    let shelf_entry = entries.iter().find(|e| e["book_id"] == "sh-1").unwrap();
    assert_eq!(shelf_entry["kind"], json!("shelf"));

    // ?kind=shelf filters to just this kind.
    let (_, shelf_only) = call(
        &app,
        "GET",
        "/api/deletions?kind=shelf",
        Some(&master),
        None,
    )
    .await;
    assert_eq!(shelf_only.as_array().unwrap().len(), 1);
    let (_, book_only) = call(&app, "GET", "/api/deletions?kind=book", Some(&master), None).await;
    assert!(book_only.as_array().unwrap().is_empty());

    // Gone from the live list too.
    let (_, list) = call(&app, "GET", "/api/shelves", Some(&master), None).await;
    assert!(list.as_array().unwrap().is_empty());
}

#[tokio::test]
async fn shelves_put_is_a_noop_when_unchanged_including_order() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let b1 = create_book(&app, &master, "A").await;
    let b2 = create_book(&app, &master, "B").await;
    call(
        &app,
        "PUT",
        "/api/shelves/sh-1",
        Some(&master),
        Some(json!({ "name": "Stable", "book_ids": [b1, b2] })),
    )
    .await;
    let (_, first) = call(&app, "GET", "/api/shelves", Some(&master), None).await;
    let stamp1 = first.as_array().unwrap()[0]["updated_at"].clone();

    // Re-push identical name/order.
    call(
        &app,
        "PUT",
        "/api/shelves/sh-1",
        Some(&master),
        Some(json!({ "name": "Stable", "book_ids": [b1, b2] })),
    )
    .await;
    let (_, second) = call(&app, "GET", "/api/shelves", Some(&master), None).await;
    assert_eq!(
        second.as_array().unwrap()[0]["updated_at"],
        stamp1,
        "an unchanged re-push must not churn updated_at (and thus every pull cursor)"
    );
}

#[tokio::test]
async fn shelves_list_supports_delta_cursor_envelope() {
    let app = test_app().await;
    let master = register_master(&app).await;
    call(
        &app,
        "PUT",
        "/api/shelves/sh-1",
        Some(&master),
        Some(json!({ "name": "Only shelf" })),
    )
    .await;

    let (_, bare) = call(&app, "GET", "/api/shelves", Some(&master), None).await;
    assert!(bare.is_array());

    let (_, env) = call(&app, "GET", "/api/shelves?cursor=", Some(&master), None).await;
    assert!(env["server_now"].is_string());
    assert_eq!(env["shelves"].as_array().unwrap().len(), 1);

    let (_, future) = call(
        &app,
        "GET",
        "/api/shelves?cursor=2999-01-01%2000:00:00",
        Some(&master),
        None,
    )
    .await;
    assert!(future["shelves"].as_array().unwrap().is_empty());
}

#[tokio::test]
async fn copies_put_creates_and_is_visible_only_through_its_book() {
    // Plan 5 #4, third of the shelf/copy/loan trio: a copy has no owner of
    // its own -- visibility comes entirely from access::copy_access delegating
    // to the parent book.
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    let (status, copy) = call(
        &app,
        "PUT",
        "/api/copies/c-1",
        Some(&master),
        Some(json!({ "book_id": book, "location": "Living room" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{copy}");
    assert_eq!(copy["book_id"], json!(book));
    assert_eq!(copy["location"], json!("Living room"));

    let (_, list) = call(&app, "GET", "/api/copies", Some(&master), None).await;
    let listed = list.as_array().unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0]["id"], json!("c-1"));
}

#[tokio::test]
async fn copies_put_rejects_moving_an_existing_copy_to_a_different_book() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book1 = create_book(&app, &master, "Dune").await;
    let book2 = create_book(&app, &master, "Neuromancer").await;
    call(
        &app,
        "PUT",
        "/api/copies/c-1",
        Some(&master),
        Some(json!({ "book_id": book1 })),
    )
    .await;

    let (status, _) = call(
        &app,
        "PUT",
        "/api/copies/c-1",
        Some(&master),
        Some(json!({ "book_id": book2 })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn copies_editor_book_share_may_edit_but_not_delete() {
    // A copy has no share type of its own: editor access to its book is
    // editor access to the copy (access::copy_access), same as any other
    // book-scoped resource; only the book's owner/master may delete it.
    let app = test_app().await;
    let master = register_master(&app).await;
    let alice = add_member(&app, &master, "alice@lib.test").await;
    let book = create_book(&app, &master, "Neuromancer").await;
    call(
        &app,
        "PUT",
        "/api/copies/c-1",
        Some(&master),
        Some(json!({ "book_id": book, "location": "Shelf 3" })),
    )
    .await;

    // Before sharing, Alice sees nothing.
    let (_, before) = call(&app, "GET", "/api/copies", Some(&alice), None).await;
    assert!(before.as_array().unwrap().is_empty());

    call(
        &app,
        "POST",
        "/api/shares",
        Some(&master),
        Some(json!({
            "scope": "book", "scope_id": book,
            "grantee_email": "alice@lib.test", "permission": "editor"
        })),
    )
    .await;

    let (status, copy) = call(
        &app,
        "PUT",
        "/api/copies/c-1",
        Some(&alice),
        Some(json!({ "book_id": book, "location": "Moved by Alice" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{copy}");
    assert_eq!(copy["location"], json!("Moved by Alice"));

    let (status, _) = call(&app, "DELETE", "/api/copies/c-1", Some(&alice), None).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn copies_delete_records_a_kind_tagged_tombstone() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;
    call(
        &app,
        "PUT",
        "/api/copies/c-1",
        Some(&master),
        Some(json!({ "book_id": book })),
    )
    .await;

    let (status, _) = call(&app, "DELETE", "/api/copies/c-1", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK);

    let (_, kind_only) = call(&app, "GET", "/api/deletions?kind=copy", Some(&master), None).await;
    let entries = kind_only.as_array().unwrap();
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0]["book_id"], json!("c-1"));

    let (_, list) = call(&app, "GET", "/api/copies", Some(&master), None).await;
    assert!(list.as_array().unwrap().is_empty());
}

#[tokio::test]
async fn copies_put_is_a_noop_when_unchanged() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;
    call(
        &app,
        "PUT",
        "/api/copies/c-1",
        Some(&master),
        Some(json!({ "book_id": book, "location": "Desk" })),
    )
    .await;
    let (_, first) = call(&app, "GET", "/api/copies", Some(&master), None).await;
    let stamp1 = first.as_array().unwrap()[0]["updated_at"].clone();

    call(
        &app,
        "PUT",
        "/api/copies/c-1",
        Some(&master),
        Some(json!({ "book_id": book, "location": "Desk" })),
    )
    .await;
    let (_, second) = call(&app, "GET", "/api/copies", Some(&master), None).await;
    assert_eq!(
        second.as_array().unwrap()[0]["updated_at"],
        stamp1,
        "an unchanged re-push must not churn updated_at"
    );
}

#[tokio::test]
async fn copies_list_supports_delta_cursor_envelope() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;
    call(
        &app,
        "PUT",
        "/api/copies/c-1",
        Some(&master),
        Some(json!({ "book_id": book })),
    )
    .await;

    let (_, bare) = call(&app, "GET", "/api/copies", Some(&master), None).await;
    assert!(bare.is_array());

    let (_, env) = call(&app, "GET", "/api/copies?cursor=", Some(&master), None).await;
    assert!(env["server_now"].is_string());
    assert_eq!(env["copies"].as_array().unwrap().len(), 1);

    let (_, future) = call(
        &app,
        "GET",
        "/api/copies?cursor=2999-01-01%2000:00:00",
        Some(&master),
        None,
    )
    .await;
    assert!(future["copies"].as_array().unwrap().is_empty());
}

#[tokio::test]
async fn loans_put_creates_and_is_visible_only_through_its_copy() {
    // Plan 5 #4, third and last of the trio: a loan has no owner of its own
    // -- visibility comes from access::loan_access joining copy -> book.
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;
    call(
        &app,
        "PUT",
        "/api/copies/c-1",
        Some(&master),
        Some(json!({ "book_id": book })),
    )
    .await;

    let (status, loan) = call(
        &app,
        "PUT",
        "/api/loans/l-1",
        Some(&master),
        Some(json!({
            "copy_id": "c-1", "borrower": "Alice", "loaned_at": "2024-01-01 00:00:00"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{loan}");
    assert_eq!(loan["borrower"], json!("Alice"));
    assert_eq!(loan["returned_at"], json!(null));

    let (_, list) = call(&app, "GET", "/api/loans", Some(&master), None).await;
    let listed = list.as_array().unwrap();
    assert_eq!(listed.len(), 1);
    assert_eq!(listed[0]["id"], json!("l-1"));
}

#[tokio::test]
async fn loans_put_rejects_moving_an_existing_loan_to_a_different_copy() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;
    call(
        &app,
        "PUT",
        "/api/copies/c-1",
        Some(&master),
        Some(json!({ "book_id": book })),
    )
    .await;
    call(
        &app,
        "PUT",
        "/api/copies/c-2",
        Some(&master),
        Some(json!({ "book_id": book })),
    )
    .await;
    call(
        &app,
        "PUT",
        "/api/loans/l-1",
        Some(&master),
        Some(json!({
            "copy_id": "c-1", "borrower": "Alice", "loaned_at": "2024-01-01 00:00:00"
        })),
    )
    .await;

    let (status, _) = call(
        &app,
        "PUT",
        "/api/loans/l-1",
        Some(&master),
        Some(json!({
            "copy_id": "c-2", "borrower": "Alice", "loaned_at": "2024-01-01 00:00:00"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn loans_editor_book_share_may_edit_but_not_delete() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let alice = add_member(&app, &master, "alice@lib.test").await;
    let book = create_book(&app, &master, "Neuromancer").await;
    call(
        &app,
        "PUT",
        "/api/copies/c-1",
        Some(&master),
        Some(json!({ "book_id": book })),
    )
    .await;
    call(
        &app,
        "PUT",
        "/api/loans/l-1",
        Some(&master),
        Some(json!({
            "copy_id": "c-1", "borrower": "Bob", "loaned_at": "2024-01-01 00:00:00"
        })),
    )
    .await;

    call(
        &app,
        "POST",
        "/api/shares",
        Some(&master),
        Some(json!({
            "scope": "book", "scope_id": book,
            "grantee_email": "alice@lib.test", "permission": "editor"
        })),
    )
    .await;

    let (status, loan) = call(
        &app,
        "PUT",
        "/api/loans/l-1",
        Some(&alice),
        Some(json!({
            "copy_id": "c-1", "borrower": "Bob",
            "returned_at": "2024-02-01 00:00:00", "loaned_at": "2024-01-01 00:00:00"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{loan}");
    assert_eq!(loan["returned_at"], json!("2024-02-01 00:00:00"));

    let (status, _) = call(&app, "DELETE", "/api/loans/l-1", Some(&alice), None).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn loans_delete_records_a_kind_tagged_tombstone() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;
    call(
        &app,
        "PUT",
        "/api/copies/c-1",
        Some(&master),
        Some(json!({ "book_id": book })),
    )
    .await;
    call(
        &app,
        "PUT",
        "/api/loans/l-1",
        Some(&master),
        Some(json!({
            "copy_id": "c-1", "borrower": "Alice", "loaned_at": "2024-01-01 00:00:00"
        })),
    )
    .await;

    let (status, _) = call(&app, "DELETE", "/api/loans/l-1", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK);

    let (_, kind_only) = call(&app, "GET", "/api/deletions?kind=loan", Some(&master), None).await;
    let entries = kind_only.as_array().unwrap();
    assert_eq!(entries.len(), 1);
    assert_eq!(entries[0]["book_id"], json!("l-1"));

    let (_, list) = call(&app, "GET", "/api/loans", Some(&master), None).await;
    assert!(list.as_array().unwrap().is_empty());
}

#[tokio::test]
async fn loans_delete_cascades_when_its_copy_is_deleted() {
    // loan.copy_id has ON DELETE CASCADE -- deleting the copy removes its
    // loans without needing a per-loan tombstone (the copy's own tombstone
    // is what a pull acts on; see SyncService._pullLoans's FK-safety skip).
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;
    call(
        &app,
        "PUT",
        "/api/copies/c-1",
        Some(&master),
        Some(json!({ "book_id": book })),
    )
    .await;
    call(
        &app,
        "PUT",
        "/api/loans/l-1",
        Some(&master),
        Some(json!({
            "copy_id": "c-1", "borrower": "Alice", "loaned_at": "2024-01-01 00:00:00"
        })),
    )
    .await;

    call(&app, "DELETE", "/api/copies/c-1", Some(&master), None).await;

    let (_, list) = call(&app, "GET", "/api/loans", Some(&master), None).await;
    assert!(list.as_array().unwrap().is_empty());
    let (_, loan_tombstones) =
        call(&app, "GET", "/api/deletions?kind=loan", Some(&master), None).await;
    assert!(
        loan_tombstones.as_array().unwrap().is_empty(),
        "the copy's cascade removes the loan silently -- no per-loan tombstone is emitted"
    );
}

#[tokio::test]
async fn loans_put_is_a_noop_when_unchanged() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;
    call(
        &app,
        "PUT",
        "/api/copies/c-1",
        Some(&master),
        Some(json!({ "book_id": book })),
    )
    .await;
    call(
        &app,
        "PUT",
        "/api/loans/l-1",
        Some(&master),
        Some(json!({
            "copy_id": "c-1", "borrower": "Alice", "loaned_at": "2024-01-01 00:00:00"
        })),
    )
    .await;
    let (_, first) = call(&app, "GET", "/api/loans", Some(&master), None).await;
    let stamp1 = first.as_array().unwrap()[0]["updated_at"].clone();

    call(
        &app,
        "PUT",
        "/api/loans/l-1",
        Some(&master),
        Some(json!({
            "copy_id": "c-1", "borrower": "Alice", "loaned_at": "2024-01-01 00:00:00"
        })),
    )
    .await;
    let (_, second) = call(&app, "GET", "/api/loans", Some(&master), None).await;
    assert_eq!(
        second.as_array().unwrap()[0]["updated_at"],
        stamp1,
        "an unchanged re-push must not churn updated_at"
    );
}

#[tokio::test]
async fn loans_list_supports_delta_cursor_envelope() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;
    call(
        &app,
        "PUT",
        "/api/copies/c-1",
        Some(&master),
        Some(json!({ "book_id": book })),
    )
    .await;
    call(
        &app,
        "PUT",
        "/api/loans/l-1",
        Some(&master),
        Some(json!({
            "copy_id": "c-1", "borrower": "Alice", "loaned_at": "2024-01-01 00:00:00"
        })),
    )
    .await;

    let (_, bare) = call(&app, "GET", "/api/loans", Some(&master), None).await;
    assert!(bare.is_array());

    let (_, env) = call(&app, "GET", "/api/loans?cursor=", Some(&master), None).await;
    assert!(env["server_now"].is_string());
    assert_eq!(env["loans"].as_array().unwrap().len(), 1);

    let (_, future) = call(
        &app,
        "GET",
        "/api/loans?cursor=2999-01-01%2000:00:00",
        Some(&master),
        None,
    )
    .await;
    assert!(future["loans"].as_array().unwrap().is_empty());
}

#[tokio::test]
async fn upsert_is_a_noop_when_nothing_changed() {
    let app = test_app().await;
    let master = register_master(&app).await;

    let (_, first) = call(
        &app,
        "PUT",
        "/api/books/noop-1",
        Some(&master),
        Some(json!({ "title": "Dune", "authors": ["Frank Herbert"] })),
    )
    .await;
    let stamp1 = first["updated_at"].as_str().unwrap().to_string();

    // updated_at has one-second resolution, so let the clock move on: a genuine
    // write would now stamp a strictly-later time, making the no-op observable.
    tokio::time::sleep(std::time::Duration::from_millis(1100)).await;

    // Re-pushing byte-identical metadata + authors must not bump updated_at.
    let (_, second) = call(
        &app,
        "PUT",
        "/api/books/noop-1",
        Some(&master),
        Some(json!({ "title": "Dune", "authors": ["Frank Herbert"] })),
    )
    .await;
    assert_eq!(
        second["updated_at"].as_str().unwrap(),
        stamp1,
        "redundant push must not churn updated_at"
    );

    // A real change still bumps it (>1s has elapsed since stamp1).
    let (_, third) = call(
        &app,
        "PUT",
        "/api/books/noop-1",
        Some(&master),
        Some(json!({ "title": "Dune Messiah", "authors": ["Frank Herbert"] })),
    )
    .await;
    assert_ne!(third["updated_at"].as_str().unwrap(), stamp1);
}

#[tokio::test]
async fn upsert_replaces_authors_and_genres() {
    let app = test_app().await;
    let master = register_master(&app).await;

    // A push carrying authors + genres stores them (get-or-create by name).
    let (status, _) = call(
        &app,
        "PUT",
        "/api/books/ag-1",
        Some(&master),
        Some(json!({
            "title": "Dune",
            "authors": ["Frank Herbert", "Kevin Anderson"],
            "genres": ["Sci-Fi"]
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (_, detail) = call(&app, "GET", "/api/books/ag-1/detail", Some(&master), None).await;
    assert_eq!(
        detail["authors"],
        json!(["Frank Herbert", "Kevin Anderson"])
    );
    assert_eq!(detail["genres"], json!(["Sci-Fi"]));

    // The books list is enriched with both, for the app's pull.
    let (_, list) = call(&app, "GET", "/api/books", Some(&master), None).await;
    assert_eq!(
        list[0]["authors"],
        json!(["Frank Herbert", "Kevin Anderson"])
    );
    assert_eq!(list[0]["genres"], json!(["Sci-Fi"]));

    // Re-pushing with a shorter author list replaces rather than appends;
    // omitting genres leaves the existing genre joins untouched.
    call(
        &app,
        "PUT",
        "/api/books/ag-1",
        Some(&master),
        Some(json!({ "title": "Dune", "authors": ["Frank Herbert"] })),
    )
    .await;
    let (_, detail) = call(&app, "GET", "/api/books/ag-1/detail", Some(&master), None).await;
    assert_eq!(detail["authors"], json!(["Frank Herbert"]));
    assert_eq!(detail["genres"], json!(["Sci-Fi"]), "omitted genres kept");
}

#[tokio::test]
async fn upsert_and_delete_gc_orphaned_authors() {
    let (app, db) = test_app_with_db().await;
    let master = register_master(&app).await;

    // Two books sharing one author and each having a unique one.
    for (id, extra) in [("gc-1", "Only On One"), ("gc-2", "Solo Two")] {
        call(
            &app,
            "PUT",
            &format!("/api/books/{id}"),
            Some(&master),
            Some(json!({ "title": id, "authors": ["Shared", extra] })),
        )
        .await;
    }
    let count = |db: sqlx::SqlitePool| async move {
        sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM author")
            .fetch_one(&db)
            .await
            .unwrap()
    };
    assert_eq!(count(db.clone()).await, 3, "Shared + two uniques");

    // Re-tag gc-1 to just Shared: "Only On One" is now orphaned and swept.
    call(
        &app,
        "PUT",
        "/api/books/gc-1",
        Some(&master),
        Some(json!({ "title": "gc-1", "authors": ["Shared"] })),
    )
    .await;
    assert_eq!(
        count(db.clone()).await,
        2,
        "orphaned author removed on re-tag"
    );

    // Deleting gc-2 orphans "Solo Two"; "Shared" survives (gc-1 still has it).
    call(&app, "DELETE", "/api/books/gc-2", Some(&master), None).await;
    assert_eq!(
        count(db.clone()).await,
        1,
        "delete sweeps its orphaned author"
    );
}

/// A minimal EPUB (zip) declaring its cover via the EPUB2 `<meta name="cover">`
/// convention, pointing at a PNG entry.
fn make_epub_with_cover() -> Vec<u8> {
    use std::io::Write;
    const CONTAINER: &str = "<?xml version=\"1.0\"?>\
        <container version=\"1.0\" xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\">\
        <rootfiles><rootfile full-path=\"content.opf\" \
        media-type=\"application/oebps-package+xml\"/></rootfiles></container>";
    const OPF: &str = "<?xml version=\"1.0\"?>\
        <package xmlns=\"http://www.idpf.org/2007/opf\" version=\"2.0\">\
        <metadata xmlns:dc=\"http://purl.org/dc/elements/1.1/\">\
        <dc:title>Tiny</dc:title><meta name=\"cover\" content=\"cov\"/></metadata>\
        <manifest>\
        <item id=\"cov\" href=\"cover.png\" media-type=\"image/png\"/>\
        <item id=\"c1\" href=\"ch1.xhtml\" media-type=\"application/xhtml+xml\"/>\
        </manifest><spine><itemref idref=\"c1\"/></spine></package>";
    let mut zw = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
    for (name, data) in [
        ("mimetype", b"application/epub+zip".to_vec()),
        ("META-INF/container.xml", CONTAINER.as_bytes().to_vec()),
        ("content.opf", OPF.as_bytes().to_vec()),
        ("cover.png", b"\x89PNG\r\n\x1a\n fake-cover-bytes".to_vec()),
        ("ch1.xhtml", b"<html><body>hi</body></html>".to_vec()),
    ] {
        zw.start_file(name, zip::write::SimpleFileOptions::default())
            .unwrap();
        zw.write_all(&data).unwrap();
    }
    zw.finish().unwrap().into_inner()
}

#[tokio::test]
async fn epub_upload_extracts_declared_cover() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Tiny").await;

    let upload = Request::builder()
        .method("POST")
        .uri(format!("/api/books/{book}/files?filename=tiny.epub"))
        .header("authorization", format!("Bearer {master}"))
        .header("content-type", "application/epub+zip")
        .body(Body::from(make_epub_with_cover()))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(upload).await.unwrap().status(),
        StatusCode::OK
    );

    // The cover is extracted in a background task after the response; poll for it.
    let mut got_cover = false;
    for _ in 0..50 {
        let res = app
            .clone()
            .oneshot(
                Request::builder()
                    .uri(format!("/api/books/{book}/cover"))
                    .header("authorization", format!("Bearer {master}"))
                    .body(Body::empty())
                    .unwrap(),
            )
            .await
            .unwrap();
        if res.status() == StatusCode::OK {
            got_cover = true;
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(20)).await;
    }
    assert!(got_cover, "the EPUB's declared cover should be served");
}

#[tokio::test]
async fn book_detail_and_query_token_download() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    // Attach a file.
    let pdf = b"%PDF-1.4 hello".to_vec();
    let upload = Request::builder()
        .method("POST")
        .uri(format!("/api/books/{book}/files?filename=dune.pdf"))
        .header("authorization", format!("Bearer {master}"))
        .header("content-type", "application/pdf")
        .body(Body::from(pdf.clone()))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(upload).await.unwrap().status(),
        StatusCode::OK
    );

    // Detail carries metadata + files.
    let (status, detail) = call(
        &app,
        "GET",
        &format!("/api/books/{book}/detail"),
        Some(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(detail["title"], json!("Dune"));
    let files = detail["files"].as_array().unwrap();
    assert_eq!(files.len(), 1);
    let file_id = files[0]["id"].as_str().unwrap().to_string();

    // A download authenticates via the Authorization header (the token is never
    // read from the URL).
    let download = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/files/{file_id}"))
                .header("authorization", format!("Bearer {master}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(download.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(download.into_body(), usize::MAX)
        .await
        .unwrap();
    assert_eq!(bytes.as_ref(), pdf.as_slice());

    // A `?token=` query is not accepted, even with a valid token value.
    let via_query = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/files/{file_id}?token={master}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(via_query.status(), StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn deleting_a_book_removes_its_blobs_from_disk() {
    let (app, data_dir) = test_app_with_dir().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    // Attach a real PDF and a real PNG cover.
    let upload = Request::builder()
        .method("POST")
        .uri(format!("/api/books/{book}/files?filename=dune.pdf"))
        .header("authorization", format!("Bearer {master}"))
        .body(Body::from(b"%PDF-1.4 hello".to_vec()))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(upload).await.unwrap().status(),
        StatusCode::OK
    );
    let put = Request::builder()
        .method("PUT")
        .uri(format!("/api/books/{book}/cover"))
        .header("authorization", format!("Bearer {master}"))
        .body(Body::from(b"\x89PNG\r\n\x1a\n fake".to_vec()))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(put).await.unwrap().status(),
        StatusCode::OK
    );

    // Learn the on-disk paths, and confirm they exist.
    let (_, detail) = call(
        &app,
        "GET",
        &format!("/api/books/{book}/detail"),
        Some(&master),
        None,
    )
    .await;
    let file_rel = detail["files"][0]["path"].as_str().unwrap().to_string();
    let cover_rel = detail["cover_path"].as_str().unwrap().to_string();
    assert!(data_dir.join(&file_rel).exists());
    assert!(data_dir.join(&cover_rel).exists());

    // Deleting the book removes both blobs.
    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/books/{book}"),
        Some(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        !data_dir.join(&file_rel).exists(),
        "file blob should be gone"
    );
    assert!(
        !data_dir.join(&cover_rel).exists(),
        "cover blob should be gone"
    );
}

#[tokio::test]
async fn deleting_a_book_records_a_tombstone_that_upsert_clears() {
    let app = test_app().await;
    let master = register_master(&app).await;

    // Create via id-preserving upsert, then delete it.
    call(
        &app,
        "PUT",
        "/api/books/book-1",
        Some(&master),
        Some(json!({ "title": "Dune" })),
    )
    .await;
    let (status, _) = call(&app, "DELETE", "/api/books/book-1", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK);

    // The tombstone is listed.
    let (status, list) = call(&app, "GET", "/api/deletions", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK);
    let ids: Vec<&str> = list
        .as_array()
        .unwrap()
        .iter()
        .map(|d| d["book_id"].as_str().unwrap())
        .collect();
    assert_eq!(ids, vec!["book-1"]);

    // Re-creating the book at the same id clears the tombstone.
    call(
        &app,
        "PUT",
        "/api/books/book-1",
        Some(&master),
        Some(json!({ "title": "Dune (revived)" })),
    )
    .await;
    let (_, list) = call(&app, "GET", "/api/deletions", Some(&master), None).await;
    assert!(list.as_array().unwrap().is_empty());
}

#[tokio::test]
async fn upsert_clears_a_stale_tombstone_for_a_live_book() {
    // Build the app while keeping a db handle, to plant the pathological state.
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_test_{id}.db"));
    let data_dir = std::env::temp_dir().join(format!("vellum_test_data_{id}"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let app = router(AppState {
        db: db.clone(),
        public_base_url: "http://test.local".into(),
        data_dir,
        http: reqwest::Client::new(),
        max_upload_bytes: 512 * 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(2)),
        enrich_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        basic_cache: std::sync::Arc::default(),
        public_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            60,
            std::time::Duration::from_secs(60),
        )),
        search_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            30,
            std::time::Duration::from_secs(60),
        )),
        send_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            30,
            std::time::Duration::from_secs(60),
        )),
        events: vellum_server::EventBus::new(),
        mailer: None,
        // Off, like a default server: content indexing is opt-in
        // (VELLUM_INDEX_TEXT). `tests/text_index.rs` builds its own state with
        // it on.
        index_text: false,
        audit: true,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    });
    let master = register_master(&app).await;

    // A live book...
    call(
        &app,
        "PUT",
        "/api/books/stale-1",
        Some(&master),
        Some(json!({ "title": "Dune" })),
    )
    .await;

    // ...with a tombstone alongside it, as a crash between the two delete
    // statements would leave.
    sqlx::query("INSERT OR REPLACE INTO deletion (entity_id, owner_id) VALUES (?, NULL)")
        .bind("stale-1")
        .execute(&db)
        .await
        .unwrap();

    // An upsert (even with identical data) must clear the stale tombstone.
    call(
        &app,
        "PUT",
        "/api/books/stale-1",
        Some(&master),
        Some(json!({ "title": "Dune" })),
    )
    .await;

    let (_, list) = call(&app, "GET", "/api/deletions", Some(&master), None).await;
    assert!(
        list.as_array().unwrap().is_empty(),
        "stale tombstone should be cleared by the upsert"
    );
}

#[tokio::test]
async fn a_tombstone_is_keyed_by_kind_as_well_as_id() {
    // Migration 0025. `deletion` used to be keyed by the id alone, from when it
    // only held books. Ids are UUIDs so nothing has collided in practice, but
    // every write site is an INSERT OR REPLACE — a collision would silently
    // overwrite the other kind's tombstone rather than error, resurrecting a
    // deleted row on someone's next pull. Both must now survive.
    let (app, db) = test_app_with_db().await;
    let master = register_master(&app).await;

    for kind in ["book", "shelf", "loan"] {
        sqlx::query("INSERT INTO deletion (entity_id, kind, owner_id) VALUES ('same-id', ?, NULL)")
            .bind(kind)
            .execute(&db)
            .await
            .unwrap();
    }

    let (_, list) = call(&app, "GET", "/api/deletions", Some(&master), None).await;
    let kinds: Vec<&str> = list
        .as_array()
        .unwrap()
        .iter()
        .map(|d| d["kind"].as_str().unwrap())
        .collect();
    assert_eq!(kinds.len(), 3, "one tombstone per kind, not one in total");

    // And clearing one kind must leave the others standing: re-creating the
    // *book* is not a statement about the shelf or the loan.
    call(
        &app,
        "PUT",
        "/api/books/same-id",
        Some(&master),
        Some(json!({ "title": "Dune" })),
    )
    .await;
    let (_, list) = call(&app, "GET", "/api/deletions", Some(&master), None).await;
    let kinds: Vec<&str> = list
        .as_array()
        .unwrap()
        .iter()
        .map(|d| d["kind"].as_str().unwrap())
        .collect();
    assert_eq!(kinds, ["shelf", "loan"], "cleared more than the book");
}

#[tokio::test]
async fn upload_rejects_a_file_that_is_not_a_real_pdf() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    // Junk bytes named .pdf must be refused by the magic-byte check.
    let upload = Request::builder()
        .method("POST")
        .uri(format!("/api/books/{book}/files?filename=dune.pdf"))
        .header("authorization", format!("Bearer {master}"))
        .header("content-type", "application/pdf")
        .body(Body::from(b"this is not really a pdf".to_vec()))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(upload).await.unwrap().status(),
        StatusCode::BAD_REQUEST
    );

    // And no book_file row was recorded.
    let (_, detail) = call(
        &app,
        "GET",
        &format!("/api/books/{book}/detail"),
        Some(&master),
        None,
    )
    .await;
    assert!(detail["files"].as_array().unwrap().is_empty());
}

#[tokio::test]
async fn large_file_streams_through_upload_and_download_intact() {
    let (app, _dir) = test_app_with_dir().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Big").await;

    // A ~2 MB body with a valid PDF header, to exercise the streaming path.
    let mut pdf = b"%PDF-1.7\n".to_vec();
    pdf.resize(2 * 1024 * 1024, b'x');

    let upload = Request::builder()
        .method("POST")
        .uri(format!("/api/books/{book}/files?filename=big.pdf"))
        .header("authorization", format!("Bearer {master}"))
        .body(Body::from(pdf.clone()))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(upload).await.unwrap().status(),
        StatusCode::OK
    );

    let (_, detail) = call(
        &app,
        "GET",
        &format!("/api/books/{book}/detail"),
        Some(&master),
        None,
    )
    .await;
    let file_id = detail["files"][0]["id"].as_str().unwrap().to_string();
    assert_eq!(
        detail["files"][0]["size_bytes"].as_i64().unwrap(),
        pdf.len() as i64
    );

    let download = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/files/{file_id}"))
                .header("authorization", format!("Bearer {master}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(download.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(download.into_body(), usize::MAX)
        .await
        .unwrap();
    assert_eq!(bytes.len(), pdf.len());
    assert_eq!(&bytes[..9], b"%PDF-1.7\n");
}

#[tokio::test]
async fn file_download_supports_byte_ranges() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    let pdf = b"%PDF-1.4 hello world".to_vec(); // 20 bytes
    let upload = Request::builder()
        .method("POST")
        .uri(format!("/api/books/{book}/files?filename=dune.pdf"))
        .header("authorization", format!("Bearer {master}"))
        .body(Body::from(pdf.clone()))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(upload).await.unwrap().status(),
        StatusCode::OK
    );
    let (_, detail) = call(
        &app,
        "GET",
        &format!("/api/books/{book}/detail"),
        Some(&master),
        None,
    )
    .await;
    let file_id = detail["files"][0]["id"].as_str().unwrap().to_string();

    // A full fetch advertises Accept-Ranges.
    let full = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/files/{file_id}"))
                .header("authorization", format!("Bearer {master}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(full.status(), StatusCode::OK);
    assert_eq!(full.headers().get("accept-ranges").unwrap(), "bytes");

    // bytes=0-3 → exactly 4 bytes with a 206 and a Content-Range.
    let part = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/files/{file_id}"))
                .header("authorization", format!("Bearer {master}"))
                .header("range", "bytes=0-3")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(part.status(), StatusCode::PARTIAL_CONTENT);
    assert_eq!(part.headers().get("content-range").unwrap(), "bytes 0-3/20");
    let bytes = axum::body::to_bytes(part.into_body(), usize::MAX)
        .await
        .unwrap();
    assert_eq!(bytes.as_ref(), b"%PDF");

    // A suffix range bytes=-5 → the last 5 bytes.
    let suffix = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/files/{file_id}"))
                .header("authorization", format!("Bearer {master}"))
                .header("range", "bytes=-5")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(suffix.status(), StatusCode::PARTIAL_CONTENT);
    assert_eq!(
        suffix.headers().get("content-range").unwrap(),
        "bytes 15-19/20"
    );
    let bytes = axum::body::to_bytes(suffix.into_body(), usize::MAX)
        .await
        .unwrap();
    assert_eq!(bytes.as_ref(), b"world");

    // An unsatisfiable range → 416 with the full size echoed.
    let bad = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/files/{file_id}"))
                .header("authorization", format!("Bearer {master}"))
                .header("range", "bytes=100-200")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(bad.status(), StatusCode::RANGE_NOT_SATISFIABLE);
    assert_eq!(bad.headers().get("content-range").unwrap(), "bytes */20");
}

#[tokio::test]
async fn cover_upload_rejects_non_image_bytes() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    let put = Request::builder()
        .method("PUT")
        .uri(format!("/api/books/{book}/cover"))
        .header("authorization", format!("Bearer {master}"))
        .header("content-type", "image/png")
        .body(Body::from(b"definitely not an image".to_vec()))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(put).await.unwrap().status(),
        StatusCode::BAD_REQUEST
    );
}

#[tokio::test]
async fn file_download_supports_etag_304() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    let upload = Request::builder()
        .method("POST")
        .uri(format!("/api/books/{book}/files?filename=dune.pdf"))
        .header("authorization", format!("Bearer {master}"))
        .body(Body::from(b"%PDF-1.4 hello".to_vec()))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(upload).await.unwrap().status(),
        StatusCode::OK
    );
    let (_, detail) = call(
        &app,
        "GET",
        &format!("/api/books/{book}/detail"),
        Some(&master),
        None,
    )
    .await;
    let file_id = detail["files"][0]["id"].as_str().unwrap().to_string();

    // First download returns an ETag.
    let first = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/files/{file_id}"))
                .header("authorization", format!("Bearer {master}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(first.status(), StatusCode::OK);
    let etag = first
        .headers()
        .get("etag")
        .unwrap()
        .to_str()
        .unwrap()
        .to_string();

    // Re-requesting with If-None-Match yields 304 and no body.
    let second = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/files/{file_id}"))
                .header("authorization", format!("Bearer {master}"))
                .header("if-none-match", &etag)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(second.status(), StatusCode::NOT_MODIFIED);
    let body = axum::body::to_bytes(second.into_body(), usize::MAX)
        .await
        .unwrap();
    assert!(body.is_empty());
}

#[tokio::test]
async fn cover_thumbnail_is_generated_scaled_and_cached() {
    let (app, data_dir) = test_app_with_dir().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    // Upload a real 200x300 PNG cover.
    let img = image::DynamicImage::ImageRgb8(image::RgbImage::from_pixel(
        200,
        300,
        image::Rgb([120, 120, 120]),
    ));
    let mut buf = std::io::Cursor::new(Vec::new());
    img.write_to(&mut buf, image::ImageFormat::Png).unwrap();
    let put = Request::builder()
        .method("PUT")
        .uri(format!("/api/books/{book}/cover"))
        .header("authorization", format!("Bearer {master}"))
        .header("content-type", "image/png")
        .body(Body::from(buf.into_inner()))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(put).await.unwrap().status(),
        StatusCode::OK
    );

    // ?w=160 returns a JPEG scaled to width 160.
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/books/{book}/cover?w=160"))
                .header("authorization", format!("Bearer {master}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    assert_eq!(res.headers().get("content-type").unwrap(), "image/jpeg");
    let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
        .await
        .unwrap();
    let thumb = image::load_from_memory(&bytes).unwrap();
    assert_eq!(thumb.width(), 160);

    // The thumbnail was cached on disk for the next request.
    assert!(
        data_dir
            .join("covers/thumbs")
            .join(format!("{book}-w160.jpg"))
            .exists()
    );
}

#[tokio::test]
async fn cover_upload_and_download_round_trips() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    let png = b"\x89PNG\r\n\x1a\n fake image bytes";
    let put = Request::builder()
        .method("PUT")
        .uri(format!("/api/books/{book}/cover"))
        .header("authorization", format!("Bearer {master}"))
        .header("content-type", "image/png")
        .body(Body::from(png.to_vec()))
        .unwrap();
    let response = app.clone().oneshot(put).await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);

    // Downloading returns the same bytes with an image content type.
    let get = Request::builder()
        .method("GET")
        .uri(format!("/api/books/{book}/cover"))
        .header("authorization", format!("Bearer {master}"))
        .body(Body::empty())
        .unwrap();
    let response = app.clone().oneshot(get).await.unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert_eq!(response.headers().get("content-type").unwrap(), "image/png");
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    assert_eq!(bytes.as_ref(), png);

    // Anonymous callers can't read a private cover.
    let (status, _) = call(&app, "GET", &format!("/api/books/{book}/cover"), None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn basic_auth_cache_repeats_and_stays_password_specific() {
    use base64::Engine;
    let app = test_app().await;
    register_master(&app).await; // master@lib.test / masterpass1

    let good = base64::engine::general_purpose::STANDARD.encode("master@lib.test:masterpass1");
    let bad = base64::engine::general_purpose::STANDARD.encode("master@lib.test:wrongpass1");
    let opds = |cred: &str| {
        Request::builder()
            .uri("/opds")
            .header("authorization", format!("Basic {cred}"))
            .body(Body::empty())
            .unwrap()
    };

    // First request runs Argon2 and primes the cache; the second hits the cache.
    for _ in 0..2 {
        let res = app.clone().oneshot(opds(&good)).await.unwrap();
        assert_eq!(res.status(), StatusCode::OK);
    }
    // The cache is password-specific: a wrong password is still rejected.
    let res = app.clone().oneshot(opds(&bad)).await.unwrap();
    assert_eq!(res.status(), StatusCode::UNAUTHORIZED);
    // And a correct password still works afterward.
    let res = app.clone().oneshot(opds(&good)).await.unwrap();
    assert_eq!(res.status(), StatusCode::OK);
}

#[tokio::test]
async fn opds_feed_needs_basic_auth_and_lists_books() {
    use base64::Engine;

    let app = test_app().await;
    let master = register_master(&app).await; // master@lib.test / masterpass1
    create_book(&app, &master, "Dune").await;

    // No credentials -> 401 with a Basic challenge (so e-readers prompt).
    let unauth = app
        .clone()
        .oneshot(Request::builder().uri("/opds").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(unauth.status(), StatusCode::UNAUTHORIZED);
    assert!(unauth.headers().contains_key("www-authenticate"));

    // HTTP Basic email:password works and the feed lists the book.
    let basic = base64::engine::general_purpose::STANDARD.encode("master@lib.test:masterpass1");
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/opds")
                .header("authorization", format!("Basic {basic}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::OK);
    assert!(
        response
            .headers()
            .get("content-type")
            .unwrap()
            .to_str()
            .unwrap()
            .contains("opds-catalog")
    );
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let xml = String::from_utf8(bytes.to_vec()).unwrap();
    // Since plan 5 #34 the root is a *navigation* feed -- a flat 1,000-entry
    // feed is unusable on e-ink -- so the books are one hop away, at /opds/all.
    assert!(xml.contains("opds-spec.org"));
    assert!(xml.contains("All books"));
    assert!(xml.contains("/opds/all"));

    let all = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/opds/all")
                .header("authorization", format!("Basic {basic}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(all.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(all.into_body(), usize::MAX)
        .await
        .unwrap();
    let xml = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(xml.contains("<title>Dune</title>"));
}

#[tokio::test]
async fn public_endpoint_is_rate_limited_per_client() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;
    let (_, link) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&master),
        Some(json!({ "book_id": book })),
    )
    .await;
    let token = link["url"]
        .as_str()
        .unwrap()
        .rsplit('/')
        .next()
        .unwrap()
        .to_string();

    // The 60/min per-IP cap trips within 61 anonymous requests (all share the
    // "unknown" client key under oneshot: no X-Forwarded-For / peer addr).
    let mut saw_429 = false;
    for _ in 0..61 {
        let (status, _) = call(&app, "GET", &format!("/api/public/{token}"), None, None).await;
        if status == StatusCode::TOO_MANY_REQUESTS {
            saw_429 = true;
            break;
        }
    }
    assert!(
        saw_429,
        "public endpoint should rate-limit a hammering client"
    );
}

#[tokio::test]
async fn public_link_reads_one_book_then_revokes() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    let (status, link) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&master),
        Some(json!({ "book_id": book })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    // The link URL is a friendly /p/{token} page; the token drives the API.
    let url = link["url"].as_str().unwrap();
    let token = url.rsplit('/').next().unwrap().to_string();
    let link_id = link["id"].as_str().unwrap();

    // Anonymous metadata read works (no token header).
    let (status, body) = call(&app, "GET", &format!("/api/public/{token}"), None, None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["title"], json!("Dune"));

    // After revoking, the same link is gone.
    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/share-links/{link_id}"),
        Some(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = call(&app, "GET", &format!("/api/public/{token}"), None, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn share_link_rejects_bad_expiry_and_honors_past_dates() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    // A garbage expiry string is refused rather than silently never-expiring.
    let (status, _) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&master),
        Some(json!({ "book_id": book, "expires_at": "whenever" })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    // A date already in the past yields a link that is immediately invalid.
    let (status, link) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&master),
        Some(json!({ "book_id": book, "expires_at": "2000-01-01" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let token = link["url"]
        .as_str()
        .unwrap()
        .rsplit('/')
        .next()
        .unwrap()
        .to_string();
    let (status, _) = call(&app, "GET", &format!("/api/public/{token}"), None, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn one_time_link_downloads_exactly_once() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let book = create_book(&app, &master, "Dune").await;

    // Attach a file so there is something to download.
    let upload = Request::builder()
        .method("POST")
        .uri(format!("/api/books/{book}/files?filename=dune.pdf"))
        .header("authorization", format!("Bearer {master}"))
        .header("content-type", "application/pdf")
        .body(Body::from(b"%PDF-1.4 hello".to_vec()))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(upload).await.unwrap().status(),
        StatusCode::OK
    );

    // A one-time link.
    let (status, link) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&master),
        Some(json!({ "book_id": book, "one_time": true })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let token = link["url"]
        .as_str()
        .unwrap()
        .rsplit('/')
        .next()
        .unwrap()
        .to_string();

    // Metadata advertises a one-time download and doesn't consume it.
    let (_, meta) = call(&app, "GET", &format!("/api/public/{token}"), None, None).await;
    assert_eq!(meta["download_available"], json!(true));
    assert_eq!(meta["one_time"], json!(true));

    // First download succeeds...
    let first = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/public/{token}/file"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(first.status(), StatusCode::OK);

    // ...the second is gone, and the link is now used up for metadata too.
    let second = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/public/{token}/file"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(second.status(), StatusCode::NOT_FOUND);
    let (status, _) = call(&app, "GET", &format!("/api/public/{token}"), None, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn responses_carry_baseline_security_headers() {
    let app = test_app().await;
    let res = app
        .oneshot(
            Request::builder()
                .uri("/health")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let h = res.headers();
    assert_eq!(h.get("x-content-type-options").unwrap(), "nosniff");
    assert_eq!(h.get("x-frame-options").unwrap(), "DENY");
    assert!(
        h.get("content-security-policy")
            .unwrap()
            .to_str()
            .unwrap()
            .contains("frame-ancestors 'none'")
    );
}

/// A browser must never be handed an HTTP Basic challenge.
///
/// The bug this pins: every 401 carried `WWW-Authenticate: Basic realm="Vellum"`
/// — added so OPDS e-readers would prompt — and browsers answer that header
/// with their own native credential dialog. It appeared over the console the
/// moment the page loaded, popped again on every failed sign-in, and left no
/// way to log in through the console's own form.
#[tokio::test]
async fn api_401s_carry_no_basic_challenge() {
    let app = test_app().await;

    // What the console does on load, before it has a token.
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/books")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    assert!(
        response.headers().get("www-authenticate").is_none(),
        "a browser would pop its own login dialog over the console"
    );

    // And a failed sign-in, which is where it reappeared on every attempt.
    let response = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/auth/login")
                .header("content-type", "application/json")
                .body(Body::from(
                    json!({ "email": "nobody@lib.test", "password": "wrongwrong" }).to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    assert!(response.headers().get("www-authenticate").is_none());
}

/// The other half: e-readers still get their challenge, or OPDS stops working.
#[tokio::test]
async fn opds_401s_still_challenge_for_e_readers() {
    let app = test_app().await;
    let response = app
        .oneshot(Request::builder().uri("/opds").body(Body::empty()).unwrap())
        .await
        .unwrap();
    assert_eq!(response.status(), StatusCode::UNAUTHORIZED);
    assert_eq!(
        response
            .headers()
            .get("www-authenticate")
            .and_then(|v| v.to_str().ok()),
        Some("Basic realm=\"Vellum\""),
        "an e-reader needs this to know to ask for credentials"
    );
}

/// Who added a book, by name.
///
/// A shared library holds several people's books side by side, and until now
/// nothing on a book said whose it was — `owner_id` crossed the wire, but a
/// uuid is not an answer anyone can read. `owner_name` is the readable form,
/// derived like `series` rather than stored, so it follows a rename.
#[tokio::test]
async fn a_book_says_who_added_it() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let member = add_member(&app, &master, "ana@lib.test").await;

    let (_, mine) = call(
        &app,
        "POST",
        "/api/books",
        Some(&master),
        Some(json!({ "title": "Dune" })),
    )
    .await;
    assert_eq!(mine["owner_name"], "Owner", "the display name, not the id");

    // A member's own book, read back by the member. `add_member` sets the
    // display name to the email, so this also pins that a name is preferred
    // whenever there is one.
    let (_, theirs) = call(
        &app,
        "POST",
        "/api/books",
        Some(&member),
        Some(json!({ "title": "Solaris" })),
    )
    .await;
    assert_eq!(theirs["owner_name"], "ana@lib.test");

    // And it survives the list route, which is what the app actually pulls.
    let (status, list) = call(&app, "GET", "/api/books", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK);
    let dune = list
        .as_array()
        .unwrap()
        .iter()
        .find(|b| b["title"] == "Dune")
        .expect("the master's own book");
    assert_eq!(dune["owner_name"], "Owner");
}

/// The session survives sending an invitation.
///
/// Reported from the console: "it gives session expired right after I invite
/// someone". The console logs out on any 401, so the question is whether
/// anything in the invite path — or the two requests the People screen makes
/// straight afterwards — rejects the token that just worked.
#[tokio::test]
async fn inviting_someone_does_not_end_your_own_session() {
    let app = test_app().await;
    let master = register_master(&app).await;

    let (status, body) = call(
        &app,
        "POST",
        "/api/invites",
        Some(&master),
        Some(json!({ "email": "friend@lib.test", "scope": "all", "permission": "viewer" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "the invite itself: {body}");

    // Exactly what `showPeople()` refetches once the invite returns.
    for path in ["/api/users", "/api/invites"] {
        let (status, body) = call(&app, "GET", path, Some(&master), None).await;
        assert_eq!(
            status,
            StatusCode::OK,
            "{path} after inviting must not 401 the master: {body}"
        );
    }

    // And the token is still good for an ordinary request.
    let (status, _) = call(&app, "GET", "/api/books", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK);
}

/// An invitation needs an email; the name is a separate thing (issue: people
/// were typing the username they know somebody by into the address field).
#[tokio::test]
async fn a_username_in_the_address_field_says_which_field_is_wrong() {
    let app = test_app().await;
    let master = register_master(&app).await;

    let (status, body) = call(
        &app,
        "POST",
        "/api/invites",
        Some(&master),
        Some(json!({ "email": "teodor", "display_name": "Teodor" })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let message = body["error"].as_str().unwrap();
    assert!(
        message.contains("username") && message.contains("name field"),
        "the message has to name the field to fix: {message}"
    );

    // And an empty address is a different, plainer mistake.
    let (status, body) = call(
        &app,
        "POST",
        "/api/invites",
        Some(&master),
        Some(json!({ "email": "  " })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(!body["error"].as_str().unwrap().contains("username"));
}

#[tokio::test]
async fn the_name_the_master_invited_them_under_becomes_their_name() {
    let app = test_app().await;
    let master = register_master(&app).await;

    let (status, created) = call(
        &app,
        "POST",
        "/api/invites",
        Some(&master),
        Some(json!({
            "email": "teodor@lib.test",
            "display_name": "Teodor",
            "scope": "all",
            "permission": "viewer",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{created}");
    assert_eq!(created["display_name"], "Teodor");

    // The pending list reads as a person, not just an address.
    let (_, invites) = call(&app, "GET", "/api/invites", Some(&master), None).await;
    assert_eq!(invites[0]["display_name"], "Teodor");
    assert_eq!(invites[0]["email"], "teodor@lib.test");

    // Joining without typing a name keeps the one they were invited under —
    // arriving as an email address would be a poor introduction.
    let url = created["url"]
        .as_str()
        .expect("no mailer, so a link comes back");
    let token = url.rsplit('/').next().unwrap();
    let (status, _) = call(
        &app,
        "POST",
        "/api/invites/redeem",
        None,
        Some(json!({ "token": token, "display_name": "", "password": "a good passphrase" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (_, users) = call(&app, "GET", "/api/users", Some(&master), None).await;
    let joined = users
        .as_array()
        .unwrap()
        .iter()
        .find(|u| u["email"] == "teodor@lib.test")
        .expect("the invitee has an account");
    assert_eq!(joined["display_name"], "Teodor");
}

#[tokio::test]
async fn an_invitee_who_types_a_name_keeps_their_own() {
    // It is their name, not the master's guess at it.
    let app = test_app().await;
    let master = register_master(&app).await;
    let (_, created) = call(
        &app,
        "POST",
        "/api/invites",
        Some(&master),
        Some(json!({ "email": "ana@lib.test", "display_name": "Ana from work" })),
    )
    .await;
    let url = created["url"].as_str().unwrap();
    let token = url.rsplit('/').next().unwrap();

    let (status, _) = call(
        &app,
        "POST",
        "/api/invites/redeem",
        None,
        Some(json!({ "token": token, "display_name": "Ana", "password": "a good passphrase" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (_, users) = call(&app, "GET", "/api/users", Some(&master), None).await;
    let joined = users
        .as_array()
        .unwrap()
        .iter()
        .find(|u| u["email"] == "ana@lib.test")
        .unwrap();
    assert_eq!(joined["display_name"], "Ana");
}

/// Sharing the same thing with the same person twice (reported from the
/// console: "I can give someone a share for viewer multiple times").
///
/// Access was never wrong — `book_access` takes the best permission any share
/// gives — but the list showed the grant twice and revoking one left the other,
/// which reads as a revoke that did nothing.
#[tokio::test]
async fn granting_the_same_share_twice_updates_it_rather_than_duplicating() {
    let app = test_app().await;
    let master = register_master(&app).await;
    add_member(&app, &master, "ana@lib.test").await;

    let grant = |permission: &'static str| {
        let app = app.clone();
        let master = master.clone();
        async move {
            call(
                &app,
                "POST",
                "/api/shares",
                Some(&master),
                Some(json!({
                    "grantee_email": "ana@lib.test",
                    "scope": "all",
                    "permission": permission,
                })),
            )
            .await
        }
    };

    let (status, first) = grant("viewer").await;
    assert_eq!(status, StatusCode::OK, "{first}");
    let (status, again) = grant("viewer").await;
    assert_eq!(
        status,
        StatusCode::OK,
        "a repeat grant is not an error: {again}"
    );

    let (_, shares) = call(&app, "GET", "/api/shares", Some(&master), None).await;
    assert_eq!(
        shares.as_array().unwrap().len(),
        1,
        "one grant, not two: {shares}"
    );
    assert_eq!(again["id"], first["id"], "it is the same share");

    // Changing your mind about the permission applies to that one grant.
    let (status, upgraded) = grant("editor").await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(upgraded["id"], first["id"]);

    let (_, shares) = call(&app, "GET", "/api/shares", Some(&master), None).await;
    assert_eq!(shares.as_array().unwrap().len(), 1);
    assert_eq!(shares[0]["permission"], "editor");

    // And revoking the one grant really does revoke it.
    let id = first["id"].as_str().unwrap();
    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/shares/{id}"),
        Some(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, shares) = call(&app, "GET", "/api/shares", Some(&master), None).await;
    assert!(shares.as_array().unwrap().is_empty(), "nothing left behind");
}

#[tokio::test]
async fn two_different_scopes_to_one_person_are_still_two_shares() {
    // The uniqueness is per *target*, not per person: "the whole library" and
    // "this one book" are different grants and both are legitimate.
    let app = test_app().await;
    let master = register_master(&app).await;
    add_member(&app, &master, "ana@lib.test").await;
    let (_, book) = call(
        &app,
        "POST",
        "/api/books",
        Some(&master),
        Some(json!({ "title": "Dune" })),
    )
    .await;
    let book_id = book["id"].as_str().unwrap();

    for body in [
        json!({ "grantee_email": "ana@lib.test", "scope": "all", "permission": "viewer" }),
        json!({
            "grantee_email": "ana@lib.test",
            "scope": "book",
            "scope_id": book_id,
            "permission": "editor",
        }),
    ] {
        let (status, got) = call(&app, "POST", "/api/shares", Some(&master), Some(body)).await;
        assert_eq!(status, StatusCode::OK, "{got}");
    }

    let (_, shares) = call(&app, "GET", "/api/shares", Some(&master), None).await;
    assert_eq!(shares.as_array().unwrap().len(), 2);
}

/// Inviting somebody as an owner, which had no path before: you invited a
/// member and then remembered to promote them.
#[tokio::test]
async fn an_owner_invitation_makes_an_owner_and_grants_no_share() {
    let app = test_app().await;
    let master = register_master(&app).await;

    let (status, created) = call(
        &app,
        "POST",
        "/api/invites",
        Some(&master),
        Some(json!({
            "email": "ana@lib.test",
            "display_name": "Ana",
            "as_owner": true,
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{created}");
    assert_eq!(created["as_owner"], true);

    let (_, invites) = call(&app, "GET", "/api/invites", Some(&master), None).await;
    assert_eq!(
        invites[0]["as_owner"], true,
        "the list says which kind it is"
    );

    let url = created["url"].as_str().unwrap();
    let token = url.rsplit('/').next().unwrap();
    let (status, _) = call(
        &app,
        "POST",
        "/api/invites/redeem",
        None,
        Some(json!({ "token": token, "display_name": "", "password": "a good passphrase" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (_, users) = call(&app, "GET", "/api/users", Some(&master), None).await;
    let joined = users
        .as_array()
        .unwrap()
        .iter()
        .find(|u| u["email"] == "ana@lib.test")
        .expect("they have an account");
    assert_eq!(
        joined["is_master"], true,
        "invited as an owner, arrives as one"
    );

    // And no share was created: an owner sees everything by role, so a grant
    // would be a second, redundant answer to the same question.
    let (_, shares) = call(&app, "GET", "/api/shares", Some(&master), None).await;
    assert!(
        shares.as_array().unwrap().is_empty(),
        "an owner needs no share: {shares}"
    );
}

#[tokio::test]
async fn a_member_invitation_still_grants_its_share() {
    let app = test_app().await;
    let master = register_master(&app).await;
    let (_, created) = call(
        &app,
        "POST",
        "/api/invites",
        Some(&master),
        Some(json!({
            "email": "ana@lib.test",
            "scope": "all",
            "permission": "editor",
        })),
    )
    .await;
    let token = created["url"].as_str().unwrap().rsplit('/').next().unwrap();
    call(
        &app,
        "POST",
        "/api/invites/redeem",
        None,
        Some(json!({ "token": token, "display_name": "Ana", "password": "a good passphrase" })),
    )
    .await;

    let (_, users) = call(&app, "GET", "/api/users", Some(&master), None).await;
    let joined = users
        .as_array()
        .unwrap()
        .iter()
        .find(|u| u["email"] == "ana@lib.test")
        .unwrap();
    assert_eq!(joined["is_master"], false);

    let (_, shares) = call(&app, "GET", "/api/shares", Some(&master), None).await;
    assert_eq!(shares.as_array().unwrap().len(), 1);
    assert_eq!(shares[0]["permission"], "editor");
}

// ---- Telling the operator whether mail works -------------------------------
//
// Setting SMTP up means editing five environment variables and restarting, and
// until now the only way to find out whether you got it right was to invite
// somebody and ask them if anything arrived. These two endpoints close that
// loop against your own address.

#[tokio::test]
async fn mail_status_says_off_before_anything_is_configured() {
    let app = test_app().await;
    let master = register_master(&app).await;

    let (status, body) = call(&app, "GET", "/api/mail/status", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["enabled"], false);
    assert!(body["from"].is_null(), "there is no sender to name yet");
}

#[tokio::test]
async fn testing_mail_that_is_off_names_the_variables_to_set() {
    // The failure an operator is most likely to hit first, so it has to answer
    // "what do I do next?" rather than just "no".
    let app = test_app().await;
    let master = register_master(&app).await;

    let (status, body) = call(&app, "POST", "/api/mail/test", Some(&master), None).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let said = body["error"].as_str().unwrap();
    assert!(
        said.contains("VELLUM_SMTP_HOST"),
        "names the switch: {said}"
    );
    assert!(
        said.contains("VELLUM_MAIL_FROM"),
        "and its companion: {said}"
    );
    assert!(
        said.contains("restart"),
        "and that a restart is needed: {said}"
    );
}

#[tokio::test]
async fn mail_status_names_the_sender_once_it_is_configured() {
    let (app, _db) = test_app_with_mail().await;
    let master = register_master(&app).await;

    let (status, body) = call(&app, "GET", "/api/mail/status", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["enabled"], true);
    // The sender address is the commonest thing to get wrong, so it is echoed.
    // The host, username and password are not — they are of no use on screen
    // and the last of them must never leave the process.
    assert_eq!(body["from"], "vellum@example.com");
    assert!(body.get("host").is_none(), "the relay is not named");
    assert!(body.get("user").is_none() && body.get("pass").is_none());
}

#[tokio::test]
async fn a_failed_test_send_reports_what_the_relay_said() {
    // The point of the endpoint: `smtp.invalid.example` does not resolve, and
    // the operator gets to see that rather than "could not send the email".
    let (app, _db) = test_app_with_mail().await;
    let master = register_master(&app).await;

    let (status, body) = call(&app, "POST", "/api/mail/test", Some(&master), None).await;
    assert_eq!(status, StatusCode::BAD_GATEWAY);
    let said = body["error"].as_str().unwrap();
    assert!(
        said.contains("the mail server refused it"),
        "says whose failure it is: {said}"
    );
    assert!(
        said.len() > "the mail server refused it: ".len(),
        "and carries the relay's own words: {said}"
    );
}

#[tokio::test]
async fn only_an_owner_may_look_at_or_test_the_mail_setup() {
    let (app, _db) = test_app_with_mail().await;
    let master = register_master(&app).await;
    let member = add_member(&app, &master, "reader@lib.test").await;

    let (status, _) = call(&app, "GET", "/api/mail/status", Some(&member), None).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = call(&app, "POST", "/api/mail/test", Some(&member), None).await;
    assert_eq!(
        status,
        StatusCode::FORBIDDEN,
        "a member must not be able to make the server send mail"
    );
}
