-- Reminding a borrower that a book is due (8/25 request: "loans that are due
-- should be automatically notified via mail, if configured").
--
-- ## What is sent, and once
--
-- `reminder_sent_at` (migration 0014) is one timestamp, and one is not enough
-- for three reminders: a book gets one a few days before it is due, one on the
-- day, and one when it goes late. A single column cannot say which of those
-- have gone, so a row per (loan, stage) does — present means sent.
--
-- The alternative, a `last_stage` column on `loan`, would have been smaller and
-- wrong in the one case that matters: a due date moved *back* after a reminder
-- went out should send the earlier reminder again, and a scalar that only ever
-- counts up cannot express that. Deleting this loan's rows when its due date
-- changes is one statement.
CREATE TABLE loan_reminder (
    loan_id  TEXT NOT NULL REFERENCES loan(id) ON DELETE CASCADE,
    -- 'before' | 'due' | 'overdue'. Not constrained: a server that learns a
    -- fourth stage should not need its schema changed first.
    stage    TEXT NOT NULL,
    sent_at  TEXT NOT NULL DEFAULT (datetime('now')),
    -- Kept for the audit trail: which address it actually went to, since a
    -- borrower's contact can be edited afterwards.
    sent_to  TEXT,
    PRIMARY KEY (loan_id, stage)
);

-- Per-loan opt-out. A book lent to someone who does not want email — or lent
-- across the kitchen table — should not be nagged about, and turning it off
-- for one loan must not turn it off for the rest.
--
-- Constant default, then backfilled: SQLite rejects a non-constant default on
-- ADD COLUMN once a table has rows (0023 learned this the hard way).
ALTER TABLE loan ADD COLUMN remind INTEGER NOT NULL DEFAULT 1;

-- Server-wide settings that a person edits, as opposed to the environment
-- variables that configure the process. The reminder switch and its message
-- templates live here because they are the master's to change from the console,
-- and a restart to reword an email would be absurd.
--
-- A key/value table rather than columns: this is the first such setting, and a
-- table with one row and a growing column list is a migration per preference.
CREATE TABLE server_setting (
    key        TEXT PRIMARY KEY,
    value      TEXT NOT NULL,
    updated_at TEXT NOT NULL DEFAULT (datetime('now'))
);
