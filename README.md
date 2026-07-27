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
- **A wishlist too** — keep books you want but don't own; scan a barcode in a
  shop, or fill a gap in a series you collect. They stay off the shelf until you
  attach a file or record a copy, which moves them into the library by itself.
- **Integrated reader** — read your PDFs and EPUBs right in the app.
- **Keyboard-first on desktop** — Ctrl+K opens a command palette that runs any
  action or jumps to any book; the common ones have their own shortcuts.
- **Backed up** — export the whole library (database, covers, files) to a
  single archive and restore it anywhere. Removing a book puts it in a trash
  that holds it for 30 days, so a mis-click isn't a restore-from-backup.
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

#### Building for Android

Release builds need a signing keystore. Copy
[`android/key.properties.example`](app/android/key.properties.example) to
`android/key.properties` (gitignored) and fill it in — that file documents the
one-time `keytool` command. Without it, release builds fall back to the debug
key so a fresh checkout still runs, but such a build isn't distributable.

```sh
cd app
flutter build appbundle --release        # distribution artifact for Play
                                         # (Play delivers per-ABI, ~30 MB)
flutter build apk --release --split-per-abi   # sideload APKs, one per ABI
```

Prefer the app bundle for the store: the single fat APK carries every ABI
(arm64 + armeabi-v7a + x86_64 + pdfium/sqlite natives, ~87 MB), while Play
delivers only the device's ABI from a bundle.

### Server (`server/`)

Requires [Rust](https://rustup.rs/).

```sh
cd server
cargo run            # starts the API on http://localhost:3000
```

#### Connecting the Android app (HTTPS)

Android blocks cleartext to a remote host, so the phone needs TLS. Enable the
server's built-in self-signed certificate — it's **generated once and reused on
every restart**, so the app only imports it a single time:

```sh
cd server
# Include the LAN IP the phone uses; the cert also lives under the data dir so
# a re-run from anywhere reuses it (VELLUM_DATA_DIR overrides that location).
VELLUM_TLS=1 VELLUM_TLS_SANS=192.168.1.50 cargo run
```

For anything beyond trying it out — Docker, a compose file with automatic TLS, a
systemd unit, the full environment-variable table, backups and upgrades — see
[`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md).

On startup it logs whether it **generated** or is **reusing** the certificate,
its path, and the SHA-256 fingerprint. In the app, connect to
`https://<LAN-IP>:3000`, tap **Import** on the certificate row, paste
`cert.pem` (or choose the file), and verify the fingerprint matches.

- The cert **persists** — don't delete it between runs, or the app will reject
  the new one. Delete both `cert.pem` and `key.pem` only when you *want* to
  rotate it (then re-import).
- **Bring your own cert** by pointing `VELLUM_TLS_CERT` / `VELLUM_TLS_KEY` at
  your files (or dropping `cert.pem`/`key.pem` in the data dir) — an existing
  pair is always preferred over generating one.

## Status

The standalone app is functional: add books with online metadata, a spine/cover
shelf, a PDF reader, and physical-copy loan tracking. The optional server adds
multi-user accounts, RBAC, book groups, sharing, and public per-book links. The
app logs in and syncs **both ways** — metadata, covers, and files stream to and
from the server, with **last-write-wins by timestamp** and **delete tombstones**
so edits and deletions propagate instead of resurrecting. See the build order
and the connected-mode sync roadmap in
[DESIGN.md](DESIGN.md#build-order--status).
