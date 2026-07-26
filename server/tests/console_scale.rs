//! Server-side paging/search/sort/filter and the activity log (plan 5 #35).
//!
//! The console used to pull the whole library into the browser and filter it
//! there; these pin the query params that moved that work to the server, and
//! the audit rows that answer "who deleted that book?".

use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;
use vellum_server::{AppState, RateLimiter, connect_db, router};

async fn app(audit: bool) -> axum::Router {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_scale_{id}.db"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    router(AppState {
        db,
        public_base_url: "http://test.local".into(),
        data_dir: std::env::temp_dir().join(format!("vellum_scale_data_{id}")),
        http: reqwest::Client::new(),
        max_upload_bytes: 8 * 1024 * 1024,
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
        audit,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    })
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

async fn add(app: &axum::Router, token: &str, body: serde_json::Value) -> String {
    let (status, created) = call(app, "POST", "/api/books", Some(token), Some(body)).await;
    assert_eq!(status, StatusCode::OK);
    created["id"].as_str().unwrap().to_string()
}

fn titles(page: &serde_json::Value) -> Vec<String> {
    page["items"]
        .as_array()
        .unwrap()
        .iter()
        .map(|i| i["title"].as_str().unwrap().to_string())
        .collect()
}

#[tokio::test]
async fn the_server_searches_so_the_browser_does_not_have_to() {
    let app = app(false).await;
    let token = master(&app).await;
    let dune = add(&app, &token, serde_json::json!({ "title": "Dune" })).await;
    add(&app, &token, serde_json::json!({ "title": "Emma" })).await;
    add(
        &app,
        &token,
        serde_json::json!({ "title": "Neuromancer", "publisher": "Ace" }),
    )
    .await;
    // Authors arrive on the upsert, not the create.
    call(
        &app,
        "PUT",
        &format!("/api/books/{dune}"),
        Some(&token),
        Some(serde_json::json!({ "title": "Dune", "authors": ["Frank Herbert"] })),
    )
    .await;

    let (_, by_title) = call(&app, "GET", "/api/books?page=1&q=dun", Some(&token), None).await;
    assert_eq!(titles(&by_title), ["Dune"]);
    assert_eq!(by_title["total"], 1, "the count reflects the filter too");

    let (_, by_author) = call(
        &app,
        "GET",
        "/api/books?page=1&q=herbert",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(titles(&by_author), ["Dune"]);

    let (_, by_publisher) = call(&app, "GET", "/api/books?page=1&q=ace", Some(&token), None).await;
    assert_eq!(titles(&by_publisher), ["Neuromancer"]);

    let (_, nothing) = call(
        &app,
        "GET",
        "/api/books?page=1&q=nothingmatches",
        Some(&token),
        None,
    )
    .await;
    assert!(titles(&nothing).is_empty());
    assert_eq!(nothing["total"], 0);
}

#[tokio::test]
async fn sorting_is_a_closed_set_and_always_deterministic() {
    let app = app(false).await;
    let token = master(&app).await;
    add(
        &app,
        &token,
        serde_json::json!({ "title": "Beta", "published_year": 1999 }),
    )
    .await;
    add(
        &app,
        &token,
        serde_json::json!({ "title": "Alpha", "published_year": 2020 }),
    )
    .await;

    let (_, default) = call(&app, "GET", "/api/books?page=1", Some(&token), None).await;
    assert_eq!(titles(&default), ["Alpha", "Beta"]);

    let (_, desc) = call(
        &app,
        "GET",
        "/api/books?page=1&sort=title&dir=desc",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(titles(&desc), ["Beta", "Alpha"]);

    // Newest year first when descending, and NULL years stay last either way.
    let (_, year) = call(
        &app,
        "GET",
        "/api/books?page=1&sort=year&dir=desc",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(titles(&year), ["Alpha", "Beta"]);
    let (_, year_asc) = call(
        &app,
        "GET",
        "/api/books?page=1&sort=year",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(titles(&year_asc), ["Beta", "Alpha"]);

    // An unknown sort key falls back to the default rather than reaching SQL —
    // this value arrives in a query string.
    let (status, bogus) = call(
        &app,
        "GET",
        "/api/books?page=1&sort=title;DROP+TABLE+book&dir=;--",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(titles(&bogus), ["Alpha", "Beta"]);
}

#[tokio::test]
async fn filters_narrow_by_tag_and_by_what_is_missing() {
    let app = app(false).await;
    let token = master(&app).await;
    let tagged = add(&app, &token, serde_json::json!({ "title": "Tagged" })).await;
    add(
        &app,
        &token,
        serde_json::json!({ "title": "Untagged", "published_year": 1990 }),
    )
    .await;

    let (_, group) = call(
        &app,
        "POST",
        "/api/groups",
        Some(&token),
        Some(serde_json::json!({ "name": "Favourites" })),
    )
    .await;
    let group_id = group["id"].as_str().unwrap();
    let (status, _) = call(
        &app,
        "POST",
        &format!("/api/groups/{group_id}/books"),
        Some(&token),
        Some(serde_json::json!({ "book_id": tagged })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (_, in_tag) = call(
        &app,
        "GET",
        &format!("/api/books?page=1&tag={group_id}"),
        Some(&token),
        None,
    )
    .await;
    assert_eq!(titles(&in_tag), ["Tagged"]);

    let (_, untagged) = call(
        &app,
        "GET",
        "/api/books?page=1&tag=untagged",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(titles(&untagged), ["Untagged"]);

    let (_, no_year) = call(
        &app,
        "GET",
        "/api/books?page=1&missing=year",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(titles(&no_year), ["Tagged"]);

    // Both books lack a file, so this narrows nothing — and must not error.
    let (_, no_file) = call(
        &app,
        "GET",
        "/api/books?page=1&missing=file",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(no_file["total"], 2);
}

#[tokio::test]
async fn a_filtered_page_still_pages() {
    let app = app(false).await;
    let token = master(&app).await;
    for i in 0..5 {
        add(
            &app,
            &token,
            serde_json::json!({ "title": format!("Match {i}") }),
        )
        .await;
    }
    add(&app, &token, serde_json::json!({ "title": "Other" })).await;

    let (_, first) = call(
        &app,
        "GET",
        "/api/books?page=1&limit=2&q=match",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(first["total"], 5, "total counts matches, not the page");
    assert_eq!(first["next"], 2);
    assert_eq!(titles(&first).len(), 2);

    let (_, last) = call(
        &app,
        "GET",
        "/api/books?page=3&limit=2&q=match",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(titles(&last).len(), 1);
    assert!(last["next"].is_null(), "the last page promises no next");
}

#[tokio::test]
async fn a_delta_pull_is_never_narrowed_by_console_filters() {
    // The trap: `?cursor=&q=…` must return the *whole* delta window. A pull
    // silently filtered by a stray query param loses rows forever, because the
    // cursor moves past them.
    let app = app(false).await;
    let token = master(&app).await;
    add(&app, &token, serde_json::json!({ "title": "Dune" })).await;
    add(&app, &token, serde_json::json!({ "title": "Emma" })).await;

    let (_, pull) = call(
        &app,
        "GET",
        "/api/books?cursor=&q=dune&tag=untagged&sort=year",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(pull["books"].as_array().unwrap().len(), 2);
}

// ---- the activity log -----------------------------------------------------

#[tokio::test]
async fn the_log_records_who_did_what_and_survives_the_target() {
    let app = app(true).await;
    let token = master(&app).await;
    let id = add(&app, &token, serde_json::json!({ "title": "Doomed" })).await;
    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/books/{id}"),
        Some(&token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (status, log) = call(&app, "GET", "/api/admin/audit", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(log["enabled"], true);
    let rows = log["rows"].as_array().unwrap();

    let deleted = rows
        .iter()
        .find(|r| r["action"] == "book.delete")
        .expect("a delete row");
    // The title is captured before the row goes — naming the book after it is
    // gone is the entire point of the log.
    assert_eq!(deleted["detail"], "Doomed");
    assert_eq!(deleted["target_id"], id);
    assert_eq!(deleted["actor_email"], "master@lib.test");
    assert!(rows.iter().any(|r| r["action"] == "book.create"));
    // Newest first, so the console shows what just happened.
    assert_eq!(rows[0]["action"], "book.delete");
}

#[tokio::test]
async fn the_log_can_be_filtered_by_action_and_actor() {
    let app = app(true).await;
    let token = master(&app).await;
    add(&app, &token, serde_json::json!({ "title": "One" })).await;
    add(&app, &token, serde_json::json!({ "title": "Two" })).await;
    call(
        &app,
        "POST",
        "/api/users",
        Some(&token),
        Some(serde_json::json!({
            "email": "other@lib.test",
            "password": "another good passphrase",
            "display_name": "Other",
        })),
    )
    .await;

    let (_, creates) = call(
        &app,
        "GET",
        "/api/admin/audit?action=book.create",
        Some(&token),
        None,
    )
    .await;
    let rows = creates["rows"].as_array().unwrap();
    assert_eq!(rows.len(), 2);
    assert!(rows.iter().all(|r| r["action"] == "book.create"));

    // A prefix narrows to a family of actions.
    let (_, books) = call(
        &app,
        "GET",
        "/api/admin/audit?action=book.",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(books["rows"].as_array().unwrap().len(), 2);

    let (_, by_actor) = call(
        &app,
        "GET",
        "/api/admin/audit?actor=master@lib.test",
        Some(&token),
        None,
    )
    .await;
    assert!(by_actor["rows"].as_array().unwrap().len() >= 3);

    let (_, nobody) = call(
        &app,
        "GET",
        "/api/admin/audit?actor=ghost@lib.test",
        Some(&token),
        None,
    )
    .await;
    assert!(nobody["rows"].as_array().unwrap().is_empty());
}

#[tokio::test]
async fn the_log_is_master_only() {
    let app = app(true).await;
    let token = master(&app).await;
    let (status, _) = call(
        &app,
        "POST",
        "/api/users",
        Some(&token),
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

    let (status, _) = call(&app, "GET", "/api/admin/audit", Some(other), None).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn with_the_log_off_nothing_is_written_and_the_endpoint_says_so() {
    let app = app(false).await;
    let token = master(&app).await;
    add(&app, &token, serde_json::json!({ "title": "Quiet" })).await;

    let (status, log) = call(&app, "GET", "/api/admin/audit", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(log["enabled"], false);
    assert!(log["rows"].as_array().unwrap().is_empty());
}

#[tokio::test]
async fn the_log_pages_backwards_by_id() {
    // Keyset, not offset: the trim runs underneath a reader, and an offset
    // would silently skip rows as older ones vanish.
    let app = app(true).await;
    let token = master(&app).await;
    for i in 0..5 {
        add(
            &app,
            &token,
            serde_json::json!({ "title": format!("B{i}") }),
        )
        .await;
    }

    let (_, first) = call(&app, "GET", "/api/admin/audit?limit=2", Some(&token), None).await;
    let rows = first["rows"].as_array().unwrap();
    assert_eq!(rows.len(), 2);
    let before = first["next_before"].as_i64().expect("more to read");

    let (_, second) = call(
        &app,
        "GET",
        &format!("/api/admin/audit?limit=2&before={before}"),
        Some(&token),
        None,
    )
    .await;
    let next_rows = second["rows"].as_array().unwrap();
    assert_eq!(next_rows.len(), 2);
    assert!(
        next_rows[0]["id"].as_i64().unwrap() < before,
        "the second page is strictly older"
    );
}
