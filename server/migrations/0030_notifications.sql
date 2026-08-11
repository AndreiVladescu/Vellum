-- Things that happened while you weren't looking.
--
-- Lending is a conversation between two people, and until now the server only
-- held its *state*: a request was pending, then it was approved. Whether either
-- person ever found out was left to them opening the right screen and noticing
-- that something had changed. That is fine for the person who pressed the
-- button and useless for the other one.
--
-- A notification is addressed to an account, so this is per-user data in the
-- same sense as `reading_progress` and the personal tables: keyed by `user_id`,
-- never visible to anyone else, and never part of the book row. It is *not*
-- synced to the app's database — it is fetched, like borrow requests, because
-- it is a conversation on a server rather than a fact about a library.
CREATE TABLE notification (
    id         TEXT PRIMARY KEY,
    user_id    TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    -- 'borrow.requested' | 'borrow.approved' | 'borrow.declined' |
    -- 'borrow.cancelled'. Deliberately not a CHECK constraint: a new kind
    -- should not need a migration, and a client that meets one it doesn't
    -- recognise shows the title and body it was sent.
    kind       TEXT NOT NULL,
    title      TEXT NOT NULL,
    body       TEXT,
    -- What it is about, so a client can offer a way there. Nulled rather than
    -- cascaded when the book goes: "Ana returned Dune" is still true after the
    -- book is deleted, and losing the sentence would be worse than losing the
    -- link.
    book_id    TEXT REFERENCES book(id) ON DELETE SET NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    read_at    TEXT
);

-- The one query this table has: my notifications, newest first.
CREATE INDEX notification_user ON notification(user_id, created_at DESC);
-- And the badge, which counts unread ones without reading them.
CREATE INDEX notification_unread ON notification(user_id) WHERE read_at IS NULL;
