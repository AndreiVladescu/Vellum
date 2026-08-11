# Changelog

Notable changes to Vellum. Dates are the release date; the format loosely
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [semantic versioning](https://semver.org/).

---

## v1.1.1 — 2026-08-06

A small release: one new way to look at your library, and the release
machinery made harder to get wrong.

**If you are upgrading on Linux, read the last section first.** The
application id changed, and on Linux that is where the app keeps its files.

### Added

- **A list view.** A third choice beside spine-out and cover-out, in
  *Preferences → Books on the shelf*: one line per book and no artwork, so a
  screenful is dozens of books rather than a dozen. It shows the things a spine
  cannot — the author, whether there is a file to open at all, how far into a
  book you are, your rating and its status. The *B* shortcut now cycles all
  three views instead of flipping between two.

### Changed

- **Your whole library is in one directory now.** The catalogue used to sit in
  your Documents folder while the covers, book files and settings it describes
  lived under the application-support directory — so backing Vellum up by hand
  meant knowing about two places. The database moves in beside them on first
  start, with its write-ahead log, and copying that one folder now copies
  everything. An existing database at the destination is never overwritten, and
  a move that cannot complete leaves the original where it is.
- **Docker Compose no longer insists on Caddy.** `docker compose up -d` now
  starts the server alone on `127.0.0.1:3000`, for anyone who already runs
  nginx, HAProxy or Traefik — `packaging/nginx.conf.example` is a working server
  block. `docker compose --profile caddy up -d` keeps the automatic-TLS setup.
  `VELLUM_PUBLIC_URL` can be set directly for a proxy that is not simply
  `https://<domain>`.
- **The application id is now `app.vellum.Vellum`**, replacing
  `com.avladescu.vellum` — a name that belongs to the project rather than to a
  person. See below for what that means if you already have Vellum installed.
- Store metadata for F-Droid and other listings lives in `fastlane/`, and
  [docs/FDROID.md](docs/FDROID.md) is honest about what currently stops
  f-droid.org building Vellum: PDFium arrives as a prebuilt binary, and ML Kit
  is proprietary.

### Fixed

- **A tagged release can no longer ship debug-signed Android artefacts.** v1.1.0
  did, because a missing signing key only produced a warning in a build log. A
  release without signing secrets now simply has **no Android artefacts** — the
  rest still ships — and the check reads the built APK rather than trusting that
  a key was configured, since a wrong alias falls back to the debug key just as
  silently. A debug-signed install can never be upgraded in place, so publishing
  one is worse than publishing none.
- **Each platform's checksums have their own name.** All four build jobs wrote a
  file called `SHA256SUMS`, and release assets must be uniquely named, so three
  of the four were dropped. They are now `SHA256SUMS-linux`, `-windows`,
  `-macos` and `-android`. (GitHub also shows a SHA-256 for every asset itself,
  so nothing was ever unverifiable.)
- The server's systemd unit points its `Documentation=` at the real repository.

### Upgrading

**Linux.** Two things move in this release, and only one of them moves itself.

The **database** relocates on its own, out of `~/Documents/vellum.sqlite` and
into the application-support directory. Nothing to do.

Your **covers, book files and settings** do not, because the directory holding
them is named after the application id — which changed. A fresh v1.1.1 looks in
`~/.local/share/app.vellum.Vellum` while they sit in
`~/.local/share/com.avladescu.vellum`, so the symptom is a library that still
lists every book but has lost their covers, their files and your settings. Move
the directory **before first launch**:

```sh
mv ~/.local/share/com.avladescu.vellum ~/.local/share/app.vellum.Vellum
```

If you have already started v1.1.1 once, it will have created the new directory
and moved the database into it. Close Vellum and copy the rest in on top —
there is no `vellum.sqlite` in the old directory to clash with, because before
this release the database was never kept there:

```sh
cp -r ~/.local/share/com.avladescu.vellum/. ~/.local/share/app.vellum.Vellum/
```

**Android.** The id *is* the package name, so v1.1.1 installs as a separate app
rather than updating v1.1.0. Uninstall the old one once you have moved anything
you want to keep. (v1.1.0's Android builds were debug-signed and could never
have been updated in place regardless — see above.)

**macOS and Windows** store per-application data under the same renamed
identifier; the same "lost its covers and files" symptom applies, and the same
fix — move the old directory to the new name before first launch.

---

## v1.1.0 — 2026-08-05

Everything here is additive: your library, its files and its database carry over
untouched. The app's schema moves 28 → 30 and the server gains two migrations,
both applied on first start.

The theme of this release is **things that used to need a server, and no longer
do** — searching inside your books, and translating a passage — plus a Linux
release that installs like a normal program.

### Reading

- **Translate the passage you have selected.** The Translate button appears
  beside the highlighter when you select text: pick the languages, read the
  translation, and keep it as a note on the passage if it is worth keeping.
  **Nothing is sent anywhere.** On Android and iOS it runs on the device, with
  language packs you download and delete under *Languages*; on a desktop it uses
  a translator installed on the machine (Argos Translate or Apertium) and says
  exactly what to install if there is none. Where both engines are present, the
  one that actually has your language pair answers.
- **Search inside your books, offline.** A local full-text index over book
  *contents*, so the search box finds a phrase that appears in the body of a
  book and not in its catalogue entry. Desktop only and off by default — the
  index is roughly the size of the text it holds, and it should not appear on
  your disk unasked.
- The reader no longer reopens the document when night mode is toggled, which
  used to lose your place.
- A book that will not open now says so, and offers to try again, instead of
  showing a blank page.
- The reader spends far less memory on a phone: the shelf's covers are handed
  back when a book opens, and both the image cache and the page cache are
  bounded.

### Your library

- **A page for your series**, showing what you have and which volumes are
  missing from a run.
- **Tap an author** to see the rest of their books.
- **An overdue book comes and finds you** — the drawer's Loans row carries a
  count of loans wanting attention. Everything else on that screen you go
  looking for; an overdue loan is the one thing that should arrive on its own.
- **Keep a book on this device only.** A cloud button on the book's page stops
  it syncing in either direction, without hiding it from you.
- Imports keep your **ratings, shelves and reviews** — the columns a Goodreads
  or StoryGraph export actually carries.
- The OPDS browser offers somewhere to go rather than an empty address bar.
- *Open in another app* opens the book in another app on Android, instead of
  handing it to the share sheet.
- The health check reports the things only you can decide about.

### Physical books

- A room you published from one device can be **brought down onto another** —
  before this your own rooms were invisible everywhere else.
- A shared room arrives **with its ornaments**, and a prop's artwork is no
  longer its collider, so a book can sit under a plant's leaves.

### Sharing

- **A share link can carry a password.** The URL alone stops being enough,
  which is what a link posted into a group chat needs. Argon2-hashed, throttled
  per link and per address, and a revoked or expired link cannot be unlocked.
- **A link's address can be read again.** It used to exist only in the dialog
  that created it — see *Security* below for the trade that makes this possible.
- **A Shares screen**: every public link in every state (live, expired, used up,
  revoked) and every account share, on one page, with the URL and a Revoke.

### The console

- **The master account can be created from the console.** A fresh server used to
  show a login box with nothing to log in as; it now opens on a *Create the
  master account* form, and asks for the bootstrap token when one is set.
- Shares, People and Borrow requests are **pages** now rather than boxes
  floating over the library.
- *Fetch metadata* looks the book up under the title you just typed, and
  **nothing in the detail panel is written until you press Save** — a wrong
  match costs a Cancel instead of an edit to undo.
- The sign-in and first-run forms were redrawn.

### Linux

- **An AppImage, a `.deb` and an installer.** The AppImage is one file; the
  `.deb` and `install.sh` put the app out of the way and leave a single `vellum`
  command on your PATH.
- The window and launcher **icon now appears** — including on a build you have
  not installed, which is what `flutter run` produces.

### For operators

- `server/.env.example` lists every setting with its default, and
  `docs/DEPLOYMENT.md` gained a section on generating a TLS certificate with
  openssl, including the `subjectAltName` without which every client refuses it.
- The Android release is signed properly **when a keystore is configured** —
  see DEVELOPER.md. Without one it still falls back to a debug key.

### Security

- Share-link passwords are Argon2, never stored or returned in the clear, and
  the unlock rides an HttpOnly cookie rather than a query string.
- **`share_link` now stores its token.** Only the hash was kept before, which
  meant a link's URL existed exactly once and could never be shown again. The
  hash protected the *route* to a book whose row and file sit in the same
  database and data directory, so a reader of that database already had the
  book. Session and password-reset tokens are unaffected and stay hashed.
- `GET /api/auth/registration` reports whether a first account can still be
  made. It answers "open" only in the state anyone can detect by POSTing to
  `/auth/register`, and permanently "closed" once a master exists.

### Known limitations

Carried over from v1.0.0, with one addition:

- **A book sometimes opens blank the first time**, and shows correctly when
  reopened. The cause is not yet found; the reader now shows a spinner and,
  after a few seconds, an explanation with a *Try again* that rebuilds the
  viewer — which is what closing and reopening the book does by hand.
- The code was written by an LLM with a human directing and reviewing it. 1,351
  automated tests run against it (1,054 app, 297 server).
- Desktop builds are unsigned; macOS is Apple Silicon only.

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
