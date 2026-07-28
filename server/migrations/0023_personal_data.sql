-- Personal data: the things that belong to *you* rather than to the library.
--
-- Until now a highlight, a reading session, a private note about a book and
-- your profile photo lived only on the device that made them. Three devices
-- meant three disjoint sets, silently. These tables give them a home so an
-- account carries them between devices.
--
-- The rule that shapes every table here: **scoped by user_id, never by book
-- alone**. A library can be shared, and my notes in a book you lent me are not
-- yours to read. Every query filters on the caller's id taken from the token,
-- exactly as `reading_progress` (0011) already does — that endpoint is the
-- template this follows.

-- Highlights, notes and bookmarks. Mutable — a note is edited, a highlight
-- recoloured, either deleted — so it carries `updated_at` for last-write-wins
-- and leans on the existing `deletion` table (kind = 'annotation') so a delete
-- propagates instead of the row reappearing on the next pull.
CREATE TABLE annotation (
    id          TEXT PRIMARY KEY,
    user_id     TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    book_id     TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    kind        TEXT NOT NULL,          -- highlight | note | bookmark
    page        INTEGER,                -- PDF
    chapter     INTEGER,                -- EPUB
    locator     TEXT,                   -- versioned JSON, see annotation_locator.dart
    quoted_text TEXT,
    note        TEXT,
    color       INTEGER,                -- ARGB of the marker, null = the default
    created_at  TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at  TEXT NOT NULL DEFAULT (datetime('now'))
);
-- The delta-pull index: "my annotations changed since X", which is the only
-- query the sync makes.
CREATE INDEX idx_annotation_user_updated ON annotation(user_id, updated_at);
CREATE INDEX idx_annotation_book ON annotation(book_id);

-- Reading sittings. **Immutable facts**, which is what makes them the easy
-- half: a sitting happened, on a device, between two times. Merging is a union
-- keyed by id, so there is no conflict to resolve and no tombstone to chase —
-- re-pushing the same session is idempotent rather than a second row.
--
-- `device_id` is kept so "which device do I actually read on" stays answerable
-- once the statistics span several.
CREATE TABLE reading_session (
    id         TEXT PRIMARY KEY,
    user_id    TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    book_id    TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    device_id  TEXT,
    device_label TEXT,
    started_at TEXT NOT NULL,
    ended_at   TEXT NOT NULL,
    start_page INTEGER,
    end_page   INTEGER,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_session_user_updated ON reading_session(user_id, updated_at);
CREATE INDEX idx_session_book ON reading_session(book_id);

-- The private note you keep about a book — `book.reader_notes` in the app.
--
-- A per-user table rather than a column on `book`, because `book` is the
-- shared thing: putting personal notes there would publish them to everyone the
-- library is shared with the moment the column synced. One row per (user,
-- book); clearing the note is an empty string rather than a tombstone, since
-- there is nothing else in the row to lose.
CREATE TABLE book_note (
    user_id    TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    book_id    TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    note       TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (datetime('now')),
    PRIMARY KEY (user_id, book_id)
);
CREATE INDEX idx_book_note_updated ON book_note(user_id, updated_at);

-- Profile photo. The bytes live in the blob store beside covers and book files
-- (`<data dir>/avatars/<user id>`), so backups already cover them; only the
-- pointer and its timestamp are here. `display_name` is already on app_user —
-- this is what lets a device tell whether its copy is stale.
ALTER TABLE app_user ADD COLUMN avatar_path TEXT;
ALTER TABLE app_user ADD COLUMN profile_updated_at TEXT NOT NULL DEFAULT (datetime('now'));
