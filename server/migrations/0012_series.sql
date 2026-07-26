-- Series and volume tracking (plan 5 #17).
--
-- Synced, unlike the app-local additions around it: a series is catalogue
-- metadata that Open Library and Google Books often supply, and a library of
-- trilogies is unusable without it. Both sides therefore change, and
-- `server/tests/schema_parity.rs` gains the table and the two columns.
CREATE TABLE series (
  id   TEXT PRIMARY KEY,
  -- Unique so two clients pushing "Dune" independently converge on one series
  -- rather than accumulating duplicates; the app resolves by name for the same
  -- reason authors and genres do.
  name TEXT NOT NULL UNIQUE
);

-- Nullable: most books belong to no series, and that must stay the cheap case.
ALTER TABLE book ADD COLUMN series_id TEXT REFERENCES series(id);

-- REAL, not INTEGER: novellas and interquels are numbered 1.5, 2.5, 0.5. An
-- integer column would force them to lie about where they sit.
ALTER TABLE book ADD COLUMN series_index REAL;

-- The series strip and the series sort both read "every book in this series, in
-- order", which is this index exactly.
CREATE INDEX idx_book_series ON book (series_id, series_index);
