//! `GET /api/admin/config`: the settings in effect, for the console's Server
//! page. The point of the tests is the negative half — a secret in the
//! environment must never reach the response.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{Value, json};
use tower::ServiceExt;
use vellum_server::{AppState, connect_db, router};

const SECRETS: [(&str, &str); 4] = [
    ("VELLUM_SMTP_PASS", "smtp-pass-s3cret-7731"),
    ("VELLUM_SMTP_USER", "smtp-user-s3cret-7732"),
    ("VELLUM_BOOTSTRAP_TOKEN", "bootstrap-s3cret-7733"),
    ("VELLUM_TLS_KEY", "/keys/tls-key-s3cret-7734.pem"),
];

/// Puts the secrets in the process environment, once, before anything reads the
/// bootstrap token (it is cached on first use).
fn set_secrets() {
    static ONCE: std::sync::Once = std::sync::Once::new();
    ONCE.call_once(|| {
        for (k, v) in SECRETS {
            // SAFETY: runs once, before any request in this test binary starts;
            // no other thread is reading the environment yet.
            unsafe { std::env::set_var(k, v) };
        }
    });
}

async fn test_app() -> axum::Router {
    set_secrets();
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_cfg_{id}.db"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    router(AppState {
        db,
        public_base_url: "http://test.local".into(),
        data_dir: std::env::temp_dir().join(format!("vellum_cfg_data_{id}")),
        http: reqwest::Client::new(),
        max_upload_bytes: 64 * 1024 * 1024,
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
        mailer: None,
        index_text: true,
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
    body: Option<Value>,
) -> (StatusCode, String) {
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
    (status, String::from_utf8_lossy(&bytes).into_owned())
}

async fn master(app: &axum::Router) -> String {
    let (status, body) = call(
        app,
        "POST",
        "/api/auth/register",
        None,
        Some(json!({
            "email": "master@lib.test",
            "display_name": "Owner",
            "password": "masterpass1",
            "bootstrap_token": "bootstrap-s3cret-7733",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "register failed: {body}");
    serde_json::from_str::<Value>(&body).unwrap()["token"]
        .as_str()
        .unwrap()
        .to_string()
}

async fn member(app: &axum::Router, master: &str) -> String {
    let (status, body) = call(
        app,
        "POST",
        "/api/users",
        Some(master),
        Some(json!({ "email": "m@lib.test", "display_name": "M", "password": "memberpass1" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (_, body) = call(
        app,
        "POST",
        "/api/auth/login",
        None,
        Some(json!({ "email": "m@lib.test", "password": "memberpass1" })),
    )
    .await;
    serde_json::from_str::<Value>(&body).unwrap()["token"]
        .as_str()
        .unwrap()
        .to_string()
}

#[tokio::test]
async fn the_owner_reads_the_settings_in_effect() {
    let app = test_app().await;
    let token = master(&app).await;
    let (status, body) = call(&app, "GET", "/api/admin/config", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let v: Value = serde_json::from_str(&body).unwrap();
    assert_eq!(v["public_url"], json!("http://test.local"));
    assert_eq!(v["max_upload_mb"], json!(64));
    assert_eq!(v["tls"], json!(false));
    assert_eq!(v["mail"], json!(false));
    assert_eq!(v["text_indexing"], json!(true));
    assert_eq!(v["audit_log"], json!(false));
    assert_eq!(v["bootstrap_token"], json!(true), "set in the environment");
    assert!(v["port"].is_number());
    assert!(v["data_dir"].is_string());
}

#[tokio::test]
async fn the_response_has_exactly_the_allowlisted_keys() {
    let app = test_app().await;
    let token = master(&app).await;
    let (_, body) = call(&app, "GET", "/api/admin/config", Some(&token), None).await;
    let v: Value = serde_json::from_str(&body).unwrap();
    let mut keys: Vec<&str> = v.as_object().unwrap().keys().map(|k| k.as_str()).collect();
    keys.sort();
    assert_eq!(
        keys,
        [
            "audit_log",
            "backup",
            "bootstrap_token",
            "data_dir",
            "database_path",
            "mail",
            "max_upload_mb",
            "port",
            "public_url",
            "text_indexing",
            "tls",
        ]
    );
}

#[tokio::test]
async fn no_secret_from_the_environment_appears_in_the_response() {
    let app = test_app().await;
    let token = master(&app).await;
    let (_, body) = call(&app, "GET", "/api/admin/config", Some(&token), None).await;
    for (name, value) in SECRETS {
        assert!(!body.contains(value), "{name}'s value leaked: {body}");
    }
}

#[tokio::test]
async fn a_member_is_refused_and_a_stranger_is_unauthorised() {
    let app = test_app().await;
    let token = master(&app).await;
    let m = member(&app, &token).await;
    let (status, _) = call(&app, "GET", "/api/admin/config", Some(&m), None).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = call(&app, "GET", "/api/admin/config", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}
