-- The same fix as 0034, in the one channel it missed.
--
-- A copy photo stores the *writing device's* `updated_at` (it is the
-- last-write-wins key) and the delta pull filtered on that same column against
-- a cursor that is the server's clock. So a photo taken on Monday and pushed on
-- Friday was invisible to any device that had synced in between — the bug 0034
-- describes at length, in library data rather than personal data.
--
-- Constant default, then backfilled by UPDATE: SQLite rejects a non-constant
-- default on ADD COLUMN once a table has rows. Stamped as changed-now for the
-- same reason 0034 does it — every existing client holds a cursor from before
-- this migration, so one bulk re-pull is what closes the gaps.
ALTER TABLE copy_photo ADD COLUMN synced_at TEXT NOT NULL
    DEFAULT '1970-01-01 00:00:00';
UPDATE copy_photo SET synced_at = datetime('now');
CREATE INDEX idx_copy_photo_synced ON copy_photo(synced_at);
