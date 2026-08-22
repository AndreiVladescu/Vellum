-- Two fixes to personal data, both about a device not seeing what another one
-- wrote (v1.1.5 reports: "only the new notes made on a book sync", "the pages
-- on the phone didn't update").
--
-- ## 1. A delta pull was filtered by the *writer's* clock
--
-- Every personal row carried one timestamp doing two jobs. `updated_at` is the
-- app's own clock, sent with the row, and it has to be: last-write-wins between
-- two devices needs the time the *edit* happened, not the time it reached the
-- server. But the delta pull — "what changed since my last sync" — was filtered
-- on that same column against a cursor that is the *server's* clock. So a note
-- written on Monday and pushed on Friday was invisible to every device that had
-- synced in between: it arrived after their cursor and was stamped before it.
--
-- The two clocks are now two columns. `updated_at` stays exactly as it was, and
-- `synced_at` is stamped by the server on every write, which is what a cursor
-- can be compared against.
--
-- The backfill is `datetime('now')` rather than each row's `updated_at`: every
-- existing client holds a cursor from before this migration, so stamping the
-- rows as changed-now makes the next sync hand each device the whole of its own
-- personal data once. That is the repair — those devices are missing rows they
-- can no longer ask for by time — and every write is an idempotent upsert, so
-- the cost is one bulk pull, not a mess.
--
-- The default is a constant and the value is backfilled by UPDATE: SQLite
-- rejects a non-constant default on ADD COLUMN, but only once a table has rows,
-- so it passes every test against a fresh database and fails on the first real
-- server (see 0023, which learned this the same way).
ALTER TABLE annotation ADD COLUMN synced_at TEXT NOT NULL
    DEFAULT '1970-01-01 00:00:00';
UPDATE annotation SET synced_at = datetime('now');
CREATE INDEX idx_annotation_user_synced ON annotation(user_id, synced_at);

ALTER TABLE reading_session ADD COLUMN synced_at TEXT NOT NULL
    DEFAULT '1970-01-01 00:00:00';
UPDATE reading_session SET synced_at = datetime('now');
CREATE INDEX idx_session_user_synced ON reading_session(user_id, synced_at);

ALTER TABLE book_note ADD COLUMN synced_at TEXT NOT NULL
    DEFAULT '1970-01-01 00:00:00';
UPDATE book_note SET synced_at = datetime('now');
CREATE INDEX idx_book_note_synced ON book_note(user_id, synced_at);

ALTER TABLE reading_progress ADD COLUMN synced_at TEXT NOT NULL
    DEFAULT '1970-01-01 00:00:00';
UPDATE reading_progress SET synced_at = datetime('now');
CREATE INDEX idx_reading_progress_synced ON reading_progress(user_id, synced_at);

-- ## 2. Reading status had nowhere to live
--
-- "Finished", "Wishlist", "Abandoned" — the app has had these since plan 5 #18
-- and they have never left the device. A book wanted on the phone arrived on
-- the tablet as an ordinary owned book, and a book read to the end on one
-- device stayed unread on the other.
--
-- It does not go back on `book`: migration 0006 took reading state off that row
-- deliberately, and that decision stands. A shared library holds several
-- people's reading of the same book, and "I finished it" is mine, not the
-- library's. So it lives here, keyed by user like `book_note` — the same shape,
-- for the same reason.
--
-- One row per (user, book), last-write-wins on `updated_at`. No tombstone: a
-- status is never absent, only different, and 'unread' is what a book with no
-- row means.
CREATE TABLE book_status (
    user_id    TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    book_id    TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    -- unread | reading | finished | abandoned | reference | wishlist, as the
    -- app's `ReadingStatus` enum names them. Not validated here beyond being
    -- non-empty: a client that learns a new state should not need a server
    -- upgrade to keep its own devices in step.
    status     TEXT NOT NULL,
    -- The reader's own dates, which travel with the status because they are the
    -- same act: when it was started, when it was finished, how many times.
    started_at  TEXT,
    finished_at TEXT,
    read_count  INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    synced_at  TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (user_id, book_id)
);
CREATE INDEX idx_book_status_synced ON book_status(user_id, synced_at);
