-- A physical copy can be in one person's hands at a time.
--
-- Loans are bookkeeping for a *physical* object, so the number of books you can
-- have out is the number of copies you own — one loan per copy, and no more.
-- Nothing enforced that: the borrow-request path checked before approving, but
-- a push from the app or a direct API call could open a second active loan on a
-- copy that was already lent, and then the library claimed two people were
-- holding the same book.
--
-- 0009 already indexed exactly this predicate for lookups. Making that index
-- unique turns the convention into a rule the database keeps.

-- Any duplicates already recorded have to go first, or the index cannot be
-- built and the server would refuse to start. The reconstruction is the only
-- one the data supports: where a copy has several open loans, all but the most
-- recent are closed at the moment the next one began, which is when the book
-- must in fact have changed hands. Nothing is deleted — the history stays, it
-- is only given the end date it always implied.
--
-- Worked out into a temp table first, deliberately. The same query written as
-- one self-referencing UPDATE reads each loan's neighbours *while* closing
-- them, so with three open loans on a copy the answer would depend on the order
-- SQLite happened to visit the rows in.
CREATE TEMP TABLE loan_handover AS
SELECT l.id AS id,
       (SELECT MIN(n.loaned_at) FROM loan n
         WHERE n.copy_id = l.copy_id
           AND n.returned_at IS NULL
           AND (n.loaned_at, n.id) > (l.loaned_at, l.id)) AS handed_over_at
FROM loan l
WHERE l.returned_at IS NULL
  AND EXISTS (SELECT 1 FROM loan n
               WHERE n.copy_id = l.copy_id
                 AND n.returned_at IS NULL
                 AND (n.loaned_at, n.id) > (l.loaned_at, l.id));

UPDATE loan SET returned_at =
    (SELECT handed_over_at FROM loan_handover WHERE loan_handover.id = loan.id)
WHERE id IN (SELECT id FROM loan_handover);

DROP TABLE loan_handover;

DROP INDEX IF EXISTS idx_loan_active;
CREATE UNIQUE INDEX idx_loan_active ON loan(copy_id) WHERE returned_at IS NULL;
