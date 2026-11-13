//! KOReader progress sync (v1.6.3), driven the way KOReader's kosync plugin
//! drives it: `x-auth-user` / `x-auth-key: md5(password)` headers, the
//! `application/vnd.koreader.v1+json` accept type, and documents named by
//! KOReader's partial MD5 of the file.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use md5::{Digest, Md5};
use serde_json::{Value, json};
use tower::ServiceExt;
use vellum_server::{AppState, EventBus, RateLimiter, connect_db, partial_md5, router};

struct TestApp {
    app: axum::Router,
}

async fn test_app() -> TestApp {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_kosync_{id}.db"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let limiter =
        || std::sync::Arc::new(RateLimiter::new(1000, std::time::Duration::from_secs(60)));
    let app = router(AppState {
        db,
        public_base_url: "http://books.test".into(),
        data_dir: std::env::temp_dir().join(format!("vellum_kosync_data_{id}")),
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
        audit: false,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    });
    TestApp { app }
}

const MASTER: &str = "master@lib.test";
const MEMBER: &str = "member@lib.test";
const PASSWORD: &str = "a long enough passphrase";

fn md5_hex(s: &str) -> String {
    hex::encode(Md5::digest(s.as_bytes()))
}

async fn send(app: &axum::Router, request: Request<Body>) -> (StatusCode, Value) {
    let response = app.clone().oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

/// The Vellum API, with a session token.
async fn api(
    app: &axum::Router,
    method: &str,
    uri: &str,
    token: Option<&str>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut b = Request::builder().method(method).uri(uri);
    if let Some(t) = token {
        b = b.header("authorization", format!("Bearer {t}"));
    }
    let req = match body {
        Some(v) => b
            .header("content-type", "application/json")
            .body(Body::from(v.to_string()))
            .unwrap(),
        None => b.body(Body::empty()).unwrap(),
    };
    send(app, req).await
}

/// A fake KOReader: what `KOSyncClient.lua` sends.
async fn ko(
    app: &axum::Router,
    method: &str,
    path: &str,
    creds: Option<(&str, &str)>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut b = Request::builder()
        .method(method)
        .uri(format!("/koreader{path}"))
        .header("accept", "application/vnd.koreader.v1+json");
    if let Some((user, key)) = creds {
        b = b.header("x-auth-user", user).header("x-auth-key", key);
    }
    let req = match body {
        Some(v) => b
            .header("content-type", "application/json")
            .body(Body::from(v.to_string()))
            .unwrap(),
        None => b.body(Body::empty()).unwrap(),
    };
    send(app, req).await
}

async fn register_master(app: &axum::Router) -> String {
    let (status, body) = api(
        app,
        "POST",
        "/api/auth/register",
        None,
        Some(json!({ "email": MASTER, "password": PASSWORD, "display_name": "M" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body["token"].as_str().unwrap().to_string()
}

async fn add_member(app: &axum::Router, master: &str) -> String {
    let (status, _) = api(
        app,
        "POST",
        "/api/users",
        Some(master),
        Some(json!({ "email": MEMBER, "password": PASSWORD, "display_name": "Ana" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, body) = api(
        app,
        "POST",
        "/api/auth/login",
        None,
        Some(json!({ "email": MEMBER, "password": PASSWORD })),
    )
    .await;
    body["token"].as_str().unwrap().to_string()
}

/// Mints an app password; returns (id, secret, koreader flag as reported).
async fn mint(app: &axum::Router, token: &str, koreader: bool) -> (String, String, bool) {
    let (status, body) = api(
        app,
        "POST",
        "/api/app-passwords",
        Some(token),
        Some(json!({ "label": "KOReader on the Kobo", "koreader": koreader })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    (
        body["id"].as_str().unwrap().to_string(),
        body["password"].as_str().unwrap().to_string(),
        body["koreader"].as_bool().unwrap(),
    )
}

/// A file body that passes the upload's magic-byte check, distinct per `seed`.
fn file_bytes(format: &str, seed: u8, len: usize) -> Vec<u8> {
    let mut bytes: Vec<u8> = (0..len)
        .map(|j| ((j * 31 + seed as usize) % 251) as u8)
        .collect();
    let magic: &[u8] = if format == "pdf" {
        b"%PDF-1.4\n"
    } else {
        b"PK\x03\x04"
    };
    bytes[..magic.len()].copy_from_slice(magic);
    bytes
}

async fn add_book(app: &axum::Router, token: &str, title: &str) -> String {
    let (status, book) = api(
        app,
        "POST",
        "/api/books",
        Some(token),
        Some(json!({ "title": title })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    book["id"].as_str().unwrap().to_string()
}

async fn upload(app: &axum::Router, token: &str, book: &str, format: &str, bytes: Vec<u8>) {
    let req = Request::builder()
        .method("POST")
        .uri(format!("/api/books/{book}/files?filename=book.{format}"))
        .header("authorization", format!("Bearer {token}"))
        .body(Body::from(bytes))
        .unwrap();
    let (status, body) = send(app, req).await;
    assert_eq!(status, StatusCode::OK, "{body}");
}

fn document_of(bytes: &[u8]) -> String {
    partial_md5(&mut std::io::Cursor::new(bytes)).unwrap()
}

async fn positions(app: &axum::Router, token: &str) -> Vec<Value> {
    let (status, body) = api(app, "GET", "/api/reading-progress", Some(token), None).await;
    assert_eq!(status, StatusCode::OK);
    body.as_array().unwrap().clone()
}

fn report(document: &str, progress: &str, percentage: f64) -> Value {
    json!({
        "document": document,
        "progress": progress,
        "percentage": percentage,
        "device": "Kobo Libra 2",
        "device_id": "B7C1F00D",
    })
}

#[tokio::test]
async fn a_koreader_round_trip_lands_in_the_reading_position_channel() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let book = add_book(&t.app, &master, "Dune").await;
    let epub = file_bytes("epub", 3, 50_000);
    let document = document_of(&epub);
    upload(&t.app, &master, &book, "epub", epub).await;
    let (_, secret, flagged) = mint(&t.app, &master, true).await;
    assert!(flagged);
    let creds = (MASTER, md5_hex(&secret));
    let creds = Some((creds.0, creds.1.as_str()));

    let (status, body) = ko(&t.app, "GET", "/healthcheck", None, None).await;
    assert_eq!((status, body), (StatusCode::OK, json!({ "state": "OK" })));
    let (status, body) = ko(&t.app, "GET", "/users/auth", creds, None).await;
    assert_eq!(
        (status, body),
        (StatusCode::OK, json!({ "authorized": "OK" }))
    );

    // Nothing yet: the reference server's empty object.
    let (status, body) = ko(
        &t.app,
        "GET",
        &format!("/syncs/progress/{document}"),
        creds,
        None,
    )
    .await;
    assert_eq!((status, body), (StatusCode::OK, json!({})));

    let xpointer = "/body/DocFragment[3]/body/div/p[22]/text().17";
    let (status, put) = ko(
        &t.app,
        "PUT",
        "/syncs/progress",
        creds,
        Some(report(&document, xpointer, 0.43)),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{put}");
    assert_eq!(put["document"], json!(document));
    let timestamp = put["timestamp"].as_i64().expect("unix seconds");

    // Handed back verbatim, as KOReader expects.
    let (status, got) = ko(
        &t.app,
        "GET",
        &format!("/syncs/progress/{document}"),
        creds,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        got,
        json!({
            "document": document,
            "progress": xpointer,
            "percentage": 0.43,
            "device": "Kobo Libra 2",
            "device_id": "B7C1F00D",
            "timestamp": timestamp,
        })
    );

    // And the app sees it as another device.
    let rows = positions(&t.app, &master).await;
    assert_eq!(rows.len(), 1, "{rows:?}");
    let row = &rows[0];
    assert_eq!(row["book_id"], json!(book));
    assert_eq!(row["device_id"], json!("koreader:B7C1F00D"));
    assert_eq!(row["device_label"], json!("KOReader on Kobo Libra 2"));
    assert_eq!(row["progress"], json!(0.43));
    assert_eq!(row["page"], json!(3));
    assert_eq!(row["unit"], json!("chapter"));

    // A later page turn replaces this device's row rather than adding one.
    let (status, _) = ko(
        &t.app,
        "PUT",
        "/syncs/progress",
        creds,
        Some(report(
            &document,
            "/body/DocFragment[5]/body/p[1]/text().0",
            0.61,
        )),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let rows = positions(&t.app, &master).await;
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["page"], json!(5));
    assert_eq!(rows[0]["progress"], json!(0.61));
}

#[tokio::test]
async fn a_pdf_reports_its_page() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let book = add_book(&t.app, &master, "Manual").await;
    let pdf = file_bytes("pdf", 9, 20_000);
    let document = document_of(&pdf);
    upload(&t.app, &master, &book, "pdf", pdf).await;
    let (_, secret, _) = mint(&t.app, &master, true).await;
    let key = md5_hex(&secret);

    // Some kosync clients send the page as a number rather than a string.
    let (status, _) = ko(
        &t.app,
        "PUT",
        "/syncs/progress",
        Some((MASTER, &key)),
        Some(json!({
            "document": document, "progress": 214, "percentage": 0.72,
            "device": "PocketBook", "device_id": "PB1",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let rows = positions(&t.app, &master).await;
    assert_eq!(rows[0]["page"], json!(214));
    assert_eq!(rows[0]["unit"], json!("page"));
    let (_, got) = ko(
        &t.app,
        "GET",
        &format!("/syncs/progress/{document}"),
        Some((MASTER, &key)),
        None,
    )
    .await;
    assert_eq!(got["progress"], json!("214"));
}

#[tokio::test]
async fn only_a_koreader_app_password_opens_kosync() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let (id, secret, _) = mint(&t.app, &master, true).await;
    let (_, opds_only, flagged) = mint(&t.app, &master, false).await;
    assert!(!flagged);
    let app = &t.app;
    let auth = |user: &'static str, key: String| async move {
        ko(app, "GET", "/users/auth", Some((user, &key)), None).await
    };

    // The spellings a person types: as shown, without dashes, in capitals.
    for typed in [
        secret.clone(),
        secret.replace('-', ""),
        secret.to_uppercase(),
        secret.replace('-', " "),
    ] {
        let (status, _) = auth(MASTER, md5_hex(&typed)).await;
        assert_eq!(status, StatusCode::OK, "{typed}");
    }
    // The MD5 in capitals is the same key.
    let (status, _) = auth(MASTER, md5_hex(&secret).to_uppercase()).await;
    assert_eq!(status, StatusCode::OK);

    for (why, user, key) in [
        ("wrong key", MASTER, md5_hex("not the secret")),
        ("the account password", MASTER, md5_hex(PASSWORD)),
        ("an OPDS-only app password", MASTER, md5_hex(&opds_only)),
        ("the secret itself, unhashed", MASTER, secret.clone()),
        ("someone else's email", "nobody@lib.test", md5_hex(&secret)),
    ] {
        let (status, body) = auth(user, key).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{why}");
        assert_eq!(body["code"], json!(2001), "{why}");
    }
    let (status, body) = ko(&t.app, "GET", "/users/auth", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert_eq!(body["code"], json!(2001));

    // Registration from the device is refused, in the protocol's terms.
    let (status, body) = ko(
        &t.app,
        "POST",
        "/users/create",
        None,
        Some(json!({ "username": "x@lib.test", "password": md5_hex("pw") })),
    )
    .await;
    assert_eq!(status, StatusCode::PAYMENT_REQUIRED);
    assert_eq!(body["code"], json!(2005));

    // The list says which ones sync.
    let (_, list) = api(&t.app, "GET", "/api/app-passwords", Some(&master), None).await;
    let flags: Vec<bool> = list
        .as_array()
        .unwrap()
        .iter()
        .map(|p| p["koreader"].as_bool().unwrap())
        .collect();
    assert_eq!(flags.iter().filter(|f| **f).count(), 1);

    // Revoking it shuts KOReader out on the next request.
    let (status, _) = api(
        &t.app,
        "DELETE",
        &format!("/api/app-passwords/{id}"),
        Some(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = auth(MASTER, md5_hex(&secret)).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn a_document_nothing_matches_is_kept_and_linked_by_a_later_upload() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let (_, secret, _) = mint(&t.app, &master, true).await;
    let key = md5_hex(&secret);
    let creds = Some((MASTER, key.as_str()));

    let epub = file_bytes("epub", 42, 30_000);
    let document = document_of(&epub);
    let (status, _) = ko(
        &t.app,
        "PUT",
        "/syncs/progress",
        creds,
        Some(report(&document, "/body/DocFragment[7]/body/p[2]", 0.25)),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::OK,
        "an unknown document is still recorded"
    );
    let (_, got) = ko(
        &t.app,
        "GET",
        &format!("/syncs/progress/{document}"),
        creds,
        None,
    )
    .await;
    assert_eq!(got["percentage"], json!(0.25));
    assert!(
        positions(&t.app, &master).await.is_empty(),
        "no book to show it on yet"
    );

    // The book is imported afterwards: the upload's digest links it.
    let book = add_book(&t.app, &master, "Later").await;
    upload(&t.app, &master, &book, "epub", epub).await;
    let mut rows = Vec::new();
    for _ in 0..100 {
        rows = positions(&t.app, &master).await;
        if !rows.is_empty() {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(50)).await;
    }
    assert_eq!(rows.len(), 1, "linked after the upload");
    assert_eq!(rows[0]["book_id"], json!(book));
    assert_eq!(rows[0]["page"], json!(7));
}

#[tokio::test]
async fn one_persons_koreader_progress_is_invisible_to_another() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let member = add_member(&t.app, &master).await;
    // The master's book, not shared with the member.
    let book = add_book(&t.app, &master, "Private").await;
    let epub = file_bytes("epub", 77, 40_000);
    let document = document_of(&epub);
    upload(&t.app, &master, &book, "epub", epub).await;

    let (_, master_secret, _) = mint(&t.app, &master, true).await;
    let (_, member_secret, _) = mint(&t.app, &member, true).await;
    let master_key = md5_hex(&master_secret);
    let member_key = md5_hex(&member_secret);

    let (status, _) = ko(
        &t.app,
        "PUT",
        "/syncs/progress",
        Some((MASTER, &master_key)),
        Some(report(&document, "/body/DocFragment[2]", 0.5)),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // A key only works with its own owner's email.
    let (status, _) = ko(
        &t.app,
        "GET",
        "/users/auth",
        Some((MEMBER, &master_key)),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    // The member, holding the same file on their e-reader, sees nothing of it.
    let (_, got) = ko(
        &t.app,
        "GET",
        &format!("/syncs/progress/{document}"),
        Some((MEMBER, &member_key)),
        None,
    )
    .await;
    assert_eq!(got, json!({}));

    // Their own report is theirs alone, and is not attached to a book they
    // cannot see.
    let (status, _) = ko(
        &t.app,
        "PUT",
        "/syncs/progress",
        Some((MEMBER, &member_key)),
        Some(report(&document, "/body/DocFragment[9]", 0.9)),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(positions(&t.app, &member).await.is_empty());
    let (_, mine) = ko(
        &t.app,
        "GET",
        &format!("/syncs/progress/{document}"),
        Some((MASTER, &master_key)),
        None,
    )
    .await;
    assert_eq!(
        mine["percentage"],
        json!(0.5),
        "the master's own is untouched"
    );
    let rows = positions(&t.app, &master).await;
    assert_eq!(rows.len(), 1);
    assert_eq!(rows[0]["progress"], json!(0.5));

    // Forgetting takes it all back off the server.
    let (status, body) = api(&t.app, "DELETE", "/api/mine/koreader", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert!(positions(&t.app, &master).await.is_empty());
    let (_, got) = ko(
        &t.app,
        "GET",
        &format!("/syncs/progress/{document}"),
        Some((MASTER, &master_key)),
        None,
    )
    .await;
    assert_eq!(got, json!({}));
}

#[tokio::test]
async fn malformed_reports_answer_in_the_protocols_error_shape() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let (_, secret, _) = mint(&t.app, &master, true).await;
    let key = md5_hex(&secret);
    let creds = Some((MASTER, key.as_str()));
    for (body, code) in [
        (
            json!({ "progress": "1", "percentage": 0.1, "device": "x" }),
            2004,
        ),
        (
            json!({ "document": "a/b", "progress": "1", "percentage": 0.1, "device": "x" }),
            2007,
        ),
        (
            json!({ "document": "abc", "percentage": 0.1, "device": "x" }),
            2003,
        ),
    ] {
        let (status, got) = ko(&t.app, "PUT", "/syncs/progress", creds, Some(body)).await;
        assert_eq!(status, StatusCode::FORBIDDEN);
        assert_eq!(got["code"], json!(code));
    }
}
