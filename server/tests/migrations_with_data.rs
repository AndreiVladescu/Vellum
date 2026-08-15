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
        // Three *open* loans on the one copy — the state 0028 makes impossible,
        // and which therefore has to survive being made impossible. A real
        // database can hold this: nothing checked before 0028, so lending an
        // already-lent copy simply inserted.
        for (id, borrower, day) in [
            ("l1", "A friend", "2026-01-01 10:00:00"),
            ("l2", "Another friend", "2026-02-01 10:00:00"),
            ("l3", "Whoever has it now", "2026-03-01 10:00:00"),
        ] {
            sqlx::query(
                "INSERT INTO loan (id, copy_id, borrower, loaned_at, updated_at) \
                 VALUES (?, 'c1', ?, ?, datetime('now'))",
            )
            .bind(id)
            .bind(borrower)
            .bind(day)
            .execute(&pool)
            .await
            .unwrap();
        }

        // And two shares saying the same thing, which 0032 has to clean up
        // before it can add its unique index — the state every server that ever
        // double-clicked "Grant" is in.
        sqlx::query(
            "INSERT INTO app_user (id, email, display_name, password_hash, is_master) \
             VALUES ('u2', 'ana@lib.test', 'Ana', 'x', 0)",
        )
        .execute(&pool)
        .await
        .unwrap();
        for (id, permission) in [("sh1", "viewer"), ("sh2", "editor")] {
            sqlx::query(
                "INSERT INTO share (id, owner_id, grantee_id, scope, scope_id, permission) \
                 VALUES (?, 'u1', 'u2', 'all', NULL, ?)",
            )
            .bind(id)
            .bind(permission)
            .execute(&pool)
            .await
            .unwrap();
        }
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

    // 0028's backfill: the history is all still there, but only the most recent
    // loan is still open, and the earlier two were closed when the next one
    // started rather than at some invented date.
    let loans: i64 = sqlx::query_scalar("SELECT COUNT(*) FROM loan")
        .fetch_one(&db)
        .await
        .unwrap();
    assert_eq!(loans, 3, "no loan was deleted to satisfy the index");
    let open: Vec<String> =
        sqlx::query_scalar("SELECT id FROM loan WHERE returned_at IS NULL ORDER BY id")
            .fetch_all(&db)
            .await
            .unwrap();
    assert_eq!(open, vec!["l3".to_string()], "one copy, one open loan");
    let closed: Vec<(String, String)> = sqlx::query_as(
        "SELECT id, returned_at FROM loan WHERE returned_at IS NOT NULL ORDER BY id",
    )
    .fetch_all(&db)
    .await
    .unwrap();
    assert_eq!(
        closed,
        vec![
            ("l1".to_string(), "2026-02-01 10:00:00".to_string()),
            ("l2".to_string(), "2026-03-01 10:00:00".to_string()),
        ],
        "each closed when the next lend began, not when the last one did"
    );
    let second_loan = sqlx::query(
        "INSERT INTO loan (id, copy_id, borrower, loaned_at, updated_at) \
         VALUES ('l4', 'c1', 'Someone else', datetime('now'), datetime('now'))",
    )
    .execute(&db)
    .await;
    assert!(second_loan.is_err(), "a copy cannot be lent twice at once");

    // 0032's dedupe: one share left, and it is the editor one — the permission
    // that was already deciding access.
    let shares: Vec<(String, String)> =
        sqlx::query_as("SELECT id, permission FROM share ORDER BY id")
            .fetch_all(&db)
            .await
            .unwrap();
    assert_eq!(shares, vec![("sh2".to_string(), "editor".to_string())]);
    let duplicate = sqlx::query(
        "INSERT INTO share (id, owner_id, grantee_id, scope, scope_id, permission) \
         VALUES ('sh3', 'u1', 'u2', 'all', NULL, 'viewer')",
    )
    .execute(&db)
    .await;
    assert!(
        duplicate.is_err(),
        "the same person cannot be granted the same thing twice"
    );

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
