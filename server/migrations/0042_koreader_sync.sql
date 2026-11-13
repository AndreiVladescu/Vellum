-- KOReader progress sync (v1.6.3): the server speaks KOReader's kosync
-- protocol under /koreader, feeding the per-device reading_progress channel.
--
-- Server-only, all of it: the app never sees these tables, so none is in
-- `schema_parity.rs`. What the app sees is the ordinary `reading_progress` row
-- each KOReader write is mirrored into (see `koreader.rs`).
--
-- (0040 and 0041 are reserved for work landing in parallel; this is 0042 so the
-- three can merge in any order.)

-- ## The credential
--
-- KOReader never sends a password. It sends `x-auth-key: md5(password)`, the
-- hex MD5 of whatever was typed into its password box, on every request. So the
-- server has to recognise md5(app password) — and since only the SHA-256 of an
-- app password is kept (0039), that can never be derived later: it has to be
-- recorded when the secret exists, at creation, for app passwords made for
-- KOReader.
--
-- What is stored is `sha256(md5_hex)`, never the MD5 itself. The MD5 *is* the
-- credential on the wire — a table holding it would be a table of replayable
-- logins, exactly what 0039 refuses to keep. Hashing it once more makes a dump
-- useless, the same as `secret_hash`.
--
-- MD5's weaknesses do not matter here. Collisions are irrelevant to a lookup,
-- and preimages are the only attack that would, and against a 120-bit random
-- secret even a brute force over the *input* is 2^120 guesses.
--
-- One row per spelling. The md5 is over the characters as typed, so the
-- forgiving normalisation OPDS gets ("capitals and dashes don't matter") cannot
-- be applied after the fact; instead the handful of ways a person plausibly
-- types the secret are each recorded — with or without the dashes, or with
-- spaces, in lower or upper case. Revoking the app password removes them all.
CREATE TABLE koreader_key (
  key_hash        TEXT PRIMARY KEY,
  app_password_id TEXT NOT NULL REFERENCES app_password(id) ON DELETE CASCADE
);
CREATE INDEX idx_koreader_key_app_password ON koreader_key (app_password_id);

-- ## Which book a KOReader "document" is
--
-- KOReader names a book by a partial MD5 of its file: 1 KiB samples at offsets
-- 0, 1 KiB, 4 KiB, 16 KiB … 1 GiB (`util.partialMD5`). Computed once per file,
-- on upload and lazily for files that predate this migration, so a progress
-- write resolves to a book with one indexed lookup.
--
-- Keyed by `book_file.id` rather than `book_file.sha256`, so a deleted file
-- takes its digest with it. Not a column on `book_file`: that table is synced
-- and pinned by `schema_parity.rs`, and this is nothing the app needs.
CREATE TABLE koreader_file_digest (
  file_id TEXT PRIMARY KEY REFERENCES book_file(id) ON DELETE CASCADE,
  digest  TEXT NOT NULL
);
CREATE INDEX idx_koreader_file_digest ON koreader_file_digest (digest);

-- ## What KOReader said, verbatim
--
-- Kept per (user, document, device) and independent of any book, for two
-- reasons. A GET must hand back KOReader's own `progress` — an xpointer into the
-- EPUB's DOM, or a page number — byte for byte, and `reading_progress` has no
-- place for an opaque string. And a document no stored file matches yet (the
-- book was copied onto the e-reader before it was imported) is still recorded,
-- so the import that later adds the file links it.
--
-- `user_id` comes from the credential, never the body: the same rule as every
-- other personal table. `timestamp` is Unix seconds on the server's clock, as
-- the reference server returns it and as KOReader compares it.
CREATE TABLE koreader_progress (
  user_id    TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  document   TEXT NOT NULL,
  device_id  TEXT NOT NULL,
  device     TEXT NOT NULL,
  progress   TEXT NOT NULL,
  percentage REAL NOT NULL,
  timestamp  INTEGER NOT NULL,
  PRIMARY KEY (user_id, document, device_id)
);
-- "The latest position in this document", the GET.
CREATE INDEX idx_koreader_progress_latest
  ON koreader_progress (user_id, document, timestamp);
-- "Who has been reading this document", when an upload links it.
CREATE INDEX idx_koreader_progress_document ON koreader_progress (document);
