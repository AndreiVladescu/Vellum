use std::net::SocketAddr;

use vellum_server::{AppState, connect_db, router};

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
    };

    // Sweep temp files left by uploads a previous run couldn't finish.
    sweep_tmp_files(&state.data_dir.join("files")).await;

    let port: u16 = std::env::var("VELLUM_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(3000);
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("vellum-server listening on http://{addr} (db: {db_path})");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    // Graceful shutdown on Ctrl-C / SIGINT lets in-flight uploads finish instead
    // of guaranteeing fresh `.tmp-*` junk on every restart.
    axum::serve(listener, router(state))
        .with_graceful_shutdown(async {
            tokio::signal::ctrl_c().await.ok();
        })
        .await?;
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
