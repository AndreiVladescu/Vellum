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
added to the server schema or sync payloads — reading state, `readerNotes`
(personal), and `sourceMetadata` (the import snapshot behind "revert to
defaults").

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
