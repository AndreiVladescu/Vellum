//! Audiobooks on the server (migration 0043, docs/AUDIOBOOKS.md §3–§4):
//! audio uploads with their part fields, audio kept from pre-1.5 clients, and
//! the audio position on the reading-progress channel.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;
use vellum_server::{AppState, EventBus, RateLimiter, connect_db, router};

async fn app() -> axum::Router {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_audio_{id}.db"));
    let data_dir = std::env::temp_dir().join(format!("vellum_audio_data_{id}"));
    tokio::fs::create_dir_all(data_dir.join("files"))
        .await
        .unwrap();
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let limiter =
        || std::sync::Arc::new(RateLimiter::new(1000, std::time::Duration::from_secs(60)));
    router(AppState {
        db,
        public_base_url: "http://test.local".into(),
        data_dir,
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
    })
}

async fn send(
    app: &axum::Router,
    method: &str,
    uri: &str,
    token: Option<&str>,
    body: Body,
    json: bool,
) -> (StatusCode, serde_json::Value, Vec<u8>) {
    let mut builder = Request::builder().method(method).uri(uri);
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
    if json {
        builder = builder.header("content-type", "application/json");
    }
    let res = app
        .clone()
        .oneshot(builder.body(body).unwrap())
        .await
        .unwrap();
    let status = res.status();
    let raw = axum::body::to_bytes(res.into_body(), usize::MAX)
        .await
        .unwrap()
        .to_vec();
    (
        status,
        serde_json::from_slice(&raw).unwrap_or(serde_json::Value::Null),
        raw,
    )
}

async fn call(
    app: &axum::Router,
    method: &str,
    uri: &str,
    token: Option<&str>,
    body: Option<serde_json::Value>,
) -> (StatusCode, serde_json::Value) {
    let (status, json, _) = match body {
        Some(b) => send(app, method, uri, token, Body::from(b.to_string()), true).await,
        None => send(app, method, uri, token, Body::empty(), false).await,
    };
    (status, json)
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

async fn make_book(app: &axum::Router, token: &str, id: &str) {
    let (status, _) = call(
        app,
        "PUT",
        &format!("/api/books/{id}"),
        Some(token),
        Some(serde_json::json!({ "title": id })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
}

/// Leading bytes that pass the sniff: an ID3 tag, or `ftyp` at offset 4.
fn mp3_bytes(marker: &str) -> Vec<u8> {
    let mut b = b"ID3\x03\x00\x00\x00\x00\x00\x00".to_vec();
    b.extend_from_slice(marker.as_bytes());
    b.extend_from_slice(&[0u8; 64]);
    b
}

fn m4b_bytes() -> Vec<u8> {
    let mut b = vec![0, 0, 0, 0x18];
    b.extend_from_slice(b"ftypM4B \x00\x00\x00\x00isomM4B ");
    b.extend_from_slice(&[0u8; 64]);
    b
}

async fn upload(
    app: &axum::Router,
    token: &str,
    book: &str,
    query: &str,
    bytes: Vec<u8>,
) -> (StatusCode, serde_json::Value) {
    let (status, json, _) = send(
        app,
        "POST",
        &format!("/api/books/{book}/files?{query}"),
        Some(token),
        Body::from(bytes),
        false,
    )
    .await;
    (status, json)
}

#[tokio::test]
async fn audio_uploads_carry_their_part_fields() {
    let app = app().await;
    let token = register(&app).await;
    make_book(&app, &token, "dune").await;

    let (status, file) = upload(
        &app,
        &token,
        "dune",
        "filename=01.mp3&duration_ms=61000&track=2&label=Chapter%202&narrator=Scott%20Brick",
        mp3_bytes("a"),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{file}");
    assert_eq!(file["format"], "mp3");
    assert_eq!(file["duration_ms"], 61000);
    assert_eq!(file["track"], 2);
    assert_eq!(file["label"], "Chapter 2");
    assert_eq!(file["narrator"], "Scott Brick");

    let (status, file) = upload(&app, &token, "dune", "filename=book.m4b", m4b_bytes()).await;
    assert_eq!(status, StatusCode::OK, "{file}");
    assert_eq!(file["format"], "m4b");
    assert!(file["track"].is_null());

    // Served with an audio type, so an OPDS client or a browser plays it.
    let id = file["id"].as_str().unwrap();
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/files/{id}"))
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.headers()["content-type"], "audio/mp4");
}

#[tokio::test]
async fn audio_is_checked_by_its_bytes_and_text_ignores_the_audio_fields() {
    let app = app().await;
    let token = register(&app).await;
    make_book(&app, &token, "dune").await;

    let (status, _) = upload(
        &app,
        &token,
        "dune",
        "filename=x.mp3",
        b"%PDF-1.7 no".to_vec(),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "a PDF named .mp3");
    let (status, _) = upload(&app, &token, "dune", "filename=x.m4b", mp3_bytes("b")).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "an mp3 named .m4b");
    let (status, _) = upload(&app, &token, "dune", "filename=x.ogg", mp3_bytes("c")).await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "not a 1.5 format");

    let mut epub = vec![0x50, 0x4B, 0x03, 0x04];
    epub.extend_from_slice(&[0u8; 64]);
    let (status, file) = upload(&app, &token, "dune", "filename=a.epub&track=3", epub).await;
    assert_eq!(status, StatusCode::OK);
    assert!(file["track"].is_null(), "a text file has no part fields");
}

#[tokio::test]
async fn the_delta_pull_hides_audio_from_clients_that_do_not_ask() {
    let app = app().await;
    let token = register(&app).await;
    make_book(&app, &token, "dune").await;
    let mut epub = vec![0x50, 0x4B, 0x03, 0x04];
    epub.extend_from_slice(&[0u8; 64]);
    upload(&app, &token, "dune", "filename=a.epub", epub).await;
    upload(
        &app,
        &token,
        "dune",
        "filename=01.mp3&track=1",
        mp3_bytes("d"),
    )
    .await;

    let formats = |body: &serde_json::Value| -> Vec<String> {
        let mut out: Vec<String> = body["books"][0]["files"]
            .as_array()
            .unwrap()
            .iter()
            .map(|f| f["format"].as_str().unwrap().to_string())
            .collect();
        out.sort();
        out
    };
    let (_, old) = call(&app, "GET", "/api/books?cursor=", Some(&token), None).await;
    assert_eq!(formats(&old), ["epub"], "a pre-1.5 app gets no audio");
    assert_eq!(old["books"][0]["file_count"], 1);
    let (_, new) = call(
        &app,
        "GET",
        "/api/books?cursor=&audio=1",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(formats(&new), ["epub", "mp3"]);
    assert_eq!(new["books"][0]["files"].as_array().unwrap().len(), 2);

    let (_, caps) = call(&app, "GET", "/api/capabilities", None, None).await;
    assert!(
        caps["features"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f == "audiobooks")
    );
}

#[tokio::test]
async fn reading_progress_keeps_the_audio_position_across_text_pushes() {
    let app = app().await;
    let token = register(&app).await;
    make_book(&app, &token, "dune").await;

    let (status, row) = call(
        &app,
        "PUT",
        "/api/reading-progress/dune",
        Some(&token),
        Some(serde_json::json!({
            "device_id": "phone",
            "progress": 0.2,
            "page": 3,
            "unit": "chapter",
            "audio_position": 18753.5,
            "audio_duration": 54000.0,
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{row}");
    assert_eq!(row["audio_position"], 18753.5);
    assert_eq!(row["audio_duration"], 54000.0);

    // An older app on the same device pushes text only: the audio stays.
    let (_, row) = call(
        &app,
        "PUT",
        "/api/reading-progress/dune",
        Some(&token),
        Some(serde_json::json!({ "device_id": "phone", "progress": 0.3, "page": 4, "unit": "chapter" })),
    )
    .await;
    assert_eq!(row["page"], 4);
    assert_eq!(row["audio_position"], 18753.5);

    let (_, listed) = call(
        &app,
        "GET",
        "/api/reading-progress?cursor=",
        Some(&token),
        None,
    )
    .await;
    let entry = &listed["entries"][0];
    assert_eq!(entry["audio_position"], 18753.5);
    assert_eq!(entry["audio_duration"], 54000.0);

    // `unit` is still only page|chapter: audio never needed a new unit.
    let (status, _) = call(
        &app,
        "PUT",
        "/api/reading-progress/dune",
        Some(&token),
        Some(serde_json::json!({ "device_id": "phone", "page": 1, "unit": "second" })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

/// GET [uri] with an optional `Range` and `If-Range`, returning the status,
/// the `Content-Range` header and the body.
async fn fetch_range(
    app: &axum::Router,
    uri: &str,
    token: Option<&str>,
    range: Option<&str>,
    if_range: Option<&str>,
) -> (StatusCode, Option<String>, Vec<u8>) {
    let mut builder = Request::builder().uri(uri);
    if let Some(token) = token {
        builder = builder.header("authorization", format!("Bearer {token}"));
    }
    if let Some(range) = range {
        builder = builder.header("range", range);
    }
    if let Some(tag) = if_range {
        builder = builder.header("if-range", tag);
    }
    let res = app
        .clone()
        .oneshot(builder.body(Body::empty()).unwrap())
        .await
        .unwrap();
    let status = res.status();
    let content_range = res
        .headers()
        .get("content-range")
        .map(|v| v.to_str().unwrap().to_string());
    let body = axum::body::to_bytes(res.into_body(), usize::MAX)
        .await
        .unwrap()
        .to_vec();
    (status, content_range, body)
}

/// On-demand audio download (docs/AUDIOBOOKS.md §6): the app resumes a part
/// it was partway through with `Range: bytes=N-` and an `If-Range` naming the
/// part's hash, and must get exactly the rest, whether it signs in with its
/// header or comes through a signed link.
#[tokio::test]
async fn an_interrupted_audio_download_resumes_with_a_range() {
    let app = app().await;
    let token = register(&app).await;
    make_book(&app, &token, "dune").await;

    // Big enough that the split lands well inside the body.
    let mut audio = m4b_bytes();
    audio.extend((0..4000u32).map(|i| (i % 251) as u8));
    let (status, file) = upload(&app, &token, "dune", "filename=book.m4b", audio.clone()).await;
    assert_eq!(status, StatusCode::OK, "{file}");
    let id = file["id"].as_str().unwrap().to_string();
    let etag = format!("\"{}\"", file["sha256"].as_str().unwrap());
    let uri = format!("/api/files/{id}");
    let total = audio.len();

    // The first attempt got 1500 bytes before the connection dropped; the
    // second asks for the rest, open-ended, guarded by the hash.
    let split = 1500;
    let (status, range, rest) = fetch_range(
        &app,
        &uri,
        Some(&token),
        Some(&format!("bytes={split}-")),
        Some(&etag),
    )
    .await;
    assert_eq!(status, StatusCode::PARTIAL_CONTENT);
    assert_eq!(
        range.as_deref(),
        Some(format!("bytes {split}-{}/{total}", total - 1).as_str())
    );
    let mut joined = audio[..split].to_vec();
    joined.extend_from_slice(&rest);
    assert_eq!(joined, audio, "the two halves are the file");

    // An If-Range naming some other blob means the partial file is of
    // something else: the whole file comes back instead, as a 200.
    let (status, range, whole) = fetch_range(
        &app,
        &uri,
        Some(&token),
        Some(&format!("bytes={split}-")),
        Some("\"not-this-file\""),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(range.is_none());
    assert_eq!(whole, audio);

    // A partial that is already complete asks past the end: 416 with the
    // size, so the client checks what it holds instead.
    let (status, range, _) = fetch_range(
        &app,
        &uri,
        Some(&token),
        Some(&format!("bytes={total}-")),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::RANGE_NOT_SATISFIABLE);
    assert_eq!(range.as_deref(), Some(format!("bytes */{total}").as_str()));

    // The same through a signed link, which carries no header.
    let (status, links) = call(
        &app,
        "POST",
        "/api/links",
        Some(&token),
        Some(serde_json::json!({ "paths": [uri] })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{links}");
    let signed = links["links"][0]["url"].as_str().unwrap().to_string();
    let (status, _, rest) = fetch_range(
        &app,
        &signed,
        None,
        Some(&format!("bytes={split}-")),
        Some(&etag),
    )
    .await;
    assert_eq!(status, StatusCode::PARTIAL_CONTENT);
    assert_eq!(rest, audio[split..].to_vec());
}
