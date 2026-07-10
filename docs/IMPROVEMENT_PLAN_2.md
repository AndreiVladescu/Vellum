# Improvement plan 2

Follow-up to [`IMPROVEMENT_PLAN.md`](IMPROVEMENT_PLAN.md) (July 2026 — all 14
tasks landed). This is the next round, from a fresh review of the codebase as it
stands after those fixes. Same ground rules as the first plan:

- Read `CLAUDE.md` and `DESIGN.md` first. Schema changes = drift `schemaVersion`
  bump + drift migration + **new** SQL migration + build_runner rerun + update
  `server/tests/schema_parity.rs` when a synced table changes.
- Reading state, `readerNotes`, `sourceMetadata` stay app-local-only.
- After every task: `cargo test && cargo clippy --all-targets -- -D warnings`
  in `server/`, `flutter analyze && flutter test` in `app/`.
- One cohesive feature per commit, short title, optional succinct bullets,
  no Co-Authored-By.

Items are grouped by theme and ordered by severity within each group.
**§A is correctness — do those first**; the rest can be cherry-picked.

---

## A. Sync correctness & data integrity

### 1. Reading a book can clobber console edits (split the sync clock from local-only writes)

**Problem.** `updatedAt` on the app's `books` row is both the sync
conflict clock *and* bumped by local-only changes:
`saveReadingPosition` (`library_repository.dart:519-528`) sets
`updatedAt: Value(now)` on every page turn. Sequence that loses data:

1. Someone edits a book's metadata in the web console (server `updated_at` = T1).
2. The user merely *reads* that book on the device (local `updatedAt` = T2 > T1).
3. Sync: `pull` skips the book (`!local.isBefore(server)` in
   `sync_service.dart:61`), then `push` unconditionally upserts the stale local
   metadata over the console edit (`books.rs::upsert` always overwrites).

The console edit is gone. Any local-only write (reading state) effectively pins
the row "newest" and turns the next push into an overwrite of remote edits.

**Change.**
- `saveReadingPosition` must **not** touch `updatedAt` (reading state is never
  synced; there is nothing to win a conflict for). Drop the
  `updatedAt: Value(now)` from its companion. Same check for `setReaderNotes`
  (already correct — it doesn't bump) and any future local-only setter.
- Make LWW symmetric on push (defense in depth): `pushBook`
  (`server_client.dart:189`) sends the local row's `updated_at`
  (`"YYYY-MM-DD HH:MM:SS"` UTC, the inverse of `_parseServerTime`); server
  `BookInput` gains `updated_at: Option<String>`, and `upsert`'s UPDATE branch
  becomes conditional: only apply (and only bump `updated_at`) when the incoming
  timestamp is **strictly newer** than the stored one, else return the current
  row untouched. Missing/unparseable incoming timestamp keeps today's
  always-overwrite behavior (older app clients).
- Tests: app — page-turn then pull applies a newer server edit; server
  (`tests/api.rs`) — upsert with older `updated_at` leaves the row unchanged.

**Commit:** `Sync: keep reading state off the conflict clock, guard push by timestamp`

### 2. Deleting a placed book throws an FK violation

**Problem.** `book_placements.copy_id` references `physical_copies.id`
(`database.dart:173`, no ON DELETE), and `PRAGMA foreign_keys = ON` is set in
`beforeOpen`. `LibraryRepository.deleteBook` (`library_repository.dart:668`)
deletes `physical_copies WHERE book_id = ?` but never deletes the placements
pointing at those copies → deleting any book that has been placed in a physical
environment aborts the transaction with a FOREIGN KEY error. Pull-driven deletes
(`SyncService.pull` → `deleteBook`) hit the same wall, so one placed book can
wedge the delete-propagation phase of every sync.

**Change.** Inside `deleteBook`'s transaction, before the copies delete:

```dart
await db.customStatement(
  'DELETE FROM book_placements WHERE copy_id IN '
  '(SELECT id FROM physical_copies WHERE book_id = ?)',
  [book.id],
);
```

Test: place a book via `placeBook`, `deleteBook` it, assert books, copies, and
placements are all gone (extend `app/test/sync_service_test.dart` or a new
repository test — the in-memory `VellumDatabase` + `forTesting` repo already
support this).

**Commit:** `App: delete placements when deleting a placed book`

### 3. Sync authors and genres (they are silently not synced at all)

**Problem.** DESIGN.md says sync covers "metadata", and
`schema_parity.rs` pins `author`/`book_author`/`genre`/`book_genre` as synced
tables — but no author or genre ever crosses the wire. `pushBook`
(`server_client.dart:189`) has no authors/genres; server `BookInput`
(`books.rs:31`) has none; `SyncService.pull` ignores the `authors[]` array that
`GET /api/books` already returns. A book pushed from the app appears
author-less in the console/OPDS; a pulled book has no authors locally.

**Change.**
- Server: `BookInput` gains `authors: Option<Vec<String>>` and
  `genres: Option<Vec<String>>`. In `upsert` (both branches), when present,
  replace the joins inside one transaction: get-or-create by unique `name`
  (`INSERT INTO author (id, name) VALUES (?, ?) ON CONFLICT(name) DO NOTHING`
  then `SELECT id`), `DELETE FROM book_author WHERE book_id = ?`, re-insert with
  `position` = list order. `None` (old clients) leaves joins untouched.
  Also add `genres[]` to `books::list`'s `BookListItem` (same grouped-scan
  pattern already used for `authors`, `books.rs:100-131`).
- App push: load the book's authors/genres (`detailsFor`) and include them.
- App pull: when the metadata upsert actually applies (server newer), call
  `repository.setAuthors(b.id, b.authors)` and a new symmetric
  `setGenres` (mirror of `setAuthors`, `library_repository.dart:162`).
  `ServerBook` gains `authors`/`genres` parsed from the list JSON.
- Tests: server round-trip via upsert; app pull maps authors into the local DB.

**Commit:** `Sync: carry authors and genres both ways`

### 4. Push everything every time → O(n) server writes and timestamp churn

**Problem.** `SyncService.push` upserts **every** local book and re-uploads
**every** cover on every push (`sync_service.dart:196-243`). Each upsert bumps
the server's `updated_at` (`books.rs:209`), so after any push the *entire*
server library is "strictly newer" and the next pull rewrites every local row
(and re-adopts timestamps). Every sync cycle is O(library) in both directions,
plus O(total cover bytes) of blob writes; the LWW guard degrades into
"whoever pushed last owns everything".

**Change** (two independent halves):

1. **App dirty tracking.** Drift schema v7: `Books` gains
   `BoolColumn get needsPush => boolean().withDefault(const Constant(true))();`
   (default true so existing rows push once). This column is app-local
   bookkeeping like `local_deletions` — do **not** mirror it on the server.
   Set `needsPush = true` in every synced-metadata mutation
   (`updateBookDetails`, `setAuthors`, `setCoverBytes`, `addFromSearch`,
   `createCustomBook`, `attachFile`); leave it alone in local-only setters.
   `push` selects `WHERE needsPush = 1`, clears the flag per book after a
   successful upsert, and `pull` clears it when adopting a server-newer row.
2. **Server no-op guard.** In `upsert`'s UPDATE branch, skip the write (and the
   `updated_at` bump) when every incoming field equals the stored row —
   fetch the row you already look up for the owner check and compare in Rust.
   This keeps even a redundant push from invalidating everyone's pull state.

Covers: only upload when the book is dirty **and** (the server row's
`cover_path` is empty, or the local cover changed since last push — fold cover
changes into `needsPush` via `setCoverBytes`). Item 12 (ETag round-trip) covers
the pull direction.

**Commit:** `Sync: push only dirty books, skip no-op upserts server-side`

### 5. Make server delete + tombstone atomic; clear tombstones on update too

**Problem.** `books.rs::delete` (`books.rs:361-408`) runs owner check, path
collection, tombstone INSERT, and book DELETE as four separate statements on
the pool. A crash (or a concurrent re-create) between tombstone and delete
leaves both a live book *and* a tombstone: clients then delete the book locally
on pull, re-download it in the same pull's book loop, and re-fetch all its
blobs. Also `upsert` clears the tombstone only in its INSERT branch
(`books.rs:246`); the UPDATE branch of a revived id leaves the tombstone alive.

**Change.** Wrap owner check → path SELECTs → tombstone INSERT → book DELETE in
one `state.db.begin()` transaction (blob `remove_file`s stay after commit,
best-effort as today). Move the `DELETE FROM deletion WHERE book_id = ?` out of
the INSERT-only branch so both upsert branches clear it. Test: simulate the
stale state by inserting a tombstone for a live book, upsert it, assert the
tombstone is gone.

**Commit:** `Server: atomic delete+tombstone, clear tombstone on any upsert`

### 6. Delta pull with a server-issued cursor (also kills the clock-skew caveat)

**Problem.** Every pull fetches the whole library (`GET /api/books`), all
deletions, and does a per-book `listFiles` round-trip (see item 15). DESIGN.md
documents the wall-clock-skew limitation of comparing device time to server
time. Both are solved by the same mechanism.

**Change.**
- Server: `GET /api/books?updated_since=<YYYY-MM-DD HH:MM:SS>` filters
  `WHERE b.updated_at > ?`; `GET /api/deletions?since=<ts>` filters
  `deleted_at > ?`. Both responses gain a `server_now` field (SQLite
  `datetime('now')`) — for the books list this means wrapping the bare array in
  `{ "server_now": …, "books": […] }` under a new versioned path or an
  `Accept`-style query flag, keeping the bare-array shape for old clients.
- App: store the last `server_now` per connection in `SharedPreferences`
  (`sync.cursor.<baseUrl>`), send it verbatim next pull. Because the cursor is
  the **server's** clock echoed back, device skew stops mattering for pull
  selection; the per-row LWW compare stays as a tiebreaker. First pull (no
  cursor) behaves exactly like today. A push updates the cursor from the last
  upsert response.
- Update DESIGN.md's skew caveat.

**Commit:** `Sync: delta pull with a server-issued cursor`

### 7. Sync report + progress instead of swallowed errors, and a re-entrancy guard

**Problem.** `SyncService` returns bare counts and swallows every per-book
failure with `catch (_) {}` (`sync_service.dart:102,138,159,167,189,239`) — a
library that half-syncs looks identical to one that fully synced, and there is
nothing to debug from. Nothing stops two concurrent `pull()`s if the user
double-taps the sync button.

**Change.** Introduce:

```dart
class SyncReport {
  final int pulled, pushed, deletedLocally, deletedRemotely;
  final List<SyncIssue> issues; // (bookId, title, stage, message)
}
```

Every current `catch (_)` records a `SyncIssue` (stage = 'cover', 'file',
'push', …) instead of dropping it. Add an optional
`void Function(int done, int total, String phase)` progress callback threaded
from `server_page.dart` into a `LinearProgressIndicator` + a post-sync snackbar
("Synced 214 books, 3 issues" → expandable issue list). Guard re-entrancy with
a simple `bool _running` in `SyncService` (throw `StateError` or return null on
overlap) and disable the button while running.

**Commit:** `Sync: report issues and progress, guard against overlapping runs`

### 8. Stale-blob hygiene: sweep `.part` / `.tmp-*` leftovers

**Problem.** An interrupted app download leaves `files/<id>.<ext>.part`
(`sync_service.dart:122`) forever; a crashed server upload leaves
`files/.tmp-<uuid>` (`blobs.rs:202`) forever. Multi-GB junk accumulates
invisibly.

**Change.** App: in `LibraryRepository._withDataDir`, after creating the dirs,
delete `*.part` files under `files/` (any that exist are by definition
incomplete). Server: in `main.rs` after `connect_db`, walk
`data_dir/files` and remove `.tmp-*` entries older than 24h (age check so a
concurrent in-flight upload on a slow link isn't killed). Also add graceful
shutdown while there — `axum::serve(...).with_graceful_shutdown(async {
tokio::signal::ctrl_c().await.ok(); })` — so in-flight uploads get to finish
instead of guaranteeing fresh tmp junk on every deploy.

**Commit:** `Cleanup: sweep interrupted transfer temp files, graceful shutdown`

---

## B. Server performance & robustness

### 9. Enable WAL mode and a busy timeout on the server's SQLite pool

**Problem.** `connect_db` (`lib.rs:41-53`) opens a default `SqlitePoolOptions`
pool — multiple connections, rollback journal, no busy timeout. Under
journal mode DELETE, one writer blocks all readers; with several pool
connections, a long streaming upload's `INSERT` racing the console's list query
surfaces as `SQLITE_BUSY` → opaque 500s. This is the single cheapest
reliability fix on the server.

**Change.**

```rust
let options = SqliteConnectOptions::new()
    .filename(path)
    .create_if_missing(true)
    .foreign_keys(true)
    .journal_mode(sqlx::sqlite::SqliteJournalMode::Wal)
    .synchronous(sqlx::sqlite::SqliteSynchronous::Normal)
    .busy_timeout(std::time::Duration::from_secs(5));
```

WAL gives concurrent readers during writes; `NORMAL` sync is the standard WAL
pairing (durable except power loss in a narrow window — fine here, and the
backup story in DESIGN.md already covers the `.db` file). Note in DESIGN.md's
Deployment section that the `-wal`/`-shm` sidecar files must be backed up with
the db (or run `PRAGMA wal_checkpoint(TRUNCATE)` before copying).

**Commit:** `Server: WAL mode and busy timeout for SQLite`

### 10. Scope the 2 GB body limit to file uploads only

**Problem.** `router()` applies `DefaultBodyLimit::max(max_upload_bytes)`
(default **2 GB**) to the whole router (`lib.rs:118`). Every JSON endpoint and
`put_cover` (which buffers the full body as `Bytes`, `blobs.rs:96`) will
happily buffer up to 2 GB of request body in RAM — an unauthenticated `POST
/api/auth/login` included. That's a one-request memory-exhaustion vector.

**Change.** Layer limits per route group: keep the big limit only on
`/api/books/{id}/files` (the streaming upload), give covers a sane cap
(`DefaultBodyLimit::max(32 * 1024 * 1024)` on `/api/books/{id}/cover`), and the
default 2 MB axum limit everywhere else (just don't override it). In axum 0.8
attach with `.route_layer(...)` on the specific `MethodRouter`s, e.g.:

```rust
.route("/api/books/{id}/files",
    get(blobs::list_files)
        .post(blobs::upload_file.layer(DefaultBodyLimit::max(max_upload))))
```

(or split the three groups into sub-`Router`s and `.merge()` them). Integration
test: an 8 MB body to `/api/auth/login` → 413.

**Commit:** `Server: per-route body limits (2 GB only for file uploads)`

### 11. Timeout, kill, and background the PDF cover shell-outs

**Problem.** `render_first_page` (`blobs.rs:360-420`) runs `pdftoppm`/`mutool`/
`gs` with no timeout — a pathological or malicious PDF (already on disk, it
passed only a 4-byte sniff) can hang the child process forever, pinning the
upload request and its connection. Renders also run inline, so a big upload's
HTTP response waits for Ghostscript. Nothing bounds concurrent renders.

**Change.**
- Wrap each `Command` in `tokio::time::timeout(Duration::from_secs(30), …)`
  and add `.kill_on_drop(true)` so a timed-out child is reaped, not leaked.
- Run render + `apply_filename_metadata` **after** responding: move that tail of
  `upload_file` into `tokio::spawn` (the console already refreshes the row via
  fetch; the app pushes its own covers anyway). The DB row + blob are committed
  before spawning, so nothing user-visible is lost on failure.
- Bound concurrency with a `tokio::sync::Semaphore(2)` in `AppState` acquired
  around `render_first_page`, so ten parallel uploads don't fork ten `gs`.
- While here: `render_pdf_cover` writes `covers/{id}.jpg` but doesn't remove a
  previous cover with a different extension (`put_cover` does,
  `blobs.rs:123-127`); replicate that cleanup.

**Commit:** `Server: time-box and background PDF cover rendering`

### 12. Serve HTTP Range requests for book files (resume + streaming)

**Problem.** `serve_blob` (`blobs.rs:504`) streams full bodies only. E-readers
pulling a 300 MB PDF over the OPDS feed restart from byte 0 on every hiccup,
and browser PDF viewers can't do progressive/random-access loading. The ETag
work from plan 1 gives revalidation but not resumption.

**Change.** In `serve_blob`, parse a single-range `Range: bytes=a-b` header
(ignore multipart ranges — respond with the full body for those):
`file.seek(SeekFrom::Start(a))`, wrap in `ReaderStream::new(file.take(b - a + 1))`,
respond `206 Partial Content` with `Content-Range: bytes a-b/total` and
`Content-Length: b - a + 1`. Always set `Accept-Ranges: bytes` on 200s. If an
`If-Range` header is present and doesn't match the ETag, ignore the range.
Malformed/unsatisfiable → `416` with `Content-Range: bytes */total`.
Tests: full fetch unchanged; `bytes=0-3` of a known blob returns exactly 4
bytes and correct `Content-Range`; suffix range `bytes=-5`.

Then use it in the app: `downloadFileTo` checks for an existing `.part` file
and resumes with `Range: bytes=<len>-` (append mode), falling back to a full
download when the server answers 200.

**Commit:** `Server: byte-range downloads; App: resume interrupted pulls`

### 13. Cache Basic-auth verifications (OPDS does an Argon2 per request)

**Problem.** Every OPDS request (and every console `?token=`-less Basic call)
runs a full Argon2 verify (`auth.rs:84-126`) — that's ~10²ms of CPU *per feed
item fetch* for e-readers that send Basic on each request, and a free CPU-DoS
amplifier (each anonymous request costs the server an Argon2).

**Change.** Add to `AppState` a `verified_basic: Mutex<HashMap<String, (String,
Instant)>>` mapping lowercase email → (`sha256_hex(password)`, verified-at).
In `user_from_basic`, before Argon2: if an entry exists, is younger than 5
minutes, and the sha256 of the presented password matches, skip Argon2 and load
the user row. On successful Argon2, insert/refresh the entry; on failure or
password change, remove it. SHA-256 of a high-entropy in-memory value gated by
TTL is fine here — the threat is repeated *hashing cost*, not storage. Evict
entries lazily (drop expired on lookup) so the map can't grow past the user
count. The login throttle still applies before the cache check for unknown
emails.

**Commit:** `Server: short-lived Basic-auth verification cache`

### 14. Batch the OPDS feed queries (N+1) and reuse the list aggregation

**Problem.** `opds::feed` (`opds.rs:16-54`) runs two queries **per book**
(authors, files). A 1,000-book library = 2,001 queries per feed fetch, on top
of item 13's Argon2.

**Change.** Reuse the grouped-scan pattern from `books::list`
(`books.rs:100-131`): factor those two scans into a shared helper in `books.rs`
(e.g. `pub async fn author_map(state) -> HashMap<String, Vec<String>>` and a
`files_map` variant returning `(id, format)` pairs), call it once, and index
into the maps inside the entry loop. While there, restrict the author scan to
visible books if you want to be tidy (build the map after `visible_books` and
filter by its id set) — today it scans all rows and discards, which is wasted
work but not a leak.

**Commit:** `Server: batch OPDS feed queries`

### 15. Ship `files[]` in the books list (kills the app's per-book listFiles round-trip)

**Problem.** `SyncService.pull` calls `client.listFiles(b.id)` for **every**
server book on **every** pull (`sync_service.dart:111`) — an HTTP round-trip
per book, dominated by latency (1,000 books × ~50 ms RTT ≈ 50 s of pure
waiting even when nothing changed). `push` does it again per book.

**Change.** Server: `BookListItem` gains `files: Vec<FileDto>` populated from
one grouped scan (`SELECT … FROM book_file ORDER BY book_id` folded into a
map — the `file_count` scan can then be dropped and computed as
`files.len()`). The console keeps working (extra field), and per DESIGN.md the
response-only enrichment pattern is established. App: `ServerBook` gains
`files: List<ServerFile>` parsed from the list JSON; `pull` and `push` use it
instead of `listFiles` (keep the endpoint for the console detail view).

**Commit:** `Server: include files in the books list; App: drop per-book file fetches`

### 16. Thumbnail variant for covers (console table + OPDS thumbnails)

**Problem.** The console's table and the OPDS `image/thumbnail` link both serve
the **full** cover (first-page renders are 1400 px JPEGs, often 300–800 KB) for
every row. A 500-book console load pulls hundreds of MB to paint 40 px thumbs.

**Change.** `get_cover` accepts `?w=<px>` (whitelist, e.g. only `160`):
on first request, generate and cache `covers/thumbs/{id}-w160.jpg` — add the
`image` crate (decode + `thumbnail()` + JPEG-encode in `spawn_blocking`; pure
Rust, keeps the single-binary story, unlike shelling out) — then serve the
cached file through the existing `serve_blob` with a weak ETag. Invalidate by
deleting the thumb in `put_cover` and `render_pdf_cover`. Point the console's
row thumbnails and the OPDS `thumbnail` rel at `?w=160`.

**Commit:** `Server: cached cover thumbnails`

### 17. Prune the login-throttle map

**Problem.** `LoginThrottle` (`throttle.rs`) keeps one `Vec<Instant>` per
distinct email key forever unless that email later logs in successfully
(`clear`). An attacker spraying random emails grows the map without bound;
`retain` only trims timestamps inside each entry, never the entries.

**Change.** In `allowed()`, after `hits.retain(…)`, drop empty entries — easiest
as a periodic pass: `map.retain(|_, v| { v.retain(|t| now - *t < WINDOW); !v.is_empty() });`
executed when the map exceeds, say, 1,000 entries. Unit test: 2,000 distinct
keys, all older than the window → map shrinks on next `allowed()`.

**Commit:** `Server: prune stale throttle entries`

### 18. Sliding session expiry

**Problem.** Sessions are a fixed 30-day row (`auth.rs:379-390`). A daily-use
app hits day 31, every request 401s, and sync silently stops until the user
figures out they must re-login.

**Change.** In `user_from_token`, when the matched session's `expires_at` is
within 15 days, extend it: `UPDATE session SET expires_at = datetime('now',
'+30 days') WHERE token_hash = ?` (fire-and-forget; at most one write per
request and only in the renewal window). App side: on a 401 from any sync call,
`ServerConnection` should clear the token and surface "session expired — log in
again" instead of a generic error (check `server_page.dart` error paths).

**Commit:** `Server: sliding session expiry`

---

## C. Security hardening

### 19. Scope `?token=` auth to blob GETs only

**Problem.** The `AuthUser` extractor accepts `?token=` on **every** endpoint
(`auth.rs:56-60`), not just the cover/file GETs it exists for. That needlessly
widens the documented leak surface (proxy logs, browser history) to mutating
endpoints — a logged URL with a token can replay a DELETE.

**Change.** In the extractor's query-token branch, gate on method + path:
allow only `GET` requests whose path starts with `/api/books/` and ends with
`/cover`, or starts with `/api/files/` (`parts.method` and `parts.uri.path()`
are both available). Everything else requires a header. Document in DESIGN.md.
Longer-term (deferred in plan 1, still deferred): HMAC-signed short-lived
per-resource URLs minted by a `GET /api/books/{id}/cover-url` endpoint.

**Commit:** `Server: restrict query-param tokens to blob downloads`

### 20. Cap password length; add basic strength floor

**Problem.** `validate_credentials` (`auth.rs:323`) enforces only `len >= 8`.
Argon2 will happily hash a 10 MB password — combined with item 10's fix the
body cap bounds this, but a 2 MB JSON password is still ~free CPU for an
unauthenticated caller (login runs Argon2 even for wrong passwords, by design).

**Change.** Reject passwords longer than 128 bytes with a 400 in
`validate_credentials`, and enforce the same check at the top of `login` /
`user_from_basic` **before** hashing (that's the DoS-relevant spot — the
registration-time check alone doesn't protect the verify path since it hashes
whatever arrives). Trim + lowercase handling stays as is.

**Commit:** `Server: cap password length before hashing`

### 21. Rate-limit the anonymous public endpoints and metadata search

**Problem** (deferred in plan 1, now the biggest unthrottled surface). `/api/
public/{token}` and `/p/{token}` are unauthenticated and unthrottled — token
brute force is hopeless (24 random bytes) but each guess costs the server a
SHA-256 + DB probe, and `GET /api/metadata/search` (authenticated) fans out to
Open Library / Google Books, so a misbehaving client can burn the shared
outbound quota.

**Change.** Generalize `LoginThrottle` into a keyed
`RateLimiter { max, window }` (same Mutex<HashMap> shape) and add two
instances to `AppState`: per-IP for `/api/public/*` (e.g. 60/min; key from
`axum::extract::ConnectInfo<SocketAddr>` — plumb `into_make_service_with_connect_info`
in `main.rs`, and honor `X-Forwarded-For`'s first hop when set, since DESIGN.md
mandates a reverse proxy) and per-user for `/api/metadata/search` (e.g.
30/min keyed on `user.id`). 429 with the existing `TooManyRequests` error.

**Commit:** `Server: rate-limit public links and metadata search`

---

## D. App performance

### 22. Bound cover decode size and stop `existsSync` in build

**Problem.** Two hot-path issues in the shelf (`shelf_view.dart`):
- `Image.file(cover, fit: BoxFit.cover)` (`:232`, `:373`) decodes covers at
  **full** resolution — a 1400×2000 first-page render is ~11 MB of decoded RGBA
  *per book*. A 200-book shelf can pin hundreds of MB of image cache and jank
  the first paint of every row.
- `cover.existsSync()` runs a synchronous `stat()` per book per rebuild
  (`:219`, `:361`) — and the search field rebuilds the whole shelf **per
  keystroke** (`main.dart:123`).

**Change.**
- Pass a decode budget:
  `Image.file(cover, cacheWidth: (logicalWidth * dpr).round(), …)` where
  `logicalWidth` is the spine width (or `_coverWidth` face-out) and `dpr` =
  `MediaQuery.devicePixelRatioOf(context)`. The framework then decodes a
  spine-sized bitmap and caches that. Do the same in the physical editor's
  `SpineFace` usage and `book_detail_page.dart:704` (detail can use a larger
  budget, e.g. 2× the layout width).
- Drop `existsSync`: trust `book.coverPath != null` (the DB is the source of
  truth; the repository deletes the path and the file together) and add an
  `errorBuilder` on `Image.file` that falls back to `_generatedSpine` for the
  rare orphaned path. Net: zero filesystem calls in build.
- While in `main.dart`: debounce the search `onChanged` (150 ms `Timer`) so
  typing doesn't re-pack rows per character.

**Commit:** `App: bounded cover decodes, no sync IO in shelf build`

### 23. Repaint isolation in the physical editor

**Problem.** `environment_editor_page.dart` (1,400 lines) drives every drag
frame through `setState` on the whole page (`:205`, `:211`) — every placed
book, shelf, wallpaper, and toolbar rebuilds and repaints ~120×/s while
dragging one book.

**Change** (behavior-preserving, no schema impact):
- Wrap each placed book widget in a `RepaintBoundary` so untouched spines keep
  their raster layer.
- Move the in-flight drag to a `ValueNotifier<Offset>` consumed by a
  `ValueListenableBuilder` around **only** the dragged book (and the dragged
  shelf's delta likewise); commit to `setState`/DB only on release, as today.
- Longer term, split the file: `environment_canvas.dart` (gesture + paint),
  `placement_toolbar.dart`, `shelf_dialogs.dart` — same treatment
  `book_detail_page.dart` (1,009 lines) deserves (edit sheet / files section /
  loans section as separate widgets). Mechanical extraction, no logic change.

**Commit:** `App: isolate repaints in the environment editor` (+ separate
split-file commits)

### 24. Use the pull ETags the server already sends (cover refresh)

**Problem.** Plan-1 Task 9 gave the server ETag/304 on blobs, but the app never
sends `If-None-Match`. Worse, `pull` skips any cover whose file already exists
locally (`sync_service.dart:94`), so a cover changed on the server (console
edit, better online art) **never** reaches a device that has any old cover.

**Change.** Drift v7 (same migration as item 4's flag): `Books` gains an
app-local `coverEtag` text column. `downloadCover` becomes
`downloadCover(bookId, {String? etag})`, sends `If-None-Match`, returns a
record `(bytes, etag)` — `null` bytes on 304. `pull` always calls it for
`hasCover` books (no more exists-check), passing the stored etag: 304 = no-op;
200 = write bytes, store new etag from the `ETag` response header. Cheap
because the server's 304 path never opens the file. Do **not** apply to book
files (content-hash dedup already covers those).

**Commit:** `App: conditional cover pulls via ETag`

### 25. Parallelize blob transfers in sync

**Problem.** `pull`'s cover and file loops and `push`'s upload loop are strictly
sequential — total sync time is the *sum* of every transfer's latency. Blob
transfers are independent and the server streams them.

**Change.** Use a bounded pool (add `pool: ^1.5.0`, tiny and canonical):

```dart
final pool = Pool(4);
await Future.wait([
  for (final f in pendingFiles)
    pool.withResource(() => _downloadOne(f)),
]);
```

Concurrency 4 keeps a personal server comfortable. DB writes stay where they
are (drift serializes internally, but keep the existing per-file insert order:
record the row only after its rename). Apply to the cover loop, the file loop,
and push's file uploads; metadata upserts stay in the single transaction.

**Commit:** `App: parallel blob transfers during sync`

---

## E. Architecture & maintainability

### 26. Split `console.html` (1,203 lines) into html/css/js

**Problem.** The console is one 1,200-line HTML string with inline CSS and JS —
the largest single file in the server tree, unreviewable diffs, no syntax
tooling. (Called out as deferred in plan 1.)

**Change.** Split `server/web/` into `console.html`, `console.css`,
`console.js` (and the same for `public.html` if it grows). Two options; take
the first: keep single-binary by embedding all three
(`include_str!`) and serving `/assets/console.css`, `/assets/console.js` from
tiny handlers with the right `Content-Type` (same-origin, CSP-friendly, no
CDN — the DESIGN.md constraint holds). `console.html` references them with
plain `<link>`/`<script src>`. No behavior change; verify by driving the
console once (`cargo run`, add/edit/upload).

**Commit:** `Server: split the console into html/css/js assets`

### 27. Garbage-collect orphaned authors and genres

**Problem.** Both sides get-or-create author/genre rows by name but never
delete them: removing a book's last reference (app `setAuthors`, server
cascade on book delete) leaves the name row forever. Harmless at first, but
the unique-name tables grow monotonically and pollute future autocomplete UIs.

**Change.** After join mutations, sweep in the same transaction:
`DELETE FROM author WHERE id NOT IN (SELECT author_id FROM book_author)` (and
the genre equivalent). App: at the end of `setAuthors` / `setGenres` and
`deleteBook`; server: after upsert's join replacement (item 3) and in
`books::delete`. Sub-millisecond at this scale; the subselect uses the join
table's PK index.

**Commit:** `Both: garbage-collect orphaned author/genre rows`

### 28. Extract a `BookWriteService` boundary in the repository (optional, prep for Android)

**Problem.** `LibraryRepository` (710 lines) is back on a growth path: it mixes
book CRUD, file store, physical-layout CRUD, loans, and metadata import. Not
urgent — but the Android milestone (build order step 6) will add
platform-conditional code (secure storage, file pickers, barcode scan), and a
flatter surface makes that harder.

**Change** (pure refactor, mirror of plan-1 Task 11): move the physical-layout
block (`library_repository.dart:319-511` — environments, shelves, placements)
into `app/lib/physical/layout_repository.dart` holding a reference to the same
`VellumDatabase`; `LibraryRepository` keeps a getter for it so call sites
change mechanically. Loans + copies could follow later. Keep `watch*` streams
drift-based per CLAUDE.md.

**Commit:** `App: extract physical-layout repository`

---

## F. Testing & tooling

### 29. CI: fail when generated drift code is stale

**Problem.** `database.g.dart` is committed but nothing verifies it matches
`database.dart` — a schema edit without the build_runner rerun (the CLAUDE.md
checklist's most forgettable step) compiles locally against the stale generated
file and lands green.

**Change.** In `.github/workflows/ci.yml`'s app job, after `flutter pub get`:

```yaml
- run: dart run build_runner build --delete-conflicting-outputs
- run: git diff --exit-code -- lib/data/database.g.dart
```

A stale file now fails CI with the diff in the log.

**Commit:** `CI: verify drift codegen is up to date`

### 30. Cross-stack sync smoke test

**Problem.** Sync is tested app-side against a hand-written fake client
(`sync_service_test.dart`) and server-side via `tests/api.rs` — nothing ever
exercises the real wire format end-to-end. Items 1, 3, 4, 6, 15 all change
that contract; a fake-only suite will happily pass with both sides wrong in
mirrored ways (exactly how the authors-not-synced gap survived).

**Change.** New CI job (or a script in `scripts/`): `cargo build` the server,
launch it on a random port with `VELLUM_DB`/`VELLUM_DATA_DIR` in a temp dir,
then run a dedicated `flutter test test/e2e_sync_test.dart` (tagged, excluded
from the default `flutter test` via `dart_test.yaml` tags) that registers,
pushes a book with an author + file from an in-memory repository, pulls into a
**second** in-memory repository, and asserts metadata/authors/file hash + a
delete tombstone round-trip. ~30 lines of Dart once the pieces exist; catches
every wire-format regression in one place.

**Commit:** `CI: end-to-end sync smoke test against the real server`

---

## Deferred / explicitly out of scope (carried + new)

- Field-level merge and live updates (websocket/long-poll) — still the big one;
  item 6's cursor is a prerequisite worth doing first.
- Android build & barcode scanning (build order step 6).
- Cover-derived spine colours and cover-slice spines (BACKLOG.md).
- OPDS pagination + OpenSearch — worth it only if a library outgrows what
  e-readers will render in one feed.
- Upsert ID-squatting (unchanged assessment from plan 1: acceptable on a
  personal server).
- Server-side full-text search endpoint — the console filters client-side and
  the app searches locally; revisit if either becomes slow.
