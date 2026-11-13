//! Short-lived signed links for covers and downloads (v1.6.2).

use axum::body::Body;
use axum::http::{Request, StatusCode};
use serde_json::{Value, json};
use tower::ServiceExt;
use vellum_server::{AppState, RateLimiter, connect_db, router};

async fn test_app() -> axum::Router {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_test_{id}.db"));
    let data_dir = std::env::temp_dir().join(format!("vellum_test_data_{id}"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let limiter = |n| std::sync::Arc::new(RateLimiter::new(n, std::time::Duration::from_secs(60)));
    router(AppState {
        db,
        public_base_url: "http://test.local".into(),
        data_dir,
        http: reqwest::Client::new(),
        max_upload_bytes: 512 * 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(2)),
        enrich_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        basic_cache: std::sync::Arc::default(),
        public_limiter: limiter(60),
        search_limiter: limiter(30),
        send_limiter: limiter(30),
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
    let mut b = Request::builder().method(method).uri(uri);
    if let Some(t) = token {
        b = b.header("authorization", format!("Bearer {t}"));
    }
    let req = match body {
        Some(v) => b
            .header("content-type", "application/json")
            .body(Body::from(v.to_string()))
            .unwrap(),
        None => b.body(Body::empty()).unwrap(),
    };
    let res = app.clone().oneshot(req).await.unwrap();
    let status = res.status();
    let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
        .await
        .unwrap();
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

async fn status_of(app: &axum::Router, uri: &str) -> StatusCode {
    app.clone()
        .oneshot(Request::builder().uri(uri).body(Body::empty()).unwrap())
        .await
        .unwrap()
        .status()
}

struct World {
    app: axum::Router,
    master: String,
    alice: String,
    book: String,
    file: String,
}

async fn world() -> World {
    let app = test_app().await;
    let (s, b) = call(
        &app,
        "POST",
        "/api/auth/register",
        None,
        Some(json!({ "email": "o@lib.test", "display_name": "O", "password": "password123" })),
    )
    .await;
    assert_eq!(s, StatusCode::OK, "{b}");
    let master = b["token"].as_str().unwrap().to_string();
    call(
        &app,
        "POST",
        "/api/users",
        Some(&master),
        Some(json!({ "email": "a@lib.test", "display_name": "A", "password": "memberpass1" })),
    )
    .await;
    let (s, b) = call(
        &app,
        "POST",
        "/api/auth/login",
        None,
        Some(json!({ "email": "a@lib.test", "password": "memberpass1" })),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    let alice = b["token"].as_str().unwrap().to_string();
    let (_, b) = call(
        &app,
        "POST",
        "/api/books",
        Some(&master),
        Some(json!({ "title": "Dune" })),
    )
    .await;
    let book = b["id"].as_str().unwrap().to_string();
    let put = Request::builder()
        .method("PUT")
        .uri(format!("/api/books/{book}/cover"))
        .header("authorization", format!("Bearer {master}"))
        .header("content-type", "image/png")
        .body(Body::from(b"\x89PNG\r\n\x1a\n fake".to_vec()))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(put).await.unwrap().status(),
        StatusCode::OK
    );
    let up = Request::builder()
        .method("POST")
        .uri(format!("/api/books/{book}/files?filename=d.pdf"))
        .header("authorization", format!("Bearer {master}"))
        .header("content-type", "application/pdf")
        .body(Body::from(b"%PDF-1.4 hi".to_vec()))
        .unwrap();
    assert_eq!(
        app.clone().oneshot(up).await.unwrap().status(),
        StatusCode::OK
    );
    let (_, d) = call(
        &app,
        "GET",
        &format!("/api/books/{book}/detail"),
        Some(&master),
        None,
    )
    .await;
    let file = d["files"][0]["id"].as_str().unwrap().to_string();
    World {
        app,
        master,
        alice,
        book,
        file,
    }
}

async fn sign(w: &World, token: &str, path: &str) -> Option<String> {
    let (s, b) = call(
        &w.app,
        "POST",
        "/api/links",
        Some(token),
        Some(json!({ "paths": [path] })),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    b["links"][0]["url"].as_str().map(String::from)
}

#[tokio::test]
async fn signed_links_open_cover_and_file_without_a_header() {
    let w = world().await;
    let cover = sign(&w, &w.master, &format!("/api/books/{}/cover", w.book))
        .await
        .unwrap();
    assert_eq!(status_of(&w.app, &cover).await, StatusCode::OK);
    // Extra query (thumbnail width) is outside the signature.
    assert_eq!(
        status_of(&w.app, &format!("{cover}&w=160")).await,
        StatusCode::OK
    );
    let file = sign(&w, &w.master, &format!("/api/files/{}", w.file))
        .await
        .unwrap();
    assert_eq!(status_of(&w.app, &file).await, StatusCode::OK);
}

#[tokio::test]
async fn tampered_wrong_path_expired_and_other_user_are_refused() {
    let w = world().await;
    let cover_path = format!("/api/books/{}/cover", w.book);
    let url = sign(&w, &w.master, &cover_path).await.unwrap();
    let q = url.split_once('?').unwrap().1.to_string();

    // Wrong path: the cover's signature on the file route.
    assert_eq!(
        status_of(&w.app, &format!("/api/files/{}?{q}", w.file)).await,
        StatusCode::UNAUTHORIZED
    );
    // Tampered signature, and tampered expiry.
    assert_eq!(
        status_of(&w.app, &url.replace("sig=", "sig=0")).await,
        StatusCode::UNAUTHORIZED
    );
    let exp: i64 = q
        .split('&')
        .find_map(|p| p.strip_prefix("exp="))
        .unwrap()
        .parse()
        .unwrap();
    let later = url.replace(&format!("exp={exp}"), &format!("exp={}", exp + 1000));
    assert_eq!(status_of(&w.app, &later).await, StatusCode::UNAUTHORIZED);
    // An expiry in the past is refused (and cannot be re-signed without the key).
    let past = url.replace(&format!("exp={exp}"), "exp=1");
    assert_eq!(status_of(&w.app, &past).await, StatusCode::UNAUTHORIZED);
    // Another user id with the owner's signature.
    let (_, me) = call(&w.app, "GET", "/api/auth/me", Some(&w.alice), None).await;
    let alice_id = me["id"].as_str().unwrap();
    let u = q.split('&').find_map(|p| p.strip_prefix("u=")).unwrap();
    assert_eq!(
        status_of(&w.app, &url.replace(u, alice_id)).await,
        StatusCode::UNAUTHORIZED
    );
    // A signature never opens an endpoint that is not a cover or file.
    assert_eq!(
        status_of(&w.app, &format!("/api/books/{}/detail?{q}", w.book)).await,
        StatusCode::UNAUTHORIZED
    );
}

#[tokio::test]
async fn link_follows_access_and_rotation() {
    let w = world().await;
    // Alice cannot get a link to a book she cannot see.
    let path = format!("/api/books/{}/cover", w.book);
    assert!(sign(&w, &w.alice, &path).await.is_none());

    let (s, share) = call(
        &w.app,
        "POST",
        "/api/shares",
        Some(&w.master),
        Some(json!({ "scope": "book", "scope_id": w.book, "grantee_email": "a@lib.test" })),
    )
    .await;
    assert_eq!(s, StatusCode::OK);
    let url = sign(&w, &w.alice, &path).await.unwrap();
    assert_eq!(status_of(&w.app, &url).await, StatusCode::OK);

    // Revoke: the already-minted link stops working.
    let id = share["id"].as_str().unwrap();
    call(
        &w.app,
        "DELETE",
        &format!("/api/shares/{id}"),
        Some(&w.master),
        None,
    )
    .await;
    assert_eq!(status_of(&w.app, &url).await, StatusCode::NOT_FOUND);

    // Rotation kills every link; members cannot rotate.
    let mine = sign(&w, &w.master, &path).await.unwrap();
    assert_eq!(status_of(&w.app, &mine).await, StatusCode::OK);
    let (s, _) = call(&w.app, "POST", "/api/links/rotate", Some(&w.alice), None).await;
    assert_eq!(s, StatusCode::FORBIDDEN);
    let (s, _) = call(&w.app, "POST", "/api/links/rotate", Some(&w.master), None).await;
    assert_eq!(s, StatusCode::OK);
    assert_eq!(status_of(&w.app, &mine).await, StatusCode::UNAUTHORIZED);
    let fresh = sign(&w, &w.master, &path).await.unwrap();
    assert_eq!(status_of(&w.app, &fresh).await, StatusCode::OK);
}

#[tokio::test]
async fn signing_rejects_other_paths_and_session_token_query_still_fails() {
    let w = world().await;
    let (s, _) = call(
        &w.app,
        "POST",
        "/api/links",
        Some(&w.master),
        Some(json!({ "paths": ["/api/admin/snapshot"] })),
    )
    .await;
    assert_eq!(s, StatusCode::BAD_REQUEST);
    let (s, _) = call(
        &w.app,
        "POST",
        "/api/links",
        None,
        Some(json!({ "paths": [] })),
    )
    .await;
    assert_eq!(s, StatusCode::UNAUTHORIZED);
    assert_eq!(
        status_of(
            &w.app,
            &format!("/api/books/{}/cover?token={}", w.book, w.master)
        )
        .await,
        StatusCode::UNAUTHORIZED
    );
}
