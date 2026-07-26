//! Content search over book text (plan 5 #32).
//!
//! These build their own `AppState` rather than using `api.rs`'s helper, because
//! indexing is a background worker and a deterministic test has to drive it by
//! hand (`drain_text_index`) instead of sleeping and hoping.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;
use vellum_server::{AppState, RateLimiter, connect_db, drain_text_index, router};

/// A state and a router over the same state, so a test can both make requests
/// and drive the indexer.
async fn indexed_app(index_text: bool) -> (axum::Router, AppState) {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_text_{id}.db"));
    let data_dir = std::env::temp_dir().join(format!("vellum_text_data_{id}"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let state = AppState {
        db,
        public_base_url: "http://test.local".into(),
        data_dir,
        http: reqwest::Client::new(),
        max_upload_bytes: 64 * 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(2)),
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
        index_text,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    };
    (router(state.clone()), state)
}

async fn json(app: &axum::Router, req: Request<Body>) -> (StatusCode, serde_json::Value) {
    let res = app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
        .await
        .unwrap();
    let value = serde_json::from_slice(&bytes).unwrap_or(serde_json::Value::Null);
    (status, value)
}

async fn register(app: &axum::Router, email: &str, password: &str) -> String {
    let (_, body) = json(
        app,
        Request::builder()
            .method("POST")
            .uri("/api/auth/register")
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::json!({
                    "email": email,
                    "password": password,
                    "display_name": "T",
                })
                .to_string(),
            ))
            .unwrap(),
    )
    .await;
    body["token"].as_str().unwrap().to_string()
}

async fn login(app: &axum::Router, email: &str, password: &str) -> String {
    let (_, body) = json(
        app,
        Request::builder()
            .method("POST")
            .uri("/api/auth/login")
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::json!({ "email": email, "password": password }).to_string(),
            ))
            .unwrap(),
    )
    .await;
    body["token"].as_str().unwrap().to_string()
}

async fn create_book(app: &axum::Router, token: &str, title: &str) -> String {
    let (_, body) = json(
        app,
        Request::builder()
            .method("POST")
            .uri("/api/books")
            .header("authorization", format!("Bearer {token}"))
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::json!({ "title": title }).to_string(),
            ))
            .unwrap(),
    )
    .await;
    body["id"].as_str().unwrap().to_string()
}

async fn upload(app: &axum::Router, token: &str, book: &str, name: &str, bytes: Vec<u8>) {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri(format!("/api/books/{book}/files?filename={name}"))
                .header("authorization", format!("Bearer {token}"))
                .header("content-type", "application/octet-stream")
                .body(Body::from(bytes))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK, "upload {name}");
}

/// Uploads, waits for the upload's background task to queue the file, then
/// indexes it.
///
/// The wait is the point: enqueueing happens *after* the response on purpose
/// (extracting a 900-page PDF must not hold an upload open), so a test that
/// drained immediately would usually find an empty queue and prove nothing.
async fn upload_and_index(
    app: &axum::Router,
    state: &AppState,
    token: &str,
    book: &str,
    name: &str,
    bytes: Vec<u8>,
) {
    upload(app, token, book, name, bytes).await;
    for _ in 0..200 {
        let queued: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM book_text")
            .fetch_one(&state.db)
            .await
            .unwrap();
        if queued > 0 {
            break;
        }
        tokio::time::sleep(std::time::Duration::from_millis(10)).await;
    }
    drain_text_index(state).await;
}

/// A minimal EPUB with two chapters of real prose, in spine order.
fn epub_with_text() -> Vec<u8> {
    use std::io::Write;
    const CONTAINER: &str = "<?xml version=\"1.0\"?>\
        <container version=\"1.0\"><rootfiles>\
        <rootfile full-path=\"content.opf\"/></rootfiles></container>";
    const OPF: &str = "<?xml version=\"1.0\"?>\
        <package version=\"2.0\"><metadata><dc:title>Tiny</dc:title></metadata>\
        <manifest>\
        <item id=\"c1\" href=\"ch1.xhtml\" media-type=\"application/xhtml+xml\"/>\
        <item id=\"c2\" href=\"ch2.xhtml\" media-type=\"application/xhtml+xml\"/>\
        </manifest>\
        <spine><itemref idref=\"c1\"/><itemref idref=\"c2\"/></spine></package>";
    const CH1: &str = "<html><head><style>.x{color:red}</style>\
        <script>var hidden='scriptsecret';</script></head>\
        <body><h1>Chapter One</h1><p>The quick brown fox.</p></body></html>";
    const CH2: &str = "<html><body><p>Levenshtein distance measures edits.</p>\
        <p>Ana &amp; Bob agreed.</p></body></html>";
    let mut zw = zip::ZipWriter::new(std::io::Cursor::new(Vec::new()));
    for (name, data) in [
        ("mimetype", b"application/epub+zip".to_vec()),
        ("META-INF/container.xml", CONTAINER.as_bytes().to_vec()),
        ("content.opf", OPF.as_bytes().to_vec()),
        ("ch1.xhtml", CH1.as_bytes().to_vec()),
        ("ch2.xhtml", CH2.as_bytes().to_vec()),
    ] {
        zw.start_file(name, zip::write::SimpleFileOptions::default())
            .unwrap();
        zw.write_all(&data).unwrap();
    }
    zw.finish().unwrap().into_inner()
}

/// A real one-page PDF carrying [text], built with `lopdf` rather than shipped
/// as an opaque binary fixture.
fn pdf_with_text(text: &str) -> Vec<u8> {
    use lopdf::{Document, Object, Stream, dictionary};
    let mut doc = Document::with_version("1.5");
    let pages_id = doc.new_object_id();
    let font_id = doc.add_object(dictionary! {
        "Type" => "Font",
        "Subtype" => "Type1",
        "BaseFont" => "Helvetica",
    });
    let resources_id = doc.add_object(dictionary! {
        "Font" => dictionary! { "F1" => font_id },
    });
    let content = format!("BT /F1 24 Tf 72 700 Td ({text}) Tj ET");
    let content_id = doc.add_object(Stream::new(dictionary! {}, content.into_bytes()));
    let page_id = doc.add_object(dictionary! {
        "Type" => "Page",
        "Parent" => pages_id,
        "Contents" => content_id,
        "Resources" => resources_id,
        "MediaBox" => vec![0.into(), 0.into(), 612.into(), 792.into()],
    });
    doc.objects.insert(
        pages_id,
        Object::Dictionary(dictionary! {
            "Type" => "Pages",
            "Kids" => vec![page_id.into()],
            "Count" => 1,
        }),
    );
    let catalog_id = doc.add_object(dictionary! {
        "Type" => "Catalog",
        "Pages" => pages_id,
    });
    doc.trailer.set("Root", catalog_id);
    let mut out = Vec::new();
    doc.save_to(&mut out).unwrap();
    out
}

async fn search(app: &axum::Router, token: &str, q: &str) -> serde_json::Value {
    let (status, body) = json(
        app,
        Request::builder()
            .uri(format!("/api/search?q={}", urlencode(q)))
            .header("authorization", format!("Bearer {token}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "search {q}: {body}");
    body
}

fn urlencode(raw: &str) -> String {
    raw.chars()
        .map(|c| match c {
            'a'..='z' | 'A'..='Z' | '0'..='9' | '-' | '_' | '.' => c.to_string(),
            ' ' => "+".to_string(),
            other => format!("%{:02X}", other as u32),
        })
        .collect()
}

#[tokio::test]
async fn epub_text_is_extracted_in_spine_order_and_searchable() {
    let (app, state) = indexed_app(true).await;
    let master = register(&app, "m@example.com", "correct horse staple").await;
    let book = create_book(&app, &master, "Tiny").await;
    upload_and_index(&app, &state, &master, &book, "tiny.epub", epub_with_text()).await;

    let hits = search(&app, &master, "levenshtein").await;
    let hit = &hits["hits"][0];
    assert_eq!(hit["book_id"], book);
    assert_eq!(hit["title"], "Tiny");
    // Chapter two is the second spine item, so the hit names section 2 — an
    // EPUB has no pages, and claiming one would be a lie the reader can't use.
    assert_eq!(hit["page"], 2);
    assert!(
        hit["snippet"].as_str().unwrap().contains("[Levenshtein]"),
        "snippet should highlight the match: {hit}"
    );
}

#[tokio::test]
async fn markup_and_scripts_never_become_search_terms() {
    // The bug this closes: indexing raw XHTML makes every book match "div",
    // "html" and whatever is inside a <script>.
    let (app, state) = indexed_app(true).await;
    let master = register(&app, "m@example.com", "correct horse staple").await;
    let book = create_book(&app, &master, "Tiny").await;
    upload_and_index(&app, &state, &master, &book, "tiny.epub", epub_with_text()).await;

    for noise in ["html", "body", "scriptsecret", "color"] {
        let hits = search(&app, &master, noise).await;
        assert!(
            hits["hits"].as_array().unwrap().is_empty(),
            "{noise} should not be a search term: {hits}"
        );
    }
    // And the prose either side of a tag is still two words, not one.
    assert!(
        !search(&app, &master, "quick brown").await["hits"]
            .as_array()
            .unwrap()
            .is_empty()
    );
    // An HTML entity is decoded rather than indexed as "amp".
    assert!(
        search(&app, &master, "amp").await["hits"]
            .as_array()
            .unwrap()
            .is_empty()
    );
}

#[tokio::test]
async fn pdf_text_is_extracted_and_named_by_page() {
    let (app, state) = indexed_app(true).await;
    let master = register(&app, "m@example.com", "correct horse staple").await;
    let book = create_book(&app, &master, "Paper").await;
    upload_and_index(
        &app,
        &state,
        &master,
        &book,
        "paper.pdf",
        pdf_with_text("Kolmogorov complexity"),
    )
    .await;

    let hits = search(&app, &master, "kolmogorov").await;
    let list = hits["hits"].as_array().unwrap();
    assert!(!list.is_empty(), "expected a hit: {hits}");
    assert_eq!(list[0]["page"], 1);
}

#[tokio::test]
async fn a_pdf_with_no_text_layer_records_no_text_rather_than_failing() {
    // A scanned book is a real, reportable state — not an error, and not
    // something to reach for OCR over.
    let (app, state) = indexed_app(true).await;
    let master = register(&app, "m@example.com", "correct horse staple").await;
    let book = create_book(&app, &master, "Scan").await;
    upload_and_index(&app, &state, &master, &book, "scan.pdf", pdf_with_text("")).await;

    let status: String = sqlx::query_scalar("SELECT status FROM book_text LIMIT 1")
        .fetch_one(&state.db)
        .await
        .unwrap();
    assert!(
        status == "no_text" || status == "failed",
        "a text-free PDF should not be reported as indexed, got {status}"
    );
    assert!(
        search(&app, &master, "anything").await["hits"]
            .as_array()
            .unwrap()
            .is_empty()
    );
}

#[tokio::test]
async fn results_are_rbac_filtered_exactly_like_books() {
    // The failure this prevents is the worst kind: leaking the *contents* of a
    // book to someone who cannot even see it exists.
    let (app, state) = indexed_app(true).await;
    let master = register(&app, "owner@example.com", "correct horse staple").await;
    let book = create_book(&app, &master, "Private").await;
    upload_and_index(&app, &state, &master, &book, "tiny.epub", epub_with_text()).await;

    // A second, ordinary account with no share.
    let (status, _) = json(
        &app,
        Request::builder()
            .method("POST")
            .uri("/api/users")
            .header("authorization", format!("Bearer {master}"))
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::json!({
                    "email": "other@example.com",
                    "password": "another good passphrase",
                    "display_name": "Other",
                })
                .to_string(),
            ))
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let other = login(&app, "other@example.com", "another good passphrase").await;

    assert!(
        search(&app, &other, "levenshtein").await["hits"]
            .as_array()
            .unwrap()
            .is_empty(),
        "a stranger must not see inside someone else's book"
    );
    assert!(
        !search(&app, &master, "levenshtein").await["hits"]
            .as_array()
            .unwrap()
            .is_empty()
    );

    // Once the book is shared, the same query works for them.
    let (status, _) = json(
        &app,
        Request::builder()
            .method("POST")
            .uri("/api/shares")
            .header("authorization", format!("Bearer {master}"))
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::json!({
                    "grantee_email": "other@example.com",
                    "scope": "book",
                    "scope_id": book,
                    "permission": "viewer",
                })
                .to_string(),
            ))
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        !search(&app, &other, "levenshtein").await["hits"]
            .as_array()
            .unwrap()
            .is_empty()
    );
}

#[tokio::test]
async fn deleting_a_book_removes_it_from_the_index() {
    let (app, state) = indexed_app(true).await;
    let master = register(&app, "m@example.com", "correct horse staple").await;
    let book = create_book(&app, &master, "Tiny").await;
    upload_and_index(&app, &state, &master, &book, "tiny.epub", epub_with_text()).await;
    assert!(
        !search(&app, &master, "levenshtein").await["hits"]
            .as_array()
            .unwrap()
            .is_empty()
    );

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("DELETE")
                .uri(format!("/api/books/{book}"))
                .header("authorization", format!("Bearer {master}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);

    assert!(
        search(&app, &master, "levenshtein").await["hits"]
            .as_array()
            .unwrap()
            .is_empty(),
        "a deleted book's contents must not stay searchable"
    );
    let rows: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM book_text")
        .fetch_one(&state.db)
        .await
        .unwrap();
    assert_eq!(rows, 0);
}

#[tokio::test]
async fn reindexing_is_idempotent() {
    let (app, state) = indexed_app(true).await;
    let master = register(&app, "m@example.com", "correct horse staple").await;
    let book = create_book(&app, &master, "Tiny").await;
    upload_and_index(&app, &state, &master, &book, "tiny.epub", epub_with_text()).await;
    let before = search(&app, &master, "levenshtein").await["hits"]
        .as_array()
        .unwrap()
        .len();

    for _ in 0..2 {
        let (status, _) = json(
            &app,
            Request::builder()
                .method("POST")
                .uri("/api/admin/reindex")
                .header("authorization", format!("Bearer {master}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        drain_text_index(&state).await;
    }

    assert_eq!(
        search(&app, &master, "levenshtein").await["hits"]
            .as_array()
            .unwrap()
            .len(),
        before,
        "re-indexing must replace rows, not duplicate every hit"
    );
}

#[tokio::test]
async fn reindex_is_master_only() {
    let (app, _state) = indexed_app(true).await;
    let master = register(&app, "m@example.com", "correct horse staple").await;
    let (status, _) = json(
        &app,
        Request::builder()
            .method("POST")
            .uri("/api/users")
            .header("authorization", format!("Bearer {master}"))
            .header("content-type", "application/json")
            .body(Body::from(
                serde_json::json!({
                    "email": "other@example.com",
                    "password": "another good passphrase",
                    "display_name": "Other",
                })
                .to_string(),
            ))
            .unwrap(),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let other = login(&app, "other@example.com", "another good passphrase").await;

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/admin/reindex")
                .header("authorization", format!("Bearer {other}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn a_server_with_indexing_off_says_so_instead_of_pretending() {
    let (app, state) = indexed_app(false).await;
    let master = register(&app, "m@example.com", "correct horse staple").await;
    let book = create_book(&app, &master, "Tiny").await;
    upload_and_index(&app, &state, &master, &book, "tiny.epub", epub_with_text()).await;

    // Nothing was queued at all — the feature is off, not merely quiet.
    let rows: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM book_text")
        .fetch_one(&state.db)
        .await
        .unwrap();
    assert_eq!(rows, 0);

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/api/search?q=anything")
                .header("authorization", format!("Bearer {master}"))
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::BAD_REQUEST);

    let (_, caps) = json(
        &app,
        Request::builder()
            .uri("/api/capabilities")
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    let features = caps["features"].as_array().unwrap();
    assert!(!features.iter().any(|f| f == "content_search"));

    let (_, status_body) = json(
        &app,
        Request::builder()
            .uri("/api/search/status")
            .header("authorization", format!("Bearer {master}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    assert_eq!(status_body["enabled"], false);
}

#[tokio::test]
async fn an_enabled_server_advertises_the_capability_and_reports_progress() {
    let (app, state) = indexed_app(true).await;
    let master = register(&app, "m@example.com", "correct horse staple").await;
    let book = create_book(&app, &master, "Tiny").await;
    upload_and_index(&app, &state, &master, &book, "tiny.epub", epub_with_text()).await;

    let (_, caps) = json(
        &app,
        Request::builder()
            .uri("/api/capabilities")
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    assert!(
        caps["features"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f == "content_search")
    );

    let (_, body) = json(
        &app,
        Request::builder()
            .uri("/api/search/status")
            .header("authorization", format!("Bearer {master}"))
            .body(Body::empty())
            .unwrap(),
    )
    .await;
    assert_eq!(body["enabled"], true);
    assert_eq!(body["counts"]["ok"], 1);
}

#[tokio::test]
async fn a_nonsense_query_returns_nothing_rather_than_an_error() {
    // Raw user text reaching FTS5's MATCH is a syntax error waiting to happen;
    // punctuation-only input must simply find nothing.
    let (app, _state) = indexed_app(true).await;
    let master = register(&app, "m@example.com", "correct horse staple").await;
    for q in ["***", "   ", "\"", "AND OR"] {
        let body = search(&app, &master, q).await;
        assert!(body["hits"].as_array().unwrap().is_empty(), "q={q}");
    }
}
