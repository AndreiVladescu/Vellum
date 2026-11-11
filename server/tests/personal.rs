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
    test_app_with_db().await.0
}

/// The app plus its pool, for the few tests that must look at rows no endpoint
/// returns any more — what a cascade left behind.
async fn test_app_with_db() -> (axum::Router, sqlx::SqlitePool) {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_personal_{id}.db"));
    let data_dir = std::env::temp_dir().join(format!("vellum_personal_data_{id}"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let app = router(AppState {
        db: db.clone(),
        public_base_url: "http://test.local".into(),
        data_dir,
        http: reqwest::Client::new(),
        max_upload_bytes: 64 * 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(2)),
        enrich_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
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
    });
    (app, db)
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
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
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

/// A server timestamp has a space in it, which a URI does not.
fn encode(cursor: &str) -> String {
    cursor.replace(' ', "%20")
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
    call(
        &app,
        "DELETE",
        &format!("/api/books/{book}"),
        Some(&master),
        None,
    )
    .await;
    let (_, body) = call(&app, "GET", "/api/deletions", Some(&stranger), None).await;
    assert!(
        body.as_array()
            .unwrap()
            .iter()
            .any(|d| d["book_id"] == book),
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
    assert_eq!(
        status,
        StatusCode::OK,
        "3 MB is under the stated cap: {body}"
    );

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
    assert_eq!(
        status,
        StatusCode::NOT_FOUND,
        "and not FORBIDDEN, which would confirm the id exists"
    );
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
    // "Since" means since the server heard it, not since the device wrote it —
    // see `a_late_push_of_an_old_edit_still_reaches_the_other_device` for the
    // bug that distinction fixes. So the cursor is taken between the two
    // pushes rather than made up from their timestamps.
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

    // The server's clock has one-second resolution and the pull is inclusive,
    // so a row written in the same second as the cursor is genuinely ambiguous.
    // Wait that second out rather than assert something the format cannot
    // support.
    tokio::time::sleep(std::time::Duration::from_millis(1100)).await;
    let (_, body) = call(&app, "GET", "/api/annotations?cursor=", Some(&token), None).await;
    let cursor = encode(body["server_now"].as_str().unwrap());

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
        &format!("/api/annotations?cursor={cursor}"),
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
async fn the_master_can_rename_someone_without_touching_their_role() {
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let friend = add_member(&app, &master, "friend@lib.test").await;
    let (_, me) = call(&app, "GET", "/api/auth/me", Some(&friend), None).await;
    let id = me["id"].as_str().unwrap();

    let (status, body) = call(
        &app,
        "PUT",
        &format!("/api/users/{id}"),
        Some(&master),
        Some(json!({ "display_name": "Ana" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["display_name"], "Ana");
    assert_eq!(body["is_master"], false, "renaming must not touch the role");

    // The rename sticks — not just echoed back in the response.
    let (_, users) = call(&app, "GET", "/api/users", Some(&master), None).await;
    let renamed = users
        .as_array()
        .unwrap()
        .iter()
        .find(|u| u["id"] == id)
        .unwrap();
    assert_eq!(renamed["display_name"], "Ana");
}

#[tokio::test]
async fn a_blank_name_is_refused_and_an_empty_request_does_nothing() {
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let friend = add_member(&app, &master, "friend@lib.test").await;
    let (_, me) = call(&app, "GET", "/api/auth/me", Some(&friend), None).await;
    let id = me["id"].as_str().unwrap();

    let (status, body) = call(
        &app,
        "PUT",
        &format!("/api/users/{id}"),
        Some(&master),
        Some(json!({ "display_name": "   " })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");

    let (status, body) = call(
        &app,
        "PUT",
        &format!("/api/users/{id}"),
        Some(&master),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST, "{body}");
}

#[tokio::test]
async fn a_member_cannot_rename_anyone_including_themselves() {
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
        Some(json!({ "display_name": "Ana" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
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
    let (status, _) = call(
        &app,
        "GET",
        &format!("/api/books/{book}"),
        Some(&master),
        None,
    )
    .await;
    assert_eq!(
        status,
        StatusCode::OK,
        "removing a person is not removing books"
    );
}

#[tokio::test]
async fn you_cannot_remove_your_own_account() {
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let (_, me) = call(&app, "GET", "/api/auth/me", Some(&master), None).await;
    let id = me["id"].as_str().unwrap();

    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/users/{id}"),
        Some(&master),
        None,
    )
    .await;
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

// ---- copy photos (plan 6 #4) ----------------------------------------------
//
// Library data rather than personal: a photo hangs off a copy, and a copy is
// visible to whoever the book is shared with. So the tests here are about the
// *opposite* property to the ones above — that it is shared, correctly, with
// the people who can already see the book, and with nobody else.

async fn create_copy(app: &axum::Router, token: &str, book: &str) -> String {
    let id = uuid::Uuid::new_v4().to_string();
    let (status, body) = call(
        app,
        "PUT",
        &format!("/api/copies/{id}"),
        Some(token),
        Some(json!({ "book_id": book, "location": "Shelf A" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "create copy: {body}");
    id
}

#[tokio::test]
async fn a_copy_photo_round_trips_with_its_bytes() {
    let app = test_app().await;
    let token = register(&app, "solo@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    let copy = create_copy(&app, &token, &book).await;

    let (status, body) = call(
        &app,
        "PUT",
        "/api/copy-photos/p1",
        Some(&token),
        Some(json!({ "copy_id": copy, "caption": "top shelf, by the window" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    // The path is the server's choice, never the client's — the rule that
    // closed H1 for covers.
    assert_eq!(body["path"], "copy-photos/p1");

    let (status, body) = call_bytes(&app, "PUT", "/api/copy-photos/p1/image", &token, png()).await;
    assert_eq!(status, StatusCode::OK, "{body}");

    let (status, list) = call(&app, "GET", "/api/copy-photos?cursor=", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    let photos = list["photos"].as_array().unwrap();
    assert_eq!(photos.len(), 1);
    assert_eq!(photos[0]["caption"], "top shelf, by the window");
}

#[tokio::test]
async fn a_photo_is_visible_to_whoever_can_see_the_book() {
    // The deliberate difference from personal data: this is *not* private.
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let friend = add_member(&app, &master, "friend@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;
    let copy = create_copy(&app, &master, &book).await;
    call(
        &app,
        "PUT",
        "/api/copy-photos/p1",
        Some(&master),
        Some(json!({ "copy_id": copy })),
    )
    .await;
    call_bytes(&app, "PUT", "/api/copy-photos/p1/image", &master, png()).await;

    // Before the share: invisible.
    let (_, list) = call(&app, "GET", "/api/copy-photos?cursor=", Some(&friend), None).await;
    assert!(list["photos"].as_array().unwrap().is_empty());
    let (status, _) = call(
        &app,
        "GET",
        "/api/copy-photos/p1/image",
        Some(&friend),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);

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

    // After: visible, because the book is.
    let (_, list) = call(&app, "GET", "/api/copy-photos?cursor=", Some(&friend), None).await;
    assert_eq!(list["photos"].as_array().unwrap().len(), 1);
    let (status, _) = call(
        &app,
        "GET",
        "/api/copy-photos/p1/image",
        Some(&friend),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "a viewer may look at it");
}

#[tokio::test]
async fn a_viewer_cannot_add_or_remove_photos() {
    // Looking is view; changing what a copy carries is editing.
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let friend = add_member(&app, &master, "friend@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;
    let copy = create_copy(&app, &master, &book).await;
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

    let (status, _) = call(
        &app,
        "PUT",
        "/api/copy-photos/nope",
        Some(&friend),
        Some(json!({ "copy_id": copy })),
    )
    .await;
    assert_eq!(status, StatusCode::NOT_FOUND);
}

#[tokio::test]
async fn deleting_a_photo_tombstones_it_and_removes_the_file() {
    let app = test_app().await;
    let token = register(&app, "solo@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    let copy = create_copy(&app, &token, &book).await;
    call(
        &app,
        "PUT",
        "/api/copy-photos/p1",
        Some(&token),
        Some(json!({ "copy_id": copy })),
    )
    .await;
    call_bytes(&app, "PUT", "/api/copy-photos/p1/image", &token, png()).await;

    let (status, _) = call(&app, "DELETE", "/api/copy-photos/p1", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);

    let (status, _) = call(&app, "GET", "/api/copy-photos/p1/image", Some(&token), None).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "the bytes go with the row");

    let (_, body) = call(
        &app,
        "GET",
        "/api/deletions?kind=copy_photo",
        Some(&token),
        None,
    )
    .await;
    assert!(
        body.as_array()
            .unwrap()
            .iter()
            .any(|d| d["book_id"] == "p1"),
        "the other device has to learn it went: {body}"
    );
}

#[tokio::test]
async fn a_photo_that_is_not_an_image_is_refused() {
    let app = test_app().await;
    let token = register(&app, "solo@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    let copy = create_copy(&app, &token, &book).await;
    call(
        &app,
        "PUT",
        "/api/copy-photos/p1",
        Some(&token),
        Some(json!({ "copy_id": copy })),
    )
    .await;
    let (status, _) = call_bytes(
        &app,
        "PUT",
        "/api/copy-photos/p1/image",
        &token,
        b"not an image at all".to_vec(),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

/// Un-publishing (next features #8): a switch turned off can take back what is
/// already on the server, and it must take back *only the caller's*.
#[tokio::test]
async fn un_publishing_removes_my_rows_and_leaves_everyone_else_alone() {
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let other = add_member(&app, &master, "other@lib.test").await;

    // Each account owns a book, a copy of it, and a loan of that copy.
    for (token, book) in [(&master, "mine"), (&other, "theirs")] {
        let (status, _) = call(
            &app,
            "PUT",
            &format!("/api/books/{book}"),
            Some(token),
            Some(json!({ "title": book })),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        let (status, _) = call(
            &app,
            "PUT",
            &format!("/api/copies/copy-{book}"),
            Some(token),
            Some(json!({ "book_id": book })),
        )
        .await;
        assert_eq!(status, StatusCode::OK);
        let (status, _) = call(
            &app,
            "PUT",
            &format!("/api/loans/loan-{book}"),
            Some(token),
            Some(json!({
                "copy_id": format!("copy-{book}"),
                "borrower": "A friend",
                "loaned_at": "2026-01-01 00:00:00",
            })),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "seeding {book}");
    }

    let (status, body) = call(&app, "DELETE", "/api/mine/loans", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["deleted"], 1, "should have forgotten exactly one loan");

    // Mine is gone...
    let (_, mine) = call(&app, "GET", "/api/loans", Some(&master), None).await;
    let listed: Vec<&str> = mine
        .as_array()
        .unwrap()
        .iter()
        .map(|l| l["id"].as_str().unwrap())
        .collect();
    assert!(!listed.contains(&"loan-mine"), "my loan survived: {mine}");

    // ...and theirs is untouched, which is the whole risk of a bulk delete.
    let (_, theirs) = call(&app, "GET", "/api/loans", Some(&other), None).await;
    let listed: Vec<&str> = theirs
        .as_array()
        .unwrap()
        .iter()
        .map(|l| l["id"].as_str().unwrap())
        .collect();
    assert!(
        listed.contains(&"loan-theirs"),
        "un-publishing reached another account's loan: {theirs}"
    );

    // A tombstone went out, so this account's other devices drop it too rather
    // than pushing it straight back.
    let (_, deletions) = call(&app, "GET", "/api/deletions?kind=loan", Some(&master), None).await;
    assert!(
        deletions
            .as_array()
            .unwrap()
            .iter()
            .any(|d| d["book_id"] == "loan-mine"),
        "no tombstone, so the next push would resurrect it: {deletions}"
    );
}

#[tokio::test]
async fn un_publishing_my_marks_leaves_another_account_s_alone() {
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let other = add_member(&app, &master, "other@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;
    // Shared as an editor so the other account can mark it too.
    call(
        &app,
        "POST",
        "/api/shares",
        Some(&master),
        Some(json!({
            "scope": "book", "scope_id": book,
            "grantee_email": "other@lib.test", "permission": "editor"
        })),
    )
    .await;

    for (token, id) in [(&master, "a-mine"), (&other, "a-theirs")] {
        let (status, _) = call(
            &app,
            "PUT",
            &format!("/api/annotations/{id}"),
            Some(token),
            Some(json!({
                "book_id": book,
                "kind": "highlight",
                "quoted_text": "a line",
            })),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "seeding {id}");
    }

    let (status, body) = call(&app, "DELETE", "/api/mine/annotations", Some(&master), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["deleted"], 1);

    let (_, mine) = call(&app, "GET", "/api/annotations", Some(&master), None).await;
    assert!(mine.as_array().unwrap().is_empty());

    let (_, theirs) = call(&app, "GET", "/api/annotations", Some(&other), None).await;
    assert_eq!(
        theirs.as_array().unwrap().len(),
        1,
        "un-publishing reached another account's highlights: {theirs}"
    );
}

#[tokio::test]
async fn un_publishing_something_that_is_not_a_resource_is_refused() {
    let app = test_app().await;
    let master = register(&app, "master@lib.test").await;
    let (status, _) = call(&app, "DELETE", "/api/mine/books", Some(&master), None).await;
    assert_eq!(
        status,
        StatusCode::BAD_REQUEST,
        "books are the library itself; there is no 'un-publish my catalogue'"
    );
}

// ---- the delta cursor -----------------------------------------------------

/// The v1.1.5 bug, in one test: "only the new notes made on a book sync".
///
/// A note is written on one device on Monday and pushed on Friday, while the
/// other device syncs on Wednesday. The row's `updated_at` is Monday — it has
/// to be, that is when the edit happened and it is what last-write-wins
/// compares — but the cursor is the *server's* clock. Filtering the pull on
/// `updated_at` made that note invisible to the Wednesday device forever: it
/// arrived after the cursor and was stamped before it.
#[tokio::test]
async fn a_late_push_of_an_old_edit_still_reaches_the_other_device() {
    let app = test_app().await;
    let token = register(&app, "two-devices@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;

    // The other device syncs first and takes the server's clock as its cursor.
    let (_, body) = call(&app, "GET", "/api/annotations?cursor=", Some(&token), None).await;
    let cursor = encode(body["server_now"].as_str().unwrap());

    // Only now does the first device push what it wrote days ago.
    let (status, body) = call(
        &app,
        "PUT",
        "/api/annotations/old-note",
        Some(&token),
        Some(json!({
            "book_id": book,
            "kind": "note",
            "note": "written long before it was pushed",
            "updated_at": "2020-01-01 00:00:00",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "upsert: {body}");

    let (status, body) = call(
        &app,
        "GET",
        &format!("/api/annotations?cursor={cursor}"),
        Some(&token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        entries(&body).len(),
        1,
        "a delta pull must be about when the server heard, not when the device wrote"
    );
    assert_eq!(
        entries(&body)[0]["updated_at"],
        "2020-01-01 00:00:00",
        "and the edit keeps its own clock, which is what LWW compares"
    );
}

#[tokio::test]
async fn the_same_holds_for_private_notes_and_reading_positions() {
    let app = test_app().await;
    let token = register(&app, "late@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;

    let (status, body) = call(&app, "GET", "/api/notes?cursor=", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK, "notes list: {body}");
    let cursor = encode(body["server_now"].as_str().unwrap());

    call(
        &app,
        "PUT",
        &format!("/api/notes/{book}"),
        Some(&token),
        Some(json!({"note": "old thought", "updated_at": "2020-01-01 00:00:00"})),
    )
    .await;
    call(
        &app,
        "PUT",
        &format!("/api/reading-progress/{book}"),
        Some(&token),
        Some(json!({
            "device_id": "phone",
            "progress": 0.7,
            "page": 210,
            "unit": "page",
            "updated_at": "2020-01-01 00:00:00",
        })),
    )
    .await;

    let (_, notes) = call(
        &app,
        "GET",
        &format!("/api/notes?cursor={cursor}"),
        Some(&token),
        None,
    )
    .await;
    assert_eq!(entries(&notes).len(), 1, "the private note arrives");

    let (_, positions) = call(
        &app,
        "GET",
        &format!("/api/reading-progress?cursor={cursor}"),
        Some(&token),
        None,
    )
    .await;
    assert_eq!(
        entries(&positions).len(),
        1,
        "so does the position — the same bug read as 'the pages didn’t update'"
    );
}

// ---- reading status -------------------------------------------------------

#[tokio::test]
async fn a_books_status_travels_between_a_readers_own_devices() {
    // v1.1.5: a book on the wishlist arrived on the tablet as one you own, and
    // a book read to the end stayed unread on the phone. Reading status had no
    // server representation at all.
    let app = test_app().await;
    let token = register(&app, "reader@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;

    let (status, body) = call(
        &app,
        "PUT",
        &format!("/api/statuses/{book}"),
        Some(&token),
        Some(json!({
            "status": "finished",
            "started_at": "2026-08-01 09:00:00",
            "finished_at": "2026-08-20 22:15:00",
            "read_count": 2,
            "updated_at": "2026-08-20 22:15:00",
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "upsert: {body}");

    let (status, body) = call(&app, "GET", "/api/statuses?cursor=", Some(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    let list = entries(&body);
    assert_eq!(list.len(), 1);
    assert_eq!(list[0]["status"], "finished");
    assert_eq!(list[0]["finished_at"], "2026-08-20 22:15:00");
    assert_eq!(
        list[0]["read_count"], 2,
        "the dates travel with the status: they are the same act"
    );
}

#[tokio::test]
async fn a_wishlist_book_stays_wanted_rather_than_becoming_owned() {
    let app = test_app().await;
    let token = register(&app, "wants@lib.test").await;
    let book = create_book(&app, &token, "Piranesi").await;

    call(
        &app,
        "PUT",
        &format!("/api/statuses/{book}"),
        Some(&token),
        Some(json!({"status": "wishlist", "updated_at": "2026-08-21 10:00:00"})),
    )
    .await;

    let (_, body) = call(&app, "GET", "/api/statuses?cursor=", Some(&token), None).await;
    assert_eq!(entries(&body)[0]["status"], "wishlist");
}

#[tokio::test]
async fn an_older_status_does_not_overwrite_a_newer_one() {
    let app = test_app().await;
    let token = register(&app, "race@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;

    call(
        &app,
        "PUT",
        &format!("/api/statuses/{book}"),
        Some(&token),
        Some(json!({"status": "finished", "updated_at": "2026-08-21 12:00:00"})),
    )
    .await;
    // A device that has been offline since yesterday pushes what it knew then.
    call(
        &app,
        "PUT",
        &format!("/api/statuses/{book}"),
        Some(&token),
        Some(json!({"status": "reading", "updated_at": "2026-08-20 12:00:00"})),
    )
    .await;

    let (_, body) = call(&app, "GET", "/api/statuses?cursor=", Some(&token), None).await;
    assert_eq!(
        entries(&body)[0]["status"],
        "finished",
        "last write wins by the writer's clock, and the stale one is not it"
    );
}

#[tokio::test]
async fn one_readers_status_is_invisible_to_another_sharing_the_book() {
    // The rule the whole module exists for: in a shared library, "I finished
    // it" is a fact about the reader, not about the book.
    let app = test_app().await;
    let master = register(&app, "owner@lib.test").await;
    let member = add_member(&app, &master, "friend@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;

    call(
        &app,
        "PUT",
        &format!("/api/statuses/{book}"),
        Some(&master),
        Some(json!({"status": "finished", "updated_at": "2026-08-21 12:00:00"})),
    )
    .await;

    let (status, body) = call(&app, "GET", "/api/statuses?cursor=", Some(&member), None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        entries(&body).is_empty(),
        "the other reader sees their own statuses only"
    );
}

#[tokio::test]
async fn a_status_must_say_something() {
    let app = test_app().await;
    let token = register(&app, "empty@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;

    let (status, _) = call(
        &app,
        "PUT",
        &format!("/api/statuses/{book}"),
        Some(&token),
        Some(json!({"status": "  "})),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}

// ---- rating, and the merge rules of migration 0038 ------------------------

async fn put_status(
    app: &axum::Router,
    token: &str,
    book: &str,
    body: Value,
) -> (StatusCode, Value) {
    call(
        app,
        "PUT",
        &format!("/api/statuses/{book}"),
        Some(token),
        Some(body),
    )
    .await
}

async fn my_status(app: &axum::Router, token: &str) -> Value {
    let (status, body) = call(app, "GET", "/api/statuses?cursor=", Some(token), None).await;
    assert_eq!(status, StatusCode::OK);
    let list = entries(&body);
    assert_eq!(list.len(), 1, "one row per reader and book: {body}");
    list[0].clone()
}

async fn share_book(app: &axum::Router, master: &str, book: &str, email: &str) -> String {
    let (status, body) = call(
        app,
        "POST",
        "/api/shares",
        Some(master),
        Some(json!({
            "scope": "book", "scope_id": book,
            "grantee_email": email, "permission": "editor"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "share: {body}");
    body["id"].as_str().unwrap().to_string()
}

#[tokio::test]
async fn a_rating_travels_with_the_status() {
    let app = test_app().await;
    let token = register(&app, "rater@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;

    let (status, body) = put_status(
        &app,
        &token,
        &book,
        json!({"status": "finished", "updated_at": "2026-08-20 22:15:00",
               "rating": 5, "rating_updated_at": "2026-08-20 22:15:00"}),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["rating"], 5, "the answer is the stored row");
    assert_eq!(my_status(&app, &token).await["rating"], 5);

    // Taking the rating away is a statement too: null *with* a clock.
    put_status(
        &app,
        &token,
        &book,
        json!({"status": "finished", "updated_at": "2026-08-20 22:15:00",
               "rating": null, "rating_updated_at": "2026-08-21 09:00:00"}),
    )
    .await;
    let row = my_status(&app, &token).await;
    assert!(row["rating"].is_null(), "{row}");
    assert_eq!(row["rating_updated_at"], "2026-08-21 09:00:00");
}

#[tokio::test]
async fn rating_and_status_are_separate_acts_on_separate_clocks() {
    // One clock for both would let either overwrite the other from a device
    // that missed the other half. Here the tablet missed the phone's finish
    // *and* its rating, and does one thing each way.
    let app = test_app().await;
    let token = register(&app, "clocks@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    // The phone: finished, five stars.
    put_status(
        &app,
        &token,
        &book,
        json!({"status": "finished", "read_count": 1, "updated_at": "2026-08-20 22:00:00",
               "rating": 5, "rating_updated_at": "2026-08-20 22:00:00"}),
    )
    .await;

    // The tablet rates it, still believing it unread (its status clock is old).
    let (_, body) = put_status(
        &app,
        &token,
        &book,
        json!({"status": "unread", "updated_at": "2026-08-01 00:00:00",
               "rating": 3, "rating_updated_at": "2026-08-21 08:00:00"}),
    )
    .await;
    assert_eq!(
        body["status"], "finished",
        "rating a book does not unfinish it"
    );
    assert_eq!(body["rating"], 3, "the newer rating wins");

    // Then sets a status, never having rated it on this clock's terms: the
    // push says nothing about the rating, and the rating stays.
    let (_, body) = put_status(
        &app,
        &token,
        &book,
        json!({"status": "abandoned", "updated_at": "2026-08-22 08:00:00"}),
    )
    .await;
    assert_eq!(body["status"], "abandoned");
    assert_eq!(body["rating"], 3, "changing the status does not unrate it");
}

#[tokio::test]
async fn a_rating_out_of_range_is_refused() {
    let app = test_app().await;
    let token = register(&app, "stars@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    for bad in [0, 6] {
        let (status, _) = put_status(
            &app,
            &token,
            &book,
            json!({"status": "reading", "rating": bad,
                   "rating_updated_at": "2026-08-20 10:00:00"}),
        )
        .await;
        assert_eq!(status, StatusCode::BAD_REQUEST, "rating {bad}");
    }
}

#[tokio::test]
async fn two_readers_of_a_shared_book_keep_their_own_verdicts() {
    // The case that rules out the `book` row: a rating there would be one
    // number for everyone the library is shared with, and the last to rate
    // would overwrite the rest.
    let app = test_app().await;
    let master = register(&app, "owner@lib.test").await;
    let friend = add_member(&app, &master, "friend@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;
    share_book(&app, &master, &book, "friend@lib.test").await;

    put_status(
        &app,
        &master,
        &book,
        json!({"status": "finished", "rating": 5, "read_count": 2,
               "updated_at": "2026-08-20 10:00:00",
               "rating_updated_at": "2026-08-20 10:00:00"}),
    )
    .await;
    // Later by the clock, and on the same book — but a different reader.
    let (status, body) = put_status(
        &app,
        &friend,
        &book,
        json!({"status": "abandoned", "rating": 1, "updated_at": "2026-08-21 10:00:00",
               "rating_updated_at": "2026-08-21 10:00:00"}),
    )
    .await;
    assert_eq!(
        status,
        StatusCode::OK,
        "an editor may keep a status: {body}"
    );
    assert_eq!(
        body["status"], "abandoned",
        "and the answer is theirs, not a merge with mine"
    );
    assert_eq!(body["read_count"], 0);

    let mine = my_status(&app, &master).await;
    assert_eq!(
        mine["status"], "finished",
        "the friend's write did not touch mine"
    );
    assert_eq!(mine["rating"], 5);
    assert_eq!(mine["read_count"], 2);
    let theirs = my_status(&app, &friend).await;
    assert_eq!(theirs["status"], "abandoned");
    assert_eq!(theirs["rating"], 1);
}

#[tokio::test]
async fn a_status_needs_a_book_you_can_see_and_goes_when_the_book_does() {
    let app = test_app().await;
    let master = register(&app, "owner@lib.test").await;
    let friend = add_member(&app, &master, "friend@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;

    let (status, _) = put_status(&app, &friend, &book, json!({"status": "finished"})).await;
    assert_eq!(
        status,
        StatusCode::NOT_FOUND,
        "a book that is not shared with you is not one you can have a status on"
    );
    let (status, _) =
        put_status(&app, &friend, "no-such-book", json!({"status": "finished"})).await;
    assert_eq!(status, StatusCode::NOT_FOUND);

    let share = share_book(&app, &master, &book, "friend@lib.test").await;
    let (status, _) = put_status(
        &app,
        &friend,
        &book,
        json!({"status": "finished", "rating": 4, "updated_at": "2026-08-20 10:00:00"}),
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/shares/{share}"),
        Some(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (_, body) = call(&app, "GET", "/api/statuses?cursor=", Some(&friend), None).await;
    assert!(
        entries(&body).is_empty(),
        "a book that stops being shared stops returning your status on it: {body}"
    );
    let (status, _) = put_status(&app, &friend, &book, json!({"status": "reading"})).await;
    assert_eq!(status, StatusCode::NOT_FOUND, "nor can you write one");
}

#[tokio::test]
async fn deleting_the_book_or_the_account_takes_the_status_with_it() {
    let (app, db) = test_app_with_db().await;
    let master = register(&app, "owner@lib.test").await;
    let friend = add_member(&app, &master, "friend@lib.test").await;
    let kept = create_book(&app, &master, "Kept").await;
    let doomed = create_book(&app, &master, "Doomed").await;
    share_book(&app, &master, &kept, "friend@lib.test").await;
    for (token, book) in [(&master, &kept), (&master, &doomed), (&friend, &kept)] {
        let (status, body) = put_status(
            &app,
            token,
            book,
            json!({"status": "finished", "rating": 3}),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "{body}");
    }
    let rows = |book: String| {
        let db = db.clone();
        async move {
            sqlx::query_scalar::<_, i64>("SELECT COUNT(*) FROM book_status WHERE book_id = ?")
                .bind(book)
                .fetch_one(&db)
                .await
                .unwrap()
        }
    };

    let (status, body) = call(
        &app,
        "DELETE",
        &format!("/api/books/{doomed}"),
        Some(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(
        rows(doomed.clone()).await,
        0,
        "a deleted book leaves no status behind"
    );
    assert_eq!(rows(kept.clone()).await, 2);

    let (_, users) = call(&app, "GET", "/api/users", Some(&master), None).await;
    let friend_id = users
        .as_array()
        .unwrap()
        .iter()
        .find(|u| u["email"] == "friend@lib.test")
        .unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();
    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/users/{friend_id}"),
        Some(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let left: Vec<String> = sqlx::query_scalar("SELECT user_id FROM book_status WHERE book_id = ?")
        .bind(&kept)
        .fetch_all(&db)
        .await
        .unwrap();
    assert_eq!(
        left.len(),
        1,
        "the removed account's status went with it, mine stayed"
    );
    assert_ne!(left[0], friend_id);
}

#[tokio::test]
async fn an_older_app_that_knows_no_ratings_does_not_erase_one() {
    // An app from before migration 0038 sends the status without a rating. The
    // whole-row overwrite it would otherwise trigger is exactly the bug: rate a
    // book on the new phone, change its status on the old tablet, rating gone.
    let app = test_app().await;
    let token = register(&app, "mixed@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    put_status(
        &app,
        &token,
        &book,
        json!({"status": "reading", "updated_at": "2026-08-20 10:00:00",
               "rating": 4, "rating_updated_at": "2026-08-20 10:00:00"}),
    )
    .await;
    // Exactly the body a 0034-era app sends: no rating keys at all.
    put_status(
        &app,
        &token,
        &book,
        json!({"status": "finished", "started_at": null, "finished_at": null,
               "read_count": 1, "updated_at": "2026-08-21 10:00:00"}),
    )
    .await;
    let row = my_status(&app, &token).await;
    assert_eq!(row["status"], "finished", "the newer status still wins");
    assert_eq!(
        row["rating"], 4,
        "and the rating it said nothing about survives"
    );
}

#[tokio::test]
async fn a_rating_nobody_knew_is_filled_in_whatever_the_clocks_say() {
    // After the upgrade every existing row's rating is unknown. A device that
    // rated the book long ago must still be able to put that rating there, even
    // though another device has since written a newer status.
    let app = test_app().await;
    let token = register(&app, "upgrade@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    put_status(
        &app,
        &token,
        &book,
        json!({"status": "finished", "updated_at": "2026-08-21 10:00:00"}),
    )
    .await;
    assert!(
        my_status(&app, &token).await["rating_updated_at"].is_null(),
        "unknown: nobody has dated a rating here"
    );

    let (_, body) = put_status(
        &app,
        &token,
        &book,
        json!({"status": "reading", "updated_at": "2026-01-01 00:00:00",
               "rating": 5, "rating_updated_at": "2026-01-01 00:00:00"}),
    )
    .await;
    assert_eq!(body["rating"], 5, "the rating fills the gap");
    assert_eq!(body["status"], "finished", "the older status does not");
    assert_eq!(body["updated_at"], "2026-08-21 10:00:00");

    // Once known, a rating is last-write-wins on its own clock.
    let (_, body) = put_status(
        &app,
        &token,
        &book,
        json!({"status": "finished", "updated_at": "2026-02-01 00:00:00",
               "rating": 2, "rating_updated_at": "2025-12-01 00:00:00"}),
    )
    .await;
    assert_eq!(
        body["rating"], 5,
        "an older rating does not replace a known one"
    );
}

#[tokio::test]
async fn opening_a_book_on_a_stale_device_does_not_unfinish_it() {
    // The one automatic transition. The tablet has been offline since before
    // the book was finished on the phone; it still thinks the book is unread,
    // so opening it says "reading" — with a newer clock than the finish.
    let app = test_app().await;
    let token = register(&app, "twodevices@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    put_status(
        &app,
        &token,
        &book,
        json!({"status": "finished", "finished_at": "2026-08-20 22:00:00", "read_count": 1,
               "updated_at": "2026-08-20 22:00:00",
               "rating": 4, "rating_updated_at": "2026-08-20 22:00:00"}),
    )
    .await;
    // The tablet never rated it either, so it says nothing about the rating.
    let (_, body) = put_status(
        &app,
        &token,
        &book,
        json!({"status": "reading", "inferred": true, "rating": null,
               "rating_updated_at": null, "updated_at": "2026-08-21 08:00:00"}),
    )
    .await;
    assert_eq!(
        body["status"], "finished",
        "a guess does not replace a choice"
    );
    assert_eq!(body["finished_at"], "2026-08-20 22:00:00");
    assert_eq!(body["inferred"], false);
    assert_eq!(body["rating"], 4, "nor does saying nothing unrate it");
    assert_eq!(body["updated_at"], "2026-08-21 08:00:00");
}

#[tokio::test]
async fn a_finish_pushed_after_a_stale_guess_still_lands() {
    // The other order: the tablet's guess reaches the server first, and the
    // phone's earlier finish arrives after it.
    let app = test_app().await;
    let token = register(&app, "otherorder@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    put_status(
        &app,
        &token,
        &book,
        json!({"status": "reading", "inferred": true, "updated_at": "2026-08-21 08:00:00"}),
    )
    .await;
    assert_eq!(my_status(&app, &token).await["inferred"], true);
    let (_, body) = put_status(
        &app,
        &token,
        &book,
        json!({"status": "finished", "read_count": 1, "updated_at": "2026-08-20 22:00:00"}),
    )
    .await;
    assert_eq!(
        body["status"], "finished",
        "a choice replaces a guess, older or not"
    );
    assert_eq!(body["inferred"], false);

    // But a deliberate later "unread" is just a choice like any other, and a
    // guess made after it is newer information, not a stale one.
    put_status(
        &app,
        &token,
        &book,
        json!({"status": "unread", "updated_at": "2026-08-22 08:00:00"}),
    )
    .await;
    let (_, body) = put_status(
        &app,
        &token,
        &book,
        json!({"status": "reading", "inferred": true, "updated_at": "2026-08-23 08:00:00"}),
    )
    .await;
    assert_eq!(body["status"], "reading");
}

#[tokio::test]
async fn a_finish_is_never_uncounted_by_a_stale_device() {
    // The read count counts finishes and only grows. A device that never heard
    // of the second finish, changing the status later, must not take it back.
    let app = test_app().await;
    let token = register(&app, "counting@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    put_status(
        &app,
        &token,
        &book,
        json!({"status": "finished", "read_count": 2, "updated_at": "2026-08-20 22:00:00"}),
    )
    .await;
    let (_, body) = put_status(
        &app,
        &token,
        &book,
        json!({"status": "abandoned", "read_count": 1, "updated_at": "2026-08-21 22:00:00"}),
    )
    .await;
    assert_eq!(body["status"], "abandoned", "the newer status wins");
    assert_eq!(
        body["read_count"], 2,
        "and the count keeps the finish it did not know about"
    );

    // Two devices that each marked the same reading finished offline: each says
    // 3. That is one more finish, not two.
    for at in ["2026-08-22 10:00:00", "2026-08-22 11:00:00"] {
        put_status(
            &app,
            &token,
            &book,
            json!({"status": "finished", "read_count": 3, "updated_at": at}),
        )
        .await;
    }
    assert_eq!(my_status(&app, &token).await["read_count"], 3);
}

#[tokio::test]
async fn a_push_that_changes_nothing_is_not_handed_out_again() {
    let app = test_app().await;
    let token = register(&app, "quiet@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    let row = json!({"status": "finished", "updated_at": "2026-08-20 10:00:00",
                     "rating": 3, "rating_updated_at": "2026-08-20 10:00:00"});
    put_status(&app, &token, &book, row.clone()).await;
    // The server's clock has one-second resolution and the delta filter is
    // inclusive, so step past the first write before taking the cursor.
    tokio::time::sleep(std::time::Duration::from_millis(1100)).await;
    let (_, first) = call(&app, "GET", "/api/statuses?cursor=", Some(&token), None).await;
    let cursor = first["server_now"].as_str().unwrap().to_string();
    put_status(&app, &token, &book, row).await;
    let (_, body) = call(
        &app,
        "GET",
        &format!("/api/statuses?cursor={}", encode(&cursor)),
        Some(&token),
        None,
    )
    .await;
    assert!(
        entries(&body).is_empty(),
        "nothing changed, so nothing to pull: {body}"
    );
}

#[tokio::test]
async fn a_sitting_synced_mid_read_is_corrected_when_it_ends() {
    // v1.1.5 hunt: a sync during a sitting pushed a row that was true so far,
    // and `DO NOTHING` froze it. Every other device then held a sitting that
    // ended early — and the reading pace measured from it was wrong.
    let app = test_app().await;
    let token = register(&app, "reader@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;

    let mid = json!({
        "book_id": book,
        "device_id": "phone",
        "device_label": "phone",
        "started_at": "2026-08-22 09:00:00",
        "ended_at": "2026-08-22 09:10:00",
        "start_page": 10,
        "end_page": 24,
    });
    let (status, body) = call(&app, "PUT", "/api/sessions/s1", Some(&token), Some(mid)).await;
    assert_eq!(status, StatusCode::OK, "mid-read push: {body}");

    // The reader carries on and closes the book an hour later.
    let end = json!({
        "book_id": book,
        "device_id": "phone",
        "device_label": "phone",
        "started_at": "2026-08-22 09:00:00",
        "ended_at": "2026-08-22 10:05:00",
        "start_page": 10,
        "end_page": 96,
    });
    call(&app, "PUT", "/api/sessions/s1", Some(&token), Some(end)).await;

    let (_, body) = call(&app, "GET", "/api/sessions?cursor=", Some(&token), None).await;
    let list = entries(&body);
    assert_eq!(list.len(), 1, "one sitting, not two");
    assert_eq!(list[0]["ended_at"], "2026-08-22 10:05:00");
    assert_eq!(list[0]["end_page"], 96);
    assert_eq!(
        list[0]["start_page"], 10,
        "where it started is a fact, and is not moved"
    );
}

#[tokio::test]
async fn a_sitting_cannot_be_made_to_end_earlier_than_it_did() {
    let app = test_app().await;
    let token = register(&app, "late@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;

    let full = json!({
        "book_id": book,
        "device_id": "phone",
        "started_at": "2026-08-22 09:00:00",
        "ended_at": "2026-08-22 10:05:00",
        "start_page": 10,
        "end_page": 96,
    });
    call(&app, "PUT", "/api/sessions/s1", Some(&token), Some(full)).await;

    // An older copy of the same sitting arrives from a device that was offline.
    let stale = json!({
        "book_id": book,
        "device_id": "phone",
        "started_at": "2026-08-22 09:00:00",
        "ended_at": "2026-08-22 09:10:00",
        "start_page": 10,
        "end_page": 24,
    });
    call(&app, "PUT", "/api/sessions/s1", Some(&token), Some(stale)).await;

    let (_, body) = call(&app, "GET", "/api/sessions?cursor=", Some(&token), None).await;
    assert_eq!(entries(&body)[0]["end_page"], 96, "a sitting only grows");
}

#[tokio::test]
async fn another_account_cannot_edit_a_sitting_by_guessing_its_id() {
    let app = test_app().await;
    let master = register(&app, "owner@lib.test").await;
    let member = add_member(&app, &master, "friend@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;

    let mine = json!({
        "book_id": book,
        "device_id": "phone",
        "started_at": "2026-08-22 09:00:00",
        "ended_at": "2026-08-22 10:00:00",
        "start_page": 1,
        "end_page": 50,
    });
    call(&app, "PUT", "/api/sessions/s1", Some(&master), Some(mine)).await;

    // Same id, someone else's token: the update half is scoped by user, so this
    // is a new row of theirs, never an edit of mine.
    let theirs = json!({
        "book_id": book,
        "device_id": "laptop",
        "started_at": "2026-08-22 11:00:00",
        "ended_at": "2026-08-22 12:00:00",
        "start_page": 200,
        "end_page": 300,
    });
    call(&app, "PUT", "/api/sessions/s1", Some(&member), Some(theirs)).await;

    let (_, body) = call(&app, "GET", "/api/sessions?cursor=", Some(&master), None).await;
    assert_eq!(entries(&body)[0]["end_page"], 50, "my sitting is untouched");
}

#[tokio::test]
async fn a_photo_pushed_late_still_reaches_the_other_device() {
    // The 0034 bug, in the one channel that migration missed: a photo carries
    // the camera's clock (it is the last-write-wins key) and the delta pull
    // filtered on it, so a photo taken on Monday and pushed on Friday was
    // invisible to every device that had synced in between. Migration 0035.
    let app = test_app().await;
    let token = register(&app, "photos@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;
    let copy = create_copy(&app, &token, &book).await;

    let (_, body) = call(&app, "GET", "/api/copy-photos?cursor=", Some(&token), None).await;
    let cursor = encode(body["server_now"].as_str().unwrap());

    call(
        &app,
        "PUT",
        "/api/copy-photos/p1",
        Some(&token),
        Some(json!({
            "copy_id": copy,
            "caption": "taken last week, sent today",
            "taken_at": "2020-01-01 00:00:00",
            "updated_at": "2020-01-01 00:00:00",
        })),
    )
    .await;

    let (status, list) = call(
        &app,
        "GET",
        &format!("/api/copy-photos?cursor={cursor}"),
        Some(&token),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(
        list["photos"].as_array().unwrap().len(),
        1,
        "a delta pull is about when the server heard, not when the camera wrote"
    );
}

#[tokio::test]
async fn ink_is_an_annotation_like_any_other_and_stays_private() {
    // Writing on the page rides the channel highlights already ride: keyed by
    // user, so a shared library carries each reader's marks separately. The
    // payload is opaque here — the server stores the string and returns it.
    let app = test_app().await;
    let master = register(&app, "owner@lib.test").await;
    let member = add_member(&app, &master, "friend@lib.test").await;
    let book = create_book(&app, &master, "Dune").await;

    const MARKS: &str = r#"{"v":1,"strokes":[{"c":4294901760,"w":0.004,"p":[0.1,0.2,0.11,0.21]}],"texts":[{"x":0.3,"y":0.4,"s":0.02,"c":4278190080,"t":"see ch. 4"}]}"#;
    let (status, body) = call(
        &app,
        "PUT",
        "/api/annotations/ink1",
        Some(&master),
        Some(json!({
            "book_id": book,
            "kind": "ink",
            "page": 42,
            "ink": MARKS,
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "upsert: {body}");
    assert_eq!(body["ink"], MARKS, "returned verbatim");

    let (_, mine) = call(&app, "GET", "/api/annotations?cursor=", Some(&master), None).await;
    assert_eq!(entries(&mine)[0]["ink"], MARKS);
    assert_eq!(entries(&mine)[0]["kind"], "ink");

    let (_, theirs) = call(&app, "GET", "/api/annotations?cursor=", Some(&member), None).await;
    assert!(
        entries(&theirs).is_empty(),
        "what you write on a page is yours, in a library you share"
    );
}

#[tokio::test]
async fn a_page_can_be_written_on_twice() {
    let app = test_app().await;
    let token = register(&app, "pen@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;

    for (marks, at) in [
        (
            r#"{"v":1,"strokes":[{"c":1,"w":0.004,"p":[0.1,0.1,0.2,0.2]}]}"#,
            "2026-08-23 10:00:00",
        ),
        (
            r#"{"v":1,"strokes":[{"c":1,"w":0.004,"p":[0.1,0.1,0.2,0.2]},{"c":1,"w":0.004,"p":[0.3,0.3,0.4,0.4]}]}"#,
            "2026-08-23 10:05:00",
        ),
    ] {
        call(
            &app,
            "PUT",
            "/api/annotations/ink1",
            Some(&token),
            Some(
                json!({"book_id": book, "kind": "ink", "page": 1, "ink": marks, "updated_at": at}),
            ),
        )
        .await;
    }

    let (_, body) = call(&app, "GET", "/api/annotations?cursor=", Some(&token), None).await;
    let list = entries(&body);
    assert_eq!(list.len(), 1, "one page, one sheet of marks");
    assert!(
        list[0]["ink"].as_str().unwrap().contains("0.3"),
        "the later drawing wins, strokes and all"
    );
}

#[tokio::test]
async fn a_kind_the_server_does_not_know_is_still_refused() {
    let app = test_app().await;
    let token = register(&app, "odd@lib.test").await;
    let book = create_book(&app, &token, "Dune").await;

    let (status, _) = call(
        &app,
        "PUT",
        "/api/annotations/x1",
        Some(&token),
        Some(json!({"book_id": book, "kind": "sticker"})),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
}
