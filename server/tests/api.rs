//! End-to-end API tests. Each test builds the real router against a throwaway
//! SQLite database and drives it with in-process HTTP requests via
//! `tower::ServiceExt::oneshot` — no network port is opened.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{json, Value};
use tower::ServiceExt; // for `oneshot`
use vellum_server::{connect_db, router, AppState};

/// A fresh app backed by its own temp-file database (migrated) and its own
/// temp data directory for blobs.
async fn test_app() -> axum::Router {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_test_{id}.db"));
    let data_dir = std::env::temp_dir().join(format!("vellum_test_data_{id}"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    router(AppState {
        db,
        public_base_url: "http://test.local".into(),
        data_dir,
        http: reqwest::Client::new(),
        max_upload_bytes: 512 * 1024 * 1024,
    })
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
        .oneshot(Request::builder().uri("/health").body(Body::empty()).unwrap())
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
async fn requires_a_token() {
    let app = test_app().await;
    let (status, _) = call(&app, "GET", "/api/books", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
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
    let (status, _) = call(&app, "DELETE", &format!("/api/books/{book}"), Some(&alice), None).await;
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
    let (status, detail) =
        call(&app, "GET", &format!("/api/books/{book}/detail"), Some(&master), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(detail["title"], json!("Dune"));
    let files = detail["files"].as_array().unwrap();
    assert_eq!(files.len(), 1);
    let file_id = files[0]["id"].as_str().unwrap().to_string();

    // A `?token=` query authenticates a plain download (no Authorization header).
    let download = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/files/{file_id}?token={master}"))
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

    // A bad token is rejected.
    let bad = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/files/{file_id}?token=nope"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(bad.status(), StatusCode::UNAUTHORIZED);
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
    let (_, detail) =
        call(&app, "GET", &format!("/api/books/{book}/detail"), Some(&master), None).await;
    assert!(detail["files"].as_array().unwrap().is_empty());
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
    assert_eq!(
        response.headers().get("content-type").unwrap(),
        "image/png"
    );
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    assert_eq!(bytes.as_ref(), png);

    // Anonymous callers can't read a private cover.
    let (status, _) = call(&app, "GET", &format!("/api/books/{book}/cover"), None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
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
    let basic = base64::engine::general_purpose::STANDARD
        .encode("master@lib.test:masterpass1");
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
    assert!(response
        .headers()
        .get("content-type")
        .unwrap()
        .to_str()
        .unwrap()
        .contains("opds-catalog"));
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    let xml = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(xml.contains("<title>Dune</title>"));
    assert!(xml.contains("opds-spec.org"));
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
    let (status, body) =
        call(&app, "GET", &format!("/api/public/{token}"), None, None).await;
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
    let (status, _) =
        call(&app, "GET", &format!("/api/public/{token}"), None, None).await;
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
    let token = link["url"].as_str().unwrap().rsplit('/').next().unwrap().to_string();

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
