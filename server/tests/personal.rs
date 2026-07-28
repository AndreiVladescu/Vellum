//! Personal data: annotations, sittings, private notes, profile.
//!
//! The property under test throughout is **isolation**. These tables live in a
//! library that can be shared, so the failure that matters is not "sync is
//! slow" — it is one account reading another's highlights or private notes
//! about a book they both have access to. Every list here is filtered by the
//! token's user id, and these tests are what says so.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{Value, json};
use tower::ServiceExt;
use vellum_server::{AppState, connect_db, router};

async fn test_app() -> axum::Router {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_personal_{id}.db"));
    let data_dir = std::env::temp_dir().join(format!("vellum_personal_data_{id}"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    router(AppState {
        db,
        public_base_url: "http://test.local".into(),
        data_dir,
        http: reqwest::Client::new(),
        max_upload_bytes: 64 * 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(2)),
        basic_cache: std::sync::Arc::default(),
        public_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            600,
            std::time::Duration::from_secs(60),
        )),
        search_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            600,
            std::time::Duration::from_secs(60),
        )),
        send_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            600,
            std::time::Duration::from_secs(60),
        )),
        events: vellum_server::EventBus::new(),
        mailer: None,
        index_text: false,
        audit: true,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    })
}

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
    let value = serde_json::from_slice(&bytes).unwrap_or(Value::Null);
    (status, value)
}

/// Raw bytes in, status + parsed body out — for the avatar upload.
async fn call_bytes(
    app: &axum::Router,
    method: &str,
    uri: &str,
    token: &str,
    body: Vec<u8>,
) -> (StatusCode, Value) {
    let request = Request::builder()
        .method(method)
        .uri(uri)
        .header("authorization", format!("Bearer {token}"))
        .header("content-type", "application/octet-stream")
        .body(Body::from(body))
        .unwrap();
    let response = app.clone().oneshot(request).await.unwrap();
    let status = response.status();
    let bytes = axum::body::to_bytes(response.into_body(), usize::MAX)
        .await
        .unwrap();
    (status, serde_json::from_slice(&bytes).unwrap_or(Value::Null))
}

async fn register(app: &axum::Router, email: &str) -> String {
    let (status, body) = call(
        app,
        "POST",
        "/api/auth/register",
        None,
        Some(json!({ "email": email, "display_name": "Someone", "password": "goodpassword1" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "register {email}: {body}");
    body["token"].as_str().unwrap().to_string()
}

async fn add_member(app: &axum::Router, master: &str, email: &str) -> String {
    let (status, body) = call(
        app,
        "POST",
        "/api/users",
        Some(master),
        Some(json!({ "email": email, "display_name": "Member", "password": "goodpassword1" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "create {email}: {body}");
    let (status, body) = call(
        app,
        "POST",
        "/api/auth/login",
        None,
        Some(json!({ "email": email, "password": "goodpassword1" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "login {email}: {body}");
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
    assert_eq!(status, StatusCode::OK, "create book: {body}");
    body["id"].as_str().unwrap().to_string()
}

/// A minimal valid PNG, so the avatar's magic-byte check has something real.
fn png() -> Vec<u8> {
    let mut bytes = vec![0x89, b'P', b'N', b'G', 0x0D, 0x0A, 0x1A, 0x0A];
    bytes.extend_from_slice(&[0u8; 32]);
    bytes
}

fn entries(body: &Value) -> &Vec<Value> {
    body["entries"].as_array().unwrap()
}

// ---- annotations ----------------------------------------------------------

#[tokio::test]
async fn annotations_round_trip_and_carry_their_fields() {
    let app = test_app().await;
    let token = register(&app, "solo@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;

    let (status, body) = call(
        &app,
        "PUT",
        "/api/annotations/a1",
        Some(&token),
        Some(json!({
            "book_id": book,
            "kind": "highlight",
            "page": 42,
            "locator": "{\"v\":1}",
            "quoted_text": "the spice must flow",
            "color": 42949557i64,
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "upsert: {body}");

    let (status, body) = call(&app, "GET", "/api/annotations?cursor=", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    let list = entries(&body);
    assert_eq!(list.len(), 1);
    assert_eq!(list[0]["quoted_text"], "the spice must flow");
    assert_eq!(list[0]["page"], 42);
    assert_eq!(list[0]["color"], 42949557i64);
}

#[tokio::test]
async fn one_users_annotations_are_invisible_to_another_who_shares_the_book() {
    // The whole reason this module is scoped by user: a shared library holds
    // several people's highlights in the same book.
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let friend = add_member(&app, &master, "friend@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;
    let (status, body) = call(
        &app,
        "POST",
        "/api/shares",
        Some(&master),
        Some(json!({
            "scope": "book", "scope_id": book,
            "grantee_email": "friend@lib.test", "permission": "viewer"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "share: {body}");

    call(
        &app,
        "PUT",
        "/api/annotations/mine",
        Some(&master),
        Some(json!({ "book_id": book, "kind": "highlight", "quoted_text": "secret" })),
    )
    .await;

    // The friend can read the book, and sees none of the master's marks.
    let (_, body) = call(&app, "GET", "/api/annotations?cursor=", Some(&friend), None).await;
    assert!(entries(&body).is_empty(), "leaked: {body}");

    // Their own highlight in the same book is fine — view access is enough.
    let (status, body) = call(
        &app,
        "PUT",
        "/api/annotations/theirs",
        Some(&friend),
        Some(json!({ "book_id": book, "kind": "highlight", "quoted_text": "mine" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "viewer may annotate: {body}");

    let (_, body) = call(&app, "GET", "/api/annotations?cursor=", Some(&friend), None).await;
    assert_eq!(entries(&body).len(), 1);
    assert_eq!(entries(&body)[0]["quoted_text"], "mine");
}

#[tokio::test]
async fn another_account_cannot_take_over_an_annotation_by_id() {
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let friend = add_member(&app, &master, "friend@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;
    call(
        &app,
        "POST",
        "/api/shares",
        Some(&master),
        Some(json!({
            "scope": "book", "scope_id": book,
            "grantee_email": "friend@lib.test", "permission": "editor"
        })),
    )
    .await;
    call(
        &app,
        "PUT",
        "/api/annotations/shared-id",
        Some(&master),
        Some(json!({ "book_id": book, "kind": "highlight", "quoted_text": "original" })),
    )
    .await;

    // Even an editor guessing the id cannot overwrite it — the row is not theirs.
    let (status, _) = call(
        &app,
        "PUT",
        "/api/annotations/shared-id",
        Some(&friend),
        Some(json!({ "book_id": book, "kind": "highlight", "quoted_text": "hijacked" })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let (_, body) = call(&app, "GET", "/api/annotations?cursor=", Some(&master), None).await;
    assert_eq!(entries(&body)[0]["quoted_text"], "original");
}

#[tokio::test]
async fn deleting_an_annotation_leaves_a_tombstone_for_the_other_devices() {
    let app = test_app().await;
    let token = register(&app, "solo@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    call(
        &app,
        "PUT",
        "/api/annotations/a1",
        Some(&token),
        Some(json!({ "book_id": book, "kind": "bookmark", "page": 7 })),
    )
    .await;

    let (status, _) = call(&app, "DELETE", "/api/annotations/a1", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);

    let (_, body) = call(&app, "GET", "/api/annotations?cursor=", Some(&token), None).await;
    assert!(entries(&body).is_empty());

    // Without the tombstone the other device would push it straight back.
    let (status, body) = call(
        &app,
        "GET",
        "/api/annotations/deletions?cursor=",
        Some(&token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        entries(&body).iter().any(|d| d["id"] == "a1"),
        "no annotation tombstone: {body}"
    );
}

#[tokio::test]
async fn annotation_tombstones_stay_out_of_the_shared_deletions_list() {
    // Plan 6 #3, finding P1. `/deletions` is unscoped on purpose — a deleted
    // book is a library-wide fact — so an annotation tombstone sitting in it
    // handed every authenticated account the ids and timings of every other
    // account's deletions.
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let stranger = add_member(&app, &master, "stranger@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;
    call(
        &app,
        "PUT",
        "/api/annotations/secret-note",
        Some(&master),
        Some(json!({ "book_id": book, "kind": "highlight" })),
    )
    .await;
    call(
        &app,
        "DELETE",
        "/api/annotations/secret-note",
        Some(&master),
        None,
    )
    .await;

    let (status, body) = call(&app, "GET", "/api/deletions", Some(&stranger), None).await;
    assert_eq!(status, StatusCode::OK);
    let all = body.as_array().unwrap();
    assert!(
        !all.iter().any(|d| d["book_id"] == "secret-note"),
        "leaked another account's annotation deletion: {body}"
    );
    assert!(
        !all.iter().any(|d| d["kind"] == "annotation"),
        "no annotation tombstone belongs in this list: {body}"
    );

    // Book tombstones still travel, which is what the list is for.
    call(&app, "DELETE", &format!("/api/books/{book}"), Some(&master), None).await;
    let (_, body) = call(&app, "GET", "/api/deletions", Some(&stranger), None).await;
    assert!(
        body.as_array().unwrap().iter().any(|d| d["book_id"] == book),
        "book deletions must still propagate: {body}"
    );
}

#[tokio::test]
async fn an_oversized_avatar_is_refused_in_words() {
    // Plan 6 #3, finding P2. axum's 2 MB default rejected a 3 MB upload before
    // `put_avatar`'s own 4 MB check could, with "Failed to buffer the request
    // body" — a limit that disagreed with the documented one and an error that
    // mentioned neither avatars nor a size.
    let app = test_app().await;
    let token = register(&app, "solo@lib.test").await;

    let mut big = png();
    big.resize(3 * 1024 * 1024, 0);
    let (status, body) = call_bytes(&app, "PUT", "/api/profile/avatar", &token, big).await;
    assert_eq!(status, StatusCode::OK, "3 MB is under the stated cap: {body}");

    let mut too_big = png();
    too_big.resize(5 * 1024 * 1024, 0);
    let (status, _) = call_bytes(&app, "PUT", "/api/profile/avatar", &token, too_big).await;
    assert_eq!(
        status,
        StatusCode::PAYLOAD_TOO_LARGE,
        "and past it the body limit stops it before anything is read"
    );
}

#[tokio::test]
async fn my_deletions_are_not_another_accounts_business() {
    // The shared /deletions list is unscoped by design — a deleted book is a
    // library-wide fact. A deleted highlight is not.
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let friend = add_member(&app, &master, "friend@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;
    call(
        &app,
        "PUT",
        "/api/annotations/a1",
        Some(&master),
        Some(json!({ "book_id": book, "kind": "highlight" })),
    )
    .await;
    call(&app, "DELETE", "/api/annotations/a1", Some(&master), None).await;

    let (_, body) = call(
        &app,
        "GET",
        "/api/annotations/deletions?cursor=",
        Some(&friend),
        None,
    )
    .await;
    assert!(entries(&body).is_empty(), "leaked a deletion: {body}");
}

#[tokio::test]
async fn an_older_edit_does_not_overwrite_a_newer_one() {
    let app = test_app().await;
    let token = register(&app, "solo@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    call(
        &app,
        "PUT",
        "/api/annotations/a1",
        Some(&token),
        Some(json!({
            "book_id": book, "kind": "note", "note": "newer",
            "updated_at": "2026-07-20 10:00:00"
        })),
    )
    .await;
    // A device that was offline pushes an edit it made yesterday.
    call(
        &app,
        "PUT",
        "/api/annotations/a1",
        Some(&token),
        Some(json!({
            "book_id": book, "kind": "note", "note": "older",
            "updated_at": "2026-07-19 10:00:00"
        })),
    )
    .await;

    let (_, body) = call(&app, "GET", "/api/annotations?cursor=", Some(&token), None).await;
    assert_eq!(entries(&body)[0]["note"], "newer");
}

#[tokio::test]
async fn an_annotation_needs_a_book_the_caller_can_see() {
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let stranger = add_member(&app, &master, "stranger@lib.test").await;
    let book = create_book(&app, &master, "Private").await;

    let (status, _) = call(
        &app,
        "PUT",
        "/api/annotations/x",
        Some(&stranger),
        Some(json!({ "book_id": book, "kind": "highlight" })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND, "and not FORBIDDEN, which would confirm the id exists");
}

// ---- sessions -------------------------------------------------------------

#[tokio::test]
async fn sessions_merge_as_a_union_and_re_pushing_one_is_idempotent() {
    // The property that makes statistics safe to sync: a sitting is a fact, so
    // the same fact arriving twice is not a second row.
    let app = test_app().await;
    let token = register(&app, "solo@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    let payload = json!({
        "book_id": book,
        "device_id": "phone",
        "device_label": "Phone",
        "started_at": "2026-07-20 20:00:00",
        "ended_at": "2026-07-20 20:45:00",
        "start_page": 10, "end_page": 32
    });

    for _ in 0..3 {
        let (status, body) = call(
            &app,
            "PUT",
            "/api/sessions/s1",
            Some(&token),
            Some(payload.clone()),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{body}");
    }

    let (_, body) = call(&app, "GET", "/api/sessions?cursor=", Some(&token), None).await;
    assert_eq!(entries(&body).len(), 1, "re-push made a duplicate: {body}");
    assert_eq!(entries(&body)[0]["device_label"], "Phone");
    assert_eq!(entries(&body)[0]["end_page"], 32);
}

#[tokio::test]
async fn sessions_from_several_devices_all_survive() {
    let app = test_app().await;
    let token = register(&app, "solo@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    for (id, device) in [("s1", "phone"), ("s2", "laptop"), ("s3", "pc")] {
        call(
            &app,
            "PUT",
            &format!("/api/sessions/{id}"),
            Some(&token),
            Some(json!({
                "book_id": book, "device_id": device,
                "started_at": "2026-07-20 20:00:00", "ended_at": "2026-07-20 20:45:00"
            })),
        )
        .await;
    }
    let (_, body) = call(&app, "GET", "/api/sessions?cursor=", Some(&token), None).await;
    assert_eq!(entries(&body).len(), 3, "statistics span devices");
}

#[tokio::test]
async fn one_users_sessions_are_invisible_to_another() {
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let friend = add_member(&app, &master, "friend@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;
    call(
        &app,
        "POST",
        "/api/shares",
        Some(&master),
        Some(json!({
            "scope": "book", "scope_id": book,
            "grantee_email": "friend@lib.test", "permission": "viewer"
        })),
    )
    .await;
    call(
        &app,
        "PUT",
        "/api/sessions/s1",
        Some(&master),
        Some(json!({
            "book_id": book,
            "started_at": "2026-07-20 20:00:00", "ended_at": "2026-07-20 20:45:00"
        })),
    )
    .await;

    let (_, body) = call(&app, "GET", "/api/sessions?cursor=", Some(&friend), None).await;
    assert!(entries(&body).is_empty(), "reading habits leaked: {body}");
}

// ---- private notes --------------------------------------------------------

#[tokio::test]
async fn a_private_note_is_per_user_even_on_a_shared_book() {
    // The reason this is its own table rather than a column on `book`.
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let friend = add_member(&app, &master, "friend@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;
    call(
        &app,
        "POST",
        "/api/shares",
        Some(&master),
        Some(json!({
            "scope": "book", "scope_id": book,
            "grantee_email": "friend@lib.test", "permission": "editor"
        })),
    )
    .await;

    for (token, note) in [(&master, "mine"), (&friend, "theirs")] {
        let (status, body) = call(
            &app,
            "PUT",
            &format!("/api/notes/{book}"),
            Some(token),
            Some(json!({ "note": note })),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{body}");
    }

    let (_, body) = call(&app, "GET", "/api/notes?cursor=", Some(&master), None).await;
    assert_eq!(entries(&body).len(), 1);
    assert_eq!(entries(&body)[0]["note"], "mine");

    let (_, body) = call(&app, "GET", "/api/notes?cursor=", Some(&friend), None).await;
    assert_eq!(entries(&body)[0]["note"], "theirs");
}

#[tokio::test]
async fn clearing_a_note_stores_an_empty_string_rather_than_vanishing() {
    let app = test_app().await;
    let token = register(&app, "solo@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    call(
        &app,
        "PUT",
        &format!("/api/notes/{book}"),
        Some(&token),
        Some(json!({ "note": "something" })),
    )
    .await;
    call(
        &app,
        "PUT",
        &format!("/api/notes/{book}"),
        Some(&token),
        Some(json!({ "note": "" })),
    )
    .await;

    // The row stays, so the other device learns the note was cleared instead
    // of never hearing about it.
    let (_, body) = call(&app, "GET", "/api/notes?cursor=", Some(&token), None).await;
    assert_eq!(entries(&body).len(), 1);
    assert_eq!(entries(&body)[0]["note"], "");
}

// ---- profile --------------------------------------------------------------

#[tokio::test]
async fn the_profile_photo_round_trips_and_belongs_to_one_account() {
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let friend = add_member(&app, &master, "friend@lib.test").await;

    let (status, body) = call(&app, "GET", "/api/profile", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["has_avatar"], false);

    let (status, body) = call_bytes(&app, "PUT", "/api/profile/avatar", &master, png()).await;
    assert_eq!(status, StatusCode::OK, "upload: {body}");
    assert_eq!(body["has_avatar"], true);

    // The other account has its own, still empty — an avatar is not library data.
    let (_, body) = call(&app, "GET", "/api/profile", Some(&friend), None).await;
    assert_eq!(body["has_avatar"], false);

    let (status, _) = call(&app, "GET", "/api/profile/avatar", Some(&friend), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn an_avatar_that_is_not_an_image_is_refused() {
    // Judged by magic bytes, like every other upload — a declared type is a
    // claim, not evidence.
    let app = test_app().await;
    let token = register(&app, "solo@lib.test").await;
    let (status, body) = call_bytes(
        &app,
        "PUT",
        "/api/profile/avatar",
        &token,
        b"just some text".to_vec(),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
}

#[tokio::test]
async fn removing_the_photo_clears_it_everywhere() {
    let app = test_app().await;
    let token = register(&app, "solo@lib.test").await;
    call_bytes(&app, "PUT", "/api/profile/avatar", &token, png()).await;

    let (status, body) = call(&app, "DELETE", "/api/profile/avatar", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["has_avatar"], false);

    let (status, _) = call(&app, "GET", "/api/profile/avatar", Some(&token), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn the_display_name_syncs_and_cannot_be_blanked() {
    let app = test_app().await;
    let token = register(&app, "solo@lib.test").await;

    let (status, body) = call(
        &app,
        "PUT",
        "/api/profile",
        Some(&token),
        Some(json!({ "display_name": "Ana Petrescu" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["display_name"], "Ana Petrescu");

    let (status, _) = call(
        &app,
        "PUT",
        "/api/profile",
        Some(&token),
        Some(json!({ "display_name": "   " })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

// ---- the delta cursor -----------------------------------------------------

#[tokio::test]
async fn a_cursor_returns_only_what_changed_since() {
    let app = test_app().await;
    let token = register(&app, "solo@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    call(
        &app,
        "PUT",
        "/api/annotations/old",
        Some(&token),
        Some(json!({
            "book_id": book, "kind": "highlight",
            "updated_at": "2026-07-01 00:00:00"
        })),
    )
    .await;
    call(
        &app,
        "PUT",
        "/api/annotations/new",
        Some(&token),
        Some(json!({
            "book_id": book, "kind": "highlight",
            "updated_at": "2026-07-25 00:00:00"
        })),
    )
    .await;

    let (_, body) = call(
        &app,
        "GET",
        "/api/annotations?cursor=2026-07-10%2000:00:00",
        Some(&token),
        None,
    )
    .await;
    let list = entries(&body);
    assert_eq!(list.len(), 1, "a delta pull, not a full one: {body}");
    assert_eq!(list[0]["id"], "new");
    assert!(body["server_now"].is_string(), "the next cursor");
}

// ---- administering people (plan 6 #1) -------------------------------------
//
// The endpoints behind the console's People screen. The rule worth defending is
// that a library can never end up with no master: that is an account nobody can
// administer, recoverable only by editing the database by hand.

#[tokio::test]
async fn the_master_can_promote_and_demote() {
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    add_member(&app, &master, "friend@lib.test").await;

    let (_, users) = call(&app, "GET", "/api/users", Some(&master), None).await;
    let friend = users
        .as_array()
        .unwrap()
        .iter()
        .find(|u| u["email"] == "friend@lib.test")
        .unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();

    let (status, body) = call(
        &app,
        "PUT",
        &format!("/api/users/{friend}"),
        Some(&master),
        Some(json!({ "is_master": true })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["is_master"], true);

    let (status, body) = call(
        &app,
        "PUT",
        &format!("/api/users/{friend}"),
        Some(&master),
        Some(json!({ "is_master": false })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["is_master"], false);
}

#[tokio::test]
async fn the_last_master_cannot_be_demoted() {
    // Otherwise the library has no administrator and no way back.
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let (_, me) = call(&app, "GET", "/api/auth/me", Some(&master), None).await;
    let id = me["id"].as_str().unwrap();

    let (status, body) = call(
        &app,
        "PUT",
        &format!("/api/users/{id}"),
        Some(&master),
        Some(json!({ "is_master": false })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    assert!(
        body["error"].as_str().unwrap().contains("only master"),
        "the message has to say why: {body}"
    );
}

#[tokio::test]
async fn a_member_cannot_promote_themselves() {
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let friend = add_member(&app, &master, "friend@lib.test").await;
    let (_, me) = call(&app, "GET", "/api/auth/me", Some(&friend), None).await;
    let id = me["id"].as_str().unwrap();

    let (status, _) = call(
        &app,
        "PUT",
        &format!("/api/users/{id}"),
        Some(&friend),
        Some(json!({ "is_master": true })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}

#[tokio::test]
async fn removing_an_account_takes_its_personal_data_but_leaves_the_books() {
    // The cascade the People screen has to warn about before it happens.
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let friend = add_member(&app, &master, "friend@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;
    call(
        &app,
        "POST",
        "/api/shares",
        Some(&master),
        Some(json!({
            "scope": "book", "scope_id": book,
            "grantee_email": "friend@lib.test", "permission": "editor"
        })),
    )
    .await;
    call(
        &app,
        "PUT",
        "/api/annotations/theirs",
        Some(&friend),
        Some(json!({ "book_id": book, "kind": "highlight" })),
    )
    .await;

    let (_, users) = call(&app, "GET", "/api/users", Some(&master), None).await;
    let id = users
        .as_array()
        .unwrap()
        .iter()
        .find(|u| u["email"] == "friend@lib.test")
        .unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();

    let (status, body) = call(
        &app,
        "DELETE",
        &format!("/api/users/{id}"),
        Some(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");

    // Their session is gone with them.
    let (status, _) = call(&app, "GET", "/api/auth/me", Some(&friend), None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);

    // The book they annotated is still in the library.
    let (status, _) = call(&app, "GET", &format!("/api/books/{book}"), Some(&master), None).await;
    assert_eq!(status, StatusCode::OK, "removing a person is not removing books");
}

#[tokio::test]
async fn you_cannot_remove_your_own_account() {
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let (_, me) = call(&app, "GET", "/api/auth/me", Some(&master), None).await;
    let id = me["id"].as_str().unwrap();

    let (status, _) = call(&app, "DELETE", &format!("/api/users/{id}"), Some(&master), None).await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

#[tokio::test]
async fn pending_invites_are_listed_and_can_be_withdrawn() {
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;

    let (status, body) = call(
        &app,
        "POST",
        "/api/invites",
        Some(&master),
        Some(json!({ "email": "newcomer@lib.test", "permission": "viewer" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");

    let (status, list) = call(&app, "GET", "/api/invites", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK);
    let invites = list.as_array().unwrap();
    assert_eq!(invites.len(), 1);
    assert_eq!(invites[0]["email"], "newcomer@lib.test");
    let id = invites[0]["id"].as_str().unwrap().to_string();

    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/invites/{id}"),
        Some(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (_, list) = call(&app, "GET", "/api/invites", Some(&master), None).await;
    assert!(list.as_array().unwrap().is_empty());
}

#[tokio::test]
async fn a_member_cannot_see_the_invite_list() {
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let friend = add_member(&app, &master, "friend@lib.test").await;
    let (status, _) = call(&app, "GET", "/api/invites", Some(&friend), None).await;
    assert_eq!(status, StatusCode::FORBIDDEN);
}
