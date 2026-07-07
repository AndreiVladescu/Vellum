-- Public links gain an optional use cap (max_uses = 1 → one-time download) and
-- a running counter. Expiry (expires_at) already exists.
ALTER TABLE share_link ADD COLUMN max_uses  INTEGER;            -- null = unlimited
ALTER TABLE share_link ADD COLUMN use_count INTEGER NOT NULL DEFAULT 0;
