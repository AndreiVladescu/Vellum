-- Multi-user layer: accounts, sessions, RBAC, book groups, and sharing.
-- Server-only — the offline app schema does NOT mirror these tables; they exist
-- purely to let a self-hosted server share a library across people.

-- Accounts. The first account created becomes the master (library owner/admin);
-- afterwards only the master creates further accounts.
CREATE TABLE app_user (
    id            TEXT PRIMARY KEY,             -- uuid
    email         TEXT NOT NULL UNIQUE,
    display_name  TEXT NOT NULL,
    password_hash TEXT NOT NULL,                -- argon2
    is_master     INTEGER NOT NULL DEFAULT 0,   -- boolean
    created_at    TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Opaque bearer tokens. Only the SHA-256 of the token is stored, so a database
-- leak does not hand out live sessions.
CREATE TABLE session (
    token_hash TEXT PRIMARY KEY,
    user_id    TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at TEXT NOT NULL
);
CREATE INDEX idx_session_user ON session(user_id);

-- Every book belongs to the account that added it (normally the master).
-- Nullable so rows synced from an older single-user store still load.
ALTER TABLE book ADD COLUMN owner_id TEXT REFERENCES app_user(id) ON DELETE CASCADE;
CREATE INDEX idx_book_owner ON book(owner_id);

-- Book groups: shareable collections, distinct from the app's local shelves.
CREATE TABLE book_group (
    id         TEXT PRIMARY KEY,
    owner_id   TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    name       TEXT NOT NULL,
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_group_owner ON book_group(owner_id);

CREATE TABLE book_group_item (
    group_id TEXT NOT NULL REFERENCES book_group(id) ON DELETE CASCADE,
    book_id  TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    PRIMARY KEY (group_id, book_id)
);
CREATE INDEX idx_group_item_book ON book_group_item(book_id);

-- A grant of access from an owner to another account.
--   scope      = 'all' (the owner's whole library) | 'group' | 'book'
--   scope_id   = group_id or book_id; NULL when scope = 'all'
--   permission = 'viewer' (read) | 'editor' (read + modify)
CREATE TABLE share (
    id         TEXT PRIMARY KEY,
    owner_id   TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    grantee_id TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    scope      TEXT NOT NULL CHECK (scope IN ('all', 'group', 'book')),
    scope_id   TEXT,
    permission TEXT NOT NULL DEFAULT 'viewer'
                   CHECK (permission IN ('viewer', 'editor')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_share_grantee ON share(grantee_id);
CREATE INDEX idx_share_owner   ON share(owner_id);

-- A public link granting anonymous read access to a single book — for sharing
-- with someone who has no account. Only the SHA-256 of the token is stored.
CREATE TABLE share_link (
    id         TEXT PRIMARY KEY,
    owner_id   TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    book_id    TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    token_hash TEXT NOT NULL UNIQUE,
    permission TEXT NOT NULL DEFAULT 'viewer'
                   CHECK (permission IN ('viewer', 'editor')),
    created_at TEXT NOT NULL DEFAULT (datetime('now')),
    expires_at TEXT,                            -- NULL = never expires
    revoked    INTEGER NOT NULL DEFAULT 0
);
CREATE INDEX idx_share_link_book ON share_link(book_id);
