//! Guards the hand-maintained parity between the two schemas: the server's SQL
//! migrations here and the app's drift tables in `app/lib/data/database.dart`.
//! If this test fails you probably changed one side without the other — see
//! CLAUDE.md. The expected column lists below double as the canonical contract
//! for the tables that sync over REST.
//!
//! App-local-only columns/tables (reading state, reader_notes, source_metadata,
//! the physical-layout tables, local_deletions) are intentionally NOT part of
//! the server schema, so they don't appear here. `book.owner_id` is the mirror
//! image: a server-only column, present here but not in the app.

use sqlx::Row;
use vellum_server::connect_db;

async fn columns(db: &sqlx::SqlitePool, table: &str) -> Vec<String> {
    sqlx::query(&format!("PRAGMA table_info({table})"))
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
                // NOTE: migration 0002 added these three reading-state columns to
                // the server schema, but they were later declared app-local-only
                // (CLAUDE.md / DESIGN.md) and are NOT synced. They linger here as
                // dormant columns; the server never reads or writes them. Left in
                // place because an applied migration must not be edited.
                "reading_progress",
                "last_read_page",
                "last_read_at",
                "owner_id", // server-only (migration 0003); not in the app schema
            ],
        ),
        ("author", &["id", "name"]),
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
