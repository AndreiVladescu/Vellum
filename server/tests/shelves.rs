//! Personal shelves (migration 0029).
//!
//! Shelves sync, and until now everything that syncs was visible to whoever the
//! library was shared with — so a private arrangement ("books I mean to
//! reread") turned up in other people's chip rows next to the collections the
//! library genuinely shares. `personal = 1` separates the two: the shelf is
//! still the owner's on every device they use, but no share reaches it.
//!
//! The default matters as much as the flag. A client that predates this sends
//! no `personal` field, and its shelves have to stay public — quietly hiding
//! shelves that people can already see would be a change nobody asked for.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::json;
use tower::ServiceExt;
use vellum_server::{AppState, EventBus, RateLimiter, connect_db, router};

async fn app() -> axum::Router {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_shelves_{id}.db"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    router(AppState {
        db,
        public_base_url: "http://test.local".into(),
        data_dir: std::env::temp_dir().join(format!("vellum_shelves_data_{id}")),
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

/// The master (who owns the shelves) and a second account the whole library is
/// shared with — an all-scope share is the only kind that reaches shelves.
async fn two_people(app: &axum::Router) -> (String, String) {
    let (_, body) = call(
        app,
        "POST",
        "/api/auth/register",
        None,
        Some(json!({
            "email": "owner@lib.test",
            "password": "a long enough passphrase",
            "display_name": "Owner",
        })),
    )
    .await;
    let owner = body["token"].as_str().unwrap().to_string();

    let (status, _) = call(
        app,
        "POST",
        "/api/users",
        Some(&owner),
        Some(json!({
            "email": "friend@lib.test",
            "password": "another good passphrase",
            "display_name": "Friend",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "creating the second account");
    let (_, login) = call(
        app,
        "POST",
        "/api/auth/login",
        None,
        Some(json!({
            "email": "friend@lib.test",
            "password": "another good passphrase",
        })),
    )
    .await;
    let friend = login["token"].as_str().unwrap().to_string();

    let (status, body) = call(
        app,
        "POST",
        "/api/shares",
        Some(&owner),
        Some(json!({
            "scope": "all",
            "grantee_email": "friend@lib.test",
            "permission": "viewer",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "sharing the library: {body}");
    (owner, friend)
}

async fn put_shelf(
    app: &axum::Router,
    token: &str,
    id: &str,
    name: &str,
    body: serde_json::Value,
) -> serde_json::Value {
    let (status, got) = call(app, "PUT", &format!("/api/shelves/{id}"), Some(token), {
        let mut b = body;
        b["name"] = json!(name);
        Some(b)
    })
    .await;
    assert_eq!(status, StatusCode::OK, "creating shelf {name}: {got}");
    got
}

async fn shelf_names(app: &axum::Router, token: &str) -> Vec<String> {
    let (status, body) = call(app, "GET", "/api/shelves", Some(token), None).await;
    assert_eq!(status, StatusCode::OK);
    body.as_array()
        .unwrap()
        .iter()
        .map(|s| s["name"].as_str().unwrap().to_string())
        .collect()
}

#[tokio::test]
async fn a_personal_shelf_is_the_owners_alone() {
    let app = app().await;
    let (owner, friend) = two_people(&app).await;

    put_shelf(&app, &owner, "s-public", "Cookbooks", json!({})).await;
    put_shelf(&app, &owner, "s-mine", "Reread", json!({ "personal": true })).await;

    let mine = shelf_names(&app, &owner).await;
    assert!(mine.contains(&"Cookbooks".to_string()));
    assert!(
        mine.contains(&"Reread".to_string()),
        "a personal shelf is still the owner's on every device they use"
    );

    let theirs = shelf_names(&app, &friend).await;
    assert_eq!(
        theirs,
        vec!["Cookbooks".to_string()],
        "the whole library is shared, but not the shelf kept back from it"
    );
}

#[tokio::test]
async fn a_shelf_with_no_flag_is_public() {
    // The compatibility case: an app built before 0029 sends `{name, book_ids}`
    // and nothing else. Its shelves were shared when they were made, and they
    // stay shared.
    let app = app().await;
    let (owner, friend) = two_people(&app).await;
    put_shelf(&app, &owner, "s-old", "From an old client", json!({})).await;

    let created = call(&app, "GET", "/api/shelves", Some(&owner), None).await.1;
    assert_eq!(created[0]["personal"], false, "the flag is reported");
    assert_eq!(shelf_names(&app, &friend).await.len(), 1);
}

#[tokio::test]
async fn a_shelf_can_be_made_personal_later_and_public_again() {
    let app = app().await;
    let (owner, friend) = two_people(&app).await;
    put_shelf(&app, &owner, "s1", "Cookbooks", json!({})).await;
    assert_eq!(shelf_names(&app, &friend).await.len(), 1);

    // Withdrawing a shelf: it stops being visible without being deleted, so the
    // books on it are untouched and the owner keeps their arrangement.
    put_shelf(&app, &owner, "s1", "Cookbooks", json!({ "personal": true })).await;
    assert!(
        shelf_names(&app, &friend).await.is_empty(),
        "withdrawn from the share"
    );
    assert_eq!(shelf_names(&app, &owner).await.len(), 1, "still the owner's");

    put_shelf(&app, &owner, "s1", "Cookbooks", json!({ "personal": false })).await;
    assert_eq!(
        shelf_names(&app, &friend).await.len(),
        1,
        "and it can be shared again"
    );
}

#[tokio::test]
async fn flipping_only_the_flag_is_not_treated_as_a_no_op() {
    // Shelf upsert skips writes that would change nothing, comparing name,
    // order and membership. If `personal` were left out of that comparison,
    // making an existing shelf private would be silently discarded — the
    // failure mode is invisible, which is exactly why it is asserted.
    let app = app().await;
    let (owner, friend) = two_people(&app).await;
    put_shelf(&app, &owner, "s1", "Cookbooks", json!({})).await;
    put_shelf(&app, &owner, "s1", "Cookbooks", json!({ "personal": true })).await;
    assert!(shelf_names(&app, &friend).await.is_empty());
}
