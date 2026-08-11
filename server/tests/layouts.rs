//! Publishing physical room layouts (plan 5 #47).
//!
//! The two things worth pinning: a **409 on a stale base revision** (a room is
//! one arrangement, and silently overwriting somebody's is the failure this
//! design exists to prevent), and that a room is invisible to anyone it hasn't
//! been shared with.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use tower::ServiceExt;
use vellum_server::{AppState, EventBus, RateLimiter, connect_db, router};

async fn app() -> axum::Router {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_layout_{id}.db"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    router(AppState {
        db,
        public_base_url: "http://test.local".into(),
        data_dir: std::env::temp_dir().join(format!("vellum_layout_data_{id}")),
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

async fn register(app: &axum::Router, email: &str) -> String {
    let (_, body) = call(
        app,
        "POST",
        "/api/auth/register",
        None,
        Some(serde_json::json!({
            "email": email,
            "password": "a long enough passphrase",
            "display_name": "M",
        })),
    )
    .await;
    body["token"].as_str().unwrap().to_string()
}

/// A second, ordinary account.
async fn member(app: &axum::Router, master: &str, email: &str) -> String {
    let (status, _) = call(
        app,
        "POST",
        "/api/users",
        Some(master),
        Some(serde_json::json!({
            "email": email,
            "password": "another good passphrase",
            "display_name": "Other",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, login) = call(
        app,
        "POST",
        "/api/auth/login",
        None,
        Some(serde_json::json!({
            "email": email,
            "password": "another good passphrase",
        })),
    )
    .await;
    login["token"].as_str().unwrap().to_string()
}

fn doc(name: &str, shelves: usize) -> serde_json::Value {
    serde_json::json!({
        "doc": "vellum.layout",
        "version": 1,
        "environment": { "id": "room-1", "name": name },
        "shelves": (0..shelves).map(|i| serde_json::json!({
            "id": format!("shelf-{i}"),
            "x1": 0.0, "y1": 1.0 + i as f64 * 0.4,
            "x2": 2.0, "y2": 1.0 + i as f64 * 0.4,
        })).collect::<Vec<_>>(),
        "placements": [],
    })
}

#[tokio::test]
async fn a_room_round_trips_and_starts_at_revision_one() {
    let app = app().await;
    let token = register(&app, "m@lib.test").await;

    let (status, published) = call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&token),
        Some(serde_json::json!({
            "name": "Living room",
            "base_revision": 0,
            "doc": doc("Living room", 2),
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(published["revision"], 1);
    assert_eq!(published["mine"], true);

    let (status, fetched) = call(&app, "GET", "/api/layouts/room-1", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(fetched["name"], "Living room");
    // The document comes back as an object, not a string containing one.
    assert_eq!(fetched["doc"]["shelves"].as_array().unwrap().len(), 2);
    assert_eq!(fetched["doc"]["environment"]["name"], "Living room");

    let (_, list) = call(&app, "GET", "/api/layouts", Some(&token), None).await;
    assert_eq!(list.as_array().unwrap().len(), 1);
}

#[tokio::test]
async fn a_stale_publish_is_refused_rather_than_overwriting() {
    // The whole point of the revision: two devices that each rearranged the
    // room have no merge, so the second one must be told rather than win.
    let app = app().await;
    let token = register(&app, "m@lib.test").await;
    call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&token),
        Some(serde_json::json!({ "name": "R", "base_revision": 0, "doc": doc("R", 1) })),
    )
    .await;
    // Another device publishes on top.
    let (status, _) = call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&token),
        Some(serde_json::json!({ "name": "R", "base_revision": 1, "doc": doc("R", 3) })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    // This device still thinks it is at revision 1.
    let (status, body) = call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&token),
        Some(serde_json::json!({ "name": "R", "base_revision": 1, "doc": doc("R", 9) })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);
    assert!(
        body["error"].as_str().unwrap().contains("another device"),
        "the message should say what happened: {body}"
    );

    // And the stored room is still the *other* device's, untouched.
    let (_, fetched) = call(&app, "GET", "/api/layouts/room-1", Some(&token), None).await;
    assert_eq!(fetched["revision"], 2);
    assert_eq!(fetched["doc"]["shelves"].as_array().unwrap().len(), 3);

    // Republishing from the current revision succeeds.
    let (status, ok) = call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&token),
        Some(serde_json::json!({ "name": "R", "base_revision": 2, "doc": doc("R", 9) })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(ok["revision"], 3);
}

#[tokio::test]
async fn a_room_is_invisible_until_it_is_shared() {
    let app = app().await;
    let owner = register(&app, "owner@lib.test").await;
    let other = member(&app, &owner, "other@lib.test").await;
    call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&owner),
        Some(serde_json::json!({ "name": "Study", "base_revision": 0, "doc": doc("Study", 1) })),
    )
    .await;

    // 404, not 403 — the reader must not become an existence oracle.
    let (status, _) = call(&app, "GET", "/api/layouts/room-1", Some(&other), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (_, list) = call(&app, "GET", "/api/layouts", Some(&other), None).await;
    assert!(list.as_array().unwrap().is_empty());

    let (status, shared_body) = call(
        &app,
        "POST",
        "/api/shares",
        Some(&owner),
        Some(serde_json::json!({
            "grantee_email": "other@lib.test",
            "scope": "layout",
            "scope_id": "room-1",
            "permission": "viewer",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{shared_body}");

    let (status, fetched) = call(&app, "GET", "/api/layouts/room-1", Some(&other), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(fetched["name"], "Study");
    // Shared, but not theirs — so a client offers Fetch and not Publish.
    assert_eq!(fetched["mine"], false);
}

#[tokio::test]
async fn a_shared_viewer_cannot_publish_over_the_owners_room() {
    let app = app().await;
    let owner = register(&app, "owner@lib.test").await;
    let other = member(&app, &owner, "other@lib.test").await;
    call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&owner),
        Some(serde_json::json!({ "name": "Study", "base_revision": 0, "doc": doc("Study", 1) })),
    )
    .await;
    call(
        &app,
        "POST",
        "/api/shares",
        Some(&owner),
        Some(serde_json::json!({
            "grantee_email": "other@lib.test",
            "scope": "layout",
            "scope_id": "room-1",
            "permission": "viewer",
        })),
    )
    .await;

    let (status, _) = call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&other),
        Some(serde_json::json!({ "name": "Mine now", "base_revision": 1, "doc": doc("x", 1) })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (_, fetched) = call(&app, "GET", "/api/layouts/room-1", Some(&owner), None).await;
    assert_eq!(fetched["name"], "Study");
}

#[tokio::test]
async fn a_room_can_only_be_shared_for_viewing() {
    // `editor` would mean two people dragging the same shelf, which the
    // document model has no answer for beyond the 409 the publisher sees.
    let app = app().await;
    let owner = register(&app, "owner@lib.test").await;
    member(&app, &owner, "other@lib.test").await;
    call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&owner),
        Some(serde_json::json!({ "name": "Study", "base_revision": 0, "doc": doc("Study", 1) })),
    )
    .await;

    let (status, body) = call(
        &app,
        "POST",
        "/api/shares",
        Some(&owner),
        Some(serde_json::json!({
            "grantee_email": "other@lib.test",
            "scope": "layout",
            "scope_id": "room-1",
            "permission": "editor",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(body["error"].as_str().unwrap().contains("viewing"));
}

#[tokio::test]
async fn an_oversized_or_malformed_document_is_refused() {
    let app = app().await;
    let token = register(&app, "m@lib.test").await;

    // Not an object: nothing could render it.
    let (status, _) = call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&token),
        Some(serde_json::json!({ "name": "R", "base_revision": 0, "doc": "just a string" })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    // Over the cap.
    let huge = serde_json::json!({
        "doc": "vellum.layout",
        "version": 1,
        "environment": { "id": "room-1", "name": "R" },
        "filler": "x".repeat(600 * 1024),
    });
    let (status, body) = call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&token),
        Some(serde_json::json!({ "name": "R", "base_revision": 0, "doc": huge })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(body["error"].as_str().unwrap().contains("too large"));

    // A blank name.
    let (status, _) = call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&token),
        Some(serde_json::json!({ "name": "  ", "base_revision": 0, "doc": doc("R", 1) })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn deleting_a_room_takes_its_shares_with_it() {
    // A share pointing at a room that no longer exists is a dead entry in
    // someone else's list.
    let app = app().await;
    let owner = register(&app, "owner@lib.test").await;
    let other = member(&app, &owner, "other@lib.test").await;
    call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&owner),
        Some(serde_json::json!({ "name": "Study", "base_revision": 0, "doc": doc("Study", 1) })),
    )
    .await;
    call(
        &app,
        "POST",
        "/api/shares",
        Some(&owner),
        Some(serde_json::json!({
            "grantee_email": "other@lib.test",
            "scope": "layout",
            "scope_id": "room-1",
            "permission": "viewer",
        })),
    )
    .await;

    let (status, _) = call(&app, "DELETE", "/api/layouts/room-1", Some(&owner), None).await;
    assert_eq!(status, StatusCode::OK);

    let (_, shares) = call(&app, "GET", "/api/shares", Some(&other), None).await;
    assert!(shares.as_array().unwrap().is_empty());
    let (status, _) = call(&app, "GET", "/api/layouts/room-1", Some(&owner), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn only_the_owner_may_delete() {
    let app = app().await;
    let owner = register(&app, "owner@lib.test").await;
    let other = member(&app, &owner, "other@lib.test").await;
    call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&owner),
        Some(serde_json::json!({ "name": "Study", "base_revision": 0, "doc": doc("Study", 1) })),
    )
    .await;

    let (status, _) = call(&app, "DELETE", "/api/layouts/room-1", Some(&other), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
    let (status, _) = call(&app, "GET", "/api/layouts/room-1", Some(&owner), None).await;
    assert_eq!(status, StatusCode::OK);
}

#[tokio::test]
async fn layouts_are_advertised_as_a_capability() {
    let app = app().await;
    let (_, caps) = call(&app, "GET", "/api/capabilities", None, None).await;
    assert!(
        caps["features"]
            .as_array()
            .unwrap()
            .iter()
            .any(|f| f == "layouts")
    );
}

// ---- the room view and public room links (plan 5 #48) --------------------

/// A book owned by `token`, returned as its id.
async fn book(app: &axum::Router, token: &str, title: &str) -> String {
    let (status, created) = call(
        app,
        "POST",
        "/api/books",
        Some(token),
        Some(serde_json::json!({ "title": title })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    created["id"].as_str().unwrap().to_string()
}

fn doc_with(books: &[&str]) -> serde_json::Value {
    serde_json::json!({
        "doc": "vellum.layout",
        "version": 1,
        "environment": { "id": "room-1", "name": "Living room" },
        "shelves": [{ "id": "s1", "x1": 0.0, "y1": 1.0, "x2": 2.0, "y2": 1.0 }],
        "placements": books.iter().enumerate().map(|(i, b)| serde_json::json!({
            "id": format!("p{i}"),
            "copy_id": format!("c{i}"),
            "book_id": b,
            "x": 0.1 * i as f64,
            "y": 1.0,
            "rotation": 0,
            "width_m": 0.02,
            "height_m": 0.2,
        })).collect::<Vec<_>>(),
    })
}

#[tokio::test]
async fn the_room_view_names_only_the_books_the_viewer_may_see() {
    // The redaction property, end to end: geometry for every placement,
    // metadata for exactly the visible books.
    let app = app().await;
    let owner = register(&app, "owner@lib.test").await;
    let other = member(&app, &owner, "other@lib.test").await;
    let shared = book(&app, &owner, "Shared book").await;
    let private = book(&app, &owner, "Private book").await;

    call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&owner),
        Some(serde_json::json!({
            "name": "Living room",
            "base_revision": 0,
            "doc": doc_with(&[&shared, &private]),
        })),
    )
    .await;
    for (scope, scope_id) in [("layout", "room-1"), ("book", shared.as_str())] {
        let (status, _) = call(
            &app,
            "POST",
            "/api/shares",
            Some(&owner),
            Some(serde_json::json!({
                "grantee_email": "other@lib.test",
                "scope": scope,
                "scope_id": scope_id,
                "permission": "viewer",
            })),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
    }

    // The owner sees both.
    let (status, mine) = call(&app, "GET", "/api/layouts/room-1/books", Some(&owner), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(mine.as_array().unwrap().len(), 2);

    // The viewer sees the room's full geometry...
    let (_, room) = call(&app, "GET", "/api/layouts/room-1", Some(&other), None).await;
    assert_eq!(room["doc"]["placements"].as_array().unwrap().len(), 2);
    // ...but only the one book they were given.
    let (_, theirs) = call(&app, "GET", "/api/layouts/room-1/books", Some(&other), None).await;
    let names: Vec<&str> = theirs
        .as_array()
        .unwrap()
        .iter()
        .map(|b| b["title"].as_str().unwrap())
        .collect();
    assert_eq!(names, ["Shared book"]);
    // And the document itself never carried the other title at all.
    assert!(!room.to_string().contains("Private book"));
}

#[tokio::test]
async fn a_stranger_cannot_read_a_rooms_book_list() {
    let app = app().await;
    let owner = register(&app, "owner@lib.test").await;
    let other = member(&app, &owner, "other@lib.test").await;
    let b = book(&app, &owner, "Secret").await;
    call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&owner),
        Some(serde_json::json!({
            "name": "R", "base_revision": 0, "doc": doc_with(&[&b]),
        })),
    )
    .await;

    let (status, _) = call(&app, "GET", "/api/layouts/room-1/books", Some(&other), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn a_public_room_link_shows_shapes_and_by_default_no_titles() {
    let app = app().await;
    let owner = register(&app, "owner@lib.test").await;
    let b = book(&app, &owner, "On the shelf").await;
    call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&owner),
        Some(serde_json::json!({
            "name": "Living room", "base_revision": 0, "doc": doc_with(&[&b]),
        })),
    )
    .await;

    let (status, link) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&owner),
        Some(serde_json::json!({ "kind": "layout", "layout_id": "room-1" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(link["book_id"].is_null());
    assert_eq!(link["layout_id"], "room-1");
    let token = link["url"]
        .as_str()
        .unwrap()
        .rsplit('/')
        .next()
        .unwrap()
        .to_string();

    let (status, room) = call(
        &app,
        "GET",
        &format!("/api/public/{token}/room"),
        None,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(room["name"], "Living room");
    assert_eq!(room["doc"]["placements"].as_array().unwrap().len(), 1);
    // Off by default: tagging books to share with a person must not publish
    // their titles to anyone holding a URL.
    assert!(room["books"].as_array().unwrap().is_empty());
    assert!(!room.to_string().contains("On the shelf"));
}

#[tokio::test]
async fn a_public_room_link_can_name_the_books_in_the_rooms_tag() {
    let app = app().await;
    let owner = register(&app, "owner@lib.test").await;
    let tagged = book(&app, &owner, "Named book").await;
    let untagged = book(&app, &owner, "Unnamed book").await;
    call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&owner),
        Some(serde_json::json!({
            "name": "Living room",
            "base_revision": 0,
            "doc": doc_with(&[&tagged, &untagged]),
        })),
    )
    .await;

    // The `Room: <name>` tag the app's publish flow creates.
    let (_, group) = call(
        &app,
        "POST",
        "/api/groups",
        Some(&owner),
        Some(serde_json::json!({ "name": "Room: Living room" })),
    )
    .await;
    let group_id = group["id"].as_str().unwrap();
    call(
        &app,
        "POST",
        &format!("/api/groups/{group_id}/books"),
        Some(&owner),
        Some(serde_json::json!({ "book_id": tagged })),
    )
    .await;

    let (_, link) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&owner),
        Some(serde_json::json!({
            "kind": "layout", "layout_id": "room-1", "show_books": true,
        })),
    )
    .await;
    let token = link["url"]
        .as_str()
        .unwrap()
        .rsplit('/')
        .next()
        .unwrap()
        .to_string();

    let (_, room) = call(
        &app,
        "GET",
        &format!("/api/public/{token}/room"),
        None,
        None,
    )
    .await;
    let titles: Vec<&str> = room["books"]
        .as_array()
        .unwrap()
        .iter()
        .map(|b| b["title"].as_str().unwrap())
        .collect();
    // Exactly the tag's contents — the other book stays a blank spine even
    // though it is in the same room.
    assert_eq!(titles, ["Named book"]);
    assert!(!room.to_string().contains("Unnamed book"));
}

#[tokio::test]
async fn a_revoked_or_expired_room_link_shows_nothing() {
    let app = app().await;
    let owner = register(&app, "owner@lib.test").await;
    let b = book(&app, &owner, "Book").await;
    call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&owner),
        Some(serde_json::json!({
            "name": "R", "base_revision": 0, "doc": doc_with(&[&b]),
        })),
    )
    .await;
    let (_, link) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&owner),
        Some(serde_json::json!({ "kind": "layout", "layout_id": "room-1" })),
    )
    .await;
    let token = link["url"]
        .as_str()
        .unwrap()
        .rsplit('/')
        .next()
        .unwrap()
        .to_string();
    let id = link["id"].as_str().unwrap();

    let (status, _) = call(
        &app,
        "GET",
        &format!("/api/public/{token}/room"),
        None,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/share-links/{id}"),
        Some(&owner),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (status, _) = call(
        &app,
        "GET",
        &format!("/api/public/{token}/room"),
        None,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn a_book_link_is_not_a_room_link_and_the_reverse() {
    // The kinds must not be interchangeable: a book token must not open a room
    // endpoint, or the `show_books` decision could be bypassed entirely.
    let app = app().await;
    let owner = register(&app, "owner@lib.test").await;
    let b = book(&app, &owner, "Book").await;
    call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&owner),
        Some(serde_json::json!({
            "name": "R", "base_revision": 0, "doc": doc_with(&[&b]),
        })),
    )
    .await;

    let (_, book_link) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&owner),
        Some(serde_json::json!({ "book_id": b })),
    )
    .await;
    let book_token = book_link["url"]
        .as_str()
        .unwrap()
        .rsplit('/')
        .next()
        .unwrap();
    let (status, _) = call(
        &app,
        "GET",
        &format!("/api/public/{book_token}/room"),
        None,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (_, room_link) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&owner),
        Some(serde_json::json!({ "kind": "layout", "layout_id": "room-1" })),
    )
    .await;
    let room_token = room_link["url"]
        .as_str()
        .unwrap()
        .rsplit('/')
        .next()
        .unwrap();
    let (status, _) = call(
        &app,
        "GET",
        &format!("/api/public/{room_token}"),
        None,
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn a_room_link_needs_a_room_you_own() {
    let app = app().await;
    let owner = register(&app, "owner@lib.test").await;
    let other = member(&app, &owner, "other@lib.test").await;
    call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&owner),
        Some(serde_json::json!({ "name": "R", "base_revision": 0, "doc": doc("R", 1) })),
    )
    .await;

    let (status, _) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&other),
        Some(serde_json::json!({ "kind": "layout", "layout_id": "room-1" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    // And a link to nothing is refused before a token is minted.
    let (status, _) = call(
        &app,
        "POST",
        "/api/share-links",
        Some(&owner),
        Some(serde_json::json!({ "kind": "layout" })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn room_links_appear_in_the_link_list_so_they_can_be_revoked() {
    // An inner join on `book` would drop them, leaving a live link nobody can
    // find — which is how a "temporary" share becomes permanent.
    let app = app().await;
    let owner = register(&app, "owner@lib.test").await;
    call(
        &app,
        "PUT",
        "/api/layouts/room-1",
        Some(&owner),
        Some(serde_json::json!({ "name": "Living room", "base_revision": 0, "doc": doc("R", 1) })),
    )
    .await;
    call(
        &app,
        "POST",
        "/api/share-links",
        Some(&owner),
        Some(serde_json::json!({ "kind": "layout", "layout_id": "room-1" })),
    )
    .await;

    let (status, links) = call(&app, "GET", "/api/share-links", Some(&owner), None).await;
    assert_eq!(status, StatusCode::OK);
    let row = links.as_array().unwrap().first().expect("the room link");
    assert_eq!(row["kind"], "layout");
    assert_eq!(row["book_title"], "Living room");
}

#[tokio::test]
async fn the_room_page_is_served_for_both_shapes() {
    let app = app().await;
    for uri in ["/room/whatever", "/pr/sometoken", "/assets/room.js"] {
        let res = app
            .clone()
            .oneshot(Request::builder().uri(uri).body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(res.status(), StatusCode::OK, "{uri}");
    }
}
