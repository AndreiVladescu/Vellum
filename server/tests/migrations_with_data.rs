//! Migrations run against a database that **has rows in it**.
//!
//! Every other test here starts from an empty file, and that blindness shipped
//! a broken migration: SQLite rejects a non-constant `DEFAULT` on
//! `ALTER TABLE ... ADD COLUMN`, but *only when the table already has rows*. So
//! `DEFAULT (datetime('now'))` in migration 0023 passed the whole suite and
//! failed on the first real server, which had an account in it.
//!
//! An empty database exercises the schema. Only a populated one exercises the
//! *migration*, which is a different thing and the one users actually run.

use sqlx::Row;
use sqlx::sqlite::SqlitePoolOptions;
use vellum_server::connect_db;

/// Applies migrations up to and including `through`, so rows can be inserted
/// into the schema as it stood before the migration under test.
async fn migrate_partially(path: &str, through: i64) -> sqlx::SqlitePool {
    let pool = SqlitePoolOptions::new()
        .connect(&format!("sqlite://{path}?mode=rwc"))
        .await
        .unwrap();
    let migrator = sqlx::migrate!("./migrations");
    for migration in migrator.iter() {
        if migration.version > through {
            break;
        }
        // Mirrors what the real migrator does, including recording it, so the
        // remaining migrations run normally afterwards.
        sqlx::query(&migration.sql)
            .execute(&pool)
            .await
            .unwrap_or_else(|e| panic!("setup migration {}: {e}", migration.version));
    }
    // Record what we applied, so `connect_db`'s migrator picks up where we
    // stopped rather than trying to re-run it.
    sqlx::query(
        "CREATE TABLE IF NOT EXISTS _sqlx_migrations (\
            version BIGINT PRIMARY KEY, description TEXT NOT NULL, \
            installed_on TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, \
            success BOOLEAN NOT NULL, checksum BLOB NOT NULL, \
            execution_time BIGINT NOT NULL)",
    )
    .execute(&pool)
    .await
    .unwrap();
    for migration in migrator.iter() {
        if migration.version > through {
            break;
        }
        sqlx::query(
            "INSERT INTO _sqlx_migrations \
             (version, description, success, checksum, execution_time) \
             VALUES (?, ?, 1, ?, 0)",
        )
        .bind(migration.version)
        .bind(migration.description.as_ref())
        .bind(migration.checksum.as_ref())
        .execute(&pool)
        .await
        .unwrap();
    }
    pool
}

/// A database that stops just before the personal-data migration, holding the
/// rows that make it fail: an account, a book, a copy, a loan.
#[tokio::test]
async fn a_populated_database_upgrades_to_the_latest_schema() {
    let path = std::env::temp_dir().join(format!("vellum_popmig_{}.db", uuid::Uuid::new_v4()));
    let path = path.to_str().unwrap().to_string();

    {
        let pool = migrate_partially(&path, 22).await;
        sqlx::query(
            "INSERT INTO app_user (id, email, display_name, password_hash, is_master) \
             VALUES ('u1', 'someone@lib.test', 'Someone', 'x', 1)",
        )
        .execute(&pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO book (id, title, updated_at) VALUES ('b1', 'Dune', datetime('now'))",
        )
        .execute(&pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO physical_copy (id, book_id, updated_at) \
             VALUES ('c1', 'b1', datetime('now'))",
        )
        .execute(&pool)
        .await
        .unwrap();
        sqlx::query(
            "INSERT INTO loan (id, copy_id, borrower, loaned_at, updated_at) \
             VALUES ('l1', 'c1', 'A friend', datetime('now'), datetime('now'))",
        )
        .execute(&pool)
        .await
        .unwrap();
        // Tombstones under the old key, so 0025's table rebuild has rows to
        // carry across rather than migrating an empty table.
        for (id, kind) in [("gone-1", "book"), ("gone-2", "shelf")] {
            sqlx::query(
                "INSERT INTO deletion (book_id, owner_id, kind, deleted_at) \
                 VALUES (?, 'u1', ?, datetime('now'))",
            )
            .bind(id)
            .bind(kind)
            .execute(&pool)
            .await
            .unwrap();
        }
        pool.close().await;
    }

    // The whole point: this is what `cargo run` does on a real server.
    let db = connect_db(&path)
        .await
        .expect("a database with rows in it must migrate");

    // The rows survived.
    let books: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM book")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(books, 1, "the library survived the upgrade");

    // And the column that broke it is present, populated, and not the epoch —
    // the backfill ran rather than leaving the placeholder behind.
    let row = sqlx::query("SELECT profile_updated_at FROM app_user WHERE id = 'u1'")
        .fetch_one(&db)
        .await
        .unwrap();
    let stamp: String = row.get(0);
    assert!(
        stamp.as_str() > "2000-01-01",
        "existing accounts are backfilled, not left at the placeholder: {stamp}"
    );

    // 0025 rebuilds `deletion` around a (kind, entity_id) key. A rebuild that
    // loses rows would silently resurrect everything anyone had deleted.
    let kept: Vec<(String, String, Option<String>)> =
        sqlx::query_as("SELECT entity_id, kind, owner_id FROM deletion ORDER BY entity_id")
            .fetch_all(&db)
            .await
            .unwrap();
    assert_eq!(
        kept,
        vec![
            ("gone-1".into(), "book".into(), Some("u1".into())),
            ("gone-2".into(), "shelf".into(), Some("u1".into())),
        ],
        "the tombstones came through the rebuild intact"
    );

    let _ = std::fs::remove_file(&path);
}

/// A known, deliberate exception, and the only one.
///
/// `0010` carries the same mistake and cannot be fixed: it is applied on every
/// existing server, and sqlx validates migration checksums — editing it would
/// make every one of them refuse to start. That is a certain harm traded for an
/// unlikely one, since it only bites a server upgrading from *before* migration
/// 10 that already has loans, and any server that old passed it long ago.
const KNOWN_EXCEPTIONS: &[&str] = &["0010_sync_loans.sql"];

/// The general form, so this can't come back in a *future* migration either:
/// no `ADD COLUMN` may carry a parenthesised (non-constant) default.
///
/// A source check rather than a behavioural one, because the behaviour only
/// shows up when the table happens to be non-empty — which is exactly the
/// condition that made this ship.
#[test]
fn no_migration_adds_a_column_with_a_non_constant_default() {
    let mut offenders = Vec::new();
    for entry in std::fs::read_dir("migrations").unwrap() {
        let path = entry.unwrap().path();
        if path.extension().and_then(|e| e.to_str()) != Some("sql") {
            continue;
        }
        let name = path.file_name().unwrap().to_string_lossy().to_string();
        if KNOWN_EXCEPTIONS.contains(&name.as_str()) {
            continue;
        }
        let sql = std::fs::read_to_string(&path).unwrap();
        // Statement by statement, with comments stripped: the explanation of
        // this very rule contains the pattern it forbids.
        for statement in sql.split(';') {
            let code: String = statement
                .lines()
                .filter(|l| !l.trim_start().starts_with("--"))
                .collect::<Vec<_>>()
                .join(" ")
                .to_uppercase();
            if code.contains("ADD COLUMN") && code.contains("DEFAULT (") {
                offenders.push(format!("{}: {}", path.display(), code.trim()));
            }
        }
    }
    assert!(
        offenders.is_empty(),
        "SQLite rejects these on any table that already has rows — use a \
         constant default and a backfilling UPDATE:\n{}",
        offenders.join("\n")
    );
}
