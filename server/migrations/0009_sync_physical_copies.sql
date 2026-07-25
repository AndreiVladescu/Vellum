-- physical_copy was created in 0001_init.sql but never synced (plan 5 #4,
-- second of three: shelves already done in 0008, loan history is next).
-- Unlike shelf, a copy has no independent owner: it belongs to exactly one
-- book, so access derives from that book (access::copy_access delegates to
-- book_access via book_id) rather than needing its own owner_id column --
-- only updated_at for LWW is new here.
--
-- loan.copy_id REFERENCES physical_copy(id), so physical_copy can't be
-- rebuilt in place while loan still points at the old table. loan is
-- dropped and recreated in the same shape (its own sync columns are next
-- commit's job) purely to satisfy that foreign key during the rebuild.
DROP TABLE loan;
DROP TABLE physical_copy;

CREATE TABLE physical_copy (
    id         TEXT PRIMARY KEY,
    book_id    TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    location   TEXT,
    condition  TEXT,
    notes      TEXT,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_copy_book ON physical_copy(book_id);

CREATE TABLE loan (
    id          TEXT PRIMARY KEY,
    copy_id     TEXT NOT NULL REFERENCES physical_copy(id) ON DELETE CASCADE,
    borrower    TEXT NOT NULL,
    loaned_at   TEXT NOT NULL DEFAULT (datetime('now')),
    returned_at TEXT
);
CREATE INDEX idx_loan_copy   ON loan(copy_id);
CREATE INDEX idx_loan_active ON loan(copy_id) WHERE returned_at IS NULL;

-- deletion.kind already generalizes past 'book'/'shelf' (see 0008); 'copy'
-- tombstones use the same column, no further schema change needed.
