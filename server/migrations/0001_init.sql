-- Vellum initial schema. Mirrors the app's local schema (see DESIGN.md).

CREATE TABLE book (
    id             TEXT PRIMARY KEY,           -- uuid
    title          TEXT NOT NULL,
    subtitle       TEXT,
    description    TEXT,
    isbn           TEXT,
    publisher      TEXT,
    published_year INTEGER,
    page_count     INTEGER,
    cover_path     TEXT,                       -- relative to the covers dir
    spine_style    TEXT,                       -- JSON: generated spine params
    created_at     TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at     TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE TABLE author (
    id   TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE book_author (
    book_id   TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    author_id TEXT NOT NULL REFERENCES author(id) ON DELETE CASCADE,
    position  INTEGER NOT NULL DEFAULT 0,      -- author order on the cover
    PRIMARY KEY (book_id, author_id)
);

CREATE TABLE genre (
    id   TEXT PRIMARY KEY,
    name TEXT NOT NULL UNIQUE
);

CREATE TABLE book_genre (
    book_id  TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    genre_id TEXT NOT NULL REFERENCES genre(id) ON DELETE CASCADE,
    PRIMARY KEY (book_id, genre_id)
);

-- Digital files attached to a book (0..n): a book may be physical-only,
-- digital-only, or both, possibly in several formats.
CREATE TABLE book_file (
    id         TEXT PRIMARY KEY,
    book_id    TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    format     TEXT NOT NULL,                  -- 'pdf', 'epub', ...
    path       TEXT NOT NULL,                  -- relative to the files dir
    size_bytes INTEGER NOT NULL,
    sha256     TEXT NOT NULL,
    added_at   TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Physical copies of a book (0..n).
CREATE TABLE physical_copy (
    id        TEXT PRIMARY KEY,
    book_id   TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    location  TEXT,                            -- e.g. "living room, shelf 3"
    condition TEXT,
    notes     TEXT
);

-- Loan history per physical copy; the active loan is the row with
-- returned_at IS NULL.
CREATE TABLE loan (
    id          TEXT PRIMARY KEY,
    copy_id     TEXT NOT NULL REFERENCES physical_copy(id) ON DELETE CASCADE,
    borrower    TEXT NOT NULL,
    loaned_at   TEXT NOT NULL DEFAULT (datetime('now')),
    returned_at TEXT
);

-- Manual collections/panes, independent of genres, with explicit ordering.
CREATE TABLE shelf (
    id         TEXT PRIMARY KEY,
    name       TEXT NOT NULL,
    sort_order INTEGER NOT NULL DEFAULT 0
);

CREATE TABLE shelf_book (
    shelf_id TEXT NOT NULL REFERENCES shelf(id) ON DELETE CASCADE,
    book_id  TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    position INTEGER NOT NULL DEFAULT 0,
    PRIMARY KEY (shelf_id, book_id)
);

CREATE INDEX idx_book_file_book   ON book_file(book_id);
CREATE INDEX idx_copy_book        ON physical_copy(book_id);
CREATE INDEX idx_loan_copy        ON loan(copy_id);
CREATE INDEX idx_loan_active      ON loan(copy_id) WHERE returned_at IS NULL;
