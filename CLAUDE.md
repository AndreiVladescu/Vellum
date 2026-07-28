# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## What this is

Vellum is a personal library manager for digital (PDF/EPUB) and physical books,
shown as a visual bookshelf of generated book **spines**. Two projects in one
repo; DESIGN.md holds the architecture, data model, and build order — read it
before making structural decisions.

- `app/` — Flutter app (Linux/Windows/macOS + Android), the primary product.
- `server/` — Rust server (axum + sqlx), an *optional* sync backend.

## Architecture: local-first

The app must always work fully offline against its local SQLite database and
local file store; the server only adds sync on top. Never make an app feature
depend on the server being reachable.

**The schema is defined twice and must be kept in sync manually:**
- App: drift tables in `app/lib/data/database.dart` (codegen → `database.g.dart`)
- Server: SQL migrations in `server/migrations/`

Exception: a few `book` columns are **app-local-only by design** and must NOT be
added to the server schema or the *book* sync payload — `sourceMetadata` (the
import snapshot behind "revert to defaults") and `deletedAt` (the trash's grace
period, plan 5 #52: a trashed book is hidden locally and *not* deleted anywhere
until the sweep runs).

**Personal data has its own channel, never the book row.** Reading position
(plan 5 #5) goes through the opt-in per-device `reading_progress` table
(`server/src/reading.rs`); highlights/notes/bookmarks, reading sittings,
`readerNotes` and the profile photo go through `server/src/personal.rs`
(migration 0023). Every one of those tables is keyed by `user_id` taken from the
token, because a shared library holds several people's marks in the same book —
putting any of it on `book` would publish it to everyone the library is shared
with. That is why `readerNotes` is a `book_note` row server-side rather than a
column, and why it carries its own `readerNotesUpdatedAt`/`readerNotesNeedsPush`
in the app rather than riding the book's.

**Copy photos are library data, not personal** (migration 0024): they hang off a
physical copy, which already syncs, and are visible to whoever the book is
shared with — like its covers. So they carry the ordinary
`updatedAt`/`needsPush` pair and go through the blob pattern (a row, then the
bytes), not the per-user channel above.

A server without migrations 0023/0024 answers 404 to all of it; the app treats
that as "not supported yet" and syncs the library regardless — see
`_serverLacksPersonal`.

IDs are UUID strings. Book files and cover images live on the filesystem; the
DB stores paths and hashes only. Loans are a separate table from physical
copies so lending history is preserved (active loan = `returned_at IS NULL`).

## Commands

Flutter SDK is at `~/development/flutter` (on PATH in new shells).

### App (`app/`)

```sh
flutter run -d linux        # run desktop app
flutter analyze             # lint/static analysis
flutter test                # all tests
flutter test test/foo_test.dart              # single test file
flutter test --plain-name "name of test"     # single test by name
dart run build_runner build --delete-conflicting-outputs   # regenerate drift code
```

After any change to `lib/data/database.dart`, rerun build_runner. Schema
changes also require bumping `schemaVersion`, adding a drift migration, and
adding a matching SQL migration in `server/migrations/`.

### Server (`server/`)

```sh
cargo run                   # starts API on :3000, creates/migrates vellum.db
cargo test
cargo clippy
```

`VELLUM_DB=<path>` overrides the SQLite file location. Migrations in
`server/migrations/` run automatically at startup via `sqlx::migrate!` —
never edit an already-applied migration file; add a new one.

## Conventions

- The user is new to Flutter/Dart — prefer plain, idiomatic Flutter and
  briefly explain non-obvious idioms when introducing them.
- Database reads that feed UI should be drift `.watch()` streams so the UI
  updates reactively (see `watchAllBooks()`).

## Git & commits

- Never add a `Co-Authored-By` line or otherwise credit Claude/Claude Code.
  Commits are authored and pushed in the user's name only.
- Keep commit titles short. Message bodies are optional; when present, use
  very succinct bullets.
- Commit and push per feature — one cohesive feature per commit, pushed on
  its own, not batched with unrelated work.
