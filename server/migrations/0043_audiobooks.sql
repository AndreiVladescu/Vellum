-- Audiobooks (v1.5.0, docs/AUDIOBOOKS.md §3): an audiobook is a book whose
-- files are audio parts.
--
-- Every column is nullable with no default, so this is safe on a populated
-- database (see tests/migrations_with_data.rs) and every existing row reads as
-- "not audio".

-- The four part fields sync with the file, mirrored by `book_files` in the
-- app. The server never parses audio: the uploading device measured them, and
-- `track`/`label` must travel with the upload because the original file name
-- is gone once the blob is content-addressed. `duration_ms` is synced rather
-- than re-measured so every device sums the same part lengths when it turns a
-- position in seconds into (part, offset).
ALTER TABLE book_file ADD COLUMN duration_ms INTEGER;
ALTER TABLE book_file ADD COLUMN track       INTEGER;
ALTER TABLE book_file ADD COLUMN label       TEXT;
ALTER TABLE book_file ADD COLUMN narrator    TEXT;

-- Where a device is in the book's audio, in seconds from the start of part 1,
-- and the whole audiobook's length as that device sums it (the edition check
-- for a "go there?" offer). Separate from progress/page/unit so a device that
-- both reads and listens keeps both places.
ALTER TABLE reading_progress ADD COLUMN audio_position REAL;
ALTER TABLE reading_progress ADD COLUMN audio_duration REAL;
