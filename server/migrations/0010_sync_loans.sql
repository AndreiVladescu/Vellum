-- loan was rebuilt (unchanged) in 0009 purely to satisfy physical_copy's FK
-- during that rebuild; this migration is the one that actually makes it sync
-- (plan 5 #4, third and last of the trio). No table rebuild needed here --
-- nothing references loan, so a plain ALTER suffices.
--
-- "LWW on returned_at" (the plan's phrasing) means returned_at is the field
-- that actually changes after creation, not the comparison key: returned_at
-- is nullable and can't order anything before a return happens, so the
-- comparison key is the same updated_at every other synced entity uses.
ALTER TABLE loan ADD COLUMN updated_at TEXT NOT NULL DEFAULT (datetime('now'));

-- deletion.kind already generalizes (see 0008/0009); 'loan' tombstones use
-- the same column. In practice a loan is deleted only via its copy's
-- ON DELETE CASCADE (physical_copies::delete), so no code path emits a
-- kind='loan' tombstone yet -- DELETE /api/loans/{id} exists for
-- completeness (the plan lists it) and to remove exactly one loan record,
-- something no UI does today.
