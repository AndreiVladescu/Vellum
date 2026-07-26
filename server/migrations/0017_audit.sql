-- Activity log for a shared library (plan 5 #35).
--
-- Server-only and never synced: this is a record of who did what on *this*
-- server, and it has no meaning on a device. Opt-in (`VELLUM_AUDIT=1`) and
-- bounded — a library with several members wants "who deleted that book?" to
-- have an answer, and a single-user server should not pay for a table it will
-- never read.
--
-- The actor's email is denormalised on purpose: an audit row has to stay
-- readable after the account it names is deleted, which is exactly the case
-- where you most want to read it.

CREATE TABLE audit (
    id          INTEGER PRIMARY KEY AUTOINCREMENT,
    at          TEXT NOT NULL DEFAULT (datetime('now')),
    actor_id    TEXT,
    actor_email TEXT,
    -- 'book.create' | 'book.update' | 'book.delete' | 'user.create' |
    -- 'share.create' | 'share.delete' | 'file.upload' | ...
    action      TEXT NOT NULL,
    target_kind TEXT,
    target_id   TEXT,
    -- A short human-readable note (a title, an email) — never a payload dump:
    -- an audit log that records book descriptions becomes a second copy of the
    -- library, with none of its access control.
    detail      TEXT
);

CREATE INDEX idx_audit_at ON audit(at DESC);
CREATE INDEX idx_audit_actor ON audit(actor_id);
