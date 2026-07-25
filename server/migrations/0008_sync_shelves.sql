-- shelf/shelf_book were created in 0001_init.sql but never synced: no client
-- has ever written a row to either (plan 5 #4). Rebuild both with the
-- sync-ready shape rather than ALTERing empty, unused tables.
DROP TABLE shelf_book;
DROP TABLE shelf;

CREATE TABLE shelf (
    id         TEXT PRIMARY KEY,
    owner_id   TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_shelf_owner ON shelf(owner_id);

CREATE TABLE shelf_book (
    shelf_id TEXT NOT NULL REFERENCES shelf(id) ON DELETE CASCADE,
    book_id  TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    position INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (shelf_id, book_id)
);

-- deletion.book_id now carries shelf ids too (and will carry physical_copy /
-- loan ids once those sync — plan 5 #4); `kind` disambiguates. The column
-- keeps its name rather than becoming e.g. `entity_id`: an old client only
-- ever reads `book_id`/`deleted_at` and looks the id up in its own `books`
-- table, so a shelf tombstone is a harmless no-op there. Purely additive --
-- no response-shape version bump needed (see the #6 capability handshake).
ALTER TABLE deletion ADD COLUMN kind TEXT NOT NULL DEFAULT 'book';
