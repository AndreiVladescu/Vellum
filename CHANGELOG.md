# Changelog

Notable changes to Vellum. Dates are the release date; the format loosely
follows [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions
follow [semantic versioning](https://semver.org/).

---

## v1.1.6 — 2026-08-22

The sync bugs behind "only the new notes made on a book sync" and "the book I
finished is still unread on the phone", and a few things the reader wanted
after a week of use.

**Upgrade the server too.** The two sync fixes are a server change and an app
change working together; the app alone fixes nothing until the server has run
migration 0034.

### Fixed

- **A note written on one device could never reach another.** Every personal
  row — highlights, notes, sittings, reading positions — carried one timestamp
  doing two jobs: the writing device's clock, which is what decides
  last-write-wins, and the filter for "what changed since my last sync", which
  has to be the server's. So a note written on Monday and pushed on Friday was
  invisible to a device that had synced on Wednesday: it arrived after that
  device's cursor and was stamped before it, and no later sync would ever
  reconsider it. The two clocks are now two columns. The upgrade also stamps
  every existing row as changed, so each device receives its own personal data
  once and the gaps close.
- **Reading status never synced at all.** "Finished", "Wishlist" and the dates
  behind them had no server representation, so a book you wanted on the phone
  arrived on the tablet as one you own, and a book read to the end stayed
  unread everywhere else. It now travels on the per-user channel — like your
  private notes, and for the same reason: in a shared library "I finished it"
  is a fact about the reader, not about the book, and it stays off the book row
  that everyone can see.
- **A page turn on one device didn't show on the other.** The same
  clock confusion as the notes above: a position pushed after another device
  had synced was filtered out by its own timestamp.

### Added

- **Selecting text leaves reading mode.** Highlight, note, look up and
  translate all live in the toolbar that reading mode hides, so asking for one
  of them now brings the toolbar back.
- **A quiet line in the corner while the chrome is hidden**: where you are, how
  far through, and — when your pace has been measured — how long is left.
  Reading mode only; with the toolbar up, the counter already says it.
- **Books you have finished are marked on the shelf**, with a small blue check
  on the spine — inside the spine's own bounds, so it never sits on the book
  beside it.

---

## v1.1.5 — 2026-08-21

Sixteen notes from a week of using the app, and their answers. Most of them
land in the reader: it can hide itself, turn pages from a swipe, scroll at
your own pace, look a word up without a network, and hand a passage to a
model you choose. The rest are the small things that made the app feel wrong
— a fit that didn't fit, a sync that refused the first press, a library that
couldn't scroll in landscape.

### Added

- **Reading mode**, in both readers: the toolbar goes, the scroll thumb goes
  with it, and the screen is held awake — reading is the one thing you do
  with a phone without touching it, and a page that dims halfway down is why
  people tap at nothing. A swipe down from the top edge brings the chrome
  back, the way a video player does; a strip nothing else uses, because taps
  are how pages turn.
- **The page turns from a swipe** in page-by-page mode — up and left forward,
  down and right back, so nobody has to remember which one this reader
  wanted. Only while the page is at its resting zoom: once you have zoomed
  in, dragging is how you look around the page.
- **A vertical drag stays vertical** in continuous mode when you are zoomed
  in, so reading down a column no longer drifts sideways off the text.
- **The page can scroll by itself.** Press play and it moves continuously at
  a speed that starts from your own recorded sittings — pages a minute in a
  PDF, lines a minute in an EPUB, since an EPUB has no pages and a line is a
  thing the settings know the exact height of. A floating slower/faster
  control stays visible in reading mode, a finger on the page holds it still
  and it carries on when you lift, and in an EPUB it rolls into the next
  chapter instead of stopping at the break. With no measured pace it starts
  from a slow default rather than inventing one.
- **Look a word up without leaving the book.** Select a single word and the
  reader offers definitions, synonyms and WordNet's own examples. The
  dictionary is an 11 MB download, offered where it is first wanted and
  removable from the reader's options; every lookup happens on the device, so
  no word you read is ever sent anywhere. Words only, not phrases — the
  button appears for one and not the other, rather than appearing always and
  returning nothing.
- **Ask a model about a passage, a page or a chapter.** One OpenAI-compatible
  request, so a model you run yourself (Ollama, LM Studio, llama.cpp, vLLM)
  and a paid service are the same code path with a different address in it.
  Nothing is configured by default and nothing is sent until you name a
  server: the sheet shows the text before it goes and names the host it goes
  to. An answer can be kept as a note on the passage.
- **The page counter says what you want it to say.** Hold it — or right-click
  — to cycle through page and total, percent, pages read, pages left and time
  left; the reader's options offer the same list. Time left is measured from
  your own sittings, and shows a percentage rather than inventing a pace when
  there is nothing to measure yet.
- **Android shows the sync notification by default**, for background syncs
  and for the one at launch, not only for a sync you asked for by hand.

### Fixed

- **Fit width didn't fit the width.** Fit page worked because it zooms *out*;
  pdfrx's page fit refuses to zoom in, so asking for the width did nothing at
  all. It now goes to the page's own width directly.
- **"A sync is already in progress" on the first press, working on the
  second.** The sync at launch is silent by design, so the Sync button — which
  watched only its own state — looked idle while one was running. It now
  watches the service, says *Syncing…* and stays disabled until it is free.
- **Disconnect did nothing on Android.** It said goodbye to the server before
  changing anything locally, so against a server that had gone away it hung
  on the network and never disconnected. It now clears the session first and
  says goodbye afterwards.
- **The library couldn't be scrolled in landscape.** The recently-read strip
  took about 200px of a 280px-tall body, leaving the shelf no room; below a
  short screen it now shows one compact row and gives the rest back.
- **A book's page listed every annotation in a fixed-height box** that fought
  the page's own scroll. It shows three, with the rest behind a button that
  opens the full panel.
- **Continuous mode could be dragged off into empty space** — the axis lock
  replaced pdfrx's own boundary clamp instead of adding to it, so nothing
  held the document inside the view.

---

## v1.1.4 — 2026-08-19

Physical copies get their own overlay in the app and the console, Android
sync gets a status-bar notification and survives being backgrounded, and a
round of console fixes: two caching bugs that made earlier fixes look like
they hadn't shipped, a real one behind the "still looks cramped" report, and
the room viewer no longer needing a second sign-in in its own tab.

### Added

- **Physical copies now open in an overlay** instead of spending a full row
  per copy on the book page — a book with three or four copies used to be
  mostly copy rows. A single summary button ("3 physical copies") opens a
  sheet with the same detail as cards: location, lending state, condition
  photos, past borrowers, lend/return — plus a **delete button** per copy,
  confirmed, that warns specifically when the copy is on loan. The
  console's book table gets the same thing: a **Copies** button per row
  opens a modal with the same list and per-copy delete.
- **The login throttle is configurable** — `VELLUM_LOGIN_MAX_FAILURES`
  (default 10, matching the previous hardcoded limit) sets failed logins
  per email/IP per 15 minutes before throttling kicks in; `0` disables it.
  Has to be set before the server starts: someone locked out by it has no
  session to reach a console setting with.
- **An owner can rename anyone** in People, not just themselves — the one
  field an invite typo used to stick you with forever, since only the
  invited person could previously fix their own display name.
- **Android sync shows a status-bar notification with a progress bar** for
  as long as it runs, and now survives the app being backgrounded instead
  of the sync dying mid-request with a DNS lookup failure.

### Fixed

- **A failed login no longer claims your session expired.** A wrong
  password (or a throttled account) showed "Session expired — please log
  in again", which sent at least one person chasing the wrong problem; it
  now shows the server's real reason.
- **Opening a room or the reader from the console worked only if you
  happened to still be signed in in that exact tab.** Both open in a new
  tab, and the session doesn't carry over to a tab a new window opens —
  so both always failed with "sign in to the console first", even signed
  in one tab over. The console now hands the session across in the URL it
  opens with.
- **Two caching bugs made server-side fixes look like they hadn't
  shipped.** The room viewer and reader pages never got the cache header
  `console.js`/`console.css` already had, so a browser could keep serving
  a pre-fix copy after an upgrade; separately, a CDN in front of the
  server (Cloudflare, reported in the wild) could do the same regardless
  of that header, since `no-cache` still permits storing a response if
  the cache never actually revalidates it. Every embedded console page
  now sends `no-store`, which forbids storing the response at all.
- **Form fields in the console's dialogs didn't reliably stack under
  their labels.** The base `.row` layout class was missing `display:flex`
  entirely, so every inline `gap`/`align-items`/wrap style built on top of
  it — across roughly 40 places — was doing nothing; it went unnoticed
  because unwrapped content just falls back to normal inline flow and
  looks close enough. Exposed by the invite form needing a real wrap on a
  narrow window, and by extension the near-identical "Grant access" row
  on the Sharing page, which had the same problem on all three of its
  fields.
- **The OPDS browser's intro screen could hide its own last catalogue
  card** behind Android's gesture bar — the same missing-inset bug class
  fixed for seven other pages in v1.1.3, on an eighth it missed.

---

## v1.1.3 — 2026-08-16

A round of Android polish, a safer sqlx upgrade, and console/invite fixes.

### Added

- **Invite someone as an owner** — a third level beside view-only and
  read-and-write. An owner invite grants no share and stores no scope,
  matching what "owner" already means everywhere else; the People screen
  says which of the three a pending invite is for.
- The console's People screen shows whether **email is configured** and who
  it sends as, a **Send me a test** button that reports the mail server's
  own refusal back to you verbatim, and a **Set up email** panel listing the
  variables to set when it isn't.

### Changed

- **Invites ask for a name and an email as two separate fields.** Typing a
  username into the address box — what people were actually doing — is now
  corrected rather than rejected as an invalid email. The name follows the
  invite to the join screen as a default, so leaving it blank there still
  arrives as a person rather than an email address.
- **The invite link is always handed back** in the console, even after it's
  been emailed, so a link that lands in someone's spam folder can still be
  recovered without withdrawing and re-minting the invite.
- Every confirm/prompt dialog in the console is a real modal now, not the
  browser's.
- **Granting the same person the same access twice now updates the existing
  grant** instead of creating a silent duplicate — revoking used to leave a
  phantom copy of the access behind, which read as a revoke that did nothing.
- Docker Compose: SMTP variables are actually passed through to the
  container now (they previously only substituted into `.env` and never
  arrived), and a `DOMAIN` guard that misfired on correctly configured
  setups is gone.
- Server dependencies updated, including **sqlx to 0.9** — its new
  compile-time guard against dynamic SQL strings meant auditing every
  non-literal query in the server by hand; each one checked out (fixed
  column lists and closed sort keys, never raw input — real values still go
  through bind parameters).

### Fixed

- **Android's room editor had a crowded, half-broken toolbar.** Its search
  field used to be squeezed behind seven always-visible icons; search now
  takes over the bar the way in-book search already did, and the
  less-used actions (add a prop, room contents, zoom) moved into **More**.
- **The app goes properly fullscreen on Android now.** The status and
  navigation bars are hidden and only reappear on a swipe from the edge,
  instead of always sitting drawn over the content — which is what put the
  gesture bar over the Physical tab's toolbar and its *Add books* button.
- **Seven lists could hide their own last row** behind Android's gesture
  bar: trash, an author's books, series, the wishlist, duplicate books,
  search results and scanned books all lacked the bottom padding the
  *Move to trash* button already got, so the last row's action — Restore,
  Undo, a merge — could be unreachable.
- **A book's sharing actions no longer crowd the toolbar.** Ask to borrow,
  ask to edit and send to a device now collapse into one **More** button
  instead of stacking up to eight icons at once on a shared, connected book.
- A rare 500 on deleting a book under load, caused by a stale-snapshot
  transaction race on a loaded server — writes now take their lock up front
  rather than upgrading a read partway through.
- The console no longer signs you out the instant any request gets a 401;
  it double-checks with the server first, so one refused request doesn't
  cost you your place mid-task.

---

## v1.1.2 — 2026-08-12

Small bug & UI fixes

### Fixed

- Release automation and CI hardening updates from
  [#11](https://github.com/AndreiVladescu/Vellum/pull/11).

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
