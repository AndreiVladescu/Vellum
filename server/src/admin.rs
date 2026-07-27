//! Operator endpoints: integrity sweep and snapshot (plan 5 #12).
//!
//! The server has the same divergence risk as the app — a database of blob
//! *paths* plus a directory of blobs — with none of the tooling the app gained in
//! #11. And `DESIGN.md`'s backup advice ("copy the `.db` and the data dir
//! together, mind the WAL sidecars") is a manual ritual someone will get wrong
//! exactly once, at the worst possible moment.
//!
//! Both endpoints are **master-only**. A sweep lists what is wrong and deletes
//! nothing unless explicitly asked; a snapshot is the supported one-command
//! backup.

use axum::Json;
use axum::body::Body;
use axum::extract::{Query, State};
use axum::http::header;
use axum::response::{IntoResponse, Response};
use serde::{Deserialize, Serialize};

use crate::AppState;
use crate::auth::AuthUser;
use crate::error::{AppError, AppResult};

#[derive(Deserialize)]
pub struct SweepQuery {
    /// Delete blobs no row references. Off by default: a sweep that deletes by
    /// default is a footgun, and the first run on a real library is exactly when
    /// you want to look before touching anything.
    #[serde(default)]
    pub delete_orphans: bool,
}

#[derive(Serialize)]
pub struct SweepReport {
    /// `book_file` rows whose bytes are missing, as `id: path`.
    pub missing_files: Vec<String>,
    /// Books whose `cover_path` points at nothing.
    pub missing_covers: Vec<String>,
    /// Blobs on disk that no row references.
    pub orphan_blobs: Vec<String>,
    pub orphan_bytes: u64,
    /// How many orphans were actually deleted (0 unless `delete_orphans`).
    pub deleted: usize,
}

/// `POST /api/admin/sweep` — find (and optionally clean) divergence between the
/// database and the blob store.
pub async fn sweep(
    State(state): State<AppState>,
    user: AuthUser,
    Query(q): Query<SweepQuery>,
) -> AppResult<Json<SweepReport>> {
    if !user.is_master {
        return Err(AppError::Forbidden("master only".into()));
    }

    let mut referenced = std::collections::HashSet::new();
    let mut missing_files = Vec::new();
    let mut missing_covers = Vec::new();

    let files: Vec<(String, String)> = sqlx::query_as("SELECT id, path FROM book_file")
        .fetch_all(&state.db)
        .await?;
    for (id, path) in files {
        referenced.insert(normalise(&path));
        if !state.data_dir.join(&path).exists() {
            missing_files.push(format!("{id}: {path}"));
        }
    }

    let covers: Vec<(String, String)> =
        sqlx::query_as("SELECT id, cover_path FROM book WHERE cover_path IS NOT NULL")
            .fetch_all(&state.db)
            .await?;
    for (id, path) in covers {
        referenced.insert(normalise(&path));
        if !state.data_dir.join(&path).exists() {
            missing_covers.push(format!("{id}: {path}"));
        }
    }

    let mut orphan_blobs = Vec::new();
    let mut orphan_bytes = 0;
    let mut deleted = 0;
    // `files/` is sharded two hex characters deep since plan 5 #9, so the walk
    // descends one level there. `covers/` is flat apart from `covers/thumbs/`,
    // a derived cache with no rows behind it, which stays skipped.
    let mut dirs: Vec<String> = vec!["covers".to_string(), "files".to_string()];
    if let Ok(mut shards) = tokio::fs::read_dir(state.data_dir.join("files")).await {
        while let Ok(Some(shard)) = shards.next_entry().await {
            let name = shard.file_name().to_string_lossy().to_string();
            let is_shard = name.len() == 2 && name.bytes().all(|b| b.is_ascii_hexdigit());
            if is_shard && shard.file_type().await.map(|t| t.is_dir()).unwrap_or(false) {
                dirs.push(format!("files/{name}"));
            }
        }
    }
    for sub in dirs {
        let dir = state.data_dir.join(&sub);
        let Ok(mut entries) = tokio::fs::read_dir(&dir).await else {
            continue;
        };
        while let Ok(Some(entry)) = entries.next_entry().await {
            let name = entry.file_name().to_string_lossy().to_string();
            // In-flight upload temporaries are swept at startup and are not
            // divergence; flagging them would train the operator to ignore this.
            if name.ends_with(".part") || name.starts_with(".tmp-") || name.starts_with('.') {
                continue;
            }
            let Ok(kind) = entry.file_type().await else {
                continue;
            };
            // Shard directories are walked in their own pass above.
            if kind.is_dir() {
                continue;
            }
            let rel = format!("{sub}/{name}");
            if referenced.contains(&rel) {
                continue;
            }
            orphan_bytes += entry.metadata().await.map(|m| m.len()).unwrap_or(0);
            orphan_blobs.push(rel);
            if q.delete_orphans && tokio::fs::remove_file(entry.path()).await.is_ok() {
                deleted += 1;
            }
        }
    }

    tracing::info!(
        missing_files = missing_files.len(),
        missing_covers = missing_covers.len(),
        orphans = orphan_blobs.len(),
        deleted,
        "integrity sweep"
    );

    Ok(Json(SweepReport {
        missing_files,
        missing_covers,
        orphan_blobs,
        orphan_bytes,
        deleted,
    }))
}

fn normalise(path: &str) -> String {
    path.replace('\\', "/").trim_start_matches("./").to_string()
}

/// `GET /api/admin/snapshot` — the supported one-command backup.
///
/// Streams a `.tar` of a **`VACUUM INTO`** copy of the database plus the blob
/// directory. `VACUUM INTO` is the point: it produces a consistent single-file
/// copy without touching the live WAL, which is precisely the footgun the manual
/// instructions warn about (copying a `.db` while it is being written restores to
/// a database that is subtly wrong rather than obviously broken).
///
/// The archive is assembled into a temp file next to the data dir and then
/// streamed, so a large library needs transient disk rather than transient RAM.
/// For a personal server that is the right trade; the alternative is holding a
/// multi-gigabyte archive in memory.
pub async fn snapshot(State(state): State<AppState>, user: AuthUser) -> AppResult<Response> {
    if !user.is_master {
        return Err(AppError::Forbidden("master only".into()));
    }

    let stamp = chrono::Utc::now().format("%Y%m%d-%H%M%S").to_string();
    let work = state.data_dir.join(format!(".snapshot-{stamp}"));
    tokio::fs::create_dir_all(&work)
        .await
        .map_err(|e| AppError::Internal(format!("snapshot workspace: {e}")))?;

    let db_copy = work.join("vellum.db");
    sqlx::query("VACUUM INTO ?")
        .bind(db_copy.to_string_lossy().to_string())
        .execute(&state.db)
        .await?;

    let archive_path = work.join("snapshot.tar");
    let data_dir = state.data_dir.clone();
    let archive_for_task = archive_path.clone();
    let db_copy_for_task = db_copy.clone();
    // `tar` is synchronous and this walks the whole blob store: off the async
    // runtime, or a big snapshot would stall every other request.
    tokio::task::spawn_blocking(move || -> std::io::Result<()> {
        let file = std::fs::File::create(&archive_for_task)?;
        let mut builder = tar::Builder::new(file);
        builder.append_path_with_name(&db_copy_for_task, "vellum.db")?;
        for sub in ["covers", "files"] {
            let dir = data_dir.join(sub);
            if dir.is_dir() {
                builder.append_dir_all(sub, &dir)?;
            }
        }
        builder.finish()
    })
    .await
    .map_err(|e| AppError::Internal(format!("snapshot task: {e}")))?
    .map_err(|e| AppError::Internal(format!("snapshot: {e}")))?;

    let file = tokio::fs::File::open(&archive_path)
        .await
        .map_err(|e| AppError::Internal(format!("snapshot open: {e}")))?;
    let size = file
        .metadata()
        .await
        .map(|m| m.len())
        .map_err(|e| AppError::Internal(format!("snapshot size: {e}")))?;

    // The workspace is removed when the stream is dropped — which happens both on
    // a completed download and on a client that disconnects halfway, so an
    // abandoned snapshot can't leave a copy of the whole library behind.
    let guard = TempDir(work);
    let stream =
        futures_util::StreamExt::map(tokio_util::io::ReaderStream::new(file), move |chunk| {
            // Moving the guard into the closure ties its lifetime to the stream's.
            let _keep_alive = &guard;
            chunk
        });
    let body = Body::from_stream(stream);

    Ok((
        [
            (header::CONTENT_TYPE, "application/x-tar".to_string()),
            (
                header::CONTENT_DISPOSITION,
                format!("attachment; filename=\"vellum-snapshot-{stamp}.tar\""),
            ),
            (header::CONTENT_LENGTH, size.to_string()),
        ],
        body,
    )
        .into_response())
}

/// Removes a directory when dropped. Used to clean up a snapshot workspace
/// exactly once, whether the download finished or the client vanished.
struct TempDir(std::path::PathBuf);

impl Drop for TempDir {
    fn drop(&mut self) {
        let path = std::mem::take(&mut self.0);
        // Blocking removal on a runtime thread would be rude; a detached task
        // keeps the drop cheap. Best-effort: a failure here costs disk, not
        // correctness, and the next snapshot uses a differently-stamped path.
        tokio::task::spawn_blocking(move || {
            let _ = std::fs::remove_dir_all(path);
        });
    }
}
