//! Scheduled backups to a directory, with rotation (roadmap v1.6.1).
//!
//! Off unless `VELLUM_BACKUP_DIR` is set. A scheduled backup is the same
//! archive as `GET /api/admin/snapshot` (`admin::build_archive`), written to
//! `<dir>/vellum-backup-YYYYMMDD-HHMMSS.tar`.
//!
//! Two safety rules, both about never lying and never over-deleting:
//! - The archive is written under a `.part` name and renamed when complete, so
//!   a crash mid-write leaves nothing that rotation or a restore would take for
//!   a backup.
//! - Rotation only ever touches files whose names match our own pattern, so a
//!   directory shared with other things (the usual case: a mounted NAS share)
//!   loses nothing it did not get from us.
//!
//! The schedule is "every N hours since the newest backup in the directory",
//! not "every N hours since boot": a server restarted nightly would otherwise
//! back up on every start, and one restarted every few hours would never reach
//! its interval.

use std::path::{Path, PathBuf};
use std::sync::Mutex;
use std::time::Duration;

use chrono::{DateTime, NaiveDateTime, Utc};
use serde::Serialize;
use sqlx::SqlitePool;

const PREFIX: &str = "vellum-backup-";
const SUFFIX: &str = ".tar";
const STAMP_FORMAT: &str = "%Y%m%d-%H%M%S";
const DEFAULT_INTERVAL_HOURS: u64 = 24;
const DEFAULT_KEEP: usize = 7;

/// What the environment asked for.
#[derive(Clone, Debug, PartialEq, Eq)]
pub struct BackupConfig {
    pub dir: PathBuf,
    pub interval_hours: u64,
    pub keep: usize,
}

impl BackupConfig {
    pub fn from_env() -> Option<Self> {
        Self::parse(
            std::env::var("VELLUM_BACKUP_DIR").ok().as_deref(),
            std::env::var("VELLUM_BACKUP_INTERVAL").ok().as_deref(),
            std::env::var("VELLUM_BACKUP_KEEP").ok().as_deref(),
        )
    }

    /// Unset or blank directory means off. Unparseable or zero numbers fall back
    /// to the defaults: a typo must not silently switch backups off or, worse
    /// for `keep`, make rotation delete everything.
    pub fn parse(dir: Option<&str>, interval: Option<&str>, keep: Option<&str>) -> Option<Self> {
        let dir = dir.map(str::trim).filter(|d| !d.is_empty())?;
        let positive = |v: Option<&str>| {
            v.and_then(|s| s.trim().parse::<u64>().ok())
                .filter(|n| *n > 0)
        };
        Some(Self {
            dir: PathBuf::from(dir),
            interval_hours: positive(interval).unwrap_or(DEFAULT_INTERVAL_HOURS),
            keep: positive(keep).map(|n| n as usize).unwrap_or(DEFAULT_KEEP),
        })
    }
}

/// The outcome of the most recent scheduled run in this process.
#[derive(Clone, Debug, Serialize)]
pub struct LastRun {
    pub at: DateTime<Utc>,
    pub ok: bool,
    /// File name on success, the reason on failure.
    pub detail: String,
}

static LAST_RUN: Mutex<Option<LastRun>> = Mutex::new(None);

pub fn last_run() -> Option<LastRun> {
    LAST_RUN.lock().ok().and_then(|g| g.clone())
}

fn record(ok: bool, detail: String) {
    if let Ok(mut g) = LAST_RUN.lock() {
        *g = Some(LastRun {
            at: Utc::now(),
            ok,
            detail,
        });
    }
}

pub fn backup_name(at: DateTime<Utc>) -> String {
    format!("{PREFIX}{}{SUFFIX}", at.format(STAMP_FORMAT))
}

/// The time encoded in one of our file names, or `None` for anything else.
pub fn parse_backup_name(name: &str) -> Option<DateTime<Utc>> {
    let stamp = name.strip_prefix(PREFIX)?.strip_suffix(SUFFIX)?;
    // Exactly the shape we write; chrono alone would accept looser input.
    if stamp.len() != 15 {
        return None;
    }
    NaiveDateTime::parse_from_str(stamp, STAMP_FORMAT)
        .ok()
        .map(|n| n.and_utc())
}

/// Names to delete so that only the newest `keep` of our backups remain.
/// Ignores every name that is not ours. Oldest first.
pub fn select_for_rotation(names: &[String], keep: usize) -> Vec<String> {
    let mut ours: Vec<(DateTime<Utc>, &String)> = names
        .iter()
        .filter_map(|n| parse_backup_name(n).map(|t| (t, n)))
        .collect();
    ours.sort();
    let excess = ours.len().saturating_sub(keep.max(1));
    ours.into_iter()
        .take(excess)
        .map(|(_, n)| n.clone())
        .collect()
}

fn list_names(dir: &Path) -> Vec<String> {
    std::fs::read_dir(dir)
        .map(|rd| {
            rd.filter_map(|e| e.ok())
                .filter(|e| e.file_type().map(|t| t.is_file()).unwrap_or(false))
                .filter_map(|e| e.file_name().into_string().ok())
                .collect()
        })
        .unwrap_or_default()
}

/// Time of the newest backup of ours in `dir`.
pub fn newest_backup(dir: &Path) -> Option<DateTime<Utc>> {
    list_names(dir)
        .iter()
        .filter_map(|n| parse_backup_name(n))
        .max()
}

/// Takes one backup into `cfg.dir` and rotates. Returns the new file's name.
pub async fn run_backup(
    db: &SqlitePool,
    data_dir: &Path,
    cfg: &BackupConfig,
) -> Result<String, String> {
    tokio::fs::create_dir_all(&cfg.dir)
        .await
        .map_err(|e| format!("backup directory: {e}"))?;

    let now = Utc::now();
    let name = backup_name(now);
    let work = data_dir.join(format!(".scheduled-{}", now.format(STAMP_FORMAT)));
    tokio::fs::create_dir_all(&work)
        .await
        .map_err(|e| format!("backup workspace: {e}"))?;
    // Removed on every exit path, success included.
    let _guard = crate::admin::TempDir(work.clone());

    let archive = crate::admin::build_archive(db, data_dir, &work).await?;

    // Copy (not rename) into the target: the directory is often another
    // filesystem. Rename only within it, which is atomic.
    let part = cfg.dir.join(format!(".{name}.part"));
    let finished = cfg.dir.join(&name);
    let result = async {
        tokio::fs::copy(&archive, &part).await?;
        tokio::fs::rename(&part, &finished).await
    }
    .await;
    if let Err(e) = result {
        let _ = tokio::fs::remove_file(&part).await;
        return Err(format!("writing backup: {e}"));
    }

    let dir = cfg.dir.clone();
    let keep = cfg.keep;
    let _ = tokio::task::spawn_blocking(move || rotate(&dir, keep)).await;
    Ok(name)
}

/// Deletes the surplus old backups; returns how many were removed.
pub fn rotate(dir: &Path, keep: usize) -> usize {
    let mut removed = 0;
    for name in select_for_rotation(&list_names(dir), keep) {
        match std::fs::remove_file(dir.join(&name)) {
            Ok(()) => removed += 1,
            Err(e) => tracing::warn!("backup rotation: could not delete {name}: {e}"),
        }
    }
    removed
}

/// How long to wait before the next backup is due.
pub fn delay_until_due(
    newest: Option<DateTime<Utc>>,
    now: DateTime<Utc>,
    interval_hours: u64,
) -> Duration {
    // First ever backup, or one already overdue: a minute after boot, like the
    // reminder worker, so startup is not competing with a full archive build.
    let soon = Duration::from_secs(60);
    let Some(newest) = newest else {
        return soon;
    };
    let due = newest + chrono::Duration::hours(interval_hours as i64);
    (due - now).to_std().map_or(soon, |d| d.max(soon))
}

pub async fn run_backup_worker(db: SqlitePool, data_dir: PathBuf, cfg: BackupConfig) {
    tracing::info!(
        "scheduled backups: every {}h to {}, keeping {}",
        cfg.interval_hours,
        cfg.dir.display(),
        cfg.keep
    );
    loop {
        let dir = cfg.dir.clone();
        let newest = tokio::task::spawn_blocking(move || newest_backup(&dir))
            .await
            .ok()
            .flatten();
        tokio::time::sleep(delay_until_due(newest, Utc::now(), cfg.interval_hours)).await;
        match run_backup(&db, &data_dir, &cfg).await {
            Ok(name) => {
                tracing::info!("scheduled backup written: {name}");
                record(true, name);
            }
            Err(e) => {
                tracing::error!("scheduled backup failed: {e}");
                record(false, e);
                // Back off rather than retrying in a tight loop on a full disk.
                tokio::time::sleep(Duration::from_secs(3600)).await;
            }
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use chrono::TimeZone;

    fn at(h: u32) -> DateTime<Utc> {
        Utc.with_ymd_and_hms(2020, 11, 13, h, 5, 9).unwrap()
    }

    #[test]
    fn naming_round_trips() {
        let n = backup_name(at(7));
        assert_eq!(n, "vellum-backup-20201113-070509.tar");
        assert_eq!(parse_backup_name(&n), Some(at(7)));
        for bad in [
            "vellum-backup-2026.tar",
            "notes.tar",
            ".vellum-backup-20201113-070509.tar.part",
            "vellum-backup-20201113-070509.tar.bak",
        ] {
            assert_eq!(parse_backup_name(bad), None, "{bad}");
        }
    }

    #[test]
    fn rotation_keeps_newest_and_only_touches_ours() {
        let names: Vec<String> = vec![
            backup_name(at(3)),
            backup_name(at(1)),
            "photos.tar".into(),
            backup_name(at(2)),
            "vellum-backup-notes.tar".into(),
            backup_name(at(4)),
        ];
        assert_eq!(
            select_for_rotation(&names, 2),
            vec![backup_name(at(1)), backup_name(at(2))]
        );
        assert!(select_for_rotation(&names, 4).is_empty());
        // keep 0 is treated as 1: never delete the last backup.
        assert_eq!(select_for_rotation(&names, 0).len(), 3);
    }

    #[test]
    fn config_parsing() {
        assert_eq!(BackupConfig::parse(None, None, None), None);
        assert_eq!(BackupConfig::parse(Some("  "), None, None), None);
        let c = BackupConfig::parse(Some("/b"), Some("6"), Some("3")).unwrap();
        assert_eq!((c.interval_hours, c.keep), (6, 3));
        let c = BackupConfig::parse(Some("/b"), Some("x"), Some("0")).unwrap();
        assert_eq!((c.interval_hours, c.keep), (24, 7));
    }

    #[test]
    fn schedule_follows_newest_backup() {
        let soon = Duration::from_secs(60);
        assert_eq!(delay_until_due(None, at(5), 24), soon);
        assert_eq!(
            delay_until_due(Some(at(1)), at(3), 6),
            Duration::from_secs(4 * 3600)
        );
        assert_eq!(delay_until_due(Some(at(1)), at(23), 6), soon);
    }

    #[tokio::test]
    async fn run_writes_archive_and_rotates() {
        let root = std::env::temp_dir().join(format!("vellum-bk-{}", uuid::Uuid::new_v4()));
        let data = root.join("data");
        let out = root.join("out");
        std::fs::create_dir_all(data.join("covers")).unwrap();
        std::fs::create_dir_all(&out).unwrap();
        std::fs::write(data.join("covers/a.jpg"), b"x").unwrap();
        // A bystander, and old backups that rotation should trim.
        std::fs::write(out.join("keep-me.txt"), b"x").unwrap();
        std::fs::write(out.join(backup_name(at(1))), b"old").unwrap();
        std::fs::write(out.join(backup_name(at(2))), b"old").unwrap();

        let db = crate::connect_db(root.join("t.db").to_str().unwrap())
            .await
            .unwrap();
        let cfg = BackupConfig {
            dir: out.clone(),
            interval_hours: 24,
            keep: 2,
        };
        let name = run_backup(&db, &data, &cfg).await.unwrap();

        let names = list_names(&out);
        assert!(names.contains(&name) && names.contains(&"keep-me.txt".to_string()));
        assert!(!names.contains(&backup_name(at(1))));
        assert!(names.contains(&backup_name(at(2))));
        assert!(!names.iter().any(|n| n.ends_with(".part")));
        assert!(std::fs::metadata(out.join(&name)).unwrap().len() > 512);
        let _ = std::fs::remove_dir_all(&root);
    }
}
