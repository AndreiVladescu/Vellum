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
        basic_cache: std::sync::Arc::default(),
        public_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            60,
            std::time::Duration::from_secs(60),
        )),
        search_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            30,
            std::time::Duration::from_secs(60),
        )),
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
        basic_cache: std::sync::Arc::default(),
        public_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            60,
            std::time::Duration::from_secs(60),
        )),
        search_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            30,
            std::time::Duration::from_secs(60),
        )),
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
        basic_cache: std::sync::Arc::default(),
        public_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            60,
            std::time::Duration::from_secs(60),
        )),
        search_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            30,
            std::time::Duration::from_secs(60),
        )),
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
    // shelf_sync and copy_sync shipped in plan 5 #4, after this handshake --
    // confirms the list tracks what's actually built rather than staying frozen.
    assert!(features.contains(&json!("shelf_sync")));
    assert!(features.contains(&json!("copy_sync")));
    assert!(features.contains(&json!("loan_sync")));
    // Never advertised: not built (content_search, mail, batch_push) or
    // deliberately never synced (reading_progress) -- a capability handshake
    // that claims one of these would be worse than none.
    for absent in ["reading_progress", "content_search", "mail", "batch_push"] {
        assert!(
            !features.contains(&json!(absent)),
            "{absent} isn't a real server feature yet"
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
        basic_cache: std::sync::Arc::default(),
        public_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            60,
            std::time::Duration::from_secs(60),
        )),
        search_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            30,
            std::time::Duration::from_secs(60),
        )),
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
    sqlx::query("INSERT OR REPLACE INTO deletion (book_id, owner_id) VALUES (?, NULL)")
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
    assert!(xml.contains("<title>Dune</title>"));
    assert!(xml.contains("opds-spec.org"));
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
