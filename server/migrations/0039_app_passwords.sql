-- App passwords (v1.6.2): per-device secrets for OPDS e-readers, so the
-- account password never has to be typed into a Kindle, a Kobo or KOReader.
--
-- Server-only: the app never sees this table, so it is deliberately *not* in
-- `schema_parity.rs` (the same as `session` and `password_reset`).
--
-- One row per device. Revoking one deletes its row, and since every request
-- that presents an app password looks it up here, the device is locked out on
-- its very next request — there is no cache to wait out.
--
-- ## Only a hash, and a fast one
--
-- `secret_hash` is the SHA-256 of the secret, never the secret: a database
-- dump, a backup or a snapshot must not hold anything that can be replayed as a
-- credential. SHA-256 rather than Argon2 because the secret is not a human
-- password. It is 120 bits drawn from the OS RNG (see `app_passwords.rs`), so
-- there is no dictionary to try and nothing a slow hash would slow down — an
-- attacker holding the hash still faces 2^120 guesses. Argon2 would buy nothing
-- and cost ~10^2 ms of CPU on every OPDS request, which an e-reader makes for
-- every page of a feed and every cover. It is the reasoning `session.token_hash`
-- already rests on.
--
-- `prefix` is the secret's first four characters, kept in the clear so a list
-- of devices can say which secret is which ("abcd-…") without being able to
-- show it. Four of twenty-four characters leaves 100 bits unknown.
CREATE TABLE app_password (
  id           TEXT PRIMARY KEY,
  user_id      TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  -- What the person called it: "Kobo", "KOReader on the tablet".
  label        TEXT NOT NULL,
  prefix       TEXT NOT NULL,
  secret_hash  TEXT NOT NULL UNIQUE,
  created_at   TEXT NOT NULL DEFAULT (datetime('now')),
  -- Written at most once a minute per secret, so a reader paging through a feed
  -- does not turn every GET into a write. NULL until first use.
  last_used_at TEXT
);

-- Listing one person's app passwords, newest first.
CREATE INDEX idx_app_password_user ON app_password (user_id, created_at);
