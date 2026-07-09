-- Reading state is app-local-only by design (see DESIGN.md / CLAUDE.md): the
-- personal progress/notes for a book must never live on the shared server.
-- Migration 0002 added these three columns to the server before that decision;
-- the server has never read or written them. Drop them so the server schema
-- matches the design and can't accidentally carry per-user reading state.
ALTER TABLE book DROP COLUMN reading_progress;
ALTER TABLE book DROP COLUMN last_read_page;
ALTER TABLE book DROP COLUMN last_read_at;
