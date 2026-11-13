//! App passwords (v1.6.2): per-device secrets for OPDS e-readers.
//!
//! What matters is the boundary, so most of this is about where an app
//! password is *refused*: everything but the OPDS feeds and the cover/file GETs
//! they link to — admin endpoints, writes, and above all the endpoints that
//! manage app passwords, so a leaked one cannot mint itself a successor.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use base64::Engine;
use serde_json::{Value, json};
use tower::ServiceExt;
use vellum_server::{AppState, EventBus, RateLimiter, connect_db, router};

struct TestApp {
    app: axum::Router,
    db: sqlx::SqlitePool,
}

async fn test_app() -> TestApp {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_apppw_{id}.db"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let limiter =
        || std::sync::Arc::new(RateLimiter::new(1000, std::time::Duration::from_secs(60)));
    let app = router(AppState {
        db: db.clone(),
        public_base_url: "http://books.test".into(),
        data_dir: std::env::temp_dir().join(format!("vellum_apppw_data_{id}")),
        http: reqwest::Client::new(),
        max_upload_bytes: 8 * 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        enrich_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        basic_cache: std::sync::Arc::default(),
        public_limiter: limiter(),
        search_limiter: limiter(),
        send_limiter: limiter(),
        events: EventBus::new(),
        mailer: None,
        index_text: false,
        audit: true,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    });
    TestApp { app, db }
}

const MASTER: &str = "master@lib.test";
const MEMBER: &str = "member@lib.test";
const PASSWORD: &str = "a long enough passphrase";

enum Auth<'a> {
    None,
    Bearer(&'a str),
    Basic(&'a str, &'a str),
}

async fn call(
    app: &axum::Router,
    method: &str,
    uri: &str,
    auth: Auth<'_>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut builder = Request::builder().method(method).uri(uri);
    match auth {
        Auth::None => {}
        Auth::Bearer(t) => builder = builder.header("authorization", format!("Bearer {t}")),
        Auth::Basic(user, pw) => {
            let encoded = base64::engine::general_purpose::STANDARD.encode(format!("{user}:{pw}"));
            builder = builder.header("authorization", format!("Basic {encoded}"));
        }
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
    let value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, value)
}

async fn register_master(app: &axum::Router) -> String {
    let (status, body) = call(
        app,
        "POST",
        "/api/auth/register",
        Auth::None,
        Some(json!({ "email": MASTER, "password": PASSWORD, "display_name": "M" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "register: {body}");
    body["token"].as_str().unwrap().to_string()
}

async fn add_member(app: &axum::Router, master: &str) -> String {
    let (status, _) = call(
        app,
        "POST",
        "/api/users",
        Auth::Bearer(master),
        Some(json!({ "email": MEMBER, "password": PASSWORD, "display_name": "Ana" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, body) = call(
        app,
        "POST",
        "/api/auth/login",
        Auth::None,
        Some(json!({ "email": MEMBER, "password": PASSWORD })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    body["token"].as_str().unwrap().to_string()
}

/// Mints one and returns (id, secret).
async fn mint(app: &axum::Router, token: &str, label: &str) -> (String, String) {
    let (status, body) = call(
        app,
        "POST",
        "/api/app-passwords",
        Auth::Bearer(token),
        Some(json!({ "label": label })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    (
        body["id"].as_str().unwrap().to_string(),
        body["password"].as_str().unwrap().to_string(),
    )
}

async fn add_book_with_file(app: &axum::Router, token: &str) -> (String, String) {
    let (status, book) = call(
        app,
        "POST",
        "/api/books",
        Auth::Bearer(token),
        Some(json!({ "title": "Dune" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let book = book["id"].as_str().unwrap().to_string();
    let upload = Request::builder()
        .method("POST")
        .uri(format!("/api/books/{book}/files?filename=dune.pdf"))
        .header("authorization", format!("Bearer {token}"))
        .header("content-type", "application/pdf")
        .body(Body::from(b"%PDF-1.4 hello".to_vec()))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(upload).await.unwrap().status(),
        StatusCode::OK
    );
    let (_, detail) = call(
        app,
        "GET",
        &format!("/api/books/{book}/detail"),
        Auth::Bearer(token),
        None,
    )
    .await;
    let file = detail["files"][0]["id"].as_str().unwrap().to_string();
    (book, file)
}

#[tokio::test]
async fn an_app_password_opens_the_catalogue_covers_and_downloads() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let (book, file) = add_book_with_file(&t.app, &master).await;
    let (_, secret) = mint(&t.app, &master, "Kobo").await;

    for uri in ["/opds", "/opds/all", "/opds/recent", "/opds/v2"] {
        let (status, _) = call(&t.app, "GET", uri, Auth::Basic(MASTER, &secret), None).await;
        assert_eq!(status, StatusCode::OK, "{uri}");
    }
    let (status, _) = call(
        &t.app,
        "GET",
        &format!("/api/files/{file}"),
        Auth::Basic(MASTER, &secret),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "the acquisition link downloads");
    // Under the versioned prefix too: it is the same route table.
    let (status, _) = call(
        &t.app,
        "GET",
        &format!("/api/v1/files/{file}"),
        Auth::Basic(MASTER, &secret),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    // No cover was ever uploaded: a 404 is the cover route *answering*, which
    // is what matters here — not a 401 or a 403.
    let (status, _) = call(
        &t.app,
        "GET",
        &format!("/api/books/{book}/cover"),
        Auth::Basic(MASTER, &secret),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn the_account_password_still_works_on_the_catalogue() {
    // E-readers configured before app passwords existed must keep working.
    let t = test_app().await;
    let _ = register_master(&t.app).await;
    let (status, _) = call(&t.app, "GET", "/opds", Auth::Basic(MASTER, PASSWORD), None).await;
    assert_eq!(status, StatusCode::OK);
}

#[tokio::test]
async fn an_app_password_is_refused_everywhere_else() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let (book, _) = add_book_with_file(&t.app, &master).await;
    let (id, secret) = mint(&t.app, &master, "Kindle").await;
    let pw = || Auth::Basic(MASTER, &secret);

    let refused: &[(&str, String, Option<Value>)] = &[
        // Administration.
        ("GET", "/api/admin/stats".into(), None),
        ("GET", "/api/admin/config".into(), None),
        ("GET", "/api/admin/snapshot".into(), None),
        ("GET", "/api/admin/audit".into(), None),
        ("POST", "/api/admin/sweep".into(), None),
        ("GET", "/api/users".into(), None),
        (
            "POST",
            "/api/users".into(),
            Some(json!({ "email": "x@lib.test", "password": PASSWORD, "display_name": "X" })),
        ),
        // Managing app passwords — including revoking itself.
        ("GET", "/api/app-passwords".into(), None),
        (
            "POST",
            "/api/app-passwords".into(),
            Some(json!({ "label": "another" })),
        ),
        ("DELETE", format!("/api/app-passwords/{id}"), None),
        // The library beyond the catalogue, reads and writes alike.
        ("GET", "/api/books".into(), None),
        ("GET", "/api/auth/me".into(), None),
        ("GET", "/api/shares".into(), None),
        (
            "PATCH",
            format!("/api/books/{book}"),
            Some(json!({ "title": "x" })),
        ),
        ("DELETE", format!("/api/books/{book}"), None),
        ("PUT", format!("/api/books/{book}/cover"), None),
    ];
    for (method, uri, body) in refused {
        let (status, _) = call(&t.app, method, uri, pw(), body.clone()).await;
        assert_eq!(status, StatusCode::FORBIDDEN, "{method} {uri}");
    }

    // None of that counted as a failed login: the owner is not locked out of
    // their own catalogue by a misconfigured device.
    let (status, _) = call(&t.app, "GET", "/opds", pw(), None).await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = call(&t.app, "GET", "/opds", Auth::Basic(MASTER, PASSWORD), None).await;
    assert_eq!(status, StatusCode::OK);

    // And nothing changed.
    let (_, list) = call(
        &t.app,
        "GET",
        "/api/app-passwords",
        Auth::Bearer(&master),
        None,
    )
    .await;
    assert_eq!(list.as_array().unwrap().len(), 1);
    let (_, users) = call(&t.app, "GET", "/api/users", Auth::Bearer(&master), None).await;
    assert_eq!(users.as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn the_list_never_shows_a_secret_and_records_use() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let (status, created) = call(
        &t.app,
        "POST",
        "/api/app-passwords",
        Auth::Bearer(&master),
        Some(json!({ "label": "  KOReader  " })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let secret = created["password"].as_str().unwrap().to_string();
    assert_eq!(created["label"], json!("KOReader"), "trimmed");
    assert_eq!(created["prefix"], json!(&secret[..4]));
    assert!(created["last_used_at"].is_null());
    assert_eq!(secret.len(), 29, "six groups of four: {secret}");

    let (status, list) = call(
        &t.app,
        "GET",
        "/api/app-passwords",
        Auth::Bearer(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let text = list.to_string();
    assert!(
        !text.contains(&secret),
        "the list must never carry the secret"
    );
    assert!(!text.contains(&secret.replace('-', "")));
    assert!(list[0].get("password").is_none());
    assert!(list[0]["last_used_at"].is_null());

    // Nor does the database.
    let stored: String = sqlx::query_scalar("SELECT secret_hash FROM app_password")
        .fetch_one(&t.db)
        .await
        .unwrap();
    assert!(!stored.contains(&secret.replace('-', "")));
    assert_eq!(
        stored,
        vellum_server::sha256_hex_for_tests(&secret.replace('-', ""))
    );

    // Typed sloppily on an e-reader keyboard, it is still the same secret.
    let sloppy = secret.to_uppercase().replace('-', " ");
    let (status, _) = call(&t.app, "GET", "/opds", Auth::Basic(MASTER, &sloppy), None).await;
    assert_eq!(status, StatusCode::OK);

    let (_, list) = call(
        &t.app,
        "GET",
        "/api/app-passwords",
        Auth::Bearer(&master),
        None,
    )
    .await;
    assert!(list[0]["last_used_at"].is_string(), "{list}");

    // Blank names are refused.
    let (status, _) = call(
        &t.app,
        "POST",
        "/api/app-passwords",
        Auth::Bearer(&master),
        Some(json!({ "label": "   " })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn revoking_takes_effect_on_the_next_request() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let (id, secret) = mint(&t.app, &master, "Kobo").await;
    let (_, other) = mint(&t.app, &master, "Tablet").await;

    let (status, _) = call(&t.app, "GET", "/opds", Auth::Basic(MASTER, &secret), None).await;
    assert_eq!(status, StatusCode::OK);

    let (status, _) = call(
        &t.app,
        "DELETE",
        &format!("/api/app-passwords/{id}"),
        Auth::Bearer(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (status, _) = call(&t.app, "GET", "/opds", Auth::Basic(MASTER, &secret), None).await;
    assert_eq!(
        status,
        StatusCode::UNAUTHORIZED,
        "revoked means refused, now"
    );
    // The other device is untouched.
    let (status, _) = call(&t.app, "GET", "/opds", Auth::Basic(MASTER, &other), None).await;
    assert_eq!(status, StatusCode::OK);

    let (status, _) = call(
        &t.app,
        "DELETE",
        &format!("/api/app-passwords/{id}"),
        Auth::Bearer(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "already gone");
}

#[tokio::test]
async fn app_passwords_belong_to_one_account() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let member = add_member(&t.app, &master).await;
    let (id, secret) = mint(&t.app, &master, "Kobo").await;

    // Someone else's email with my secret is not a login.
    let (status, _) = call(&t.app, "GET", "/opds", Auth::Basic(MEMBER, &secret), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    // A member can neither see nor revoke the master's — not even the owner of
    // the server can be revoked by another account.
    let (_, list) = call(
        &t.app,
        "GET",
        "/api/app-passwords",
        Auth::Bearer(&member),
        None,
    )
    .await;
    assert!(list.as_array().unwrap().is_empty());
    let (status, _) = call(
        &t.app,
        "DELETE",
        &format!("/api/app-passwords/{id}"),
        Auth::Bearer(&member),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = call(&t.app, "GET", "/opds", Auth::Basic(MASTER, &secret), None).await;
    assert_eq!(status, StatusCode::OK, "still works");

    // A member's own app password reads as that member — what *they* can see.
    let (_, mine) = mint(&t.app, &member, "Kindle").await;
    let (status, _) = call(&t.app, "GET", "/opds/all", Auth::Basic(MEMBER, &mine), None).await;
    assert_eq!(status, StatusCode::OK);

    // Removing the account takes its devices with it.
    let (_, users) = call(&t.app, "GET", "/api/users", Auth::Bearer(&master), None).await;
    let member_id = users
        .as_array()
        .unwrap()
        .iter()
        .find(|u| u["email"] == json!(MEMBER))
        .unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();
    let (status, _) = call(
        &t.app,
        "DELETE",
        &format!("/api/users/{member_id}"),
        Auth::Bearer(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let left: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM app_password WHERE user_id = ?")
        .bind(&member_id)
        .fetch_one(&t.db)
        .await
        .unwrap();
    assert_eq!(left, 0);
}

#[tokio::test]
async fn a_password_reset_revokes_every_app_password() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let (_, secret) = mint(&t.app, &master, "Kobo").await;

    let user_id: String = sqlx::query_scalar("SELECT id FROM app_user WHERE email = ?")
        .bind(MASTER)
        .fetch_one(&t.db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO password_reset (token_hash, user_id, expires_at) \
         VALUES (?, ?, datetime('now', '+1 hour'))",
    )
    .bind(vellum_server::sha256_hex_for_tests("reset-token"))
    .bind(&user_id)
    .execute(&t.db)
    .await
    .unwrap();
    let (status, _) = call(
        &t.app,
        "POST",
        "/api/auth/reset",
        Auth::None,
        Some(json!({ "token": "reset-token", "password": "another long passphrase" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (status, _) = call(&t.app, "GET", "/opds", Auth::Basic(MASTER, &secret), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn the_server_advertises_app_passwords() {
    let t = test_app().await;
    let (_, caps) = call(&t.app, "GET", "/api/capabilities", Auth::None, None).await;
    assert!(
        caps["features"]
            .as_array()
            .unwrap()
            .contains(&json!("app_passwords"))
    );
}
