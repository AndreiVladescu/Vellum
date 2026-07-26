# Vellum — Design Document

Vellum is a personal library manager for both digital books (PDF, EPUB, …) and
physical books (shelf location, loan tracking), presented as a visual bookshelf
where you browse **spines**, not cover grids.

> Near-term to-do and known issues live in [`docs/BACKLOG.md`](docs/BACKLOG.md);
> the architecture + feature roadmap is
> [`docs/IMPROVEMENT_PLAN_5.md`](docs/IMPROVEMENT_PLAN_5.md).

## Goals

- One app codebase for desktop (Linux/Windows/macOS) and Android.
- Works fully offline as a standalone app with a local database.
- Optionally connects to a self-hosted server that holds the shared library.
- Visual-first UI: swipeable shelves, books shown spine-out, organized into
  panes/collections/genres.
- Automatic metadata fetch (title, authors, genre, description, cover) after
  adding a book.
- Integrated reader for PDF and EPUB.
- Physical book tracking: where a book lives, who borrowed it and when.

## Stack

| Piece | Choice | Notes |
|---|---|---|
| App (desktop + Android) | Flutter / Dart | Single codebase, custom-drawn shelf UI |
| App database | SQLite via `drift` | Typed queries, migrations, reactive streams |
| PDF rendering | `pdfrx` | |
| EPUB rendering | in-house parser + `flutter_widget_from_html_core` | an EPUB is a zip; `archive` + `xml` parse the OPF spine |
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
  metadata, covers, and book files from the server and pushes local books
  (with their covers and files) back.

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
  the (also synced, but unrelated) `shelf` panes.
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
`/api/books`, `/api/deletions` (delete tombstones for sync), `/api/groups`,
`/api/shares`, `/api/share-links`, and the unauthenticated `/api/public/{token}`. Cover images and book files are stored
as filesystem blobs under `VELLUM_DATA_DIR` and served, access-checked, from
`/api/books/{id}/cover` and `/api/files/{id}`. Auth is a bearer token or HTTP
Basic (email:password), the latter so e-readers can use the OPDS catalog at
`/opds`. Port is `VELLUM_PORT` (default 3000), public link base is
`VELLUM_PUBLIC_URL`, and the max upload size is `VELLUM_MAX_UPLOAD_MB` (default
2048). The cover and file endpoints also accept the token as a `?token=` query
param, so a browser `<img>` (cover) or `<a download>` (file) works without an
Authorization header. A `?token=` is honored **only** on `GET`s to a book cover
(`/api/books/{id}/cover`) or a file download (`/api/files/...`); every other
endpoint requires the header, so a token leaked into a log or history can't be
replayed against a mutating call. (Caveat: query-string tokens can still leak
into proxy/access logs and browser history; a future refinement is short-lived
per-resource tokens. The server speaks plain HTTP and should sit behind a TLS reverse proxy —
see **Deployment**.) The app keeps its own session token in the platform secure
store (Keychain / libsecret / Keystore), not plaintext prefs, and defaults new
server URLs to `https://`.

For book discovery the server runs the **same metadata search** as the app
(`GET /api/metadata/search`, Open Library → Google Books); `POST
/api/books/from-search` adds a chosen result, fetching its description and cover.
See **Adding & editing books** below.

The server also hosts its own **web admin console** at `/` (embedded HTML/JS,
no external assets): a spreadsheet-like table of books where you select rows,
add/remove tags (groups) in bulk or per book, delete several at once, add books
(search online or create custom, optionally attaching a file), drag-and-drop
(or click to upload) a PDF/EPUB or cover image onto a row — validated by magic
bytes — and mint public links with an expiry date and one-time-download option.
The table is built for **managing at scale**: live search, click-to-sort
columns, filters by tag / untagged / missing metadata (no file, cover, year, or
author), show/hide columns and a density toggle (both remembered), a cover
thumbnail and file/cover status dots, **inline** title/year editing
(double-click), **bulk** publisher/year edits and a shared file/cover applied to
the selection, **CSV/JSON export** of the filtered rows, **CSV import** (title
required; deduped by title), and keyboard nav (`/` search, arrows, space to
select, enter to open). To render the Author and file columns without a per-row
round-trip, `GET /api/books` is enriched with `authors[]` and `file_count`
(response-only; the app's pull ignores the extra fields).
Clicking a book opens a **detail view** — cover, metadata, tags, and files —
where you edit fields in place, **download the book file** directly, **change
the cover** (the cover shows and reveals a *Change cover* affordance on hover),
and **upload** a file (with a live upload-progress bar, since big books take a
while). It is the primary way to manage the library; the app's Sharing screen
covers the same
endpoints for on-device use.

## Email (optional)

Off unless `VELLUM_SMTP_HOST` and `VELLUM_MAIL_FROM` are set (plan 5 #31), because
a LAN-only server should need no outbound SMTP, no credential, and no egress. When
it *is* configured, `mail` appears in `GET /api/capabilities` — a conditional
capability, unlike the rest — so the app can hide "Forgot password?" rather than
offer a button that can only fail. A misconfiguration stops the server at boot
instead of surfacing weeks later as a reset that silently doesn't arrive.

**Password reset** is `POST /api/auth/forgot` → emailed
`${PUBLIC_URL}/reset/<token>` → `POST /api/auth/reset`. Three properties carry
the security of it:

- `forgot` **always answers the same thing** — "if that email exists, a link was
  sent" — whether or not the address is real, whether or not the mail send
  succeeded, and whether or not mail is even configured. Anything else makes it an
  account-existence oracle. It is throttled per email *and* per IP, checked before
  the lookup so a rate limit is indistinguishable from a missing account too.
- Only the token's **SHA-256** is stored (as with sessions), so a backup or a
  snapshot contains nothing replayable. Tokens last an hour, work once, and a new
  request invalidates the previous link.
- Redeeming one **drops every existing session** for that account: resetting is
  what someone does when they fear they are compromised.

**Invites** close the loop: registration shuts after the first account, so
`POST /api/invites` (master-only) mints a 14-day single-use token and emails a
join link, optionally carrying a share to apply on redemption. Two choices worth
noting — the account is created under the **invited address**, never one the
redeemer supplies, so a forwarded link can't become an open registration
endpoint; and when mail is off the link is **returned to the master** instead of
the invite being refused, because a LAN server without SMTP still needs to add
people. Re-inviting an address supersedes the previous link.

Both token-bearing paths (`/reset/<token>`, `/join/<token>`) are **redacted** by
the request logger — see L8 in `docs/SECURITY_AUDIT.md`.

The **app** shows "Forgot your password?" only when the server it is pointed at
advertises `mail` — probed from the unauthenticated capability endpoint as the
address is typed, since a reset by definition has no session. Its confirmation is
deliberately non-committal ("if that address has an account…") and is shown even
when the request fails: echoing success would turn the sign-in screen into the
account-existence oracle the server took care not to be.

## Observability

Every response carries an **`X-Request-Id`** (plan 5 #37) — echoed when the caller
supplies one, generated otherwise — which appears in the server's log line for that
request *and* in the body of an error response. That last part is the point: a user
can paste one string from an app error into an issue, and the operator can find the
request. An inbound id is sanitised (printable ASCII, 64 chars) before it reaches a
log line, so a caller can't forge log entries with it.

The middleware is a plain `axum::middleware::from_fn` rather than
`tower-http`'s `TraceLayer`: it is one header, one span and one log line, and the
server keeps its dependency surface deliberately small. One subtlety worth knowing
if you touch it — the span must be attached with `.instrument()`, not
`span.enter()`, because a guard is dropped at the first `.await` and the id would
then be missing from exactly the slow requests worth diagnosing.

`GET /api/admin/stats` (master-only) backs the console's **Server** dialog: library
counts, blob bytes on disk, and database size *including its WAL sidecars* — in WAL
mode the `-wal` file is part of the database, and reporting only the `.db`
understates it badly right after a large import. No Prometheus, no OpenTelemetry:
for a personal server, logs plus one stats endpoint are the right size.

## Deployment

> The operator-facing guide — Docker, compose with automatic TLS, systemd, the
> full environment-variable table, backups and upgrades — is
> [`docs/DEPLOYMENT.md`](docs/DEPLOYMENT.md) (plan 5 #36). This section is the
> design rationale behind it.

**Two TLS stories, and you pick one.** Behind a reverse proxy (Caddy, nginx,
Traefik) the server speaks plain HTTP and the proxy terminates TLS — the right
answer when you have a domain, and what `docker-compose.yml` sets up. On a LAN
with no domain, `VELLUM_TLS=1` makes the server generate and *reuse* a
self-signed certificate (stable across restarts, so the fingerprint the app
pinned stays valid) which the app imports. Running both at once means debugging
both. Either way, set **`VELLUM_PUBLIC_URL`** to the address users actually
reach, because minted share links embed it.

**Shipping.** A multi-stage `Dockerfile` builds the binary and ships it on
`debian-slim` — deliberately not `scratch`, since the PDF cover/text fallback
shells out to `pdftoppm`/`pdftotext` and an empty userland would silently lose
it. The image runs as an unprivileged user, keeps database and blobs in one
volume, and health-checks `/health` with a real request. A `v*` tag builds
musl-static Linux binaries plus Windows, macOS and the Android artefacts.

**One-command backup.** `GET /api/admin/snapshot` (master-only) streams a tar of
a `VACUUM INTO` copy of the database plus the blob directory — consistent without
touching the live WAL, which is the trap in doing it by hand.
`POST /api/admin/sweep` reports rows whose blobs are missing and blobs no row
references, deleting nothing unless asked (plan 5 #12) — the server-side
counterpart of the app's library health check.

**Back up the `.db` file and the data dir together** — the database stores blob
*paths*, so the two are only meaningful as a pair. The database runs in **WAL
mode**, so its `-wal`/`-shm` sidecar files are part of the state: back them up
alongside the `.db`, or run `PRAGMA wal_checkpoint(TRUNCATE)` before copying the
`.db` on its own. The app defaults new server URLs to `https://` and warns when
a URL is unencrypted.

## Data model

- **book** — title, subtitle, description, ISBN, publisher, year, page count,
  cover image path, spine style (JSON).
- **author**, **genre** — many-to-many with book.
- **book_file** — 0..n per book: format, path, size, content hash. A book can
  be physical-only, digital-only, or both.
- **physical_copy** — 0..n per book: location (room/shelf), condition, notes.
  **Synced** (plan 5 #4, second of three): LWW on `physical_copy.updated_at`.
  Unlike shelf, a copy has no owner of its own — it belongs to exactly one
  book, so visibility/edit rights derive entirely from that book's share
  rules (`server/src/access.rs::copy_access` delegates to `book_access`;
  `physical_copies.rs::visible_copies` reuses `books::access_predicate`
  joined on `book`). A copy can't change which book it belongs to on an
  update (rejected outright, not silently ignored).
- **loan** — per physical copy: borrower, loaned_at, returned_at. Loans are
  their own table so lending *history* comes for free. **Synced** (plan 5
  #4, third and last of the trio): LWW on `loan.updated_at` (the plan calls
  this "LWW on `returned_at`", but that field is nullable and can't order
  anything before a return happens — it's the field that actually changes,
  not the comparison key). No owner of its own, same as physical_copy —
  access derives from the loan's copy's book
  (`server/src/access.rs::loan_access` joins copy → book). `loaned_at` comes
  from the client at creation (a loan can predate this device's first sync)
  and, like `copy_id`, can't change on a later push. A loan is deleted only
  via its copy's `ON DELETE CASCADE` — no per-loan tombstone is emitted for
  that path; `DELETE /api/loans/{id}` exists for completeness but nothing
  in the app calls it today.
- **shelf** + **shelf_book** — manual collections/panes with explicit book
  ordering, independent of genres. **Synced** (plan 5 #4): LWW on
  `shelf.updated_at`, membership replaced wholesale on push (the app always
  sends the full ordered list). Visible to whoever holds an all-scope share of
  the owner's library — there is no shelf-scoped share type. A shelf naming a
  book the receiving device doesn't hold yet drops that id from the local
  membership rather than failing (`server/src/shelves.rs::existing_book_ids`
  does the same server-side, since `shelf_book.book_id` has a foreign key).

**Library health** (app, plan 5 #11) is Preferences → *Check library*: the database
and the file tree can diverge — a file deleted by hand, a partial restore, bytes
left by a failed import — and nothing detected any of it, while the shelf hid the
loss by drawing a generated spine. The scan reports six categories (missing file,
missing cover, orphan blob with the bytes it would reclaim, placement with no copy,
the same content attached twice to one book, and delete markers too old to matter
when there is no server) and is **read-only**: every repair is a separate, explicit
action, the destructive ones confirm first, and the scan is cancellable because it
stats every blob. Two deliberate non-findings: `.part` leftovers are swept at
startup and are not reported, and the same content on *two* books is legitimate
(an omnibus) rather than a duplicate.

**Loans chase people** (both, plan 5 #27). `loan` gains `due_at`,
`borrower_contact`, `notes` and `reminder_sent_at` — synced columns, because
`loan` has been a synced table since #4, which is exactly why that decision had to
come first. Lending offers **presets** (2 weeks / 1 month / pick a date / **no
date**) rather than a bare date picker: most lending is "a couple of weeks", and
"no date" has to be as easy as the rest or people invent a deadline they don't
mean. A null `due_at` is therefore a real arrangement, not missing data.

Everything about overdue-ness compares **local calendar days, not instants**: a
book due today must not read as overdue at 00:01 because the stored moment was
midnight UTC. The loans list sorts most-urgent-first (overdue, then by date, with
undated loans last) and badges the ones that need attention; *Copy a reminder*
puts a ready message on the clipboard rather than half-integrating a share sheet
that would fail on desktop. A reminder given today isn't repeated today, but one
given last week comes back for a book that is still out.

**Published rooms** (both, plan 5 #47) let a layout leave the device it was
built on. It is the one thing Vellum syncs as a **document rather than rows**,
and deliberately so: a room is a *composition*, and two devices that each moved
half the books have no meaningful row-level merge — last-write-wins would
interleave two arrangements into a third nobody made. So a publish is whole, with
a revision counter; a publish whose `base_revision` is stale gets a **409** and
the app asks the human (take theirs, or replace with mine). That is the same
reasoning that rejected field-level merge for books.

The document (`docs/LAYOUT_DOC.md`) carries **geometry only** — no titles,
authors or covers. That is what makes a shared room safe by construction rather
than by remembering to filter: a viewer resolves each `book_id` through normal
RBAC, and a book they may not see renders as an anonymous spine because there was
never anything else in the document to leak. The one denormalisation is
`width_m`/`height_m`, resolved at publish time, since a viewer who cannot read a
page count still has to draw the spine at the right thickness.

Sharing a room shares its *shape*. Making its books visible is a separate,
deliberate act: publish offers to collect them under a `Room: <name>` tag, and
that tag is shared through the ordinary group/share UI — book visibility rides
the RBAC that already exists instead of a second path to the same data. The share
scope `layout` is **viewer-only**; `editor` would mean two people dragging the
same shelf, which the document model has no answer for beyond the 409.

Applying a fetched room is **upsert-by-id then delete-what-is-missing**, so a
fetch is idempotent and a book someone took off the shelf actually disappears.
It never invents book rows — a placement whose book hasn't synced yet is skipped
and *counted*, so the app can say "3 books aren't on this device yet" instead of
looking like data loss — and a copy minted for a not-yet-synced `copy_id` is not
marked dirty, or the fetch would push the server's own data straight back.

**Rooms you can look at in a browser** (server/console, plan 5 #48) render a
published layout as inline SVG — shelf lines and one rectangle per book, pan and
zoom, hover for a title. No rendering dependency: a room is rectangles, and the
CSP forbids a CDN anyway.

The redaction is the point, and it is **structural**. The document is the same
bytes for every viewer and carries no titles; who may see which title is resolved
by a *separate* request (`/api/layouts/{id}/books`) filtered by the same access
predicate as `/api/books`. A spine with no entry there is drawn blank, and the
page says how many are blank and why. There is no filtering step anyone can
forget, because there was never anything to filter.

Public room links reuse `share_link` — `kind` now says `book` or `layout`, with a
CHECK that exactly one target is set — so expiry and revocation are the machinery
that already exists rather than a second kind of link with its own lifetime rules
to get wrong. Two deliberate choices: a room link **never consumes a use** (there
is nothing to download), and naming the books is an explicit **per-link**
`show_books` flag, off by default. The plan proposed inferring it from the owner
having tagged the room's books, but tagging books to share with a named member
must not silently publish their titles to anyone holding a URL; when the flag is
on, the titles shown are still exactly the room's `Room: <name>` tag.

**Reading in the browser** (server + console, plan 5 #33) makes a machine
without Vellum installed useful, and turns a share link from "here's a 40 MB
download" into "here's the chapter". One page serves both cases —
`/read/<book id>` signed in, `/r/<token>` for a link — and it works out which
from its own path.

**EPUB is rendered server-side into sanitised HTML.** The sanitiser is an
**allowlist, not a blocklist**: with a share link, markup somebody else uploaded
renders in your browser, and a blocklist is a list you get wrong once. Only known
elements survive, each with a known attribute set, so `on*` handlers,
`javascript:`/`data:` URLs and `<script>`/`<iframe>` bodies are gone before the
page ever sees them — the CSP forbids inline script as well, but a page that
depends on its CSP alone is one header away from being wrong. External `<img>`s
are dropped so opening a book can't phone home; the book's own images are served
out of its zip **only if they sniff as images**, and external links get
`noopener`.

**PDF is served as page images** through the existing sandboxed renderer,
generalised from "first page" to any page and cached under `pages/<file id>/`.
That was the plan's recommendation over vendoring ~1 MB of pdf.js, and it means
the reader needs no book-format code in the browser at all.

**Reading never consumes a share link.** `max_uses` counts *downloads* — the
one-time link exists so a file can be handed over once — so burning a use on a
page turn would destroy the link the moment someone opened the book. The public
landing page therefore offers "Read it here" *before* "Download", and a public
reader is told plainly that the file isn't theirs to take. Position is kept in
`localStorage` per browser and never touches #5's cross-device channel: a skim in
a browser must not overwrite where you actually are on your own devices.

**The console stopped loading the library** (console + server, plan 5 #35).
Search, sort and the tag/missing filters are now **query params the server
answers** — `?q=&sort=&dir=&tag=&missing=` on the paged `/api/books` — rather
than a filter run in the browser over whatever pages happened to be loaded. That
fixes a subtler bug than the DOM size: "no matches" used to mean "no matches in
the pages loaded so far", which is a different and much less useful statement.
Sort keys and directions are a **closed set** (they go straight into an ORDER BY),
every ordering ends in `b.id` so paging is stable, and nullable keys sort their
NULLs last in both directions — an unknown year is not year zero. The filters
apply only to the paged path: a delta pull must never be narrowed, or a client
loses rows forever as its cursor moves past them.

Three smaller things ride along. **Saved views** name a search + filters + sort +
columns and live in `localStorage`, like the density toggle — a browser
preference, not something to give a schema and a sync story. **Bulk metadata
fetch** got a cancel and per-item failures, because "3 failed" without naming
them is unactionable and a long run you cannot stop is one you learn not to
start; the cancel is checked *between* books, so it never leaves a half-applied
update. And the console's bearer token moved to `sessionStorage`, so a token
stolen through an XSS dies with the tab — defence in depth, not a fix for a known
hole.

The **activity log** (`VELLUM_AUDIT=1`) answers "who deleted that book?". A row
per mutation with actor, action, target and a short label — never a payload, or
the log becomes a second copy of the library with different access control. The
actor's email is denormalised so a row stays readable after the account is
deleted, which is exactly when you want to read it; it is master-only, keyset-
paged (an offset would skip rows as the trim runs underneath a reader), bounded
at 50,000 rows, and every write is best-effort: losing an audit row is small,
failing a user's delete because its log entry couldn't be written is not.

**OPDS grew a shape** (server, plan 5 #34). `/opds` was a flat acquisition feed,
which is unusable on e-ink past a few hundred books — the device downloads and
re-renders the whole thing to scroll. It is now a **navigation** feed (Recently
added / All / By author / By genre / By tag), every acquisition feed is **paged**
with `first`/`previous`/`next`/`last` and OpenSearch counts, and there is an
OpenSearch descriptor at `/opds/search.xml` so clients get a search box at all.
The old flat feed lives on as `/opds/all`, one hop from where it was, so an
existing bookmark still finds everything.

Three details. Feeds carry an **ETag** computed per *caller* from the count and
newest `updated_at` they can see — per-user because a share granted to one
account must not be served from another's cached feed — so an e-reader polling
hourly costs one aggregate query. `/opds/search` unions metadata matching with
**#32's content index** when the server has one, because an e-reader has one
search box and a reader who remembers a phrase shouldn't have to know which index
answers. And `/opds/v2` serves the same root as OPDS 2.0 JSON: the same
aggregation, a different serialisation, for newer clients.

**Content search** (server + app, plan 5 #32) is the one capability that is
genuinely better connected: indexing gigabytes of PDFs is not something a phone
should do, which makes this the strongest argument for running a server at all.
An opt-in `VELLUM_INDEX_TEXT=1` turns on a `book_text` + `book_text_fts` pair,
`GET /api/search` returns highlighted snippets with a book id and a page, and the
app's shelf search grows an **"In book contents"** tab — revealed by the
capability handshake, never by probing — whose hits open the reader *at that
page* without disturbing the saved position. Local search stays the default, so
offline the feature degrades to nothing rather than to an error.

Four decisions carry it. **The queue is the table**: a `book_text` row with
`status='pending'` *is* the work item, so a server killed mid-extraction resumes
exactly where it stopped and `reindex` is one UPDATE. **One sandbox, not two**:
PDF text tries pure-Rust `lopdf` first and falls back to `pdftotext`/`mutool`
through the *same* hardened shell-out as the cover renderer (L6) — a second,
weaker path would undo that hardening for exactly the files most likely to be
hostile. **Hits are RBAC-filtered by the same predicate as `/api/books`**, since
leaking the contents of a book someone cannot see exists is the worst failure
this feature could have. And **user text never reaches `MATCH` raw**: every run
of word characters becomes one quoted term, ANDed, with a prefix `*` on the last
— otherwise `foo AND` is a syntax error and `OR`/`NEAR` mean things nobody typed.

An EPUB's `page` is its **spine position**, not a page number: a reflowable book
has no pages, and claiming one would be a lie the reader can't act on. A scanned
PDF records `no_text`, which is a real outcome — there is no OCR, deliberately.

**Backups that can be trusted** (app, plan 5 #13). An archive now carries a
`manifest.json` with the drift schema version, counts, and a **SHA-256 per
entry**, and *Verify a backup* re-hashes everything without restoring — the only
way to learn a backup is bad before the moment you need it. (The manifest records
the schema version rather than an app version: that is the number which decides
whether a restored database opens at all, and it needs no extra platform plugin
to read.) Archives written before this verify as *readable but unchecked* rather
than being reported as fine.

**Scheduled backups run at app start**, not on a timer: a desktop app that is
open is one being used, and "back up if the last one is older than the interval"
needs no background service or new platform permission. Rotation keeps N and
deletes only files matching the `vellum-backup-<stamp>.zip` name it writes, sorted
**by name rather than mtime** — copying a backup folder to another drive rewrites
mtimes, and "keep 5" must never become "delete your other files". A failed run
leaves the schedule due.

**Encryption is optional and off by default.** A plain `.zip` opens in anything,
forever, with no software of ours, and that inspectability is worth keeping as the
default. When you do ask for it, the archive is sealed with AES-256-GCM under an
Argon2id-derived key, **chunked** at 1 MiB with a per-chunk nonce and MAC — a
single-message encryption would need the whole (possibly multi-gigabyte) library
in memory. Each chunk authenticates `header ‖ counter ‖ isLast`, so reordering,
splicing between backups and truncation are all detected rather than decrypting
into a shorter valid-looking archive. Nothing about the passphrase is stored, the
UI says so bluntly, and *scheduled* backups are always plain: encrypting them
unattended would mean storing the passphrase, which is the same as not encrypting
them.

**Finding a book, tidying a shelf, printing labels** (app, plan 5 #28) turns the
physical view from a map into a map with a "you are here". *Find my copy* on a
book resolves book → copy → placement → environment, opens that room, points the
camera at the book and pulses it once; with several copies placed it **asks
which**, naming the room and shelf, because a title in two rooms is exactly when
guessing is wrong. A search field in the room **dims** what doesn't match rather
than hiding it — a room with holes stops being a picture of your shelves.

*Tidy this shelf* re-packs the books resting on a shelf by author, title or
series, flush from its left end. The ordering falls through to title and then
placement id so a tidy is deterministic (a shelf that reshuffles itself on every
press looks broken), missing values sort **last**, and books wider than the shelf
overflow rather than being dropped — the existing gravity pass cleans up after.

Labels print as **HTML, not PDF**: the browser's print dialog already knows about
paper sizes, margins and previews, and a PDF generator would mean a layout engine
of our own. Each label carries the room, the shelf, a book count, and a QR of
`vellum://shelf/<id>`. That link is read by **Vellum's own scanner**, not an OS
URL handler — registering a scheme means manifest work on four platforms and lets
any web page poke it, while the app already has a camera page from #16 and you
were going to open the app anyway. The link is printed as text too, so the
desktop (no camera) can paste it. *Save a picture of this room* captures exactly
the framing on screen, because framing is what the pan and zoom are for.

**Condition photos** (app, plan 5 #51) settle the other half of a loan: what the
book looked like when it left. An app-local `copy_photos` table stores a caption,
a timestamp and a *path* — the bytes live under `photos/` in the data dir and ride
backups, which are the only copy of them that ever leaves the device. Lending
offers "photograph its condition first" as an opt-in tick per loan (it matters for
a stranger, it is noise for a flatmate), and marking a return offers the shot again
from the snackbar, where it costs nothing to ignore.

Photos are **app-local permanently**, not "for now" like #18's judgements: copies
and loans sync, but photo blobs are the exact weight that channel must not
silently acquire — one photo outweighs the whole catalogue payload of a mid-sized
library. Deleting a copy therefore reads its photo rows *before* the transaction
that clears them and unlinks the blobs after it commits; a sweep that ran
afterwards would find no rows and leak every file.

**A copy's location is derived, not stored** (app, plan 5 #50).
`physical_copy.location` is free text typed once when the copy was added, while a
*placement* records where the book was last dragged to; they diverge the first time
a shelf is rearranged, and the detail page used to show the stale string
confidently. Now a placed copy displays its **room plus the shelf it stands on**,
computed from the placement (nearest labelled shelf below it that it horizontally
overlaps), and the free text is relabelled as a *note* for unplaced copies. The
derived string is never written back into the column — derived data stays derived,
the same rule spine colours follow.

**Series and volume tracking** (both, plan 5 #17) is the one Phase-4 addition that
**syncs**: a series is catalogue metadata the online sources supply, and a library
of trilogies sorted by title puts *The Two Towers* nowhere near *The Fellowship of
the Ring*. A `series` table plus `book.series_id` / `book.series_index` exist on
both sides (`server/migrations/0012`, drift v17, `schema_parity.rs`). Two choices
worth knowing: membership crosses the wire **by name**, so two devices that each
invented an id for "Dune" still converge (the rule authors and genres already
follow), and `series_index` is **REAL** so a novella can be 1.5 instead of lying
about where it sits.

`ShelfSort.series` orders by series name, then volume, then title, with
series-less books last. The detail page shows the book's place in its series and,
more usefully, the **gaps** — whole numbers missing between the volumes you own.
Only whole numbers are ever claimed missing: a fractional 2.5 is usually a novella
nobody intended to own, and inventing gaps would make the feature cry wolf.

**Reading insights** (app, plan 5 #19) exist because the app was already writing
a position on every page turn and throwing all of it away. A `reading_sessions`
table keeps the shape of it — **one row per sitting**, not per page turn — and
*Reading insights* in the drawer draws streaks, pages a day, a 12-week heat map,
books finished per month and the genre split of what you finish, with `CustomPaint`
rather than a charting dependency.

Two details do the work. **Coalescing:** reopening a book within two minutes
extends the previous session instead of starting a new one, so a phone call
doesn't turn one evening into six sessions and make every average measure
interruptions. **Local-only, permanently:** this is behavioural data, it has no
sync channel and should never get one, it rides backups because those snapshot the
database file, and *Clear reading history* really deletes it.

**Reading status, ratings and dates** (app, plan 5 #18) add `status`
(`unread`/`reading`/`finished`/`abandoned`/`reference`), `rating` (1–5),
`startedAt`/`finishedAt` and `readCount` to the book row. They are **app-local for
now** and written to be promotable — all additive, nullable-or-defaulted — because
they are *judgements* rather than reading mechanics and users will eventually want
them on every device; promoting them is one server migration plus a parity update,
with no data conversion.

The rule is that **the app never decides for you**. Exactly one transition is
automatic: opening an unread book makes it `reading` (unambiguous and reversible).
Reaching the end *offers* "Mark as finished" instead of assuming it — someone who
skims the last chapter has not finished the book. Finishing stamps `finishedAt` and
counts a re-read; moving back out of `finished` clears the date so the two can't
disagree. Status is a facet next to the genre filter (both are predicates on the
same single shelf query), and neither status nor rating touches the sync clock.

**Reader comfort** (app, plan 5 #23) is one persisted `ReaderSettings` shared by
both readers, because theme, measure and distraction-free mode mean the same thing
in either. The format-specific halves differ for a reason: an EPUB is reflowable,
so it gets typeface, size, line spacing and line length; a PDF is a rendered page,
so its only levers are fit (width/page) and **night mode**, applied as a colour
matrix that inverts luminance while pulling toward a warm near-black — a naive
`1 - x` invert turns photographs into negatives. The PDF reader also gains in-book
text search with match navigation and a go-to-page field. These controls set the
*book's* type; the surrounding UI keeps following the system text scale.

EPUB position is stored as one **global fraction** across the book plus the 1-based
chapter, and reopening splits it back into "chapter N, this far down" — closing
plan 4 §E15's in-chapter scroll restore. The chapter index is authoritative if the
two ever disagree.

**Annotations** (app, plan 5 #22) are bookmarks, highlights and notes, all in one
app-local `annotations` table discriminated by `kind` — they differ only in which
fields they carry. Personal marginalia, so they stay on the device like
`readerNotes`; if they ever sync they get their own table and endpoint, never a
column on the book row.

Position is stored as **versioned JSON** (`annotation_locator.dart`) because the
two formats are not equally trustworthy. A PDF locator is objective: a page plus a
character range in the *PDF's own* extracted text, via `pdfrx`. An EPUB locator is
not — its offsets index this app's plain-text extraction of a chapter
(`EpubChapter.plainText`), so they are only as stable as that function, which is
exactly what the version number exists to migrate. Every text annotation therefore
also stores the quoted passage, and re-finding one is **quote-first**: the stored
offsets are used only if the text there still matches, otherwise the nearest
occurrence of the quote wins. A highlight that moves slightly beats one that
points confidently at the wrong sentence. Annotations can be **exported as
Markdown** per book or library-wide — a highlight nobody can get out of the app is
a highlight held hostage.

**App-local-only columns on `book`** (deliberately *not* synced): reading state
(progress/page/last-read), **reader notes**, and **`source_metadata`** (a JSON
snapshot of the online-library data a book was imported with, behind *revert to
library defaults*). See **Adding & editing books**. (Historical note: an early
migration, `0002`, added the three reading-state columns to the *server* table
by mistake; migration `0006` drops them again, since reading state must stay on
the device. Reader notes and `source_metadata` were never on the server.)

**Optional cross-device reading position.** The rule above stands — the `book`
row still carries no reading state either way — but a reader who owns the same
book on phone and desktop wants "resume where I left off" to follow them, so
there is now a *separate* channel for exactly that (plan 5 #5). Its shape is
what keeps it from re-opening the settled question:

- Its own server table, `reading_progress` (migration `0011`), keyed
  `(book_id, user_id, device_id)`. Per-device rows mean **no conflict
  resolution at all**: a device only ever writes its own row and reads the
  others, so LWW never enters the picture. `user_id` comes from the token, so
  one user's reading is invisible to everyone else on a shared library.
- **Opt-in, default off** (Preferences → *Sync reading position*), because it
  publishes reading behaviour rather than catalogue data. Switching it on
  queues the positions already on the device; switching it off deletes this
  device's rows from the server and clears the local cache.
- The app **offers**, never adopts: opening a book whose other device is
  further ahead asks "you were on page 214 on desktop — go there?". A silent
  merge would be worse than the prompt. The offer only appears when the units
  match (PDF pages vs EPUB chapters), since converting between them would land
  the reader somewhere plausible and wrong.
- Other devices' rows are cached in the app-local `remote_reading_positions`
  table so the prompt works offline. `readerNotes` and `sourceMetadata` get no
  channel, opt-in or otherwise.

The two schemas are kept in sync by hand, so `server/tests/schema_parity.rs`
pins the column list of every synced table (`book`, `author`, `book_author`,
`genre`, `book_genre`, `book_file`, `shelf`, `shelf_book`, `physical_copy`,
`loan`) and fails if the
server migrations drift from it — a prompt to update
`app/lib/data/database.dart` too.

**Deletion tombstones carry a `kind`** (`deletion.kind` server-side,
`local_deletions.kind` app-side; both default `'book'`, and now also carry
`'shelf'`, `'copy'`, and `'loan'`): one shared mechanism for every synced
entity's deletes rather than a table per entity. Adding `kind` was
additive — an app predating it only ever reads `book_id`/`deleted_at` and
looks the id up in its own `books` table, so a non-book tombstone (e.g. a
deleted shelf or copy) is a harmless no-op there.

**App-local-only tables** for the physical bookshelf layouts (also never
synced — a per-device arrangement of a real room, all lengths in **metres**):

- **physical_environment** — a room/"library" (name, sort order).
- **physical_shelf** — a flat resting surface as two points `(x1,y1)-(x2,y2)`
  in an environment; horizontal in practice, but two points allow angling later.
- **book_placement** — one physical copy placed at `(x, y)` (bottom-left) with a
  `rotation` (0 = spine up, 90 = lying flat) and optional per-placement
  `width`/`height` overrides. It references a **physical_copy**, so dropping a
  title in creates a copy and the same title can be placed several times. See
  **Physical bookshelf layouts**.

## Spine rendering

No API on the internet serves spine images, so Vellum **generates** spines:
pick spine colours, render the title in a vertical typeface, and vary spine
height/thickness by page count. Uniform, good-looking shelves for every book.
The generated style is stored per-book (JSON) so users can tweak it later.

> **Implementation note.** A cover-less book gets its colour from a
> **title-hash palette** (`spine_style.dart`). A book *with* cover art draws
> its spine from the cover image itself (a shaded vertical slice) — or, behind
> the **spine artwork preference** (Preferences → shelf, spine mode only), as a
> generated spine in the cover's **dominant colour**, extracted once per cover
> (`cover_color.dart`, saturation-weighted histogram) and cached in the
> spine-style JSON; existing covers are backfilled at startup. The extracted
> colour is cosmetic and device-derivable, so it never bumps the sync clock.

## Physical bookshelf layouts

The **Physical** tab (a bottom-nav destination on the home page) manages
to-scale arrangements of physical books, as a lightweight "Tetris" — an idea
that stays intentionally simple and data-driven so it's easy to extend.

- **Model.** An *environment* (room) holds *shelves* and *placements*; see
  **Data model**. Everything is metric; the view is a **front elevation** (X
  right, Y up).
- **Sizing.** A book's spine thickness comes from its page count via a **size
  preset** (mm-per-page + optional binding allowance), calibrated against a real
  book: a 367-page B5 softcover is 21 mm → **17.48 pages/mm** (~0.057 mm/page,
  no cover base). Presets (mass-market, trade, A5, B5, hardcover, A4) also set
  the trim **height**; both dimensions fall back to that default curve and are
  **overridable** per placement (the `format` key + width/height overrides live
  on `book_placement`). Width is computed **live** from `book.pageCount`, so
  editing the page count (in the detail sheet) updates every un-overridden
  placement immediately; a book with no page count uses a fixed default until
  one is set. See `physical_metrics.dart`.
- **Look.** Books render with the **same `SpineFace`** the digital shelf uses —
  a slice of the cover image if there is one, else the generated spine — so a
  book looks the same in both views. A flat (rotated) book is that spine turned
  a quarter-turn.
- **Interaction (no physics engine).** Pinch / scroll to zoom, drag empty space
  to pan. Drag a book and on release it **settles**: its bottom drops to the
  highest shelf or book-top beneath it (within its horizontal span), then it's
  nudged sideways out of any overlap — a simple packing heuristic, not a
  rigid-body sim. Removing or moving a book runs a **gravity pass** so any book
  left unsupported **falls** onto the next surface below (stacks collapse).
  Releasing a book in empty space with **no shelf beneath it takes it off the
  shelf** (removes the placement). Tap to select (toolbar:
  **open** the book to read it, rotate 90°, resize, remove); `Esc` deselects.
  **Long-press (touch) or right-click (desktop)** opens a context menu with the
  same actions plus *reset size*. **Shelves** can be dragged to move, and
  right-click/long-press to edit (endpoints/label) or delete. A help button and
  a persistent tip surface these gestures.
- **Reference, not inventory.** A placement is just “this copy sits here” for
  visualisation; it isn't concrete copy-tracking. Dropping a title in mints a
  fresh `physical_copy`, and the same title can be placed several times.
- **Local-only layout, synced copies.** The environment/shelf/placement
  tables never touch the server — a per-device view of a real room. The
  `physical_copy` row a placement mints is a real physical object, though,
  so (plan 5 #4) it syncs like any other copy; only its throwaway *placement*
  stays local. Removing a placement deletes its copy through
  `PhysicalService.deletePhysicalCopy` — the one path that also clears any
  loan history and records a tombstone, rather than `layout_repository.dart`
  deleting the row itself. The canvas and its gesture/settle logic live in
  `lib/physical/`.

## Metadata fetching

On add: query Open Library first (free, no key), fall back to Google Books.
Match by ISBN when available (Android gets barcode scanning), otherwise
title/author search with a user-facing "pick the right edition" step. Both the
app and the server run this search (the server exposes it at
`GET /api/metadata/search` for its console); a search that finds nothing lets
you create a custom book instead.

Metadata is also filled in **automatically**, without picking an edition:

- **From the file** — uploading a PDF reads its page tree (via `lopdf`, off the
  async runtime) and sets `page_count` — the digital copy is ground truth, so it
  overrides any online guess. Its **first page is rendered as the cover** (see
  below) and takes precedence over an online cover — the book's own art beats a
  generic thumbnail. The file *name* is parsed for the common
  `Author(s) - Title-Publisher (Year)` download convention: authors (when the
  book has none), publisher, and year fill the empty fields, and the title is
  tidied while it's still the raw file name — so the online lookup below then
  searches a clean title instead of the whole file name (which is why
  year/author previously came back empty).
- **From the title** — `POST /api/books/{id}/enrich` searches by the book's title
  (plus its first author, if any) and fills only the *empty* fields —
  author, year, publisher, ISBN, pages, description, cover, genres — never
  overwriting what the user set, and short-circuiting the network call when
  nothing is missing. For the cover it **prefers the PDF's first page** and only
  fetches an online cover when the book has no PDF to render. The console calls it
  after *Create book* and after a file upload, and offers it in bulk (*Fetch
  metadata*) and from the detail view. A miss leaves the book untouched.
- **Proposing before saving** — `POST /api/metadata/analyze` runs the file-name
  parse and one online search and returns the *merged* proposal without saving,
  so the console's Add-book form can show it for review/editing. It's the only
  metadata call that creates nothing.

## Adding & editing books

**Above the shelf** sits a compact strip (plan 5 #25): *Continue reading* (up to
three, most recently read first, with progress) and *Recently added*. It is
derived from the same `LibraryView` the shelf itself draws, never a second set of
queries, so it narrows with the active search and genre filter instead of
contradicting the list underneath, and collapses to nothing when there is nothing
to show. A book at 98% or more counts as finished and drops off.

**First run** (plan 5 #41) opens a three-card sheet — get your books in (folder /
scan / one at a time), connect a server (optional, skippable forever), set up a
room — which is dismissible in every direction and marked seen the moment it
opens, so swiping it away is never punished by it returning. Every empty state
(shelf, no-search-match, physical tab, loans) carries one line of what-to-do-next
copy **and** a primary action.

**Finding and merging duplicates** (app, plan 5 #21b) exists because a library
grown by bulk import will contain them. *Find duplicates* in the drawer compares
three ways, and the ordering is the safety property: an identical **file hash** or
**ISBN** is certain, while a **fuzzy title** match (normalised, token-sorted,
within a small edit distance, and only when the authors agree) is offered as a
suggestion. Merging is never automatic — it opens a side-by-side dialog where the
user picks which book survives and, per disagreeing field, which value to keep.
The merge itself moves files, physical copies (with their placements and loan
history), shelf memberships, authors and genres onto the survivor in one
transaction, keeps the further-along reading position, and **tombstones** the
loser so the merge propagates instead of the duplicate returning on the next
pull. What moved is logged and shown, because the operation can't be undone.

**Books opened or shared from another app** (Android, plan 5 #20) arrive through
`VIEW` / `SEND` / `SEND_MULTIPLE` intent filters. A small `MethodChannel` in
`MainActivity.kt` does the one thing that has to happen natively: it **copies each
`content://` stream into the app's cache before handing Dart a path**, because
such a URI is only readable while the granting intent lives. One file opens the
add-book form pre-filled; several go to the import wizard's review list. Both
cold start (the share launched the app) and warm resume (it was already running)
are handled.

**Scanning ISBN barcodes** (app, plan 5 #16) is the fast path for physical books:
the *Scan* button on the shelf opens a live camera that keeps scanning — a shelf
is dozens of books, so each accepted barcode adds a book and slides onto a strip
with an **Undo** rather than interrupting with a dialog. Barcodes are validated
before any lookup (EAN-13 check digit, a 978/979 Bookland prefix, `979-0` sheet
music excluded), because a camera pointed at a room finds plenty of non-book
EAN-13s and a "not found" for each would feel broken. A book already in the
library is **flagged, not blocked** (owning two copies is legitimate), reusing the
folder importer's duplicate classifier. No camera, or a denied permission, leaves
a manual ISBN field driving exactly the same path — which is also how desktop
uses it.

**Bulk folder import** (app, plan 5 #15) is the on-ramp for someone arriving with
an existing folder of downloads: *Import a folder* in the drawer recurses for
PDFs and EPUBs and then shows a **dry run** — one row per file with the title and
author parsed from its name, a status (**new** · **already here** · **possible
duplicate** · **unreadable**), and an edit button. Nothing is written until the
user presses Import.

- The file-name parser (`app/lib/import/filename_metadata.dart`) is a port of the
  server's `metadata::parse_filename`, rule for rule, so the same folder imported
  in the app and through the console produces the same books. It can't call the
  server's copy: import has to work with no server at all.
- Duplicate detection runs during the scan, which is why the scan hashes every
  file: an identical **sha256** is certain and decides on its own; a matching
  ISBN or title+author only *suggests* — the row is deselected but visible and
  re-selectable. A false "duplicate" would silently lose a book, so nothing is
  ever skipped without being shown.
- Online lookups are a **separate, resumable pass** after the import, one request
  at a time, and default off above ~50 books. So importing 500 books doesn't
  depend on 500 network calls, and a cancelled or offline enrichment simply
  continues next time (it skips books that already have a description).
- Each file goes through the atomic import path (#14) and each row is
  independent: one failure is reported and the run continues.
- A folder can optionally be **watched**: on launch (only — no filesystem watcher,
  no background service) Vellum offers to review new files found in it.

The console's Add-book dialog is a small **editable metadata form** (title,
authors, year, pages, publisher, ISBN, description):

- **Attach a file** (drag-and-drop or picker) and the form **auto-fills** from
  `analyze` — the file name parsed and merged with one online lookup.
- **Look up online** searches by whatever's typed and lists editions to pick
  from, filling the form from the chosen one.
- **Create book** posts the (possibly edited) form to `from-search`, so authors,
  genres and a cover are stored alongside the plain fields; the attached file is
  uploaded straight after, which sets the real page count and renders the cover
  from the PDF's first page (overriding the online one). Typing just a title
  still works — everything else fills in.

Uploads are validated by their **magic bytes** — a real `%PDF`, an EPUB zip, or
an image for covers — not just the file extension. This is enforced on the
**server** (`blobs.rs` sniffs the leading bytes and rejects a mismatch: book
files must be PDF/EPUB, covers must be JPEG/PNG/GIF/WebP, and a cover's stored
extension comes from the sniffed type), not only in the console/app clients, so
the API can't be tricked by a renamed file.

Once a book exists you can edit its **title, subtitle, year, and description**,
and change its **cover**. On both the app and the console the cover shows and is
**clickable** — hover reveals a *Change cover* affordance (a cover-less book is
a clickable placeholder); clicking picks a new image. The cover can also come
from the **first (full) page of an attached PDF**, rendered with `pdfrx` — done
automatically whenever a PDF lands on a cover-less book (including books
**pulled from the server**), and available any time from the app's edit sheet.

The server binary links **no** PDF library of its own (that would be at odds with
the single-binary server). Its first-page cover rendering — now the **preferred**
cover source for any book that has a PDF — is instead a best-effort **shell-out**
to whatever PDF CLI the host happens to have — `pdftoppm`, `pdftocairo`,
`mutool`, or `gs` — tried in turn, and simply skipped if none is installed (in
which case the online cover stands). The **app also renders on pull and pushes
back** (higher-fidelity `pdfrx`, and it reaches books the server couldn't
render); the server-side render just means a console-only workflow isn't
cover-less while waiting for an app to sync. (The app pull writing covers back is
one place a pull writes to the server.)

Two things stay **on the device only** and are never synced to a server:

- **Reader notes** — a personal per-book notes field.
- **Revert to library defaults** — books added from an online library keep a
  `source_metadata` snapshot of their original title/year/description/cover, so
  edits can be rolled back to the source. Hand-made custom books have no
  snapshot, so they offer no revert.

## Build order & status

1. ✅ Flutter desktop app: add a book (online search **or** a hand-made custom
   book for PDFs not in any library), edit details/cover, drag-and-drop file
   uploads with format validation, personal reader notes, shelf view.
2. ✅ Shelf UI — generated spines, packing into rows, pull-out open animation,
   spine/cover display toggle, spine-artwork preference (cover slice /
   dominant colour), wallpapers.
3. ✅ Metadata fetch on add — Open Library, falling back to Google Books.
4. ✅ PDF reader (`pdfrx`) with saved reading position. EPUB reader
   (chapter-at-a-time, in-house parser) with resume-by-chapter.
5. ✅ Physical copies: locations + loan tracking (lend / return / history).
6. ⏳ Android build, barcode scanning. **Not started** — desktop polish first.
7. 🚧 Rust server + sync (connected mode), OPDS feed. In place: accounts, RBAC,
   groups, sharing, public links, blob storage, OPDS, and a web admin console,
   with API integration tests. The app logs in and syncs **both ways** —
   metadata, covers, files, and (plan 5 #4) custom shelves, physical copies,
   and loan history — one-tap (pull then push) plus a quiet auto-sync at
   launch, and manages sharing on-device. Sync is **last-write-wins by
   `updated_at`** with **delete tombstones** (below); plan 5 #4's Option A
   is now fully done. Remaining: real-time updates and the Android side.
8. ✅ Backup: export the whole library (database snapshot + covers + files) to
   one `.zip` from Preferences; restore replaces the library and restarts the
   app. The safety net for standalone (serverless) installs.

## Sync roadmap (connected mode)

The connected-mode roadmap below is essentially complete; the app does a
two-way sync of metadata, covers, and files.

**Conflict handling & deletes.** A pull compares each book's server `updated_at`
against the local row and only overwrites when the server copy is strictly
newer (a missing server timestamp falls back to overwriting), so a local edit
isn't clobbered before it's pushed. Reading state, `reader_notes`, and
`source_metadata` are app-local and never bump `updated_at`, so merely reading a
book can't win the next push over a genuine remote edit. A push sends the local
`updated_at`; the server applies it only when strictly newer than the stored one
(and skips a byte-for-byte no-op entirely), so a stale push can't clobber a
newer console edit. Deletes propagate through tombstones: the server keeps a
`deletion` table (exposed at `GET /api/deletions`, cleared on any upsert of that
id) and the app keeps a local `local_deletions` table; a pull applies the
server's tombstones, a push sends the app's. The app-local `local_deletions`
table is **not** part of the server schema.

**Decision: row-level LWW is the final conflict model.** Field-level merge was
considered and rejected (July 2026) as disproportionate for a personal
library: on divergence the server is the ground truth (pull overwrites only
when the server row is strictly newer), and an authorized client push wins
only when its row is strictly newer than the server's. Concurrent edits to
*different fields* of the same book on two devices resolve to the newer whole
row — acceptable at this scale. Remaining polish is live updates
(websocket/long-poll), not merging.

**Syncing is one tap (and automatic).** The server page's primary action is
**Sync** — a pull followed by a push under a single re-entrancy guard — with
the one-directional Pull/Push kept under *Advanced*. The app also runs a
quiet best-effort sync at launch whenever a server is connected: offline is
normal for a local-first app, so failures stay silent (except an expired
session, which drops to the sign-in screen); a snackbar appears only when
something actually changed.

**Delta pull & the clock-skew caveat.** A pull is incremental: it sends the last
**server-issued** cursor (`GET /api/books?cursor=<ts>` returns
`{ server_now, books }`, and `GET /api/deletions?since=<ts>`), so only rows
changed since the previous pull cross the wire. Because the cursor is the
*server's* own clock echoed back, device wall-clock skew no longer affects which
rows a pull selects; the per-row `updated_at` compare stays only as a tiebreaker.
The filter is `>=` (SQLite timestamps are second-resolution, so `>` could skip a
row edited in the cursor's own second) and the small overlap is deduped locally.
One limitation: a book made newly **visible** by a *share* doesn't change its
`updated_at`, so a delta pull wouldn't fetch it — the app therefore clears the
cursor on each login (and disconnect), making the first pull of a session a full
one.

**Batched push.** Push sends metadata for up to 200 dirty books per
`POST /api/books:batch` instead of one `PUT /api/books/{id}` each, so the first
sync of a large library costs a handful of round trips rather than one per book.
The batch is *not* one transaction: each item reports its own outcome
(`updated` / `skipped_older` / `error`) through the same per-book `SyncIssue`
model, so one rejected book can't roll back the rest. It runs only when the
server advertises `batch_push` in `GET /api/capabilities`; a single-book push,
an older server, or a failing batch call all fall back to per-book PUTs, which
the server's unchanged-data guard makes a cheap no-op for anything the batch
already applied. Covers and files still transfer per book.

1. ✅ **Server blob storage** — upload/download endpoints for cover images and
   book files (filesystem-backed, `VELLUM_DATA_DIR`), access-checked like the
   book they belong to.
2. ✅ **App: pull covers & files** — a pull downloads each book's cover *and* its
   digital files (deduped by content hash), so synced books show real art and
   open in the reader. Covers the app derives from a PDF's first page are pushed
   back so the server shows them too.
3. ✅ **App: push** — upload local books (and their covers) to the server via an
   id-preserving `PUT /api/books/{id}` upsert, making the sync two-way.
4. ✅ **App: manage groups & shares** — a Sharing screen over the group, share,
   and public-link endpoints (create a group, add books, share the library /
   a group / a book with a user, mint and revoke public links).
5. ✅ **OPDS feed** — `/opds` serves an OPDS acquisition catalog (HTTP Basic
   auth) so third-party e-readers can browse and download books.
6. ✅ **Web admin console** — server-hosted spreadsheet-like UI at `/` to manage
   books, tags/groups (bulk), deletions, and public links with expiry +
   one-time download; friendly public landing page at `/p/{token}`. Scales with
   search, sort, tag/missing filters, column + density options, inline and bulk
   edits, CSV/JSON export, CSV import, and keyboard nav.

## Repo layout

```
Vellum/
├── DESIGN.md      # this file
├── app/           # Flutter app (desktop + Android)
└── server/        # Rust server (axum + sqlx + SQLite)
```
