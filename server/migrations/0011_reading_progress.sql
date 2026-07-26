-- Optional cross-device reading position (plan 5 #5).
--
-- This does NOT undo migration 0006. Reading state on the `book` row stays
-- app-local-only and off the LWW clock: opening a book must never clobber a
-- console edit (plan 2 §A1), and that decision stands. This is a separate,
-- additive, opt-in channel that never touches the book row or its payload --
-- the app only writes here when the user turns "Sync reading position" on.
--
-- One row per (book, user, device) means there is nothing to merge: a device
-- writes only its own row and reads the others, so two devices reading the
-- same book cannot conflict. The app *offers* to jump to another device's
-- position rather than silently adopting it.
CREATE TABLE reading_progress (
  book_id      TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
  -- Always the authenticated caller; never taken from a request body. A shared
  -- library means several users hold positions in the same book, and one
  -- user's reading must not be visible to another.
  user_id      TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  -- Opaque, app-generated, stable per install; with a human label for the
  -- prompt ("You were on page 214 on desktop").
  device_id    TEXT NOT NULL,
  device_label TEXT,
  progress     REAL,                  -- 0..1, the format-agnostic comparison key
  page         INTEGER,
  -- What `page` counts: 'page' (PDF) or 'chapter' (EPUB). The app's saved
  -- position means one or the other depending on which file the book opens
  -- into, so a row has to say which -- otherwise another device's "page 214"
  -- is a lie when it was really chapter 214 of a different format.
  unit         TEXT,
  scroll       REAL,                  -- in-page/in-chapter fraction
  updated_at   TEXT NOT NULL,
  PRIMARY KEY (book_id, user_id, device_id)
);

-- The pull is "my rows, changed since <cursor>" across all books, so the
-- cursor filter needs the user first (mirrors 0007's list indexes).
CREATE INDEX idx_reading_progress_user_updated
  ON reading_progress (user_id, updated_at);
