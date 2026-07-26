//! The access-control matrix (plan 5 #46).
//!
//! `api.rs` covers happy paths and the specific holes that have been fixed.
//! This file covers the thing those tests can't: *every* actor against *every*
//! operation, in one table. Access control is the security-critical part of the
//! server, and a matrix is the only shape that makes an accidental gap visible —
//! a new endpoint added without a row here is a conspicuously empty column
//! rather than an oversight nobody notices.
//!
//! **The policy the table encodes**, taken from `access.rs` and the handlers:
//!
//! - *Can't see it* → **404**, never 403. A 403 confirms the id exists, which
//!   tells an unauthorised caller something about a library they can't read.
//! - *Can see it but not change it* → **403**, with a message.
//! - **Deleting needs ownership**, not merely editor rights: an editor share
//!   lets someone correct a book, not destroy someone else's copy.
//! - **Public links belong to the owner**, so minting one needs ownership too.
//! - *Recording your own reading position* needs only **view** access — it is
//!   your data about someone else's book (plan 5 #5).
//!
//! Anything that disagrees with the table is either a bug in the server or a
//! deliberate policy change that has to be made here first.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{Value, json};
use tower::ServiceExt;
use vellum_server::{AppState, connect_db, router};

async fn test_app() -> (axum::Router, std::path::PathBuf) {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_rbac_{id}.db"));
    let data_dir = std::env::temp_dir().join(format!("vellum_rbac_data_{id}"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let app = router(AppState {
        db,
        public_base_url: "http://test.local".into(),
        data_dir: data_dir.clone(),
        http: reqwest::Client::new(),
        max_upload_bytes: 64 * 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(2)),
        basic_cache: std::sync::Arc::default(),
        public_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            10_000,
            std::time::Duration::from_secs(60),
        )),
        search_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            10_000,
            std::time::Duration::from_secs(60),
        )),
        mailer: None,
        index_text: true,
        audit: true,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    });
    (app, data_dir)
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
    let value = if bytes.is_empty() {
        Value::Null
    } else {
        serde_json::from_slice(&bytes).unwrap_or(Value::Null)
    };
    (status, value)
}

/// Everyone in the matrix, and the token each one carries.
struct World {
    app: axum::Router,
    master: String,
    /// A member who owns `book`.
    owner: String,
    /// Members reached through each kind of share.
    editor: String,
    viewer: String,
    grouped: String,
    /// A member with no relationship to the book at all.
    unrelated: String,
    book: String,
}

async fn login(app: &axum::Router, email: &str) -> String {
    let (status, body) = call(
        app,
        "POST",
        "/api/auth/login",
        None,
        Some(json!({ "email": email, "password": "memberpass1" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "login {email}: {body}");
    body["token"].as_str().unwrap().to_string()
}

async fn add_member(app: &axum::Router, master: &str, email: &str) -> String {
    let (status, body) = call(
        app,
        "POST",
        "/api/users",
        Some(master),
        Some(json!({
            "email": email,
            "display_name": email,
            "password": "memberpass1"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "create {email}: {body}");
    login(app, email).await
}

/// Builds the whole cast plus one book owned by `owner`, shared four ways.
async fn world() -> World {
    let (app, _dir) = test_app().await;
    let (status, body) = call(
        &app,
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
    assert_eq!(status, StatusCode::OK, "register master: {body}");
    let master = body["token"].as_str().unwrap().to_string();

    let owner = add_member(&app, &master, "owner@lib.test").await;
    let editor = add_member(&app, &master, "editor@lib.test").await;
    let viewer = add_member(&app, &master, "viewer@lib.test").await;
    let grouped = add_member(&app, &master, "grouped@lib.test").await;
    let unrelated = add_member(&app, &master, "unrelated@lib.test").await;

    // The book under test belongs to `owner`, not the master — so "master can do
    // everything" is genuinely being tested rather than trivially true.
    let (status, book) = call(
        &app,
        "POST",
        "/api/books",
        Some(&owner),
        Some(json!({ "title": "Dune" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "create book: {book}");
    let book = book["id"].as_str().unwrap().to_string();

    for (grantee, permission) in [("editor@lib.test", "editor"), ("viewer@lib.test", "viewer")] {
        let (status, body) = call(
            &app,
            "POST",
            "/api/shares",
            Some(&owner),
            Some(json!({
                "scope": "book",
                "scope_id": book,
                "grantee_email": grantee,
                "permission": permission
            })),
        )
        .await;
        assert_eq!(status, StatusCode::OK, "share to {grantee}: {body}");
    }

    // The group route to the same book, which resolves through a different arm
    // of `access_predicate` than a book-scoped share.
    let (status, group) = call(
        &app,
        "POST",
        "/api/groups",
        Some(&owner),
        Some(json!({ "name": "Shared shelf" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "create group: {group}");
    let group_id = group["id"].as_str().unwrap().to_string();
    call(
        &app,
        "POST",
        &format!("/api/groups/{group_id}/books"),
        Some(&owner),
        Some(json!({ "book_id": book })),
    )
    .await;
    let (status, body) = call(
        &app,
        "POST",
        "/api/shares",
        Some(&owner),
        Some(json!({
            "scope": "group",
            "scope_id": group_id,
            "grantee_email": "grouped@lib.test",
            "permission": "viewer"
        })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "group share: {body}");

    World {
        app,
        master,
        owner,
        editor,
        viewer,
        grouped,
        unrelated,
        book,
    }
}

/// Who is acting.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum Actor {
    Master,
    Owner,
    EditorShare,
    ViewerShare,
    GroupShare,
    Unrelated,
    Anonymous,
}

impl Actor {
    fn token(self, w: &World) -> Option<&str> {
        match self {
            Actor::Master => Some(&w.master),
            Actor::Owner => Some(&w.owner),
            Actor::EditorShare => Some(&w.editor),
            Actor::ViewerShare => Some(&w.viewer),
            Actor::GroupShare => Some(&w.grouped),
            Actor::Unrelated => Some(&w.unrelated),
            Actor::Anonymous => None,
        }
    }
}

const EVERYONE: [Actor; 7] = [
    Actor::Master,
    Actor::Owner,
    Actor::EditorShare,
    Actor::ViewerShare,
    Actor::GroupShare,
    Actor::Unrelated,
    Actor::Anonymous,
];

/// One operation on the shared book, and what each actor should get.
struct Op {
    name: &'static str,
    method: &'static str,
    /// `{book}` is substituted with the book id.
    uri: &'static str,
    body: Option<fn() -> Value>,
    /// Expected status per actor, in [`EVERYONE`] order.
    expected: [StatusCode; 7],
}

const OK: StatusCode = StatusCode::OK;
const FORBIDDEN: StatusCode = StatusCode::FORBIDDEN;
const NOT_FOUND: StatusCode = StatusCode::NOT_FOUND;
const UNAUTHORIZED: StatusCode = StatusCode::UNAUTHORIZED;

fn operations() -> Vec<Op> {
    vec![
        Op {
            name: "read the book",
            method: "GET",
            uri: "/api/books/{book}",
            body: None,
            //        master  owner  editor  viewer  group   unrelated   anon
            expected: [OK, OK, OK, OK, OK, NOT_FOUND, UNAUTHORIZED],
        },
        Op {
            name: "list its files",
            method: "GET",
            uri: "/api/books/{book}/files",
            body: None,
            expected: [OK, OK, OK, OK, OK, NOT_FOUND, UNAUTHORIZED],
        },
        Op {
            name: "edit it (PUT)",
            method: "PUT",
            uri: "/api/books/{book}",
            body: Some(|| json!({ "title": "Edited" })),
            // A viewer can see it but must not change it: 403, not 404 —
            // pretending it doesn't exist would be a lie to someone who can
            // plainly read it.
            expected: [OK, OK, OK, FORBIDDEN, FORBIDDEN, NOT_FOUND, UNAUTHORIZED],
        },
        Op {
            name: "edit it (PATCH)",
            method: "PATCH",
            uri: "/api/books/{book}",
            body: Some(|| json!({ "title": "Patched" })),
            expected: [OK, OK, OK, FORBIDDEN, FORBIDDEN, NOT_FOUND, UNAUTHORIZED],
        },
        Op {
            name: "record my reading position",
            method: "PUT",
            uri: "/api/reading-progress/{book}",
            body: Some(|| json!({ "device_id": "d1", "progress": 0.5 })),
            // View access is the right bar: where *you* are in a book someone
            // shared with you is your own data (plan 5 #5).
            expected: [OK, OK, OK, OK, OK, NOT_FOUND, UNAUTHORIZED],
        },
        Op {
            name: "mint a public link for it",
            method: "POST",
            uri: "/api/share-links",
            body: None, // built per-op below, needs the book id in the body
            expected: [
                OK,
                OK,
                FORBIDDEN,
                FORBIDDEN,
                FORBIDDEN,
                FORBIDDEN,
                UNAUTHORIZED,
            ],
        },
        Op {
            name: "delete it",
            method: "DELETE",
            uri: "/api/books/{book}",
            body: None,
            // Deleting needs *ownership*: the master and the owner may, an
            // editor share may not — it lets you correct a book, not destroy
            // someone else's copy. Someone who can't see it gets 404 like
            // everywhere else, so DELETE can't be used to probe for ids.
            expected: [
                OK,
                OK,
                FORBIDDEN,
                FORBIDDEN,
                FORBIDDEN,
                NOT_FOUND,
                UNAUTHORIZED,
            ],
        },
    ]
}

#[tokio::test(flavor = "multi_thread")]
async fn the_access_matrix_holds() {
    // A fresh world per cell, because operations mutate (an edit, a delete) and a
    // shared one would make results depend on iteration order. The cells are
    // independent, so they run concurrently — setup is dominated by Argon2
    // password hashing, which is slow on purpose, and 49 sequential setups took
    // minutes.
    let mut cells = tokio::task::JoinSet::new();
    for (index, op) in operations().into_iter().enumerate() {
        for (actor_index, actor) in EVERYONE.into_iter().enumerate() {
            cells.spawn(async move {
                let w = world().await;
                let uri = op.uri.replace("{book}", &w.book);
                let body = if op.name.starts_with("mint") {
                    Some(json!({ "book_id": w.book }))
                } else {
                    op.body.map(|f| f())
                };
                let (status, response) = call(&w.app, op.method, &uri, actor.token(&w), body).await;
                assert_eq!(
                    status, op.expected[actor_index],
                    "row {index} `{}` for {actor:?}: got {status} — {response}",
                    op.name,
                );
            });
        }
    }
    while let Some(cell) = cells.join_next().await {
        // Propagate the assertion message rather than a bare JoinError.
        if let Err(e) = cell {
            std::panic::resume_unwind(e.into_panic());
        }
    }
}

#[tokio::test]
async fn listing_shows_exactly_what_each_actor_may_see() {
    // The list endpoint is where a visibility bug leaks *titles* rather than a
    // single book, so it gets its own assertion rather than a status code.
    let w = world().await;
    for (actor, should_see) in [
        (Actor::Master, true),
        (Actor::Owner, true),
        (Actor::EditorShare, true),
        (Actor::ViewerShare, true),
        (Actor::GroupShare, true),
        (Actor::Unrelated, false),
    ] {
        let (status, body) = call(&w.app, "GET", "/api/books", actor.token(&w), None).await;
        assert_eq!(status, StatusCode::OK, "{actor:?}: {body}");
        let titles: Vec<&str> = body
            .as_array()
            .unwrap()
            .iter()
            .filter_map(|b| b["title"].as_str())
            .collect();
        assert_eq!(
            titles.contains(&"Dune"),
            should_see,
            "{actor:?} saw {titles:?}"
        );
    }

    let (status, _) = call(&w.app, "GET", "/api/books", None, None).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "anonymous listing");
}

#[tokio::test]
async fn a_revoked_share_takes_access_with_it() {
    // The matrix is a snapshot; this is the transition. Revocation that leaves
    // read access behind would be invisible to a matrix taken after setup.
    let w = world().await;
    let (status, shares) = call(&w.app, "GET", "/api/shares", Some(&w.owner), None).await;
    assert_eq!(status, StatusCode::OK, "{shares}");
    let share_id = shares
        .as_array()
        .unwrap()
        .iter()
        .find(|s| s["grantee_email"] == json!("viewer@lib.test"))
        .and_then(|s| s["id"].as_str())
        .expect("the viewer share exists")
        .to_string();

    let (status, _) = call(
        &w.app,
        "GET",
        &format!("/api/books/{}", w.book),
        Some(&w.viewer),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK, "viewer can read before revocation");

    let (status, _) = call(
        &w.app,
        "DELETE",
        &format!("/api/shares/{share_id}"),
        Some(&w.owner),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);

    let (status, _) = call(
        &w.app,
        "GET",
        &format!("/api/books/{}", w.book),
        Some(&w.viewer),
        None,
    )
    .await;
    assert_eq!(
        status,
        StatusCode::NOT_FOUND,
        "a revoked viewer must lose the book entirely, not just editing"
    );
}

#[tokio::test]
async fn a_member_cannot_act_as_the_master() {
    // The master-only surface, as its own row set: these are the endpoints where
    // a mistake hands over the library rather than one book.
    let w = world().await;
    for (method, uri, body) in [
        (
            "POST",
            "/api/users",
            Some(json!({
                "email": "sneaky@lib.test",
                "display_name": "S",
                "password": "memberpass1"
            })),
        ),
        ("GET", "/api/admin/stats", None),
        ("POST", "/api/admin/sweep", None),
        ("GET", "/api/admin/snapshot", None),
    ] {
        for actor in [Actor::Owner, Actor::ViewerShare, Actor::Unrelated] {
            let (status, response) = call(&w.app, method, uri, actor.token(&w), body.clone()).await;
            assert_eq!(
                status,
                StatusCode::FORBIDDEN,
                "{actor:?} reached {method} {uri}: {response}"
            );
        }
        let (status, _) = call(&w.app, method, uri, None, body.clone()).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "anonymous {method} {uri}");
    }
}
