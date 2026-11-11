//! The console is a folder of ES modules (`web/console/`), embedded in the
//! binary and served from `/assets/console/<name>`. What can go wrong is quiet:
//! a module left out of the embedded list 404s one import and the console stops
//! loading — in production only, since the Node tests read the files from disk.
//! So this walks the folder and asks the server for every file in it.

use axum::body::Body;
use axum::http::{Request, StatusCode, header};
use tower::ServiceExt;
use vellum_server::{AppState, EventBus, RateLimiter, connect_db, router};

async fn app() -> axum::Router {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_console_assets_{id}.db"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    router(AppState {
        db,
        public_base_url: "http://test.local".into(),
        data_dir: std::env::temp_dir().join(format!("vellum_console_assets_data_{id}")),
        http: reqwest::Client::new(),
        max_upload_bytes: 16 * 1024 * 1024,
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

async fn get(app: &axum::Router, uri: &str) -> axum::response::Response {
    app.clone()
        .oneshot(Request::builder().uri(uri).body(Body::empty()).unwrap())
        .await
        .unwrap()
}

fn module_files() -> Vec<String> {
    let dir = std::path::Path::new(env!("CARGO_MANIFEST_DIR")).join("web/console");
    let mut names: Vec<String> = std::fs::read_dir(dir)
        .unwrap()
        .map(|e| e.unwrap().file_name().into_string().unwrap())
        .filter(|n| n.ends_with(".js"))
        .collect();
    names.sort();
    names
}

#[tokio::test]
async fn every_module_in_the_folder_is_served_as_javascript() {
    let app = app().await;
    let names = module_files();
    assert!(names.contains(&"main.js".to_string()), "the entry point");
    for name in names {
        let res = get(&app, &format!("/assets/console/{name}")).await;
        assert_eq!(res.status(), StatusCode::OK, "{name} is not embedded");
        assert_eq!(
            res.headers()[header::CONTENT_TYPE],
            "text/javascript; charset=utf-8",
            "{name}: a module script with any other type is refused by the browser"
        );
        assert_eq!(res.headers()[header::CACHE_CONTROL], "no-store", "{name}");
    }
}

#[tokio::test]
async fn the_page_loads_the_entry_module_and_the_csp_allows_it() {
    let app = app().await;
    let res = get(&app, "/").await;
    assert_eq!(res.status(), StatusCode::OK);
    let csp = res.headers()[header::CONTENT_SECURITY_POLICY]
        .to_str()
        .unwrap()
        .to_string();
    assert!(csp.contains("script-src 'self'"), "{csp}");
    let body = axum::body::to_bytes(res.into_body(), usize::MAX)
        .await
        .unwrap();
    let html = String::from_utf8(body.to_vec()).unwrap();
    assert!(
        html.contains(r#"<script type="module" src="/assets/console/main.js">"#),
        "console.html must load the entry module"
    );
}

#[tokio::test]
async fn nothing_but_the_listed_modules_is_reachable() {
    let app = app().await;
    for uri in [
        "/assets/console/package.json",
        "/assets/console/nope.js",
        "/assets/console/..%2Fconsole.html",
        "/assets/console/%2E%2E%2Fconsole.css",
        "/assets/console/tests",
        "/assets/console/",
        "/assets/console.js",
        "/assets/console/../tests/pages.test.js",
    ] {
        let res = get(&app, uri).await;
        assert!(
            res.status() == StatusCode::NOT_FOUND || res.status() == StatusCode::BAD_REQUEST,
            "{uri} answered {}",
            res.status()
        );
    }
}
