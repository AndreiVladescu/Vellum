# Vellum

A personal library manager for digital **and** physical books, presented as a
visual bookshelf — browse your books spine-out, the way they look on a real
shelf, instead of scrolling a grid of covers.

## What it does

- **One library for everything** — store PDFs/EPUBs alongside records of your
  physical books: where they live, and who you lent them to.
- **A shelf, not a spreadsheet** — swipe through shelves of generated book
  spines, organize into panes, collections, and genres.
- **Add books your way** — search Open Library / Google Books for the metadata
  and cover, or create a custom book and drop in your own PDF/EPUB. Edit any
  detail later (or use a PDF's first page as its cover), keep private reader
  notes, and revert an imported book to its library defaults.
- **Integrated reader** — read your PDFs (EPUB coming later) right in the app.
- **Share it (optional)** — a self-hosted server adds accounts and roles, book
  groups, sharing (whole library, a group, or one book), public per-book links
  with expiry / one-time download, an OPDS feed for e-readers, and a web admin
  console for managing it all.
- **Yours** — works fully offline as a standalone app with a local database,
  or connects to that self-hosted server for a shared library.

## Structure

| Directory | What | Stack |
|---|---|---|
| [`app/`](app/) | Desktop (Linux/Windows/macOS) + Android app | Flutter, SQLite (drift) |
| [`server/`](server/) | Optional self-hosted library server | Rust, axum, SQLite (sqlx) |

See [DESIGN.md](DESIGN.md) for the architecture, data model, and build plan.

## Development

### App (`app/`)

Requires the [Flutter SDK](https://docs.flutter.dev/get-started/install).

```sh
cd app
flutter run          # launches on the connected device / desktop
```

### Server (`server/`)

Requires [Rust](https://rustup.rs/).

```sh
cd server
cargo run            # starts the API on http://localhost:3000
```

## Status

The standalone app is functional: add books with online metadata, a spine/cover
shelf, a PDF reader, and physical-copy loan tracking. The optional server adds
multi-user accounts, RBAC, book groups, sharing, and public per-book links. The
app logs in and syncs **both ways** — metadata, covers, and files stream to and
from the server, with **last-write-wins by timestamp** and **delete tombstones**
so edits and deletions propagate instead of resurrecting. See the build order
and the connected-mode sync roadmap in
[DESIGN.md](DESIGN.md#build-order--status).
