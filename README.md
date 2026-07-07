# Vellum

A personal library manager for digital **and** physical books, presented as a
visual bookshelf — browse your books spine-out, the way they look on a real
shelf, instead of scrolling a grid of covers.

## What it does

- **One library for everything** — store PDFs/EPUBs alongside records of your
  physical books: where they live, and who you lent them to.
- **A shelf, not a spreadsheet** — swipe through shelves of generated book
  spines, organize into panes, collections, and genres.
- **Automatic metadata** — add a book (or scan its barcode) and Vellum looks up
  the author, genre, description, and cover online.
- **Integrated reader** — read your PDFs (EPUB coming later) right in the app.
- **Yours** — works fully offline as a standalone app with a local database,
  or connects to a lightweight self-hosted server that holds the shared
  library.

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
multi-user accounts, RBAC, book groups, sharing, and public per-book links; the
app can log in and pull a shared library. See the build order and the
connected-mode sync roadmap in [DESIGN.md](DESIGN.md#build-order--status).
