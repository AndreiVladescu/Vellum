-- Listening sittings (v1.5.3, docs/AUDIOBOOKS.md section 5): a reading_session
-- row with kind = 'listen'.
--
-- A constant default plus nullable columns, so this is safe on a populated
-- database (tests/migrations_with_data.rs): every existing row is a reading
-- sitting, which the default says.
--
-- `start_second` / `end_second` are the audio position the sitting covered, in
-- seconds from the start of the book; null for reading, which has pages.
ALTER TABLE reading_session ADD COLUMN kind TEXT NOT NULL DEFAULT 'read';
ALTER TABLE reading_session ADD COLUMN start_second INTEGER;
ALTER TABLE reading_session ADD COLUMN end_second INTEGER;
