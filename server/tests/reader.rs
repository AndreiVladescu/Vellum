//! Reading in the browser (plan 5 #33).
//!
//! Two things here are worth more than the happy path: the sanitiser (a share
//! link means someone else's markup renders in your browser) and the rule that
//! **reading never consumes a one-time share link** — that counts downloads.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;
use vellum_server::{AppState, RateLimiter, connect_db, router};

async fn app() -> (axum::Router, sqlx::SqlitePool) {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_read_{id}.db"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let router = router(AppState {
        db: db.clone(),
        public_base_url: "http://test.local".into(),
        data_dir: std::env::temp_dir().join(format!("vellum_read_data_{id}")),
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
        mailer: None,
        index_text: false,
        audit: false,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    });
    (router, db)
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

async fn master(app: &axum::Router) -> String {
    let (_, body) = call(
        app,
        "POST",
        "/api/auth/register",
        None,
        Some(serde_json::json!({
            "email": "master@lib.test",
            "password": "a long enough passphrase",
            "display_name": "M",
        })),
    )
    .await;
    body["token"].as_str().unwrap().to_string()
}

/// An EPUB with two sections, one of which contains everything a sanitiser has
/// to deal with: a script, an inline handler, a `javascript:` link, an image.
fn hostile_epub() -> Vec<u8> {
    use std::io::Write;
    const CONTAINER: &str = "<?xml version=\"1.0\"?>\
        <container><rootfiles><rootfile full-path=\"OEBPS/content.opf\"/></rootfiles></container>";
    const OPF: &str = "<?xml version=\"1.0\"?>\
        <package version=\"2.0\"><manifest>\
        <item id=\"c1\" href=\"ch1.xhtml\" media-type=\"application/xhtml+xml\"/>\
        <item id=\"c2\" href=\"ch2.xhtml\" media-type=\"application/xhtml+xml\"/>\
        </manifest><spine><itemref idref=\"c1\"/><itemref idref=\"c2\"/></spine></package>";
    const CH1: &str = "<html><head><title>t</title></head><body>\
        <h1>Chapter One</h1>\
        <script>alert('pwned')</script>\
        <p onclick=\"steal()\">Hello <em>there</em>.</p>\
        <a href=\"javascript:alert(1)\">click</a>\
        <a href=\"https://example.com/x\">out</a>\
        <iframe src=\"https://evil.example\"></iframe>\
        <img src=\"img/pic.png\" alt=\"a picture\"/>\
        <img src=\"https://evil.example/track.gif\"/>\
        </body></html>";
    const CH2: &str = "<html><body><h2>Chapter Two</h2><p>The end.</p></body></html>";
    let mut zw = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
    for (name, data) in [
        ("mimetype", b"application/epub+zip".to_vec()),
        ("META-INF/container.xml", CONTAINER.as_bytes().to_vec()),
        ("OEBPS/content.opf", OPF.as_bytes().to_vec()),
        ("OEBPS/ch1.xhtml", CH1.as_bytes().to_vec()),
        ("OEBPS/ch2.xhtml", CH2.as_bytes().to_vec()),
        (
            "OEBPS/img/pic.png",
            b"\x89PNG\r\n\x1a\n and some bytes".to_vec(),
        ),
    ] {
        zw.start_file(name, zip::write::SimpleFileOptions::default())
            .unwrap();
        zw.write_all(&data).unwrap();
    }
    zw.finish().unwrap().into_inner()
}

async fn upload_epub(app: &axum::Router, token: &str, book: &str) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/books/{book}/files?filename=book.epub"))
                .header("authorization", format!("Bearer {token}"))
                .header("content-type", "application/epub+zip")
                .body(Body::from(hostile_epub()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
}

async fn book_with_epub(app: &axum::Router, token: &str) -> String {
    let (_, created) = call(
        app,
        "POST",
        "/api/books",
        Some(token),
        Some(serde_json::json!({ "title": "Readable" })),
    )
    .await;
    let id = created["id"].as_str().unwrap().to_string();
    upload_epub(app, token, &id).await;
    id
}

#[tokio::test]
async fn the_manifest_lists_the_spine_and_allows_downloading() {
    let (app, _db) = app().await;
    let token = master(&app).await;
    let book = book_with_epub(&app, &token).await;

    let (status, manifest) = call(
        &app,
        "GET",
        &format!("/api/books/{book}/read"),
        Some(&token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(manifest["kind"], "epub");
    assert_eq!(manifest["units"], 2);
    assert_eq!(manifest["title"], "Readable");
    assert_eq!(manifest["downloadable"], true);
}

#[tokio::test]
async fn a_section_arrives_as_sanitised_html() {
    // The threat is concrete: with a share link, markup someone else uploaded
    // renders in your browser. An allowlist is what makes that safe, and this
    // is the test that says so.
    let (app, _db) = app().await;
    let token = master(&app).await;
    let book = book_with_epub(&app, &token).await;

    let (status, section) = call(
        &app,
        "GET",
        &format!("/api/books/{book}/read/0"),
        Some(&token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let html = section["html"].as_str().unwrap();

    // The prose survives, with its emphasis.
    assert!(html.contains("Hello"));
    assert!(html.contains("<em>"));
    assert_eq!(section["title"], "Chapter One");

    // Nothing executable does.
    assert!(!html.contains("<script"), "script tag: {html}");
    assert!(!html.contains("alert("), "script body: {html}");
    assert!(!html.contains("onclick"), "inline handler: {html}");
    assert!(!html.contains("javascript:"), "javascript URL: {html}");
    assert!(!html.contains("<iframe"), "iframe: {html}");

    // An external image is dropped rather than fetched — a book must not be
    // able to phone home when someone opens it.
    assert!(!html.contains("evil.example"), "outbound request: {html}");
    // The book's own image is rewritten to the reader's asset route.
    assert!(html.contains("asset/OEBPS/img/pic.png"), "asset: {html}");
    // An external link survives, but can't take over the tab.
    assert!(html.contains("https://example.com/x"));
    assert!(html.contains("noopener"));
}

#[tokio::test]
async fn assets_are_served_only_when_they_are_images() {
    let (app, _db) = app().await;
    let token = master(&app).await;
    let book = book_with_epub(&app, &token).await;

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/books/{book}/read/asset/OEBPS/img/pic.png"))
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    assert_eq!(res.headers().get("content-type").unwrap(), "image/png");

    // The XHTML inside the book is not an image, so it is not served — a book
    // must not be able to get arbitrary bytes served under a type a browser
    // might execute.
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/books/{book}/read/asset/OEBPS/ch1.xhtml"))
                .header("authorization", format!("Bearer {token}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn reading_is_access_checked_and_does_not_reveal_existence() {
    let (app, _db) = app().await;
    let owner = master(&app).await;
    let book = book_with_epub(&app, &owner).await;

    let (status, _) = call(
        &app,
        "POST",
        "/api/users",
        Some(&owner),
        Some(serde_json::json!({
            "email": "other@lib.test",
            "password": "another good passphrase",
            "display_name": "Other",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, login) = call(
        &app,
        "POST",
        "/api/auth/login",
        None,
        Some(serde_json::json!({
            "email": "other@lib.test",
            "password": "another good passphrase",
        })),
    )
    .await;
    let other = login["token"].as_str().unwrap();

    // 404, not 403: the reader must not become a way to learn which ids exist.
    for uri in [
        format!("/api/books/{book}/read"),
        format!("/api/books/{book}/read/0"),
        format!("/api/books/{book}/read/asset/OEBPS/img/pic.png"),
    ] {
        let (status, _) = call(&app, "GET", &uri, Some(other), None).await;
        assert_eq!(status, StatusCode::NOT_FOUND, "{uri}");
    }

    // Unauthenticated is refused outright.
    let (status, _) = call(&app, "GET", &format!("/api/books/{book}/read"), None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn a_one_time_share_link_is_not_consumed_by_reading() {
    // The decision this pins: `max_uses` counts *downloads*. If reading burned
    // a use, opening the book would be the thing that destroys the link.
    let (app, _db) = app().await;
    let token = master(&app).await;
    let book = book_with_epub(&app, &token).await;

    let (status, link) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&token),
        Some(serde_json::json!({ "book_id": book, "max_uses": 1 })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let share = link["url"]
        .as_str()
        .unwrap()
        .rsplit('/')
        .next()
        .unwrap()
        .to_string();

    // Read the whole book, twice over.
    for _ in 0..2 {
        let (status, manifest) = call(
            &app,
            "GET",
            &format!("/api/public/{share}/read"),
            None,
            None,
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        assert_eq!(manifest["units"], 2);
        // And a public reader is told plainly that they cannot take the file.
        assert_eq!(manifest["downloadable"], false);

        for index in 0..2 {
            let (status, _) = call(
                &app,
                "GET",
                &format!("/api/public/{share}/read/{index}"),
                None,
                None,
            )
            .await;
            assert_eq!(status, StatusCode::OK);
        }
    }

    // The one download the link was for is still available.
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(format!("/api/public/{share}/file"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(
        res.status(),
        StatusCode::OK,
        "reading must not have used up the download"
    );

    // *That* consumed it, and now reading stops too — the link is spent.
    let (status, _) = call(
        &app,
        "GET",
        &format!("/api/public/{share}/read"),
        None,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn an_invalid_share_token_reads_nothing() {
    let (app, _db) = app().await;
    let _ = master(&app).await;
    let (status, _) = call(&app, "GET", "/api/public/nonsense/read", None, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = call(&app, "GET", "/api/public/nonsense/read/0", None, None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn a_book_with_no_file_says_so_instead_of_erroring() {
    let (app, _db) = app().await;
    let token = master(&app).await;
    let (_, created) = call(
        &app,
        "POST",
        "/api/books",
        Some(&token),
        Some(serde_json::json!({ "title": "Paper only" })),
    )
    .await;
    let book = created["id"].as_str().unwrap();

    let (status, manifest) = call(
        &app,
        "GET",
        &format!("/api/books/{book}/read"),
        Some(&token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(manifest["kind"], "none");
    assert_eq!(manifest["units"], 0);
}

#[tokio::test]
async fn the_reader_page_is_served_for_both_shapes() {
    let (app, _db) = app().await;
    for uri in ["/read/some-book-id", "/r/some-token", "/assets/read.js"] {
        let res = app
            .clone()
            .oneshot(Request::builder().uri(uri).body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK, "{uri}");
    }
}
