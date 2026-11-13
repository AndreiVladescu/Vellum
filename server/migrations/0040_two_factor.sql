-- Two-factor sign-in (v1.6.2): RFC 6238 TOTP codes from an authenticator app,
-- with one-time recovery codes for a lost phone. See `src/two_factor.rs`.
--
-- Server-only: the app never sees these tables, so they are deliberately *not*
-- in `schema_parity.rs` (the same as `session`, `password_reset` and
-- `app_password`). New tables only — nothing here alters a populated one.

-- One row per account that has started or finished enrolment.
--
-- ## The secret is stored as it is, not hashed and not encrypted
--
-- Unlike every other credential on this server, a TOTP secret cannot be
-- hashed: verifying a code means computing HMAC-SHA-1 *with* the secret, so the
-- server must be able to read it. Encrypting it at rest would need a key the
-- server can also read, and this server has no key store — no master key, no
-- KMS, nothing in the environment for it. A key kept next to the database (in
-- the same data directory, the same backup) protects against nothing, so this
-- does not pretend to. Consequences, stated plainly:
--
-- - Whoever can read this database (a backup, a snapshot) can generate this
--   account's codes. They could equally reset any password by writing a new
--   hash, so the database was already the crown jewels; protect it accordingly
--   (docs/SECURITY_AUDIT.md).
-- - The second factor protects against the realistic attack — a password
--   phished, reused or guessed — not against a stolen database.
--
-- `secret` is the base32 form an authenticator app is given (RFC 4648, no
-- padding): 160 random bits, the length RFC 4226 recommends for HMAC-SHA-1.
CREATE TABLE user_totp (
  user_id    TEXT PRIMARY KEY REFERENCES app_user(id) ON DELETE CASCADE,
  secret     TEXT NOT NULL,
  -- NULL while enrolment is pending: the secret has been shown but no code
  -- from it confirmed yet, so sign-in does not ask for one. Set the moment a
  -- code is confirmed, and that is what "two-factor is on" means.
  enabled_at TEXT,
  -- The last 30-second time step a code was accepted for. A code is accepted
  -- only for a *later* step, so one seen over a shoulder or lifted from a
  -- phishing page cannot be replayed inside its own validity window.
  last_step  INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);

-- Ten per account, made when two-factor is turned on (or regenerated), shown
-- once. Each works once: `used_at` is set by the same UPDATE that accepts it.
--
-- SHA-256, not Argon2, for the reasoning in 0039: a recovery code is 80 bits
-- from the OS RNG, not a human password, so there is no dictionary for a slow
-- hash to slow down. (And a reader of this table can read `user_totp.secret`
-- anyway.)
CREATE TABLE totp_recovery_code (
  user_id    TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  code_hash  TEXT NOT NULL,
  used_at    TEXT,
  created_at TEXT NOT NULL DEFAULT (datetime('now')),
  PRIMARY KEY (user_id, code_hash)
);

-- A password that was right, waiting for its second factor.
--
-- Password sign-in on a two-factor account answers with a challenge instead of
-- a session; the code is then sent with the challenge, never with the password
-- again. Short-lived (five minutes), single-use, and abandoned after a few
-- wrong codes — and wrong codes also count against the account in the login
-- throttle, so starting a fresh challenge does not reset the guessing budget.
-- Only the SHA-256 of the token is stored, as `session` does.
CREATE TABLE login_challenge (
  token_hash TEXT PRIMARY KEY,
  user_id    TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  expires_at TEXT NOT NULL,
  failures   INTEGER NOT NULL DEFAULT 0,
  created_at TEXT NOT NULL DEFAULT (datetime('now'))
);
CREATE INDEX idx_login_challenge_user ON login_challenge (user_id);
