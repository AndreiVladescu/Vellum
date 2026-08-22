//! Guards the hand-maintained parity between the two schemas: the server's SQL
//! migrations here and the app's drift tables in `app/lib/data/database.dart`.
//! If this test fails you probably changed one side without the other — see
//! CLAUDE.md. The expected column lists below double as the canonical contract
//! for the tables that sync over REST.
//!
//! App-local-only columns/tables (reading state, source_metadata, deleted_at —
//! the trash's grace period, plan 5 #52 — sync_excluded, the per-book "keep
//! this on this device" switch, which is a statement about one device's
//! appetite rather than about the book — the physical-layout tables,
//! local_deletions) are intentionally NOT part of the server schema, so they
//! don't appear here. `book.owner_id` is the mirror image: a server-only
//! column, present here but not in the app.
//!
//! The personal tables (migration 0023: annotation, reading_session, book_note;
//! migration 0034: book_status) are excluded for the same reason as
//! `reading_progress` below — they are keyed by `user_id`, which the app has no
//! column for, and `book_note`/`book_status` are whole tables on this side
//! against columns on the book row on the other (`books.reader_notes`,
//! `books.status`). Their contract is `server/tests/personal.rs`, which tests the
//! behaviour that actually matters: isolation between accounts.
//!
//! `reading_progress` (migration 0011, plan 5 #5) is excluded on purpose, not by
//! oversight: it is a per-(book, user, device) channel with no column-for-column
//! app counterpart — the app mirrors *other* devices' rows into its own
//! `remote_reading_positions` table and keeps its own position on the book row.
//! Both sides are free to carry columns the other doesn't.

use sqlx::Row;
use vellum_server::connect_db;

async fn columns(db: &sqlx::SqlitePool, table: &str) -> Vec<String> {
    sqlx::query(sqlx::AssertSqlSafe(format!("PRAGMA table_info({table})")))
        .fetch_all(db)
        .await
        .unwrap()
        .iter()
        .map(|r| r.get::<String, _>("name"))
        .collect()
}

#[tokio::test]
async fn synced_tables_have_the_expected_columns() {
    let path = std::env::temp_dir().join(format!("vellum_schema_{}.db", uuid::Uuid::new_v4()));
    let db = connect_db(path.to_str().unwrap()).await.unwrap();

    // The tables that sync between app and server, with their columns in
    // creation order. Keep in lockstep with `app/lib/data/database.dart`.
    let expected: &[(&str, &[&str])] = &[
        (
            "book",
            &[
                "id",
                "title",
                "subtitle",
                "description",
                "isbn",
                "publisher",
                "published_year",
                "page_count",
                "cover_path",
                "spine_style",
                "created_at",
                "updated_at",
                // Reading state (reading_progress/last_read_page/last_read_at) was
                // added to the server by migration 0002, then dropped again by
                // 0006 — it's app-local-only by design and never synced.
                "owner_id", // server-only (migration 0003); not in the app schema
                // Series membership (migration 0012, plan 5 #17) — synced, so
                // both sides carry these.
                "series_id",
                "series_index",
            ],
        ),
        ("author", &["id", "name"]),
        ("series", &["id", "name"]),
        ("book_author", &["book_id", "author_id", "position"]),
        ("genre", &["id", "name"]),
        ("book_genre", &["book_id", "genre_id"]),
        (
            "book_file",
            &[
                "id",
                "book_id",
                "format",
                "path",
                "size_bytes",
                "sha256",
                "added_at",
            ],
        ),
        // Synced since migration 0008 (plan 5 #4) — previously created in
        // 0001_init.sql but never synced or touched by any client.
        (
            "shelf",
            &[
                "id",
                "owner_id",
                "name",
                "sort_order",
                "updated_at",
                // Personal shelves (migration 0029): synced, because the shelf
                // is its owner's on every device they use — only *sharing* is
                // what the flag withholds. The app's matching column is
                // `shelves.is_personal`; its `accepted` column is app-local, a
                // statement about one device's willingness to show someone
                // else's shelf, so it does not appear here.
                "personal",
            ],
        ),
        ("shelf_book", &["shelf_id", "book_id", "position"]),
        // Synced since migration 0009 (plan 5 #4, second of three) -- no
        // owner_id: a copy's access derives from its book (access::copy_access).
        (
            "physical_copy",
            &[
                "id",
                "book_id",
                "location",
                "condition",
                "notes",
                "updated_at",
            ],
        ),
        // Synced since migration 0010 (plan 5 #4, third and last of the
        // trio) -- ALTERed in place (nothing referenced loan, unlike
        // physical_copy at 0009).
        (
            "loan",
            &[
                "id",
                "copy_id",
                "borrower",
                "loaned_at",
                "returned_at",
                "updated_at",
                // Due dates, contacts and notes (migration 0014, plan 5 #27) --
                // synced, because `loan` has been a synced table since 0010.
                "due_at",
                "borrower_contact",
                "notes",
                "reminder_sent_at",
            ],
        ),
    ];

    for (table, cols) in expected {
        let actual = columns(&db, table).await;
        let actual_refs: Vec<&str> = actual.iter().map(String::as_str).collect();
        assert_eq!(
            actual_refs.as_slice(),
            *cols,
            "column drift in `{table}`: the app drift schema and the server SQL \
             migrations must be kept in sync (see CLAUDE.md)"
        );
    }
}
