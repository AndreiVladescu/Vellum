-- Published physical room layouts (plan 5 #47).
--
-- Server-only, and deliberately **not** part of schema parity: this is a
-- document store, not a mirror of an app table. The app's
-- `physical_environments` / `physical_shelves` / `book_placements` stay
-- app-local; what crosses the wire is one versioned JSON document per room
-- (see docs/LAYOUT_DOC.md).
--
-- Why a document and not rows: a room is a *composition*. Two devices that each
-- moved half the books have no meaningful row-level merge — last-write-wins
-- would interleave two arrangements into a third nobody made. So a publish is
-- whole-document with a revision counter, and a stale publish is a 409 the
-- human resolves.

CREATE TABLE layout (
    id           TEXT PRIMARY KEY,   -- the environment's UUID, minted by the app
    owner_id     TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    name         TEXT NOT NULL,
    -- Bumps on every accepted publish; a publish carries the revision it
    -- started from and is refused if that is no longer current.
    revision     INTEGER NOT NULL DEFAULT 1,
    doc          TEXT NOT NULL,      -- layout_doc JSON, stored verbatim
    published_at TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_layout_owner ON layout(owner_id);

-- `share.scope` gains 'layout'. SQLite can't widen a CHECK constraint in place,
-- so the table is rebuilt — the standard twelve-step dance, minus the steps
-- that don't apply here (nothing references `share`, and its indexes are
-- recreated below).
--
-- Viewer-only is enforced in the handler rather than here: the constraint would
-- have to name the scope *and* the permission together, and a CHECK that
-- encodes policy is one nobody remembers to update when the policy changes.
CREATE TABLE share_new (
    id         TEXT PRIMARY KEY,
    owner_id   TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    grantee_id TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    scope      TEXT NOT NULL CHECK (scope IN ('all', 'group', 'book', 'layout')),
    scope_id   TEXT,
    permission TEXT NOT NULL DEFAULT 'viewer'
                   CHECK (permission IN ('viewer', 'editor')),
    created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
INSERT INTO share_new (id, owner_id, grantee_id, scope, scope_id, permission, created_at)
    SELECT id, owner_id, grantee_id, scope, scope_id, permission, created_at FROM share;
DROP TABLE share;
ALTER TABLE share_new RENAME TO share;
CREATE INDEX idx_share_grantee ON share(grantee_id);
CREATE INDEX idx_share_owner   ON share(owner_id);
