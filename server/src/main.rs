use std::net::SocketAddr;
use std::path::PathBuf;

use vellum_server::{AppState, TlsCertInfo, connect_db, router, tls};

/// Everything the server reads from the environment, in one place — the source
/// the `--help` text and `docs/DEPLOYMENT.md` are both written from.
const USAGE: &str = "\
vellum-server — the optional sync backend for Vellum

USAGE:
    vellum-server            Start the server (configured entirely by environment)
    vellum-server --version  Print the version and exit
    vellum-server --help     Print this help and exit

ENVIRONMENT:
    VELLUM_PORT              Port to listen on (default 3000)
    VELLUM_DB                SQLite file (default ./vellum.db); migrations run at startup
    VELLUM_DATA_DIR          Covers and book files (default ./data)
    VELLUM_PUBLIC_URL        Base URL used in public share links
                             (default http://localhost:3000)
    VELLUM_MAX_UPLOAD_MB     Per-file upload cap in MB (default 2048)
    VELLUM_TLS               1/true to serve HTTPS with a self-signed certificate
    VELLUM_TLS_CERT          PEM certificate path (default <data dir>/cert.pem)
    VELLUM_TLS_KEY           PEM key path (default <data dir>/key.pem)
    VELLUM_TLS_SANS          Extra comma-separated SANs for the generated cert
    VELLUM_BOOTSTRAP_TOKEN   Secret the first (master) registration must present

MAIL (all optional; without VELLUM_SMTP_HOST mail features stay off):
    VELLUM_SMTP_HOST         SMTP server for password resets and invites
    VELLUM_SMTP_PORT         Submission port (default 587, STARTTLS)
    VELLUM_SMTP_USER         Username, if the relay requires one
    VELLUM_SMTP_PASS         Password (for Gmail, an App Password, not the account one)
    VELLUM_MAIL_FROM         Sender address; required when SMTP_HOST is set
    RUST_LOG                 Log filter, e.g. info, vellum_server=debug

The first account registered becomes the master; afterwards the master
provisions members. See docs/DEPLOYMENT.md for Docker, compose and systemd.
";

#[tokio::main]
async fn main() -> anyhow::Result<()> {
    // Argument handling before anything else: a container health check or a
    // packaging script asking `--version` must not open the database first.
    // Hand-rolled rather than pulling in an argument parser — there are exactly
    // two flags, and configuration is environment-only by design.
    // Only the first argument is examined, and each case ends the process: there
    // are no combinable flags to accumulate, because configuration is
    // environment-only by design.
    if let Some(arg) = std::env::args().nth(1) {
        match arg.as_str() {
            "--version" | "-V" => {
                println!("vellum-server {}", env!("CARGO_PKG_VERSION"));
            }
            "--help" | "-h" => {
                print!("{USAGE}");
            }
            other => {
                eprintln!("vellum-server: unrecognised argument `{other}`\n");
                print!("{USAGE}");
                std::process::exit(2);
            }
        }
        return Ok(());
    }

    tracing_subscriber::fmt::init();

    let db_path = std::env::var("VELLUM_DB").unwrap_or_else(|_| "vellum.db".into());
    let db = connect_db(&db_path).await?;

    let public_base_url =
        std::env::var("VELLUM_PUBLIC_URL").unwrap_or_else(|_| "http://localhost:3000".into());
    let data_dir = std::env::var("VELLUM_DATA_DIR").unwrap_or_else(|_| "data".into());
    let data_path = PathBuf::from(&data_dir);
    let max_upload_mb: usize = std::env::var("VELLUM_MAX_UPLOAD_MB")
        .ok()
        .and_then(|v| v.parse().ok())
        .unwrap_or(2048); // 2 GB default

    // Opt-in TLS: needed for the Android app (which blocks cleartext) and for any
    // connection that leaves localhost. Off by default so the desktop local-first
    // story keeps working over plain HTTP with no setup. Resolve the certificate
    // up front so both AppState (for the console's import affordance) and the
    // serving block below can use it.
    let tls_on = std::env::var("VELLUM_TLS")
        .map(|v| v == "1" || v.eq_ignore_ascii_case("true"))
        .unwrap_or(false);
    let tls = if tls_on {
        // ring provider so we don't need the aws-lc-rs C toolchain; must be the
        // process default before rustls builds any config.
        rustls::crypto::ring::default_provider()
            .install_default()
            .ok();

        let (default_cert, default_key) = default_tls_pair(&data_path);
        let cert_path = std::env::var("VELLUM_TLS_CERT")
            .map(PathBuf::from)
            .unwrap_or(default_cert);
        let key_path = std::env::var("VELLUM_TLS_KEY")
            .map(PathBuf::from)
            .unwrap_or(default_key);
        let extra_sans: Vec<String> = std::env::var("VELLUM_TLS_SANS")
            .unwrap_or_default()
            .split(',')
            .map(|s| s.trim().to_string())
            .filter(|s| !s.is_empty())
            .collect();
        let cert = tls::ensure_self_signed(&cert_path, &key_path, &extra_sans)?;
        Some((cert_path, key_path, cert))
    } else {
        None
    };
    let tls_cert = tls.as_ref().map(|(cert_path, _, cert)| TlsCertInfo {
        cert_path: cert_path.clone(),
        fingerprint: cert.fingerprint.clone(),
    });

    // Mail is opt-in; a misconfiguration stops the server here rather than
    // surfacing as a failed password reset weeks later.
    let mailer = vellum_server::build_mailer()?;
    if mailer.is_none() {
        tracing::info!(
            "mail: disabled (set VELLUM_SMTP_HOST and VELLUM_MAIL_FROM to enable \
             password reset and invites)"
        );
    }

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
        mailer,
        tls_cert,
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

    if let Some((cert_path, key_path, cert)) = tls {
        let config =
            axum_server::tls_rustls::RustlsConfig::from_pem_file(&cert_path, &key_path).await?;

        let origin = if cert.generated {
            "generated a new self-signed certificate"
        } else {
            "reusing the existing certificate (stable across restarts)"
        };
        tracing::info!(
            "vellum-server listening on https://{addr} (db: {db_path})\n  \
             certificate: {} — {origin}\n  SHA-256 fingerprint: {}\n  \
             Import this certificate (or pin the fingerprint) in the app to \
             connect. It persists across restarts; delete both files to rotate.",
            cert_path.display(),
            cert.fingerprint,
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

/// Default locations for the TLS cert + key: under the data dir, so they live
/// in one stable place that doesn't depend on the process's working directory
/// (a re-run from elsewhere would otherwise not find a CWD-relative `cert.pem`
/// and mint a fresh one, breaking the app's pinned copy). For backward
/// compatibility, a `cert.pem`/`key.pem` pair an older version left in the CWD
/// is reused instead of silently regenerating under the data dir.
fn default_tls_pair(data_dir: &std::path::Path) -> (PathBuf, PathBuf) {
    let in_data = (data_dir.join("cert.pem"), data_dir.join("key.pem"));
    let legacy = (PathBuf::from("cert.pem"), PathBuf::from("key.pem"));
    if !in_data.0.exists() && legacy.0.exists() && legacy.1.exists() {
        legacy
    } else {
        in_data
    }
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
