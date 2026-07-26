//! OPDS navigation, search, paging and 2.0 (plan 5 #34).
//!
//! The feed is the interface every third-party e-reader sees, and unlike the
//! JSON API nothing else exercises it — so the relations we *claim* (search,
//! next/previous, subsection) are asserted here rather than trusted.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use base64::Engine;
use tower::ServiceExt;
use vellum_server::{AppState, RateLimiter, connect_db, router};

async fn app(index_text: bool) -> axum::Router {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_opds_{id}.db"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    router(AppState {
        db,
        public_base_url: "http://books.test".into(),
        data_dir: std::env::temp_dir().join(format!("vellum_opds_data_{id}")),
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
        index_text,
        audit: true,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    })
}

const EMAIL: &str = "master@lib.test";
const PASSWORD: &str = "a long enough passphrase";

async fn register(app: &axum::Router) -> String {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/auth/register")
                .header("content-type", "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "email": EMAIL,
                        "password": PASSWORD,
                        "display_name": "M",
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    body["token"].as_str().unwrap().to_string()
}

fn basic() -> String {
    format!(
        "Basic {}",
        base64::engine::general_purpose::STANDARD.encode(format!("{EMAIL}:{PASSWORD}"))
    )
}

/// A feed's body, asserting the status on the way through.
async fn feed(app: &axum::Router, uri: &str) -> String {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri(uri)
                .header("authorization", basic())
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK, "GET {uri}");
    let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
        .await
        .unwrap();
    String::from_utf8(bytes.to_vec()).unwrap()
}

async fn add_book(app: &axum::Router, token: &str, body: serde_json::Value) -> String {
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/books")
                .header("authorization", format!("Bearer {token}"))
                .header("content-type", "application/json")
                .body(Body::from(body.to_string()))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
        .await
        .unwrap();
    let created: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    created["id"].as_str().unwrap().to_string()
}

#[tokio::test]
async fn the_root_is_a_navigation_feed_with_the_relations_clients_look_for() {
    let app = app(false).await;
    let _ = register(&app).await;
    let xml = feed(&app, "/opds").await;

    // An OPDS client finds search through this exact relation; without it there
    // is no search box on the device at all.
    assert!(xml.contains(r#"rel="search""#));
    assert!(xml.contains("/opds/search.xml"));
    // And OPDS 2.0 is offered as an alternate rather than by sniffing.
    assert!(xml.contains(r#"rel="alternate""#));
    assert!(xml.contains("/opds/v2"));
    for section in [
        "/opds/recent",
        "/opds/all",
        "/opds/authors",
        "/opds/genres",
        "/opds/groups",
    ] {
        assert!(xml.contains(section), "root should link {section}");
    }
    assert!(xml.contains(r#"rel="subsection""#));
}

#[tokio::test]
async fn the_opensearch_descriptor_is_served_and_templated() {
    let app = app(false).await;
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/opds/search.xml")
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
        .await
        .unwrap();
    let xml = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(xml.contains("OpenSearchDescription"));
    // The literal `{searchTerms}` is what the client substitutes into; losing
    // it (to escaping, say) makes search silently search for nothing.
    assert!(xml.contains("{searchTerms}"));
    assert!(xml.contains("http://books.test/opds/search?q="));
}

#[tokio::test]
async fn paging_links_round_trip_through_a_long_feed() {
    let app = app(false).await;
    let token = register(&app).await;
    // 51 books: two pages at a page size of 50, so both ends of the walk exist.
    for i in 0..51 {
        add_book(
            &app,
            &token,
            serde_json::json!({ "title": format!("B{i:03}") }),
        )
        .await;
    }

    let first = feed(&app, "/opds/all").await;
    assert!(first.contains("<opensearch:totalResults>51</opensearch:totalResults>"));
    assert!(first.contains(r#"rel="next""#));
    assert!(
        !first.contains(r#"rel="previous""#),
        "page 1 has no previous"
    );
    assert!(first.contains("page=2"));
    assert_eq!(first.matches("<entry>").count(), 50);

    let second = feed(&app, "/opds/all?page=2").await;
    assert_eq!(second.matches("<entry>").count(), 1);
    assert!(second.contains(r#"rel="previous""#));
    assert!(
        !second.contains(r#"rel="next""#),
        "the last page must not promise another"
    );
    // The two pages are disjoint and cover the whole catalogue.
    assert!(first.contains("<title>B000</title>"));
    assert!(second.contains("<title>B050</title>"));
    assert!(!second.contains("<title>B000</title>"));
}

/// Creates a book and then PUTs it with authors/genres — `POST /api/books`
/// deliberately takes only the plain columns, so the joins arrive on the upsert.
async fn add_book_with(
    app: &axum::Router,
    token: &str,
    title: &str,
    authors: &[&str],
    genres: &[&str],
) -> String {
    let id = add_book(app, token, serde_json::json!({ "title": title })).await;
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("PUT")
                .uri(format!("/api/books/{id}"))
                .header("authorization", format!("Bearer {token}"))
                .header("content-type", "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "title": title,
                        "authors": authors,
                        "genres": genres,
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    id
}

#[tokio::test]
async fn browsing_by_author_and_genre_reaches_the_right_books() {
    let app = app(false).await;
    let token = register(&app).await;
    add_book_with(
        &app,
        &token,
        "Dune",
        &["Frank Herbert"],
        &["Science Fiction"],
    )
    .await;
    add_book_with(&app, &token, "Emma", &["Jane Austen"], &["Classics"]).await;

    let authors = feed(&app, "/opds/authors").await;
    assert!(authors.contains("Frank Herbert"));
    assert!(authors.contains("Jane Austen"));

    // Percent-encoded in the link, because a raw space is not a URL.
    assert!(authors.contains("/opds/authors/Frank%20Herbert"));
    let herbert = feed(&app, "/opds/authors/Frank%20Herbert").await;
    assert!(herbert.contains("<title>Dune</title>"));
    assert!(!herbert.contains("<title>Emma</title>"));

    let genres = feed(&app, "/opds/genres").await;
    assert!(genres.contains("Science Fiction"));
    let scifi = feed(&app, "/opds/genres/Science%20Fiction").await;
    assert!(scifi.contains("<title>Dune</title>"));
    assert!(!scifi.contains("<title>Emma</title>"));
}

#[tokio::test]
async fn search_matches_titles_and_authors_and_stays_well_formed_when_empty() {
    let app = app(false).await;
    let token = register(&app).await;
    add_book_with(&app, &token, "Dune", &["Frank Herbert"], &[]).await;
    add_book(&app, &token, serde_json::json!({ "title": "Emma" })).await;

    let by_title = feed(&app, "/opds/search?q=dun").await;
    assert!(by_title.contains("<title>Dune</title>"));
    assert!(!by_title.contains("<title>Emma</title>"));

    let by_author = feed(&app, "/opds/search?q=herbert").await;
    assert!(by_author.contains("<title>Dune</title>"));

    // A client probing the descriptor sends an empty q; that has to be a feed,
    // not a 400 it cannot render.
    let empty = feed(&app, "/opds/search?q=").await;
    assert!(empty.contains("<feed"));
    assert_eq!(empty.matches("<entry>").count(), 0);
}

#[tokio::test]
async fn search_honours_rbac() {
    // The catalogue is a second way to read the library; it must not be a
    // looser one.
    let app = app(false).await;
    let owner = register(&app).await;
    add_book(&app, &owner, serde_json::json!({ "title": "Private" })).await;

    // A second account with no share.
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .method("POST")
                .uri("/api/users")
                .header("authorization", format!("Bearer {owner}"))
                .header("content-type", "application/json")
                .body(Body::from(
                    serde_json::json!({
                        "email": "other@lib.test",
                        "password": "another good passphrase",
                        "display_name": "Other",
                    })
                    .to_string(),
                ))
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);

    let other = format!(
        "Basic {}",
        base64::engine::general_purpose::STANDARD.encode("other@lib.test:another good passphrase")
    );
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/opds/search?q=private")
                .header("authorization", other)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
        .await
        .unwrap();
    let xml = String::from_utf8(bytes.to_vec()).unwrap();
    assert!(
        !xml.contains("<title>Private</title>"),
        "someone else's book must not appear in the catalogue"
    );
}

#[tokio::test]
async fn an_unchanged_catalogue_answers_304() {
    let app = app(false).await;
    let token = register(&app).await;
    add_book(&app, &token, serde_json::json!({ "title": "Dune" })).await;

    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/opds/all")
                .header("authorization", basic())
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    let tag = res
        .headers()
        .get("etag")
        .expect("acquisition feeds carry an ETag")
        .to_str()
        .unwrap()
        .to_string();

    let again = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/opds/all")
                .header("authorization", basic())
                .header("if-none-match", &tag)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(again.status(), StatusCode::NOT_MODIFIED);

    // Adding a book changes the validator, so the client refetches.
    add_book(&app, &token, serde_json::json!({ "title": "Emma" })).await;
    let after = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/opds/all")
                .header("authorization", basic())
                .header("if-none-match", &tag)
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(after.status(), StatusCode::OK);
}

#[tokio::test]
async fn opds_2_serves_the_same_root_as_json() {
    let app = app(false).await;
    let _ = register(&app).await;
    let res = app
        .clone()
        .oneshot(
            Request::builder()
                .uri("/opds/v2")
                .header("authorization", basic())
                .body(Body::empty())
                .unwrap(),
        )
        .await
        .unwrap();
    assert_eq!(res.status(), StatusCode::OK);
    assert_eq!(
        res.headers().get("content-type").unwrap(),
        "application/opds+json"
    );
    let bytes = axum::body::to_bytes(res.into_body(), usize::MAX)
        .await
        .unwrap();
    let body: serde_json::Value = serde_json::from_slice(&bytes).unwrap();
    assert_eq!(body["metadata"]["title"], "Vellum Library");
    let navigation = body["navigation"].as_array().unwrap();
    assert!(
        navigation
            .iter()
            .any(|n| n["href"] == "http://books.test/opds/all")
    );
    // The search link is templated, which is how a 2.0 client builds a query.
    let search = body["links"]
        .as_array()
        .unwrap()
        .iter()
        .find(|l| l["rel"] == "search")
        .expect("a search link");
    assert_eq!(search["templated"], true);
    assert!(search["href"].as_str().unwrap().contains("{searchTerms}"));
}

#[tokio::test]
async fn the_full_text_section_appears_only_where_there_is_an_index() {
    let without = app(false).await;
    let _ = register(&without).await;
    assert!(
        !feed(&without, "/opds")
            .await
            .contains("Search inside books")
    );

    let with = app(true).await;
    let _ = register(&with).await;
    assert!(feed(&with, "/opds").await.contains("Search inside books"));
}

#[tokio::test]
async fn feeds_require_credentials() {
    // Every acquisition feed, not just the root: a catalogue that leaks one
    // page leaks the library.
    let app = app(false).await;
    let _ = register(&app).await;
    for uri in [
        "/opds",
        "/opds/all",
        "/opds/recent",
        "/opds/authors",
        "/opds/genres",
        "/opds/groups",
        "/opds/search?q=a",
        "/opds/v2",
    ] {
        let res = app
            .clone()
            .oneshot(Request::builder().uri(uri).body(Body::empty()).unwrap())
            .await
            .unwrap();
        assert_eq!(
            res.status(),
            StatusCode::UNAUTHORIZED,
            "{uri} must challenge"
        );
    }
}
