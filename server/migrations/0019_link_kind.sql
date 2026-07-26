-- A public link can now point at a published room, not only a book
-- (plan 5 #48).
--
-- `book_id` was `NOT NULL REFERENCES book(id)`, so widening this means
-- rebuilding the table: `kind` says which of `book_id`/`layout_id` is the
-- target, and exactly one of them is populated. A CHECK enforces that pairing
-- rather than leaving it to every caller to remember.
--
-- Expiry, revocation and `max_uses` are untouched: a room link expires and is
-- revoked through the machinery that already exists, which is the point of
-- reusing this table instead of inventing a second kind of link with its own
-- lifetime rules to get wrong.

CREATE TABLE share_link_new (
    id         TEXT PRIMARY KEY,
    owner_id   TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    kind       TEXT NOT NULL DEFAULT 'book' CHECK (kind IN ('book', 'layout')),
    book_id    TEXT REFERENCES book(id) ON DELETE CASCADE,
    layout_id  TEXT REFERENCES layout(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    permission TEXT NOT NULL DEFAULT 'viewer'
                   CHECK (permission IN ('viewer', 'editor')),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at TEXT,
    revoked    INTEGER NOT NULL DEFAULT 0,
    max_uses   INTEGER,
    use_count  INTEGER NOT NULL DEFAULT 0,
    -- For a room link: whether anonymous viewers may see the titles of the
    -- books in it (plan 5 #48). **Per link and off by default**, rather than
    -- inferred from the owner having tagged the room's books — tagging books to
    -- share with a named member must not silently publish their titles to
    -- anyone holding a URL. Revoking the link revokes the titles with it.
    show_books INTEGER NOT NULL DEFAULT 0,
    CHECK (
        (kind = 'book'   AND book_id   IS NOT NULL AND layout_id IS NULL) OR
        (kind = 'layout' AND layout_id IS NOT NULL AND book_id   IS NULL)
    )
);

INSERT INTO share_link_new
    (id, owner_id, kind, book_id, token_hash, permission, created_at,
     expires_at, revoked, max_uses, use_count, show_books)
SELECT id, owner_id, 'book', book_id, token_hash, permission, created_at,
       expires_at, revoked, max_uses, use_count, 0
FROM share_link;

DROP TABLE share_link;
ALTER TABLE share_link_new RENAME TO share_link;
CREATE INDEX idx_share_link_book ON share_link(book_id);
CREATE INDEX idx_share_link_layout ON share_link(layout_id);
