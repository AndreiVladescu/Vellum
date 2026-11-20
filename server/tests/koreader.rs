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

// ---- Vellum → KOReader (migration 0045) -------------------------------------

/// A real EPUB whose spine is `c1, nosuch, gone, c3, c4`: `nosuch` names no
/// manifest item (neither KOReader nor the app counts it), and `gone` names a
/// file that is not in the archive — KOReader still makes it `DocFragment[2]`,
/// the app skips it. So the app's chapters 1, 2, 3 are fragments 1, 3, 4. The
/// last is `linear="no"`, which both still count.
fn skipping_epub(seed: &str) -> Vec<u8> {
    use std::io::Write;
    const CONTAINER: &str = "<?xml version=\"1.0\"?>\
        <container xmlns=\"urn:oasis:names:tc:opendocument:xmlns:container\" version=\"1.0\">\
        <rootfiles><rootfile full-path=\"OEBPS/content.opf\" \
        media-type=\"application/oebps-package+xml\"/></rootfiles></container>";
    const OPF: &str = "<?xml version=\"1.0\"?>\
        <package xmlns=\"http://www.idpf.org/2007/opf\" version=\"3.0\">\
        <metadata><dc:title xmlns:dc=\"http://purl.org/dc/elements/1.1/\">Skips</dc:title></metadata>\
        <manifest>\
        <item id=\"c1\" href=\"ch1.xhtml\" media-type=\"application/xhtml+xml\"/>\
        <item id=\"gone\" href=\"missing.xhtml\" media-type=\"application/xhtml+xml\"/>\
        <item id=\"c3\" href=\"text/ch%203.xhtml\" media-type=\"application/xhtml+xml\"/>\
        <item id=\"c4\" href=\"ch4.xhtml\" media-type=\"application/xhtml+xml\"/>\
        </manifest>\
        <spine><itemref idref=\"c1\"/><itemref idref=\"nosuch\"/><itemref idref=\"gone\"/>\
        <itemref idref=\"c3\"/><itemref idref=\"c4\" linear=\"no\"/></spine></package>";
    let chapter = |n: u8| format!("<html><body><p>Chapter {n} of {seed}</p></body></html>");
    let mut zw = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
    for (name, data) in [
        ("mimetype", "application/epub+zip".to_string()),
        ("META-INF/container.xml", CONTAINER.to_string()),
        ("OEBPS/content.opf", OPF.to_string()),
        ("OEBPS/ch1.xhtml", chapter(1)),
        ("OEBPS/text/ch 3.xhtml", chapter(3)),
        ("OEBPS/ch4.xhtml", chapter(4)),
    ] {
        zw.start_file(name, zip::write::SimpleFileOptions::default())
            .unwrap();
        zw.write_all(data.as_bytes()).unwrap();
    }
    zw.finish().unwrap().into_inner()
}

/// `(server time text, unix seconds)` `offset` seconds from now — what the app
/// sends as `updated_at`, and what KOReader is told as `timestamp`.
fn at(offset: i64) -> (String, i64) {
    let t = chrono::Utc::now() + chrono::Duration::seconds(offset);
    (t.format("%Y-%m-%d %H:%M:%S").to_string(), t.timestamp())
}

/// One position the app publishes, as `sync_service.dart` does.
struct Read<'a> {
    device: &'a str,
    page: i64,
    unit: &'a str,
    progress: f64,
    updated_at: &'a str,
}

async fn app_reads(app: &axum::Router, token: &str, book: &str, r: Read<'_>) {
    let (status, body) = api(
        app,
        "PUT",
        &format!("/api/reading-progress/{book}"),
        Some(token),
        Some(json!({
            "device_id": r.device, "device_label": "desktop", "progress": r.progress,
            "page": r.page, "unit": r.unit, "scroll": 0.5, "updated_at": r.updated_at,
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
}

fn chapter_at(page: i64, progress: f64, updated_at: &str) -> Read<'_> {
    Read {
        device: "desk-1",
        page,
        unit: "chapter",
        progress,
        updated_at,
    }
}

async fn pull(app: &axum::Router, key: &str, user: &str, document: &str) -> Value {
    let (status, body) = ko(
        app,
        "GET",
        &format!("/syncs/progress/{document}"),
        Some((user, key)),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body
}

#[tokio::test]
async fn a_newer_vellum_epub_position_goes_to_koreader_as_the_chapter_start() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let book = add_book(&t.app, &master, "Skips").await;
    let epub = skipping_epub("epub-a");
    let document = document_of(&epub);
    upload(&t.app, &master, &book, "epub", epub).await;
    let (_, body) = api(
        &t.app,
        "POST",
        "/api/app-passwords",
        Some(&master),
        Some(json!({ "label": "Kobo", "koreader": true })),
    )
    .await;
    assert_eq!(
        body["koreader_send_position"],
        json!(true),
        "on by default for a new KOReader app password"
    );
    let key = md5_hex(body["password"].as_str().unwrap());

    // Nothing from anyone yet: still the reference server's `{}`, never a 404,
    // which KOReader would report as a network failure.
    assert_eq!(pull(&t.app, &key, MASTER, &document).await, json!({}));

    // chapter → DocFragment: the first, the one after the skipped item, the
    // last, and a stale chapter past the end (clamped, as the app's reader is).
    for (chapter, fragment) in [(1, 1), (2, 3), (3, 4), (9, 4)] {
        let (when, unix) = at(-100 + chapter);
        app_reads(&t.app, &master, &book, chapter_at(chapter, 0.4, &when)).await;
        let got = pull(&t.app, &key, MASTER, &document).await;
        assert_eq!(
            got,
            json!({
                "document": document,
                "progress": format!("/body/DocFragment[{fragment}]"),
                "percentage": 0.4,
                "device": "Vellum on desktop",
                "device_id": "vellum:desk-1",
                "timestamp": unix,
            }),
            "chapter {chapter}"
        );
    }

    // KOReader syncing straight back reports our xpointer; the app reads it as
    // the chapter it came from, not the fragment's number.
    let (status, _) = ko(
        &t.app,
        "PUT",
        "/syncs/progress",
        Some((MASTER, &key)),
        Some(report(&document, "/body/DocFragment[3]", 0.4)),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let rows = positions(&t.app, &master).await;
    let mirrored = rows
        .iter()
        .find(|r| r["device_id"] == json!("koreader:B7C1F00D"))
        .expect("mirrored");
    assert_eq!(
        mirrored["page"],
        json!(2),
        "DocFragment[3] is the app's chapter 2"
    );
    assert_eq!(mirrored["unit"], json!("chapter"));
}

#[tokio::test]
async fn a_newer_vellum_pdf_position_goes_to_koreader_as_its_page() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let book = add_book(&t.app, &master, "Manual").await;
    let pdf = file_bytes("pdf", 11, 20_000);
    let document = document_of(&pdf);
    upload(&t.app, &master, &book, "pdf", pdf).await;
    let (_, secret, _) = mint(&t.app, &master, true).await;
    let key = md5_hex(&secret);

    let (when, unix) = at(0);
    let read = Read {
        device: "desk-1",
        page: 214,
        unit: "page",
        progress: 0.72,
        updated_at: &when,
    };
    app_reads(&t.app, &master, &book, read).await;
    assert_eq!(
        pull(&t.app, &key, MASTER, &document).await,
        json!({
            "document": document,
            "progress": "214",
            "percentage": 0.72,
            "device": "Vellum on desktop",
            "device_id": "vellum:desk-1",
            "timestamp": unix,
        })
    );
}

#[tokio::test]
async fn the_newer_of_koreader_and_vellum_wins_and_koreaders_comes_back_verbatim() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let book = add_book(&t.app, &master, "Skips").await;
    let epub = skipping_epub("epub-b");
    let document = document_of(&epub);
    upload(&t.app, &master, &book, "epub", epub).await;
    let (_, secret, _) = mint(&t.app, &master, true).await;
    let key = md5_hex(&secret);

    // The app read an hour ago; KOReader reports now. KOReader's, verbatim.
    let (an_hour_ago, _) = at(-3600);
    app_reads(&t.app, &master, &book, chapter_at(3, 0.9, &an_hour_ago)).await;
    let xpointer = "/body/DocFragment[3]/body/p[22]/text().17";
    let (_, put) = ko(
        &t.app,
        "PUT",
        "/syncs/progress",
        Some((MASTER, &key)),
        Some(report(&document, xpointer, 0.43)),
    )
    .await;
    let koreader = json!({
        "document": document,
        "progress": xpointer,
        "percentage": 0.43,
        "device": "Kobo Libra 2",
        "device_id": "B7C1F00D",
        "timestamp": put["timestamp"],
    });
    assert_eq!(pull(&t.app, &key, MASTER, &document).await, koreader);

    // The mirrored `koreader:` row is newer than the app's, but it is never
    // sent back dressed as a Vellum position (the GET above was verbatim).
    let rows = positions(&t.app, &master).await;
    assert_eq!(rows.len(), 2, "{rows:?}");

    // Then the app reads on, later than KOReader's report: the app's now.
    let (later, unix) = at(120);
    app_reads(&t.app, &master, &book, chapter_at(1, 0.1, &later)).await;
    let got = pull(&t.app, &key, MASTER, &document).await;
    assert_eq!(got["progress"], json!("/body/DocFragment[1]"));
    assert_eq!(got["timestamp"], json!(unix));

    // A tie goes to KOReader, whose position is the precise one.
    let ko_ts = put["timestamp"].as_i64().unwrap();
    let tie = chrono::DateTime::from_timestamp(ko_ts, 0)
        .unwrap()
        .format("%Y-%m-%d %H:%M:%S")
        .to_string();
    app_reads(&t.app, &master, &book, chapter_at(1, 0.1, &tie)).await;
    assert_eq!(pull(&t.app, &key, MASTER, &document).await, koreader);
}

#[tokio::test]
async fn nothing_safe_to_send_leaves_koreader_with_what_it_had() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let (_, secret, _) = mint(&t.app, &master, true).await;
    let key = md5_hex(&secret);
    let (now, _) = at(0);
    let page_at = |page| Read {
        device: "desk-1",
        page,
        unit: "page",
        progress: 0.3,
        updated_at: &now,
    };

    // A book with a PDF too: the app keeps one `page` per book and calls it a
    // page whenever a PDF is there, so it cannot be trusted for the EPUB.
    let both = add_book(&t.app, &master, "Both").await;
    let pdf = file_bytes("pdf", 5, 9_000);
    let document = document_of(&pdf);
    upload(&t.app, &master, &both, "epub", skipping_epub("epub-c")).await;
    upload(&t.app, &master, &both, "pdf", pdf).await;
    app_reads(&t.app, &master, &both, page_at(2)).await;
    assert_eq!(pull(&t.app, &key, MASTER, &document).await, json!({}));

    // A unit that does not match the file: an EPUB-only book with a `page`.
    let single = add_book(&t.app, &master, "Single").await;
    let epub = skipping_epub("epub-d");
    let document = document_of(&epub);
    upload(&t.app, &master, &single, "epub", epub).await;
    app_reads(&t.app, &master, &single, page_at(2)).await;
    assert_eq!(pull(&t.app, &key, MASTER, &document).await, json!({}));

    // An "EPUB" the server cannot open (no package file): no xpointer is
    // better than a guessed one.
    let broken = add_book(&t.app, &master, "Broken").await;
    let junk = file_bytes("epub", 8, 30_000);
    let document = document_of(&junk);
    upload(&t.app, &master, &broken, "epub", junk).await;
    app_reads(&t.app, &master, &broken, chapter_at(2, 0.3, &now)).await;
    assert_eq!(pull(&t.app, &key, MASTER, &document).await, json!({}));

    // A document no book holds.
    assert_eq!(
        pull(&t.app, &key, MASTER, "0123456789abcdef0123456789abcdef").await,
        json!({})
    );
}

#[tokio::test]
async fn sending_vellums_position_is_per_app_password_and_switchable() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let book = add_book(&t.app, &master, "Skips").await;
    let epub = skipping_epub("epub-e");
    let document = document_of(&epub);
    upload(&t.app, &master, &book, "epub", epub).await;
    let (now, _) = at(0);
    app_reads(&t.app, &master, &book, chapter_at(2, 0.5, &now)).await;

    let (status, made) = api(
        &t.app,
        "POST",
        "/api/app-passwords",
        Some(&master),
        Some(json!({ "label": "Phone", "koreader": true, "koreader_send_position": false })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(made["koreader_send_position"], json!(false));
    let id = made["id"].as_str().unwrap().to_string();
    let key = md5_hex(made["password"].as_str().unwrap());
    // Off: KOReader gets back only what KOReader sent — here, nothing.
    assert_eq!(pull(&t.app, &key, MASTER, &document).await, json!({}));

    let (status, body) = api(
        &t.app,
        "PATCH",
        &format!("/api/app-passwords/{id}"),
        Some(&master),
        Some(json!({ "koreader_send_position": true })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["koreader_send_position"], json!(true));
    assert_eq!(
        pull(&t.app, &key, MASTER, &document).await["progress"],
        json!("/body/DocFragment[3]")
    );

    // Only a KOReader app password has anything to switch, and only its owner
    // can switch it.
    let (opds, _, _) = mint(&t.app, &master, false).await;
    let (status, _) = api(
        &t.app,
        "PATCH",
        &format!("/api/app-passwords/{opds}"),
        Some(&master),
        Some(json!({ "koreader_send_position": true })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (_, list) = api(&t.app, "GET", "/api/app-passwords", Some(&master), None).await;
    let opds_row = list
        .as_array()
        .unwrap()
        .iter()
        .find(|p| p["id"] == json!(opds))
        .unwrap();
    assert_eq!(opds_row["koreader_send_position"], json!(false));
    let member = add_member(&t.app, &master).await;
    let (status, _) = api(
        &t.app,
        "PATCH",
        &format!("/api/app-passwords/{id}"),
        Some(&member),
        Some(json!({ "koreader_send_position": false })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn one_persons_vellum_position_never_reaches_anothers_koreader() {
    let t = test_app().await;
    let master = register_master(&t.app).await;
    let member = add_member(&t.app, &master).await;
    let book = add_book(&t.app, &master, "Shared").await;
    let epub = skipping_epub("epub-f");
    let document = document_of(&epub);
    upload(&t.app, &master, &book, "epub", epub).await;
    // The member can see the book — and so holds the same file — but where
    // the master is in it is still the master's own business.
    let (status, body) = api(
        &t.app,
        "POST",
        "/api/shares",
        Some(&master),
        Some(json!({
            "scope": "book", "scope_id": book,
            "grantee_email": MEMBER, "permission": "viewer",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (_, master_secret, _) = mint(&t.app, &master, true).await;
    let (_, member_secret, _) = mint(&t.app, &member, true).await;
    let master_key = md5_hex(&master_secret);
    let member_key = md5_hex(&member_secret);

    let (now, _) = at(0);
    app_reads(&t.app, &master, &book, chapter_at(3, 0.8, &now)).await;
    assert_eq!(
        pull(&t.app, &member_key, MEMBER, &document).await,
        json!({}),
        "the master's app position is not the member's"
    );
    assert_eq!(
        pull(&t.app, &master_key, MASTER, &document).await["progress"],
        json!("/body/DocFragment[4]")
    );

    // The member's own app position is theirs, in the same book.
    let (later, _) = at(5);
    let read = Read {
        device: "phone-9",
        ..chapter_at(1, 0.05, &later)
    };
    app_reads(&t.app, &member, &book, read).await;
    let got = pull(&t.app, &member_key, MEMBER, &document).await;
    assert_eq!(got["progress"], json!("/body/DocFragment[1]"));
    assert_eq!(got["device_id"], json!("vellum:phone-9"));
    assert_eq!(
        pull(&t.app, &master_key, MASTER, &document).await["device_id"],
        json!("vellum:desk-1"),
        "and it does not reach the master"
    );

    // Unshared, the book is gone from the member's view, and so is its
    // position: their KOReader is told nothing about it.
    let (_, shares) = api(&t.app, "GET", "/api/shares", Some(&master), None).await;
    let share = shares.as_array().unwrap()[0]["id"]
        .as_str()
        .unwrap()
        .to_string();
    let (status, _) = api(
        &t.app,
        "DELETE",
        &format!("/api/shares/{share}"),
        Some(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        pull(&t.app, &member_key, MEMBER, &document).await,
        json!({})
    );
}
