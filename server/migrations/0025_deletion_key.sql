-- `deletion` was built in 0005 for books alone: one row per deleted book, keyed
-- by `book_id`. Since then it has grown a `kind` (0008) and been reused for
-- shelves, physical copies, loans, copy photos and annotations — so the table
-- now holds tombstones for seven kinds of thing under a column called
-- `book_id`, with a primary key that assumes an id can only ever be deleted
-- once across all of them.
--
-- In practice ids are UUIDs, so nothing has actually collided. But every write
-- site is an `INSERT OR REPLACE` or an `ON CONFLICT(book_id)`, which means a
-- collision would not error — it would silently overwrite the other kind's
-- tombstone and resurrect a deleted row on the next pull. The key should say
-- what it means: a tombstone is identified by *what kind of thing* was deleted
-- and *which one*.
--
-- Rebuild rather than ALTER, because SQLite cannot change a primary key in
-- place. The column is renamed to `entity_id` at the same time; the JSON field
-- clients read is still `book_id`, aliased in the two read paths, so this is
-- invisible on the wire.
CREATE TABLE deletion_new (
    entity_id  TEXT NOT NULL,
    kind       TEXT NOT NULL DEFAULT 'book',
    owner_id   TEXT,
    deleted_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (kind, entity_id)
);

INSERT INTO deletion_new (entity_id, kind, owner_id, deleted_at)
SELECT book_id, kind, owner_id, deleted_at FROM deletion;

DROP TABLE deletion;
ALTER TABLE deletion_new RENAME TO deletion;

-- Every read is either "since this timestamp" or "this one id", and the
-- primary key already covers the second.
CREATE INDEX deletion_deleted_at ON deletion (deleted_at);
