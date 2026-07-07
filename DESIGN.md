# Vellum — Design Document

Vellum is a personal library manager for both digital books (PDF, EPUB, …) and
physical books (shelf location, loan tracking), presented as a visual bookshelf
where you browse **spines**, not cover grids.

## Goals

- One app codebase for desktop (Linux/Windows/macOS) and Android.
- Works fully offline as a standalone app with a local database.
- Optionally connects to a self-hosted server that holds the shared library.
- Visual-first UI: swipeable shelves, books shown spine-out, organized into
  panes/collections/genres.
- Automatic metadata fetch (title, authors, genre, description, cover) after
  adding a book.
- Integrated reader: PDF first, EPUB later.
- Physical book tracking: where a book lives, who borrowed it and when.

## Stack

| Piece | Choice | Notes |
|---|---|---|
| App (desktop + Android) | Flutter / Dart | Single codebase, custom-drawn shelf UI |
| App database | SQLite via `drift` | Typed queries, migrations, reactive streams |
| PDF rendering | `pdfrx` | EPUB later |
| Server | Rust — `axum` + `sqlx` | Single static binary, easy self-hosting |
| Server database | SQLite | One binary + one `.db` file; trivial backup |
| Book files & images | Filesystem | DB stores paths + hashes, not blobs |
| Metadata sources | Open Library, Google Books | Lookup by ISBN or title/author |

## Architecture: local-first

The app **always** operates against its local SQLite database and local file
store. Standalone mode is exactly that and nothing more.

A repository layer inside the app abstracts where data comes from:

- **Standalone mode** — repository reads/writes local storage only.
- **Connected mode** — same local storage, plus a sync engine that pulls
  metadata from the server, lazily downloads book files on first open, and
  pushes local changes back.

The server is deliberately boring: a REST API over (nearly) the same schema,
plus blob storage for book files and images. Later: an OPDS feed so existing
e-reader apps can browse the server too.

```
┌────────────────────────┐        ┌─────────────────────────┐
│ Flutter app            │        │ Rust server (optional)  │
│                        │  REST  │                         │
│  UI ── repository ─────┼────────┼── axum API              │
│         │              │  sync  │      │                  │
│  SQLite (drift)        │        │  SQLite (sqlx)          │
│  files/ covers/        │        │  files/ covers/         │
└────────────────────────┘        └─────────────────────────┘
```

## Server: accounts, RBAC & sharing

The server turns one library into a shared one. It is multi-user; the app stays
single-user and offline. These tables are **server-only** (migration
`0003_users_and_sharing.sql`) and are not mirrored in the app's drift schema.

- **app_user** — email, display name, Argon2 password hash, `is_master` flag.
  The **first** account created becomes the master (library owner/admin);
  afterwards registration is closed and the master provisions member accounts.
- **session** — opaque bearer tokens (only their SHA-256 is stored), 30-day
  expiry. Sent as `Authorization: Bearer <token>`.
- **book.owner_id** — every book belongs to the account that added it.
- **book_group** / **book_group_item** — shareable collections, distinct from
  the app's local `shelf` panes.
- **share** — a grant from an owner to another account. `scope` is `all`
  (the owner's whole library), `group`, or `book`; `permission` is `viewer`
  (read) or `editor` (read + modify).
- **share_link** — a public link (SHA-256 stored) giving anonymous **read**
  access to a **single** book, for people without an account. Optional expiry
  (a date or `+N days`) and an optional use cap (`max_uses = 1` → a one-time
  download); revocable. `/p/{token}` is a friendly landing page and
  `/api/public/{token}/file` is the (use-consuming) download.

Access is resolved per request: a caller may see a book if they are the master,
own it, or reach it through any share (all / group / book). Editing needs
`editor`; deleting needs ownership. Endpoints: `/api/auth/*`, `/api/users`,
`/api/books`, `/api/groups`, `/api/shares`, `/api/share-links`, and the
unauthenticated `/api/public/{token}`. Cover images and book files are stored
as filesystem blobs under `VELLUM_DATA_DIR` and served, access-checked, from
`/api/books/{id}/cover` and `/api/files/{id}`. Auth is a bearer token or HTTP
Basic (email:password), the latter so e-readers can use the OPDS catalog at
`/opds`. Port is `VELLUM_PORT` (default 3000), public link base is
`VELLUM_PUBLIC_URL`.

The server also hosts its own **web admin console** at `/` (embedded HTML/JS,
no external assets): a spreadsheet-like table of books where you select rows,
add/remove tags (groups) in bulk or per book, delete several at once, and mint
public links with an expiry date and one-time-download option. It is the
primary way to manage the library; the app's Sharing screen covers the same
endpoints for on-device use.

## Data model

- **book** — title, subtitle, description, ISBN, publisher, year, page count,
  cover image path, spine style (JSON).
- **author**, **genre** — many-to-many with book.
- **book_file** — 0..n per book: format, path, size, content hash. A book can
  be physical-only, digital-only, or both.
- **physical_copy** — 0..n per book: location (room/shelf), condition, notes.
- **loan** — per physical copy: borrower, loaned_at, returned_at. Loans are
  their own table so lending *history* comes for free.
- **shelf** — manual collections/panes, with explicit book ordering,
  independent of genres.

## Spine rendering

No API on the internet serves spine images, so Vellum **generates** spines:
extract dominant colors from the cover, render the title in a vertical
typeface, vary spine height/thickness by page count. Uniform, good-looking
shelves for every book. The generated style is stored per-book (JSON) so users
can tweak it later.

## Metadata fetching

On add: query Open Library first (free, no key), fall back to Google Books.
Match by ISBN when available (Android gets barcode scanning), otherwise
title/author search with a user-facing "pick the right edition" step.

## Build order & status

1. ✅ Flutter desktop app: schema, add a book, shelf view.
2. ✅ Shelf UI — generated spines, packing into rows, pull-out open animation,
   spine/cover display toggle, wallpapers.
3. ✅ Metadata fetch on add — Open Library, falling back to Google Books.
4. ✅ PDF reader (`pdfrx`) with saved reading position. EPUB still later.
5. ✅ Physical copies: locations + loan tracking (lend / return / history).
6. ⏳ Android build, barcode scanning. **Not started.**
7. 🚧 Rust server + sync (connected mode), OPDS feed. Server is in place
   (accounts, RBAC, groups, sharing, public links — see above) with API
   integration tests; the app can log in and **pull** the shared library.
   Blob sync, push, and in-app sharing management are the next steps below.

## Sync roadmap (connected mode)

The server already exposes the full multi-user API; the app currently does a
one-way, metadata-only pull. Remaining work, in order:

1. ✅ **Server blob storage** — upload/download endpoints for cover images and
   book files (filesystem-backed, `VELLUM_DATA_DIR`), access-checked like the
   book they belong to.
2. 🚧 **App: pull covers & files** — a pull now downloads each book's cover so
   shelves show real art. On-demand book-*file* download (to read a synced book)
   still to come.
3. ✅ **App: push** — upload local books (and their covers) to the server via an
   id-preserving `PUT /api/books/{id}` upsert, making the sync two-way.
4. ✅ **App: manage groups & shares** — a Sharing screen over the group, share,
   and public-link endpoints (create a group, add books, share the library /
   a group / a book with a user, mint and revoke public links).
5. ✅ **OPDS feed** — `/opds` serves an OPDS acquisition catalog (HTTP Basic
   auth) so third-party e-readers can browse and download books.
6. ✅ **Web admin console** — server-hosted spreadsheet-like UI at `/` to manage
   books, tags/groups (bulk), deletions, and public links with expiry +
   one-time download; friendly public landing page at `/p/{token}`.

## Repo layout

```
Vellum/
├── DESIGN.md      # this file
├── app/           # Flutter app (desktop + Android)
└── server/        # Rust server (axum + sqlx + SQLite)
```
