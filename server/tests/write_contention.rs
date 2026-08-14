//! Writing while something else is writing.
//!
//! The bug this pins down failed **only under concurrency**, which is why it
//! reached CI rather than a desk: a `DELETE /api/books/{id}` returning 500,
//! reproducibly on a loaded runner and never once locally.
//!
//! sqlx's `begin()` issues a plain `BEGIN`, which SQLite treats as *deferred*.
//! A transaction that reads before it writes — and `books::delete` reads the
//! title and the blob paths first, deliberately, because it needs them before
//! the row goes — therefore starts as a **reader**, holding a snapshot. If any
//! other connection commits before the first write, the upgrade fails with
//! `SQLITE_BUSY_SNAPSHOT` (code 517).
//!
//! The `busy_timeout` does not save it. SQLite does not call the busy handler
//! for a snapshot conflict, because waiting cannot help: the snapshot is
//! already stale. `vellum_server::write_tx` issues `BEGIN IMMEDIATE` instead,
//! taking the write lock up front where the busy handler *does* apply.
//!
//! The other writer here is not invented for the test. Every upload spawns a
//! detached enrichment task that writes a page count and a cover path, so
//! "import a folder while the app syncs" is exactly this — and on a Raspberry
//! Pi, exactly this often.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;
use vellum_server::{AppState, EventBus, RateLimiter, connect_db, router, write_tx};

struct Harness {
    app: axum::Router,
    db: sqlx::SqlitePool,
}

async fn app() -> Harness {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_contention_{id}.db"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let app = router(AppState {
        db: db.clone(),
        public_base_url: "http://test.local".into(),
        data_dir: std::env::temp_dir().join(format!("vellum_contention_data_{id}")),
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
    Harness { app, db }
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

/// Keeps another connection committing for as long as the returned handle is
/// awaited — the shape of an upload's enrichment task.
fn a_busy_writer(db: sqlx::SqlitePool) -> tokio::task::JoinHandle<()> {
    tokio::spawn(async move {
        for n in 0..60 {
            let _ = sqlx::query("UPDATE app_user SET display_name = ? WHERE 1 = 1")
                .bind(format!("name {n}"))
                .execute(&db)
                .await;
        }
    })
}

#[tokio::test]
async fn deleting_a_book_survives_a_concurrent_writer() {
    let h = app().await;
    let token = register(&h.app).await;

    // Thirty attempts because the race is a race: one delete may well slip
    // through the gap. Before `write_tx`, roughly a quarter of these failed.
    let mut failures = Vec::new();
    for i in 0..30 {
        // The id is the server's to choose, not the caller's.
        let (status, created) = call(
            &h.app,
            "POST",
            "/api/books",
            Some(&token),
            Some(serde_json::json!({ "title": format!("Book {i}") })),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "creating book {i}: {created}");
        let id = created["id"]
            .as_str()
            .expect("a new book has an id")
            .to_string();

        let writer = a_busy_writer(h.db.clone());
        let (status, body) = call(
            &h.app,
            "DELETE",
            &format!("/api/books/{id}"),
            Some(&token),
            None,
        )
        .await;
        let _ = writer.await;
        if status != StatusCode::OK {
            failures.push(format!("{i}: {status} {body}"));
        }
    }

    assert!(
        failures.is_empty(),
        "a delete must not fail because something else was writing: {failures:?}"
    );
}

#[tokio::test]
async fn a_write_transaction_takes_its_lock_up_front() {
    // The mechanism itself, without an HTTP request in the way: read, let
    // somebody else commit, then write. With a deferred `BEGIN` this is
    // SQLITE_BUSY_SNAPSHOT; with `BEGIN IMMEDIATE` the writer waits its turn.
    let h = app().await;
    register(&h.app).await;

    for _ in 0..20 {
        let mut tx = write_tx(&h.db).await.expect("begin");
        let _: Option<String> = sqlx::query_scalar("SELECT email FROM app_user LIMIT 1")
            .fetch_optional(&mut *tx)
            .await
            .expect("read");

        let writer = a_busy_writer(h.db.clone());
        tokio::time::sleep(std::time::Duration::from_millis(1)).await;

        sqlx::query("UPDATE app_user SET display_name = 'after the read' WHERE 1 = 1")
            .execute(&mut *tx)
            .await
            .expect("a write transaction should not lose its snapshot");
        tx.commit().await.expect("commit");
        let _ = writer.await;
    }
}
