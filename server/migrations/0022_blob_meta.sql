-- A tiny key/value table for one-shot maintenance markers (plan 5 #9).
--
-- The content-addressed blob backfill has to *move files*, which SQL cannot do,
-- so it runs in Rust at startup. This table is how it knows it has already run:
-- a migration can't record that, because migrations are about schema and this
-- is about the filesystem.
--
-- Server-only, like every other table here that has no app counterpart.
CREATE TABLE meta (
    key   TEXT PRIMARY KEY,
    value TEXT NOT NULL,
    set_at TEXT NOT NULL DEFAULT (datetime('now'))
);
