//! Content-addressed, refcounted blob storage (plan 5 #9).
//!
//! Two failure modes this replaces, and both are tested here rather than
//! reasoned about: identical bytes were stored once per row, and deleting a
//! book unlinked its blob unconditionally — which, once files are shared, takes
//! another book's file with it.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;
use vellum_server::{AppState, EventBus, RateLimiter, connect_db, router};

struct Harness {
    app: axum::Router,
    db: sqlx::SqlitePool,
    data_dir: std::path::PathBuf,
}

async fn app() -> Harness {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_blobs_{id}.db"));
    let data_dir = std::env::temp_dir().join(format!("vellum_blobs_data_{id}"));
    tokio::fs::create_dir_all(data_dir.join("files"))
        .await
        .unwrap();
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let router = router(AppState {
        db: db.clone(),
        public_base_url: "http://test.local".into(),
        data_dir: data_dir.clone(),
        http: reqwest::Client::new(),
        max_upload_bytes: 8 * 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        enrich_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        basic_cache: std::sync::Arc::default(),
        public_limiter: std::sync::Arc::new(RateLimiter::new(
            1000,
            std::time::Duration::from_secs(60),
        )),
        search_limiter: std::sync::Arc::new(RateLimiter::new(
            1000,
            std::time::Duration::from_secs(60),
        )),
        send_limiter: std::sync::Arc::new(RateLimiter::new(
            1000,
            std::time::Duration::from_secs(60),
        )),
        events: EventBus::new(),
        mailer: None,
        index_text: false,
        audit: false,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    });
    Harness {
        app: router,
        db,
        data_dir,
    }
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

/// A minimal but genuinely valid EPUB: the upload path sniffs magic bytes, so
/// arbitrary content is rejected before it ever reaches the store.
fn epub_bytes(marker: &str) -> Vec<u8> {
    let mut zip = vec![0x50, 0x4B, 0x03, 0x04];
    zip.extend_from_slice(marker.as_bytes());
    zip.extend_from_slice(&[0u8; 64]);
    zip
}

async fn upload(
    app: &axum::Router,
    token: &str,
    book: &str,
    bytes: Vec<u8>,
) -> (StatusCode, serde_json::Value) {
    let request = Request::builder()
        .method("POST")
        .uri(format!("/api/books/{book}/files?filename=book.epub"))
        .header("authorization", format!("Bearer {token}"))
        .body(Body::from(bytes))
        .unwrap();
    let res = app.clone().oneshot(request).await.unwrap();
    let status = res.status();
    let raw = axum::body::to_bytes(res.into_body(), usize::MAX)
        .await
        .unwrap();
    (
        status,
        serde_json::from_slice(&raw).unwrap_or(serde_json::Value::Null),
    )
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

/// Every regular file under the data dir, relative — the whole point is to
/// count what is actually on disk rather than what the rows claim.
fn blobs_on_disk(root: &std::path::Path) -> Vec<String> {
    fn walk(dir: &std::path::Path, base: &std::path::Path, out: &mut Vec<String>) {
        let Ok(entries) = std::fs::read_dir(dir) else {
            return;
        };
        for entry in entries.flatten() {
            let path = entry.path();
            if path.is_dir() {
                walk(&path, base, out);
            } else {
                let rel = path.strip_prefix(base).unwrap().to_string_lossy();
                if !rel.contains(".tmp-") {
                    out.push(rel.replace('\\', "/"));
                }
            }
        }
    }
    let mut out = Vec::new();
    walk(&root.join("files"), root, &mut out);
    out.sort();
    out
}

#[tokio::test]
async fn identical_bytes_are_stored_once_and_referenced_twice() {
    let h = app().await;
    let token = register(&h.app).await;
    make_book(&h.app, &token, "one").await;
    make_book(&h.app, &token, "two").await;

    let bytes = epub_bytes("same");
    let (s1, f1) = upload(&h.app, &token, "one", bytes.clone()).await;
    let (s2, f2) = upload(&h.app, &token, "two", bytes).await;
    assert_eq!(s1, StatusCode::OK, "{f1}");
    assert_eq!(s2, StatusCode::OK, "{f2}");

    assert_eq!(
        f1["path"], f2["path"],
        "the same bytes must resolve to the same blob"
    );
    assert_ne!(f1["id"], f2["id"], "but they are two rows");
    assert_eq!(
        blobs_on_disk(&h.data_dir).len(),
        1,
        "one file on disk, not two"
    );
}

#[tokio::test]
async fn a_stored_path_is_content_addressed_and_sharded() {
    let h = app().await;
    let token = register(&h.app).await;
    make_book(&h.app, &token, "one").await;
    let (_, file) = upload(&h.app, &token, "one", epub_bytes("x")).await;

    let path = file["path"].as_str().unwrap();
    let sha = file["sha256"].as_str().unwrap();
    assert_eq!(
        path,
        format!("files/{}/{}.epub", &sha[..2], sha),
        "the path is derived from the content hash"
    );
    assert!(h.data_dir.join(path).exists());
}

#[tokio::test]
async fn deleting_one_book_keeps_the_other_books_file() {
    // The bug content addressing would otherwise introduce: two rows share one
    // blob, and an unconditional unlink takes both books' file away.
    let h = app().await;
    let token = register(&h.app).await;
    make_book(&h.app, &token, "one").await;
    make_book(&h.app, &token, "two").await;
    let bytes = epub_bytes("shared");
    upload(&h.app, &token, "one", bytes.clone()).await;
    let (_, kept) = upload(&h.app, &token, "two", bytes).await;

    let (status, _) = call(&h.app, "DELETE", "/api/books/one", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);

    let path = kept["path"].as_str().unwrap();
    assert!(
        h.data_dir.join(path).exists(),
        "the surviving book's file must still be on disk"
    );

    // And once the last reference goes, so does the blob.
    let (status, _) = call(&h.app, "DELETE", "/api/books/two", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(!h.data_dir.join(path).exists(), "now it is unreferenced");
}

#[tokio::test]
async fn the_sweep_sees_orphans_inside_the_shard_directories() {
    // A flat walk would skip the shard dirs entirely and report a clean library
    // no matter how much junk was in them.
    let h = app().await;
    let token = register(&h.app).await;
    let orphan = h.data_dir.join("files/ab");
    tokio::fs::create_dir_all(&orphan).await.unwrap();
    tokio::fs::write(orphan.join("abdeadbeef.epub"), b"junk")
        .await
        .unwrap();

    let (status, report) = call(&h.app, "POST", "/api/admin/sweep", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK, "{report}");
    let orphans = report["orphan_blobs"].as_array().unwrap();
    assert!(
        orphans
            .iter()
            .any(|o| o.as_str() == Some("files/ab/abdeadbeef.epub")),
        "the sweep must descend into shards: {report}"
    );
}

#[tokio::test]
async fn the_backfill_moves_old_layout_blobs_and_is_idempotent() {
    let h = app().await;
    let token = register(&h.app).await;
    make_book(&h.app, &token, "one").await;

    // Seed a pre-#9 row: a flat `files/<uuid>.epub` with a deliberately wrong
    // stored hash, so the rehash-rather-than-trust rule is exercised.
    let bytes = epub_bytes("legacy");
    let old_rel = "files/legacy-uuid.epub";
    tokio::fs::write(h.data_dir.join(old_rel), &bytes)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO book_file (id, book_id, format, path, size_bytes, sha256) \
         VALUES ('f1', 'one', 'epub', ?, ?, 'stale-and-wrong')",
    )
    .bind(old_rel)
    .bind(bytes.len() as i64)
    .execute(&h.db)
    .await
    .unwrap();

    let state = test_state(&h);
    let moved = vellum_server::backfill_content_addressed(&state)
        .await
        .unwrap();
    assert_eq!(moved, 1);

    let (path, sha): (String, String) =
        sqlx::query_as("SELECT path, sha256 FROM book_file WHERE id = 'f1'")
            .fetch_one(&h.db)
            .await
            .unwrap();
    assert_eq!(path, format!("files/{}/{}.epub", &sha[..2], sha));
    assert_ne!(
        sha, "stale-and-wrong",
        "the hash was recomputed, not trusted"
    );
    assert!(h.data_dir.join(&path).exists(), "moved into place");
    assert!(
        !h.data_dir.join(old_rel).exists(),
        "and the old file is gone"
    );

    // Second run: the marker short-circuits it, and nothing changes.
    let again = vellum_server::backfill_content_addressed(&state)
        .await
        .unwrap();
    assert_eq!(again, 0);
    let (path_after,): (String,) = sqlx::query_as("SELECT path FROM book_file WHERE id = 'f1'")
        .fetch_one(&h.db)
        .await
        .unwrap();
    assert_eq!(path_after, path);
}

#[tokio::test]
async fn the_backfill_leaves_a_row_whose_file_is_missing_alone() {
    // Rewriting the path would hide it from the integrity sweep's
    // "missing files" report, which is the only thing that would tell anyone.
    let h = app().await;
    let token = register(&h.app).await;
    make_book(&h.app, &token, "one").await;
    sqlx::query(
        "INSERT INTO book_file (id, book_id, format, path, size_bytes, sha256) \
         VALUES ('gone', 'one', 'epub', 'files/not-here.epub', 10, 'x')",
    )
    .execute(&h.db)
    .await
    .unwrap();

    let state = test_state(&h);
    vellum_server::backfill_content_addressed(&state)
        .await
        .unwrap();

    let (path,): (String,) = sqlx::query_as("SELECT path FROM book_file WHERE id = 'gone'")
        .fetch_one(&h.db)
        .await
        .unwrap();
    assert_eq!(path, "files/not-here.epub");
}

/// An `AppState` over the harness's own database and data dir, for calling the
/// backfill directly (it is a startup task, not a route).
fn test_state(h: &Harness) -> AppState {
    AppState {
        db: h.db.clone(),
        public_base_url: "http://test.local".into(),
        data_dir: h.data_dir.clone(),
        http: reqwest::Client::new(),
        max_upload_bytes: 8 * 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        enrich_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        basic_cache: std::sync::Arc::default(),
        public_limiter: std::sync::Arc::new(RateLimiter::new(
            1000,
            std::time::Duration::from_secs(60),
        )),
        search_limiter: std::sync::Arc::new(RateLimiter::new(
            1000,
            std::time::Duration::from_secs(60),
        )),
        send_limiter: std::sync::Arc::new(RateLimiter::new(
            1000,
            std::time::Duration::from_secs(60),
        )),
        events: EventBus::new(),
        mailer: None,
        index_text: false,
        audit: false,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    }
}
