//! Two-factor sign-in (v1.6.2): enrolment, the two-step login, replay and
//! throttling, recovery codes, and the edges — Basic auth, app passwords,
//! password reset and an owner clearing someone else's.
//!
//! Codes are computed with the server's own `totp` module from the secret the
//! setup endpoint hands out, as an authenticator app would. Tests use the
//! current step and the next one only, which the ±1 window always accepts
//! whichever side of a step boundary the server's clock reads.

use axum::body::Body;
use axum::http::{Request, StatusCode};
use base64::Engine;
use serde_json::{Value, json};
use tower::ServiceExt;
use vellum_server::{AppState, EventBus, RateLimiter, connect_db, router, totp};

async fn test_app() -> (axum::Router, sqlx::SqlitePool) {
    let id = uuid::Uuid::new_v4();
    let path = std::env::temp_dir().join(format!("vellum_2fa_{id}.db"));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();
    let limiter =
        || std::sync::Arc::new(RateLimiter::new(1000, std::time::Duration::from_secs(60)));
    let app = router(AppState {
        db: db.clone(),
        public_base_url: "http://books.test".into(),
        data_dir: std::env::temp_dir().join(format!("vellum_2fa_data_{id}")),
        http: reqwest::Client::new(),
        max_upload_bytes: 8 * 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        enrich_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(1)),
        basic_cache: std::sync::Arc::default(),
        public_limiter: limiter(),
        search_limiter: limiter(),
        send_limiter: limiter(),
        events: EventBus::new(),
        mailer: None,
        index_text: false,
        audit: true,
        text_notify: std::sync::Arc::new(tokio::sync::Notify::new()),
        tls_cert: None,
    });
    (app, db)
}

const MASTER: &str = "master@lib.test";
const MEMBER: &str = "member@lib.test";
const PASSWORD: &str = "a long enough passphrase";

enum Auth<'a> {
    None,
    Bearer(&'a str),
    Basic(&'a str, &'a str),
}

async fn call(
    app: &axum::Router,
    method: &str,
    uri: &str,
    auth: Auth<'_>,
    body: Option<Value>,
) -> (StatusCode, Value) {
    let mut builder = Request::builder().method(method).uri(uri);
    match auth {
        Auth::None => {}
        Auth::Bearer(t) => builder = builder.header("authorization", format!("Bearer {t}")),
        Auth::Basic(user, pw) => {
            let encoded = base64::engine::general_purpose::STANDARD.encode(format!("{user}:{pw}"));
            builder = builder.header("authorization", format!("Basic {encoded}"));
        }
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
    (
        status,
        serde_json::from_slice(&bytes).unwrap_or(Value::Null),
    )
}

async fn register_master(app: &axum::Router) -> String {
    let (status, body) = call(
        app,
        "POST",
        "/api/auth/register",
        Auth::None,
        Some(json!({ "email": MASTER, "password": PASSWORD, "display_name": "M" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body["token"].as_str().unwrap().to_string()
}

async fn add_member(app: &axum::Router, master: &str) -> String {
    let (status, body) = call(
        app,
        "POST",
        "/api/users",
        Auth::Bearer(master),
        Some(json!({ "email": MEMBER, "password": PASSWORD, "display_name": "Ana" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let (status, body) = login(app, MEMBER).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    body["token"].as_str().unwrap().to_string()
}

async fn login(app: &axum::Router, email: &str) -> (StatusCode, Value) {
    call(
        app,
        "POST",
        "/api/auth/login",
        Auth::None,
        Some(json!({ "email": email, "password": PASSWORD })),
    )
    .await
}

/// Password sign-in on a two-factor account: the challenge it hands out.
async fn challenge(app: &axum::Router, email: &str) -> String {
    let (status, body) = login(app, email).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "{body}");
    assert_eq!(body["two_factor_required"], true, "{body}");
    assert!(body.get("token").is_none(), "no session yet: {body}");
    assert!(
        body["error"].as_str().unwrap().contains("authenticator"),
        "an old client shows this, so it must say what to do: {body}"
    );
    body["challenge"].as_str().unwrap().to_string()
}

async fn second_factor(app: &axum::Router, challenge: &str, code: &str) -> (StatusCode, Value) {
    call(
        app,
        "POST",
        "/api/auth/login/2fa",
        Auth::None,
        Some(json!({ "challenge": challenge, "code": code })),
    )
    .await
}

fn code(secret: &[u8], steps_ahead: u64) -> String {
    totp::code_at(secret, totp::now_unix() + steps_ahead * totp::STEP_SECONDS)
}

/// Turns two-factor on for `token`'s account with the current step's code.
/// Returns the secret and the recovery codes.
async fn enrol(app: &axum::Router, token: &str) -> (Vec<u8>, Vec<String>) {
    let (status, body) = call(
        app,
        "POST",
        "/api/auth/2fa/setup",
        Auth::Bearer(token),
        Some(json!({ "password": PASSWORD })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert!(body["qr_svg"].as_str().unwrap().starts_with("<svg"));
    let uri = body["otpauth_uri"].as_str().unwrap();
    assert!(uri.starts_with("otpauth://totp/Vellum:"), "{uri}");
    let secret = totp::base32_decode(body["secret"].as_str().unwrap()).unwrap();
    assert_eq!(secret.len(), 20);

    let (status, body) = call(
        app,
        "POST",
        "/api/auth/2fa/enable",
        Auth::Bearer(token),
        Some(json!({ "code": code(&secret, 0) })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let codes: Vec<String> = body["recovery_codes"]
        .as_array()
        .unwrap()
        .iter()
        .map(|c| c.as_str().unwrap().to_string())
        .collect();
    (secret, codes)
}

#[tokio::test]
async fn without_two_factor_login_is_unchanged() {
    let (app, _) = test_app().await;
    let token = register_master(&app).await;
    let (status, body) = login(&app, MASTER).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert!(body["token"].is_string());

    let (status, body) = call(&app, "GET", "/api/auth/2fa", Auth::Bearer(&token), None).await;
    assert_eq!(status, StatusCode::OK);
    assert_eq!(body["enabled"], false);
    assert_eq!(body["recovery_codes_left"], 0);

    let (status, body) = call(&app, "GET", "/api/capabilities", Auth::None, None).await;
    assert_eq!(status, StatusCode::OK);
    assert!(
        body["features"]
            .as_array()
            .unwrap()
            .contains(&json!("two_factor"))
    );
}

#[tokio::test]
async fn enrolment_asks_for_the_password_and_a_working_code() {
    let (app, _) = test_app().await;
    let token = register_master(&app).await;

    // A session alone cannot start it: a stolen one must not be able to enrol
    // its own phone and lock the owner out.
    let (status, _) = call(
        &app,
        "POST",
        "/api/auth/2fa/setup",
        Auth::Bearer(&token),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, _) = call(
        &app,
        "POST",
        "/api/auth/2fa/setup",
        Auth::Bearer(&token),
        Some(json!({ "password": "not the password" })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);

    let (status, body) = call(
        &app,
        "POST",
        "/api/auth/2fa/setup",
        Auth::Bearer(&token),
        Some(json!({ "password": PASSWORD })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let secret = totp::base32_decode(body["secret"].as_str().unwrap()).unwrap();

    // Pending: sign-in does not ask for a code yet.
    let (status, _) = login(&app, MASTER).await;
    assert_eq!(status, StatusCode::OK);

    let wrong = if code(&secret, 0) == "000000" {
        "111111"
    } else {
        "000000"
    };
    let (status, _) = call(
        &app,
        "POST",
        "/api/auth/2fa/enable",
        Auth::Bearer(&token),
        Some(json!({ "code": wrong })),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    let (status, body) = call(
        &app,
        "POST",
        "/api/auth/2fa/enable",
        Auth::Bearer(&token),
        Some(json!({ "code": code(&secret, 0) })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let codes = body["recovery_codes"].as_array().unwrap();
    assert_eq!(codes.len(), 10);

    let (_, body) = call(&app, "GET", "/api/auth/2fa", Auth::Bearer(&token), None).await;
    assert_eq!(body["enabled"], true);
    assert_eq!(body["recovery_codes_left"], 10);

    // On is on: setting up again would silently move it to another phone.
    let (status, _) = call(
        &app,
        "POST",
        "/api/auth/2fa/setup",
        Auth::Bearer(&token),
        Some(json!({ "password": PASSWORD })),
    )
    .await;
    assert_eq!(status, StatusCode::CONFLICT);

    // And the session that turned it on is still a session.
    let (status, _) = call(&app, "GET", "/api/auth/me", Auth::Bearer(&token), None).await;
    assert_eq!(status, StatusCode::OK, "existing sessions stay valid");
}

#[tokio::test]
async fn login_takes_a_code_once_and_only_once() {
    let (app, _) = test_app().await;
    let token = register_master(&app).await;
    let (secret, _) = enrol(&app, &token).await;

    // Enrolment used the current step, so its code is already spent.
    let c = challenge(&app, MASTER).await;
    let (status, body) = second_factor(&app, &c, &code(&secret, 0)).await;
    assert_eq!(
        status,
        StatusCode::UNAUTHORIZED,
        "replayed enrolment code: {body}"
    );

    let next = code(&secret, 1);
    let (status, body) = second_factor(&app, &c, &next).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let session = body["token"].as_str().unwrap().to_string();
    assert_eq!(body["user"]["email"], MASTER);
    assert!(body.get("recovery_codes_left").is_none());
    let (status, _) = call(&app, "GET", "/api/auth/me", Auth::Bearer(&session), None).await;
    assert_eq!(status, StatusCode::OK);

    // The challenge is single use…
    let (status, _) = second_factor(&app, &c, &next).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    // …and the code cannot be replayed on a fresh one inside its window.
    let c2 = challenge(&app, MASTER).await;
    let (status, body) = second_factor(&app, &c2, &next).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "replay: {body}");

    // A made-up challenge goes nowhere.
    let (status, _) = second_factor(&app, "not-a-challenge", &next).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
}

#[tokio::test]
async fn recovery_codes_work_once_each() {
    let (app, _) = test_app().await;
    let token = register_master(&app).await;
    let (_, codes) = enrol(&app, &token).await;

    let c = challenge(&app, MASTER).await;
    // Typed sloppily: capitals and spaces instead of dashes.
    let typed = codes[0].to_uppercase().replace('-', " ");
    let (status, body) = second_factor(&app, &c, &typed).await;
    assert_eq!(status, StatusCode::OK, "{body}");
    assert_eq!(body["recovery_codes_left"], 9);

    let c = challenge(&app, MASTER).await;
    let (status, _) = second_factor(&app, &c, &codes[0]).await;
    assert_eq!(
        status,
        StatusCode::UNAUTHORIZED,
        "a used recovery code is spent"
    );
    let (status, _) = second_factor(&app, &c, &codes[1]).await;
    assert_eq!(status, StatusCode::OK);

    // Regenerating needs proof, and invalidates the old set.
    let (status, _) = call(
        &app,
        "POST",
        "/api/auth/2fa/recovery-codes",
        Auth::Bearer(&token),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, body) = call(
        &app,
        "POST",
        "/api/auth/2fa/recovery-codes",
        Auth::Bearer(&token),
        Some(json!({ "password": PASSWORD })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");
    let fresh = body["recovery_codes"].as_array().unwrap();
    assert_eq!(fresh.len(), 10);
    let c = challenge(&app, MASTER).await;
    let (status, _) = second_factor(&app, &c, &codes[2]).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "the old set is gone");
    let (status, _) = second_factor(&app, &c, fresh[0].as_str().unwrap()).await;
    assert_eq!(status, StatusCode::OK);
}

#[tokio::test]
async fn wrong_codes_are_throttled_and_a_new_challenge_does_not_reset_them() {
    let (app, _) = test_app().await;
    let token = register_master(&app).await;
    let (secret, _) = enrol(&app, &token).await;
    let right = code(&secret, 1);
    let wrong = if right == "000000" {
        "111111"
    } else {
        "000000"
    };

    // A challenge dies after five wrong codes.
    let c = challenge(&app, MASTER).await;
    for _ in 0..4 {
        let (status, _) = second_factor(&app, &c, wrong).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED);
    }
    let (status, body) = second_factor(&app, &c, wrong).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED);
    assert!(
        body["error"].as_str().unwrap().contains("start again"),
        "{body}"
    );
    let (status, _) = second_factor(&app, &c, &right).await;
    assert_eq!(status, StatusCode::UNAUTHORIZED, "that challenge is gone");

    // Signing in with the right password again does not reset the count:
    // five more wrong codes reach the account's limit of ten…
    let c = challenge(&app, MASTER).await;
    for _ in 0..5 {
        let _ = second_factor(&app, &c, wrong).await;
    }
    let c = challenge(&app, MASTER).await;
    let (status, _) = second_factor(&app, &c, &right).await;
    assert_eq!(
        status,
        StatusCode::TOO_MANY_REQUESTS,
        "…after which even the right code waits"
    );
}

#[tokio::test]
async fn basic_auth_needs_an_app_password_once_two_factor_is_on() {
    let (app, _) = test_app().await;
    let token = register_master(&app).await;

    let (status, _) = call(&app, "GET", "/opds", Auth::Basic(MASTER, PASSWORD), None).await;
    assert_eq!(status, StatusCode::OK, "before: the account password works");

    let (status, body) = call(
        &app,
        "POST",
        "/api/app-passwords",
        Auth::Bearer(&token),
        Some(json!({ "label": "Kobo" })),
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let app_password = body["password"].as_str().unwrap().to_string();

    enrol(&app, &token).await;

    for uri in ["/opds", "/api/books", "/api/auth/me"] {
        let (status, body) = call(&app, "GET", uri, Auth::Basic(MASTER, PASSWORD), None).await;
        assert_eq!(status, StatusCode::UNAUTHORIZED, "{uri}: {body}");
        assert!(
            body["error"].as_str().unwrap().contains("app password"),
            "{body}"
        );
    }
    // A wrong password still reads as a wrong password, not as "two-factor".
    let (_, body) = call(
        &app,
        "GET",
        "/opds",
        Auth::Basic(MASTER, "nope nope nope"),
        None,
    )
    .await;
    assert_eq!(body["error"], "invalid email or password");

    // App passwords are not subject to it — that is what they are for.
    let (status, _) = call(
        &app,
        "GET",
        "/opds",
        Auth::Basic(MASTER, &app_password),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
}

#[tokio::test]
async fn turning_it_off_needs_proof() {
    let (app, db) = test_app().await;
    let token = register_master(&app).await;
    let (secret, _) = enrol(&app, &token).await;

    let (status, _) = call(
        &app,
        "POST",
        "/api/auth/2fa/disable",
        Auth::Bearer(&token),
        Some(json!({})),
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);
    let (status, _) = call(
        &app,
        "POST",
        "/api/auth/2fa/disable",
        Auth::Bearer(&token),
        Some(json!({ "code": code(&secret, 0) })),
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN, "the enrolment code is spent");
    let (status, body) = call(
        &app,
        "POST",
        "/api/auth/2fa/disable",
        Auth::Bearer(&token),
        Some(json!({ "code": code(&secret, 1) })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");

    let (status, _) = login(&app, MASTER).await;
    assert_eq!(
        status,
        StatusCode::OK,
        "off means a password is enough again"
    );
    let left: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM totp_recovery_code")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(left, 0, "and the recovery codes went with it");
}

#[tokio::test]
async fn an_owner_can_clear_someone_elses_but_not_their_own() {
    let (app, db) = test_app().await;
    let master = register_master(&app).await;
    let member = add_member(&app, &master).await;
    enrol(&app, &member).await;
    enrol(&app, &master).await;

    let (_, users) = call(&app, "GET", "/api/users", Auth::Bearer(&master), None).await;
    let ana = users
        .as_array()
        .unwrap()
        .iter()
        .find(|u| u["email"] == MEMBER)
        .unwrap()
        .clone();
    assert_eq!(ana["two_factor"], true);
    let ana_id = ana["id"].as_str().unwrap().to_string();
    let master_id = users
        .as_array()
        .unwrap()
        .iter()
        .find(|u| u["email"] == MASTER)
        .unwrap()["id"]
        .as_str()
        .unwrap()
        .to_string();

    // A member cannot; an owner cannot do their own (that is `disable`, which
    // asks for proof).
    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/users/{master_id}/2fa"),
        Auth::Bearer(&member),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::FORBIDDEN);
    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/users/{master_id}/2fa"),
        Auth::Bearer(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::BAD_REQUEST);

    let (status, _) = call(
        &app,
        "DELETE",
        &format!("/api/users/{ana_id}/2fa"),
        Auth::Bearer(&master),
        None,
    )
    .await;
    assert_eq!(status, StatusCode::OK);
    let (status, _) = login(&app, MEMBER).await;
    assert_eq!(
        status,
        StatusCode::OK,
        "cleared: the password is enough again"
    );
    let left: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM totp_recovery_code WHERE user_id = ?")
        .bind(&ana_id)
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(left, 0, "her recovery codes went with it");

    let actions: Vec<String> = sqlx::query_scalar("SELECT action FROM audit")
        .fetch_all(&db)
        .await
        .unwrap();
    assert!(actions.iter().any(|a| a == "user.2fa_clear"), "{actions:?}");
}

#[tokio::test]
async fn a_password_reset_keeps_two_factor_on() {
    let (app, db) = test_app().await;
    let token = register_master(&app).await;
    enrol(&app, &token).await;
    let pending = challenge(&app, MASTER).await;

    // As if a reset link had been emailed.
    let user_id: String = sqlx::query_scalar("SELECT id FROM app_user WHERE email = ?")
        .bind(MASTER)
        .fetch_one(&db)
        .await
        .unwrap();
    sqlx::query(
        "INSERT INTO password_reset (token_hash, user_id, expires_at) \
         VALUES (?, ?, datetime('now', '+1 hour'))",
    )
    .bind(vellum_server::sha256_hex_for_tests("reset-token"))
    .bind(&user_id)
    .execute(&db)
    .await
    .unwrap();
    let (status, body) = call(
        &app,
        "POST",
        "/api/auth/reset",
        Auth::None,
        Some(json!({ "token": "reset-token", "password": PASSWORD })),
    )
    .await;
    assert_eq!(status, StatusCode::OK, "{body}");

    // Whoever reads the mailbox still needs the phone.
    challenge(&app, MASTER).await;
    // And a sign-in that was waiting on a code from before is gone.
    let left: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM login_challenge WHERE token_hash = ?")
        .bind(vellum_server::sha256_hex_for_tests(&pending))
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(left, 0);
}
