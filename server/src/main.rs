use std::net::SocketAddr;
use std::path::PathBuf;

use vellum_server::{AppState, connect_db, router, tls};

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    tracing_subscriber::fmt::init();

    let db_path = std::env::var("VELLUM_DB").unwrap_or_else(|_| "vellum.db".into());
    let db = connect_db(&db_path).await?;

    let public_base_url =
        std::env::var("VELLUM_PUBLIC_URL").unwrap_or_else(|_| "http://localhost:3000".into());
    let data_dir = std::env::var("VELLUM_DATA_DIR").unwrap_or_else(|_| "data".into());
    let max_upload_mb: usize = std::env::var("VELLUM_MAX_UPLOAD_MB")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(2048); // 2 GB default
    let state = AppState {
        db,
        public_base_url,
        data_dir: data_dir.into(),
        http: reqwest::Client::new(),
        max_upload_bytes: max_upload_mb * 1024 * 1024,
        throttle: std::sync::Arc::default(),
        render_semaphore: std::sync::Arc::new(tokio::sync::Semaphore::new(2)),
        basic_cache: std::sync::Arc::default(),
        public_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            60,
            std::time::Duration::from_secs(60),
        )),
        search_limiter: std::sync::Arc::new(vellum_server::RateLimiter::new(
            30,
            std::time::Duration::from_secs(60),
        )),
    };

    // Sweep temp files left by uploads a previous run couldn't finish.
    sweep_tmp_files(&state.data_dir.join("files")).await;

    let port: u16 = std::env::var("VELLUM_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(3000);
    let addr = SocketAddr::from(([0, 0, 0, 0], port));

    // `into_make_service_with_connect_info` surfaces the peer socket address to
    // handlers (the per-IP rate limiter reads it when no X-Forwarded-For is set).
    let make_service = router(state).into_make_service_with_connect_info::<SocketAddr>();

    // Opt-in TLS: needed for the Android app (which blocks cleartext) and for any
    // connection that leaves localhost. Off by default so the desktop local-first
    // story keeps working over plain HTTP with no setup.
    let tls_on = std::env::var("VELLUM_TLS")
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false);

    if tls_on {
        // ring provider so we don't need the aws-lc-rs C toolchain; must be the
        // process default before rustls builds any config.
        rustls::crypto::ring::default_provider()
            .install_default()
            .ok();

        let cert_path = std::env::var("VELLUM_TLS_CERT")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("cert.pem"));
        let key_path = std::env::var("VELLUM_TLS_KEY")
            .map(PathBuf::from)
            .unwrap_or_else(|_| PathBuf::from("key.pem"));
        let extra_sans: Vec<String> = std::env::var("VELLUM_TLS_SANS")
            .unwrap_or_default()
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();

        let fingerprint = tls::ensure_self_signed(&cert_path, &key_path, &extra_sans)?;
        let config =
            axum_server::tls_rustls::RustlsConfig::from_pem_file(&cert_path, &key_path).await?;

        tracing::info!(
            "vellum-server listening on https://{addr} (db: {db_path})\n  \
             certificate: {}\n  SHA-256 fingerprint: {fingerprint}\n  \
             Import this certificate (or pin the fingerprint) in the app to connect.",
            cert_path.display(),
        );

        // Graceful shutdown on Ctrl-C so in-flight uploads finish.
        let handle = axum_server::Handle::new();
        let shutdown = handle.clone();
        tokio::spawn(async move {
            tokio::signal::ctrl_c().await.ok();
            shutdown.graceful_shutdown(Some(std::time::Duration::from_secs(10)));
        });
        axum_server::bind_rustls(addr, config)
            .handle(handle)
            .serve(make_service)
            .await?;
    } else {
        tracing::info!("vellum-server listening on http://{addr} (db: {db_path})");
        let listener = tokio::net::TcpListener::bind(addr).await?;
        // Graceful shutdown on Ctrl-C / SIGINT lets in-flight uploads finish
        // instead of guaranteeing fresh `.tmp-*` junk on every restart.
        axum::serve(listener, make_service)
            .with_graceful_shutdown(async {
                tokio::signal::ctrl_c().await.ok();
            })
            .await?;
    }
    Ok(())
}

/// Remove interrupted-upload temp files (`files/.tmp-*`) older than 24 hours.
/// The age gate means a genuinely in-flight upload over a slow link is never
/// deleted. Best-effort: any IO error just ends the sweep.
async fn sweep_tmp_files(files_dir: &std::path::Path) {
    let Ok(mut entries) = tokio::fs::read_dir(files_dir).await else {
        return;
    };
    let cutoff = std::time::SystemTime::now() - std::time::Duration::from_secs(24 * 3600);
    while let Ok(Some(entry)) = entries.next_entry().await {
        if !entry.file_name().to_string_lossy().starts_with(".tmp-") {
            continue;
        }
        let stale = entry
            .metadata()
            .await
            .ok()
            .and_then(|m| m.modified().ok())
            .is_some_and(|t| t < cutoff);
        if stale {
            let _ = tokio::fs::remove_file(entry.path()).await;
        }
    }
}
