-- Password reset tokens (plan 5 #31, stage 2).
--
-- Server-only: the app never sees this table, so it is deliberately *not* in
-- `schema_parity.rs`.
--
-- Only the SHA-256 of the token is stored, exactly as `session` does. A reset
-- token is a credential for its lifetime: a database dump — or a backup, or a
-- snapshot — must not contain anything that can be replayed as one.
CREATE TABLE password_reset (
  token_hash TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  -- Short by design; a reset link that works for a week is a week-long
  -- account-takeover window sitting in someone's inbox.
  expires_at TEXT NOT NULL,
  -- Set when redeemed, so a token works exactly once even before it expires.
  used_at    TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- The redeem path looks a token up by hash (the primary key); this index serves
-- the housekeeping delete of a user's older outstanding tokens.
CREATE INDEX idx_password_reset_user ON password_reset (user_id, expires_at);
