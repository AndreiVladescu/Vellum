-- One share per person per thing.
--
-- `POST /api/shares` inserted unconditionally, so granting the same person the
-- same access twice made two rows saying the same thing. The console's Shares
-- list then showed the grant twice, and revoking one left the other behind —
-- which reads as "revoke did nothing".
--
-- Access itself was never wrong: `book_access` takes the best permission any
-- matching share gives, so duplicates were noise rather than a privilege bug.
-- Which is also why the cleanup below keeps the *strongest* of a duplicate set
-- rather than the newest: it is the one that was already deciding.
--
-- `IFNULL(scope_id, '')` because an all-scope share has no scope_id, and NULLs
-- are never equal to each other in a unique index — without it, "the whole
-- library, twice" would still be allowed.

CREATE TEMP TABLE share_keep AS
SELECT id FROM (
    SELECT id,
           ROW_NUMBER() OVER (
               PARTITION BY owner_id, grantee_id, scope, IFNULL(scope_id, '')
               ORDER BY (permission = 'editor') DESC, created_at ASC, id ASC
           ) AS rank
      FROM share
) WHERE rank = 1;

DELETE FROM share WHERE id NOT IN (SELECT id FROM share_keep);

DROP TABLE share_keep;

CREATE UNIQUE INDEX share_one_per_target
    ON share (owner_id, grantee_id, scope, IFNULL(scope_id, ''));
