-- Optional password on a share link.
--
-- Today the token *is* the credential: whoever holds the URL holds the book.
-- That is right for "here, take this", and wrong for a link that travels
-- through a group chat, gets forwarded, or sits in someone's history. A
-- password makes the URL insufficient on its own. NULL means the link behaves
-- exactly as it always has, which is what every existing row gets.
--
-- Argon2, like app_user.password_hash: a share password is chosen by a person
-- in a hurry and will be short, so it must be expensive to guess offline.
-- No default on purpose — a constant NULL is what the column means, and this
-- table has rows on every real server (see tests/migrations_with_data.rs).
ALTER TABLE share_link ADD COLUMN password_hash TEXT;

-- Proof that a visitor already typed the password, so they don't retype it for
-- the metadata, then the reader, then every page of it, then the download.
--
-- Shaped like `session`: an opaque token, only its SHA-256 stored, with an
-- expiry. It rides an HttpOnly cookie rather than the URL because a download is
-- an ordinary <a href> navigation — it cannot carry a header, and a secret in a
-- query string ends up in proxy logs and browser history.
--
-- ON DELETE CASCADE is the revocation story: deleting a link takes its unlocks
-- with it. Revoking one without deleting it is already covered, because every
-- read re-checks the link's own validity.
CREATE TABLE share_link_unlock (
    token_hash TEXT PRIMARY KEY,
    link_id    TEXT NOT NULL REFERENCES share_link(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at TEXT NOT NULL
);

CREATE INDEX idx_share_link_unlock_link ON share_link_unlock(link_id);
