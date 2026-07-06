-- Reading state per book (null progress = never opened).
-- Mirrors app drift schema v2.

ALTER TABLE book ADD COLUMN reading_progress REAL;
ALTER TABLE book ADD COLUMN last_read_page INTEGER;
ALTER TABLE book ADD COLUMN last_read_at TEXT;
