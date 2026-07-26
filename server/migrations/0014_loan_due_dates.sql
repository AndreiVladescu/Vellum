-- Loan due dates, contacts and notes (plan 5 #27).
--
-- `loan` has been synced since 0010 (plan 5 #4), so these are synced columns and
-- `schema_parity.rs` gains them alongside the app's drift table. That is exactly
-- why #4 had to be decided first: promoting a column after the fact is painful,
-- and the plan called this out.
--
-- All nullable: a loan with no agreed return date is normal ("borrow it as long
-- as you like"), and forcing a date would make the app lie about an arrangement
-- that doesn't have one.
ALTER TABLE loan ADD COLUMN due_at TEXT;
-- Free text: a phone number, an email, "Ana from book club". A contact-picker id
-- would tie the column to one platform's address book.
ALTER TABLE loan ADD COLUMN borrower_contact TEXT;
ALTER TABLE loan ADD COLUMN notes TEXT;
-- When a due reminder was last raised on *this* device, so a reminder isn't
-- shown twice. App-local in spirit but carried here because the row is synced
-- and splitting one loan across two tables for one column isn't worth it.
ALTER TABLE loan ADD COLUMN reminder_sent_at TEXT;

-- The loans overview sorts by due date and pulls out the overdue ones.
CREATE INDEX idx_loan_due ON loan (returned_at, due_at);
