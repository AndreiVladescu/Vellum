-- Photos of a physical copy (plan 6 #4).
--
-- After personal-data sync (0023), a photo of your shelf was the last thing
-- still stranded on the device that took it — which read as an oversight rather
-- than a decision, because every other personal thing had just started
-- following the account.
--
-- **Library data, not personal data.** A photo belongs to a *copy*, and copies
-- already sync (plan 5 #4); it is not keyed by user and it is visible to anyone
-- the book is shared with, exactly as its covers and files already are. That is
-- the consistent answer, and the one the UI has to say out loud where photos
-- are added — a photo of a copy is often a photo of a room.
--
-- The bytes go in the blob store beside covers and book files; this row keeps
-- the path, like `book_file` does.
CREATE TABLE copy_photo (
    id         TEXT PRIMARY KEY,
    copy_id    TEXT NOT NULL REFERENCES physical_copy(id) ON DELETE CASCADE,
    path       TEXT NOT NULL,
    caption    TEXT,
    taken_at   TEXT NOT NULL DEFAULT (datetime('now')),
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_copy_photo_copy ON copy_photo(copy_id);
CREATE INDEX idx_copy_photo_updated ON copy_photo(updated_at);
