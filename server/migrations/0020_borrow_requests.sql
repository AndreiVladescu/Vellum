-- Borrow requests (plan 5 #49) — closing the public-library loop.
--
-- Server-only: a request is a conversation between two *accounts* on this
-- server, so it has no meaning on a device that isn't connected and no place in
-- the app's local schema. What the app shows is fetched, not synced.
--
-- The status set is deliberately small and one-way from `pending`: a request
-- that could go back to pending after being approved would mean a loan already
-- exists for a request that says it hasn't been decided.

CREATE TABLE borrow_request (
    id           TEXT PRIMARY KEY,
    book_id      TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
    -- Optional: a specific copy, when the requester picked one off a room view.
    -- Not a foreign key to `physical_copy` on purpose — a copy can be deleted
    -- while the request's history stays worth reading.
    copy_id      TEXT,
    requester_id TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    -- Denormalised so the owner's list still reads correctly after an account
    -- is removed — the same reasoning as the audit log's actor_email.
    requester_email TEXT NOT NULL,
    -- The book's owner at request time; who has to answer it.
    owner_id     TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
    status       TEXT NOT NULL DEFAULT 'pending'
                     CHECK (status IN ('pending', 'approved', 'declined', 'cancelled')),
    -- A note each way: why you want it, and why you said no.
    note         TEXT,
    reply        TEXT,
    created_at   TEXT NOT NULL DEFAULT (datetime('now')),
    decided_at   TEXT,
    -- The loan the approval created, so a request and its loan can be read
    -- together later.
    loan_id      TEXT
);

CREATE INDEX idx_borrow_owner ON borrow_request(owner_id, status);
CREATE INDEX idx_borrow_requester ON borrow_request(requester_id, status);

-- One live request per person per book. Without this, a refresh-happy requester
-- becomes a queue of identical rows in someone's inbox.
CREATE UNIQUE INDEX idx_borrow_one_pending
    ON borrow_request(book_id, requester_id)
    WHERE status = 'pending';
