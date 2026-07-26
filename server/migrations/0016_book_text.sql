-- Full-text search over book *contents* (plan 5 #32).
--
-- Server-only, and deliberately not part of schema parity: this is the one
-- capability a server can offer that a local-first app genuinely cannot, since
-- indexing gigabytes of PDFs on a phone is not a thing anyone wants. Nothing
-- here syncs, and the whole index can be dropped and rebuilt from the blobs.

CREATE TABLE book_text (
    file_id      TEXT PRIMARY KEY REFERENCES book_file(id) ON DELETE CASCADE,
    book_id      TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    -- How many page/section rows were indexed for this file.
    pages        INTEGER,
    extracted_at TEXT NOT NULL DEFAULT (datetime('now')),
    -- 'pending' | 'ok' | 'no_text' | 'failed' | 'skipped'
    --
    -- 'pending' is not in the plan's list and is the reason the queue needs no
    -- in-memory channel: the work item *is* the row, so a server restarted
    -- mid-extraction picks up exactly where it left off.
    -- 'no_text' is a scanned PDF — a real outcome, not a failure. There is no
    -- OCR and there will not be: a tesseract dependency contradicts the
    -- single-binary rule.
    status       TEXT NOT NULL
);

CREATE INDEX idx_book_text_status ON book_text(status);
CREATE INDEX idx_book_text_book ON book_text(book_id);

-- `book_id` is carried here as well as in `book_text` so a search can filter by
-- visibility with one join to `book` instead of two.
CREATE VIRTUAL TABLE book_text_fts USING fts5(
    body,
    page     UNINDEXED,
    file_id  UNINDEXED,
    book_id  UNINDEXED,
    tokenize='unicode61 remove_diacritics 2'
);

-- A virtual table has no foreign keys, so its rows have to be swept by hand.
-- The trigger covers direct deletes; `books::delete` clears the index
-- explicitly as well, because SQLite only fires triggers for foreign-key
-- cascades when recursive triggers are enabled.
CREATE TRIGGER book_text_after_delete AFTER DELETE ON book_text BEGIN
    DELETE FROM book_text_fts WHERE file_id = old.file_id;
END;
