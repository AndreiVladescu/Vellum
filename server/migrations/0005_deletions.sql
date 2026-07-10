-- Delete tombstones, so clients can propagate deletes instead of resurrecting
-- a book on the next pull. owner_id is denormalized here because the book row
-- (and any FK target) is already gone by the time the tombstone is read.
CREATE TABLE deletion (
    book_id    TEXT PRIMARY KEY,
    owner_id   TEXT,
    deleted_at TEXT NOT NULL DEFAULT (datetime('now'))
);
