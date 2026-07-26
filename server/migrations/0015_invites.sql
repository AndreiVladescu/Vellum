-- Emailed member invites (plan 5 #31, stage 3).
--
-- Server-only, like `password_reset`: not in `schema_parity.rs`.
--
-- Same token discipline as sessions and resets — only the SHA-256 is stored, so
-- a backup or a snapshot contains nothing that can be redeemed.
CREATE TABLE invite (
  token_hash  TEXT PRIMARY KEY,
  -- Who it was sent to. The redemption must match it: an invite is for a
  -- person, and letting a forwarded link create an account under a different
  -- address would turn one invite into an open door.
  email       TEXT NOT NULL,
  -- Who sent it, so a revoked or departed master's invites can be found.
  invited_by  TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  -- Optional grant to apply on redemption, mirroring `share`'s shape:
  -- 'all' | 'group' | 'book', with the id it refers to. NULL scope = no share,
  -- just an account.
  scope       TEXT,
  scope_id    TEXT,
  permission  TEXT NOT NULL DEFAULT 'viewer',
  expires_at  TEXT NOT NULL,
  used_at     TEXT,
  created_at  TEXT NOT NULL DEFAULT (datetime('now'))
);

CREATE INDEX idx_invite_email ON invite (email, expires_at);
