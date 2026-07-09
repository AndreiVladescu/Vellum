use std::net::SocketAddr;

use vellum_server::{connect_db, router, AppState};

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

    let port: u16 = std::env::var("VELLUM_PORT")
        .ok()
        .and_then(|p| p.parse().ok())
        .unwrap_or(3000);
    let addr = SocketAddr::from(([0, 0, 0, 0], port));
    tracing::info!("vellum-server listening on http://{addr} (db: {db_path})");
    let listener = tokio::net::TcpListener::bind(addr).await?;
    axum::serve(listener, router(state)).await?;
    Ok(())
}
