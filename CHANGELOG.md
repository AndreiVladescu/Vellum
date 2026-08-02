# Changelog

Notable changes to Vellum. Dates are the release date; the format loosely
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [semantic versioning](https://semver.org/).

---

## v1.0.0 — 2026-08-02

The first release. Vellum is a personal library manager for digital **and**
physical books that shows your library as a visual bookshelf: you browse your
books spine-out, the way they look on a real shelf, rather than scrolling a grid
of covers.

It runs entirely on your own machine. There is no account to create, and nothing
leaves your computer unless you deliberately set up the optional server.

### Your library

- Add books by searching **Open Library** and **Google Books** — cover, author,
  publisher and description fill themselves in, so you usually type a few words.
- Scan an **ISBN barcode** with a camera, or type the number on a desktop.
- Books with no file are records of physical copies, so a library can be part
  digital and part paper without keeping two systems.
- A **wishlist** for books you want but don't own, off the shelf until you
  attach a file or record a copy — which moves them into the library by itself.
- Every field is editable, and *Revert to library defaults* puts back what was
  originally imported when an edit goes wrong.
- **Reading insights** — sittings, pages turned and books finished.
- Spine colours, lettering, wallpaper, spine-out or cover-out, and light/dark
  are all yours to set.

### Reading

A built-in reader for **PDF and EPUB** that remembers where you stopped, so the
button becomes *Resume reading · 43%* next time.

- Highlights in four marker colours, notes and bookmarks, all listed on the
  book's page afterwards.
- `Ctrl+F` searches inside the book in both formats; `Ctrl+G` jumps to a page.
- Night mode, page colour, and — for EPUBs — typeface, text size, line spacing
  and line width.
- PDFs read either a page at a time or as a continuous scroll.
- Or hand the file to whatever reader you already use.

### Bringing in a library you already have

Imports a **folder of files**, a **Calibre library**, a **CSV or JSON
catalogue** (including Goodreads and StoryGraph exports, which import without
editing), or an **OPDS catalogue**. Each one shows you everything it found and
what it thinks you already have **before writing anything** — nothing is added
until you confirm, and you can untick individual books.

### Physical books

The second tab treats books as objects. Build a room, put bookcases in it, and
record which copy sits where — on a photo of your actual shelves if you want.

- Bookcase templates, shelves, dividers and side panels that books stack
  against.
- Placeable decorations, and wall, floor and lighting for the room itself.
- Add many books to a shelf in one gesture instead of one at a time.
- Shelves are anchored by default and move as a unit, decorations and all.
- **Loans are kept as history**, so returning a book doesn't erase the fact it
  was lent — you keep the record of who had what.

### Optional: a server

You do not need this. The app is complete on its own and works offline. Run one
only if you want the same library on a desktop and a phone, other people with
their own accounts, an OPDS feed for an e-reader, or public links to share a
single book.

- Sync with per-resource control over what leaves the device, and un-publishing
  that takes a resource back off the server.
- Reading position, highlights, notes and reading sittings travel on a
  **per-user channel**, never on the shared book row — a shared library holds
  several people's marks in the same book, and they stay private to whoever made
  them.
- An admin console with an import wizard and a dry run.
- Rooms other people have shared with you.
- Docker and Docker Compose with automatic TLS — see
  [docs/DEPLOYMENT.md](docs/DEPLOYMENT.md).

### Downloads

| You want | File |
|---|---|
| The app on Linux, no installation | `Vellum-1.0.0-x86_64.AppImage` — `chmod +x` and run |
| The app on Debian/Ubuntu/Mint | `vellum_1.0.0_amd64.deb` — `sudo apt install ./vellum_*.deb` |
| The app on any other Linux | `vellum-linux-x64.tar.gz` — extract, then `./install.sh` |
| The app on Windows | `vellum-windows-x64.zip` |
| The app on macOS (Apple Silicon) | `vellum-macos.zip` |
| The app on Android | the `.apk` matching your phone, usually `arm64-v8a` |
| The optional server | `vellum-server-<your platform>.tar.gz` |

On Linux the `.deb` and the tarball's `install.sh` both put the app out of the
way and leave one `vellum` command on your PATH, plus a menu entry — you never
move `lib/` or `data/` by hand. Reverse either with `sudo apt remove vellum` or
`./install.sh --uninstall`; both leave your library alone. Every archive ships a
`SHA256SUMS` or `.sha256` beside it.

### Requirements

Linux, Windows 10 or later, macOS on Apple Silicon, or Android. The server runs
on Linux (x86-64 and ARM64), Windows and macOS. Building from source needs
Flutter with Dart 3.12.2+ and, for the server, Rust — [DEVELOPER.md](DEVELOPER.md)
has the per-platform guide.

### Known limitations

Worth reading before you point this at a library you care about.

- **The code was written by an LLM.** A human directed and reviewed it, and
  1,245 automated tests run against it (953 app, 292 server), but that is not
  the same as years of use by many people. Keep your book files backed up
  somewhere Vellum isn't the only copy.
- **The desktop builds are unsigned.** macOS wants right-click → Open on first
  launch; Windows SmartScreen wants *More info → Run anyway*.
- **The Android build is signed with a debug key.** It installs and runs, but it
  cannot be published to Play, and it **cannot later be upgraded** to a
  properly-signed build — that would need an uninstall, which loses local data.
  Treat the Android build as a preview.
- **macOS is Apple Silicon only.** No Intel build is produced.
- Metadata lookups contact Open Library and Google Books when you add a book.
  Nothing else leaves your machine unless you configure the server.

### Security

Three rounds of security review are recorded in
[docs/SECURITY_AUDIT.md](docs/SECURITY_AUDIT.md), including the findings that
were fixed and the ones consciously accepted. Dependencies are scanned across
four ecosystems, with Dependabot and osv-scanner in CI.

If you find something exploitable, please report it privately rather than
opening a public issue — see
[CONTRIBUTING.md](CONTRIBUTING.md#security) for where to send it.

### Licence

[AGPL-3.0](LICENSE). You may use, modify and redistribute Vellum, including as a
network service, provided you pass on the same freedoms and publish your source.
