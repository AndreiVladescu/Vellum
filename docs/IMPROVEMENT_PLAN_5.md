# Improvement plan 5 — architecture & feature roadmap

Follow-up to [`IMPROVEMENT_PLAN_4.md`](IMPROVEMENT_PLAN_4.md). Written 2026-07-25
against `main` @ `70d5f12`, after re-reading `DESIGN.md`, `CLAUDE.md`, plans 1–4,
`docs/SECURITY_AUDIT.md`, and the code itself.

> **Rev 2 (2026-07-25).** Refined after a second pass, and adds **§K — the
> physical library goes online** (#47–#51): publish a room to the server, view
> it in the console or through a public link, fetch it on another device, and
> let people with access request to borrow from it. §K **effectively decides
> item #4 in favour of Option A** (synced physical copies) — see the rev-2 notes
> in #4. Smaller refinements are marked *Rev 2* inline (#2's FTS delete caveat,
> #27's borrow-request cross-reference, §I/§J updates).

Where plans 1–4 were mostly **remedial** (sync correctness, performance,
security, Android readiness), this plan is **forward-looking**: it proposes
structural changes that make the next round of features cheap, then the features
themselves. Every item is written so it can be picked up cold.

## Progress (updated 2026-07-26)

**Phases 1 and 2 of §I are done.** Each item's commit is listed so "still true?"
is answerable from `git log`:

| # | Item | Commits |
|---|---|---|
| 45 | Performance harness + synthetic library | `d5f6865`, `5948d21`, `5932e99` |
| 10 | Split `LibraryRepository` | `7ca1f90`, `cf7c695` |
| 1 | One library view-model stream | `0b818c2`, `388d0f0`, `1752512`, `b7c4502` |
| 2 | FTS5 search | `c017654` |
| 3 | Scoped + paginated server list | `314bcc9` |
| 6 | API version + capability handshake | `8a3973e` |
| 43 | Migration tests from every schema version | `78fd14f` |
| 4 | Shelves / copies / loans sync (**Option A**) | `77605c9`, `9533a6f`, `ca48d1f` |
| 5 | Optional cross-device reading position | `1cd874f` |
| 7 | Batch book upsert on push | `b49b825`, `d915fa9` |
| 44 | Model-based sync state machine tests | `0cc9f69` |
| 14 | Atomic file import (interleaved) | `b1f9315` |
| 15 | Bulk folder import with a dry-run plan | `f2ea4d8` |
| 16 | Scan ISBN barcodes to add books | `36761ea` |
| 20 | Open-with / share-target import | `b826164` |
| 21b | Find and merge duplicate books | `25cad1e` |
| 25 | Continue-reading and recently-added strip | `466ff63` |
| 41 | First-run onboarding and better empty states | `f10820a` |
| 22 | Bookmarks, highlights, and notes | `6072552` |
| 23 | Reader typography, themes, search, scroll restore | `e3f919d` |
| 18 | Reading status, ratings, and finish dates | `f100d9b` |
| 19 | Reading sessions and an insights page | `beb1195` |
| 17 | Series and volume tracking | `b7bc567` |
| 50 | Derive a copy's location from its placement | `7f3d44d` |
| 11 | Library health check with guided repairs | `695b326` |
| 36 | Docker, compose with TLS, systemd, releases | `1869fae` |
| 37 | Request ids, tracing spans, stats dashboard | `ab00074` |
| 12 | Integrity sweep, stats, snapshot endpoints | `9a4540f` |
| 46 | RBAC matrix + compile-checked queries | `74d3864`, `b903cb5` |
| 31 | SMTP mailer, password reset, emailed invites | `d031ffd`, `eda0843`, `cf349dc` |
| 27 | Loan due dates, overdue badges, reminders* | `93574d5` |
| 51 | Condition photos on copies | `0ebe05c` |
| 28 | Find a copy, tidy a shelf, print labels | `c751607` |
| 13 | Backup manifest + verify, rotation, encryption* | `4697d31` |
| 32 | Server-side full-text search of book contents | `e194105` |
| 34 | OPDS search, navigation feeds, and paging | `3ac84a2` |
| 35 | Console paging, saved views, activity log* | `70f9d8e` |
| 33 | Read EPUBs (and share links) in the browser | `17b626c` |
| 47 | Publish and fetch physical room layouts | `b15a6d9` |
| 48 | Rendered room view + public room links | `HEAD` |

**Every item in Phases 1–5 is now done.** Everything §I lists for the on-ramp has landed, plus #14
from the interleave list.

*#35's **virtualised table body** is deliberately not built. It was proposed as
the fix for a DOM holding the whole library — but with search, sort and filters
moved onto the server, the console now holds one page (200 rows) unless the user
presses "Load more". Windowing would be solving a problem that no longer exists;
revisit only if someone loads enough pages to feel it.

*#13's **incremental** half (step 4) is deliberately not built: the plan itself
says to defer it until full backups measurably hurt, and to prefer "blobs in a
sidecar folder + small db-only archives" over an incremental format if they do.

**#46 is done but its second half is deliberately partial.** `access.rs` is the
compile-checked pilot; the rest is mechanical and can proceed module by module
(`auth.rs`, `groups.rs`, `blobs.rs` are fully static and next in line). Roughly
17% of query sites are composed with `format!` — the visibility predicate, the
dynamic-table get-or-create helpers — and can never use the macros, since those
take a string literal.

**Phase 6** (§K) is nearly done: #50, #51, #47 and #48 have landed, leaving only
#49 (borrow requests).
Still open from the interleave list: #26 shortcuts, #39 theming, #42 a11y
round two, #9 content-addressed blobs, #8 SSE, #29/#30, #38 l10n, #40 Android
background, #52 trash, #53 send-to-e-reader. #21a (wishlist) and #21c (Calibre /
CSV / OPDS import) are also still open — 21b was taken on its own because §I
sequences it into Phase 3 while the other two aren't.

Two notes for whoever picks this up:

- #5 landed as specified, with one addition the plan didn't anticipate: rows
  carry a `unit` (`page`/`chapter`), because a device reading the EPUB and one
  reading the PDF mean different things by "page 214". The jump prompt only
  appears when the units match.
- #7's server cap is 200 per batch, mirrored in `SyncService._batchPushChunk`;
  a single-book push deliberately skips both the handshake and the batch.
- #15's duplicate detection needs the scan to hash every file, which is why the
  dry run is the slow step and the import that follows is only as slow as the
  copying. #21b and #16 both reuse `import_plan.dart`'s classifier, as planned.
- #16 added the `mobile_scanner` dependency; the camera is optional
  (`uses-feature required="false"`) and a typed ISBN drives the same path, which
  is also how desktop uses the feature.
- #20 is a hand-written `MethodChannel` rather than a share-intent package: the
  only native work is copying a `content://` stream before its permission
  expires. Its device-only checks are listed under "Manual device checks" in
  `docs/BACKLOG.md`.
- **#17 is the only Phase-4 item that syncs**, and it needed two things the plan
  didn't spell out: `shares.rs` was keeping a hand-copied duplicate of the book
  select list (now `books::BOOK_COLUMNS`, `pub(crate)`), and applying a *pulled*
  series must not bump `updatedAt` — `setSeries(markDirty: false)`. #44's model
  tests caught the second one, which is exactly what they exist for.
- **#22's EPUB locators are honest approximations**: offsets index the app's own
  `EpubChapter.plainText`, so the locator is versioned and re-finding a highlight
  is quote-first. PDF locators are objective (pdfrx's own extracted text).
- **#23 left three things out deliberately** (paged EPUB mode, keep-awake,
  volume-key turns) — each needs a platform plugin or a layout engine; they are
  listed in `docs/BACKLOG.md` with the manual visual checks.
- **#37's span must be attached with `.instrument()`**, not `span.enter()`: a
  guard is dropped at the first `.await`, so entering it loses the request id on
  every handler that touches the database — i.e. exactly the slow ones. This was
  observed against a live server before being fixed, and is the sort of thing that
  looks fine in a unit test.
- **#46's matrix found a real hole on its first run**: `PUT` and `DELETE` on a
  book answered 403 (not 404) to a caller with no access, which is an existence
  oracle over the whole library, and `PUT` told them they had "read-only access"
  they didn't have. Fixed in `books.rs` and recorded as L7 in
  `docs/SECURITY_AUDIT.md`. This is the argument for the matrix in one sentence.
- **#31 introduced and then fixed a log leak** (L8 in `docs/SECURITY_AUDIT.md`):
  #37's request logger wrote full paths, and a reset link *is* a credential, so
  `/reset/<token>` was landing in the log. Secret-bearing paths are now redacted.
  Worth remembering when adding any future route whose path contains a token.
- **#12's snapshot uses `VACUUM INTO`** and cleans its workspace from a `Drop`
  guard tied to the response stream, so a client that disconnects halfway doesn't
  leave a second copy of the library on disk.
- #21b's merge is the one destructive operation in the app. It moves everything
  in a single transaction, tombstones the loser so the merge propagates, and logs
  what moved; `test/dedupe/merge_service_test.dart` is the contract.

**Status of plan 4:** §A 1–3, §B 4–6, §C 7–10, §D 11–13, §E 16–17 and §F 18 all
landed. Still open and **carried into this plan unchanged**:

| Plan 4 item | Carried here as |
|---|---|
| §D 14 — open-with / share-target import (Android) | **#20** |
| §E 15 — EPUB in-chapter scroll position | folded into **#23** |
| §G 19 — SMTP → password reset & invites | **#31** (unchanged plan, restated) |

## How to use this document

Items are grouped by theme, numbered continuously, and tagged:

- **Effort** — `S` (≤ half a day), `M` (1–2 days), `L` (multi-day / needs its own
  design pass).
- **Touches** — `app`, `server`, `console`, `docs`, `ci`.
- **Schema** — whether it changes the app schema, the server schema, or both.

Each item states the **Problem**, the **Change**, the **Files** most likely
involved, **Tests**, and a suggested **Commit** title. Groups are ordered by
leverage: **§A first** — several later features are twice the work without it.

## Ground rules (unchanged)

- Read `CLAUDE.md` and `DESIGN.md` before structural work.
- Schema changes = drift `schemaVersion` bump + **idempotent** drift migration
  (guard every step on `PRAGMA table_info` / `sqlite_master`, as `onUpgrade`
  already does) + a **new** SQL migration **only when the column/table is
  synced** + `build_runner` rerun + update `server/tests/schema_parity.rs`
  whenever a *synced* table changes.
- App-local-only columns (reading state, `readerNotes`, `sourceMetadata`,
  `needsPush`, `coverEtag`) and app-local-only tables (the three physical-layout
  tables, `local_deletions`) get **no** server migration.
- After every task: `cargo test && cargo clippy --all-targets -- -D warnings`
  and `cargo fmt --check` in `server/`; `flutter analyze && flutter test` in
  `app/`. After adding a server migration, `touch server/src/lib.rs` so
  `sqlx::migrate!()` re-embeds it.
- Never edit an applied migration; add a new one.
- One cohesive feature per commit, short title, optional succinct bullets, no
  `Co-Authored-By`.

**Standing decisions — do not revisit:** conflict handling stays **row-level
LWW** by `updated_at` with delete tombstones (field-level merge was rejected in
July 2026 and stays rejected — see `DESIGN.md`). The app stays **local-first**:
no feature may require the server. The server stays a **single static binary**
with no runtime asset or PDF-library dependency.

---

## §0. Verified state of the code

Facts this plan builds on, each checked in the tree at `70d5f12` (so a future
reader can tell "still true?" quickly):

| # | Observation | Evidence |
|---|---|---|
| 1 | The shelf tab nests **four** `StreamBuilder`s (shelves → authors-by-book → genres-by-book → books); any one emission rebuilds the whole subtree. | `app/lib/main.dart:389,403,407,411` |
| 2 | Search, genre facet and sort run **in Dart over the whole library**, per rebuild, with substring `contains` matching. | `app/lib/shelf/shelf_filter.dart`, called from `main.dart:466` |
| 3 | There is **no SQL index or FTS table** for search; `watchAllBooks()` is `SELECT *` ordered by title. | `app/lib/data/database.dart:368` |
| 4 | `GET /api/books` scans **all** authors, **all** genres and **all** book_files on every call, even for a one-row delta pull, and has **no `LIMIT`** — the console loads the entire library. | `server/src/books.rs:190,198,216` |
| 5 | `physical_copy`, `loan`, `shelf`, `shelf_book` exist in the **server** schema (migration `0001`) but **no handler and no sync path reads or writes them** — they are dead tables. Custom shelves, physical copies and loan history therefore live on exactly one device. | `server/migrations/0001_init.sql:54,64,73,79`; no hits for those tables in `server/src/**` or `app/lib/server/sync_service.dart` |
| 6 | Reading state is app-local by design, so **reading position does not follow you across devices** — deliberate, but users will read the same book on phone and desktop once Android ships. | `DESIGN.md` "App-local-only columns" |
| 7 | `LibraryRepository` is **945 lines** and owns books, authors, genres, covers, files, physical copies, loans, shelves, reading state and revert. Plan 2 §28 proposed splitting it and deferred. | `app/lib/data/library_repository.dart` |
| 8 | The PDF reader is a bare `PdfViewer.file` — no font/theme controls (n/a), **no bookmarks, no in-book text search, no TOC**. The EPUB reader resumes by chapter only. | `app/lib/reader/reader_page.dart` (65 lines), `app/lib/reader/epub_reader_page.dart` |
| 9 | **No localization**: no `flutter_localizations`, no ARB files; every string is an inline English literal. | `app/pubspec.yaml` |
| 10 | **No barcode scanning** dependency — build-order item 6's remaining half. | `app/pubspec.yaml` |
| 11 | No batch/bulk import path: books are added one at a time through `AddBookPage`, or through the console's CSV import. | `app/lib/add_book/add_book_page.dart` |
| 12 | The console keeps the bearer token in `localStorage`. | `server/web/console.js:1,81` |
| 13 | There is **no API version prefix** and no capability handshake; app and server are assumed to be lock-step. | `server/src/lib.rs:95` |
| 14 | Server observability is `tracing_subscriber::fmt::init()` with a handful of `info!` lines — no request spans, no request id, no metrics. | `server/src/main.rs:8,102,123` |
| 15 | No **Dockerfile**, compose file, systemd unit, or release-artifact job; CI builds and tests but publishes nothing. | repo root, `.github/workflows/ci.yml` |
| 16 | Blobs are stored by **row id** (`covers/<book_id>.jpg`, `files/<file_id>.<fmt>`), not by content hash, so the same PDF attached to two books is stored twice. | `server/src/blobs.rs`, `app/lib/server/sync_service.dart` |

---

## §A. Architecture — do these first

### 1. One library query instead of four nested streams

**Effort M · app · no schema change**

**Problem.** `_shelfTab` (`main.dart:384–433`) nests `StreamBuilder`s for
shelves, authors-by-book, genres-by-book and books. Each stream emits
independently, so adding one book rebuilds the whole shelf subtree up to four
times, and `_shelfBody` re-runs `filterBooks` + `sortBooks` over the **entire**
library on every one of those rebuilds (§0.1, §0.2). It also means the widget
tree, not the data layer, owns the shelf's business logic.

**Change.** Introduce a **library view-model** that emits one immutable snapshot:

```dart
/// One shelf row's worth of data, denormalised once in the data layer.
class LibraryEntry {
  final Book book;
  final List<String> authors;   // ordered by book_authors.position
  final List<String> genres;
  final bool hasFile;           // for the "digital" badge, no extra query
}

class LibraryView {
  final List<LibraryEntry> entries;   // already filtered + sorted
  final List<Shelf> shelves;
  final List<String> allGenres;       // for the facet menu
}
```

Back it with **one** drift query (`watchLibrary({shelfId, query, genre, sort})`)
that joins `books`, `book_authors`/`authors`, `book_genres`/`genres` and a
`EXISTS(book_files)` sub-select, and does the filtering/ordering **in SQL** (see
#2 for the search half). Expose it from `LibraryRepository`; `main.dart` becomes
a single `StreamBuilder<LibraryView>`.

Keep the pure functions in `shelf_filter.dart` — they are well-tested and stay
the fallback for in-memory filtering (tests, small lists) — but stop calling
them from `build()`.

**Files.** `app/lib/data/library_repository.dart`, `app/lib/data/database.dart`
(the new query), `app/lib/main.dart`, `app/lib/shelf/shelf_view.dart`.

**Tests.** Extend `library_repository_test.dart` with view-model cases
(filter × genre × sort × shelf); keep `shelf_filter_test.dart` as-is. Add a
widget test asserting the shelf rebuilds **once** per library mutation (count
builds in a `Builder`).

**Commit:** `App: one library view-model stream behind the shelf`

### 2. Search in SQLite (FTS5) instead of Dart substring scans

**Effort M · app · app-local schema change (no server migration)**

**Problem.** Search is `String.contains` over every book, subtitle and author
name, in Dart, on the UI isolate, on every keystroke-after-debounce (§0.2). At a
few hundred books this is invisible; at 5–10k (a realistic PDF hoard) it is a
frame-time problem on a phone, and it can never do prefix/word matching, ranking
or diacritic folding.

**Change.** Add a **contentless FTS5 virtual table** fed by triggers:

```sql
CREATE VIRTUAL TABLE book_search USING fts5(
  title, subtitle, authors, genres, publisher, isbn,
  tokenize='unicode61 remove_diacritics 2'
);
```

*Rev 2 — why not contentless.* A `content=''` table would be smaller, but
contentless FTS5 cannot service a plain `DELETE` (it needs
`contentless_delete=1`, which requires SQLite ≥ 3.43, or the special
`'delete'`-command insert with the original values — easy to get subtly wrong
from triggers). At library-metadata scale the stored text is a few hundred KB;
take the **plain FTS5 table** and keep deletion trivial.

- Populate/maintain it from drift with `customStatement` in the repository's
  write paths (simplest, keeps one source of truth) **or** with SQL triggers on
  `books`/`book_authors`/`book_genres` (fewer places to forget — preferred; write
  the triggers in the drift migration).
- The migration backfills the index for existing rows.
- `watchLibrary(query:)` (#1) becomes
  `... WHERE books.id IN (SELECT rowid FROM book_search WHERE book_search MATCH ?)`
  with a query built as `"tok1"* AND "tok2"*` so typing prefixes works.
- Keep `genre:<name>` as a parsed prefix, mapping it to the `genres` column.
- **Fallback:** if the FTS module is unavailable (it is compiled into
  `sqlite3_flutter_libs`, but be defensive), degrade to the existing Dart path.
- This is **app-local only** — the index is derived data, so no server migration
  and no `schema_parity.rs` change. It **must not** touch `updated_at` or
  `needsPush`.

**Note.** This is the foundation for #35 (full-text search of book *contents*):
same table pattern, one more column, populated from extracted text.

**Files.** `app/lib/data/database.dart` (migration + query), new
`app/lib/data/search_index.dart` if trigger SQL gets long,
`app/lib/data/library_repository.dart`.

**Tests.** New `search_index_test.dart`: insert/rename/delete keeps the index
consistent; prefix, multi-token, diacritic-folded and `genre:` queries; a
migration test that backfills an old database.

**Commit:** `App: FTS5-backed library search`

### 3. Scope the server's list aggregation to the delta window, and paginate it

**Effort S · server · no schema change**

**Problem.** `books::list` fetches all authors, all genres and all book_files
regardless of the cursor (§0.4). A delta pull that returns one book still reads
three whole tables. The console's un-cursored call has no `LIMIT` at all, so it
renders the entire library in one response — the "manage at scale" console is the
least scalable endpoint.

**Change.**

1. After computing `visible_books`, collect the resulting ids and scope the three
   aggregation queries to them. SQLite has no array binding; either build an
   `IN (?,?,…)` list in chunks of ≤ 900 ids, or insert the ids into a `TEMP
   TABLE pull_ids` and join against it (cleaner, one query, no chunking).
2. Add `limit`/`offset` (or keyset: `after_id` + stable `ORDER BY title, id`) to
   `ListQuery`, defaulting to **unbounded when a `cursor` is present** (the app's
   delta pull wants the whole window) and to a page when it is not (the console).
   Return `{ items, total, next }` for the paged shape — a **new response shape,
   so gate it behind an explicit `page=1` param** to avoid breaking the console
   mid-change, then move the console over and drop the flag.
3. While here: add the indexes the aggregation implies —
   `idx_book_author_book(book_id)`, `idx_book_genre_book(book_id)` — in a new
   migration (`0007_list_indexes.sql`). Index-only, no column change, so
   `schema_parity.rs` is unaffected.

**Files.** `server/src/books.rs`, new `server/migrations/0007_*.sql`,
`server/web/console.js` (paged fetch + "load more" or a page bar).

**Tests.** `server/tests/api.rs`: a delta pull with one changed book issues no
full-table scan (assert via response shape + a seeded library where a full scan
would return extra ids); paging returns stable, non-overlapping pages.

**Commit:** `server: scope list aggregation to the page, paginate /api/books`

### 4. Decide the fate of the server's dead `shelf` / `physical_copy` / `loan` tables

**Effort L (as sync) or S (as removal) · server + app · server schema change**

**Problem.** §0.5: four tables were created in `0001_init.sql` and never used.
Two consequences: (a) the schema lies about what the server does, and
`schema_parity.rs` doesn't cover them so they can rot silently; (b) **custom
shelves, physical copies and loan history are single-device data** — reinstall
the app, or add a second device, and your "Read next" shelf and the record of
who has your paperback are gone, even though a server is connected. That is the
single largest functional gap in connected mode.

**Change — recommended: sync them (Option A).** They are ordinary
book-associated rows and fit the existing LWW model with one wrinkle each:

- **`shelf` + `shelf_book`** — a shelf is a small row with a name, a sort order
  and an ordered membership list. Sync the shelf row LWW by a new
  `updated_at`, and treat **membership as a set replace** on push (send the full
  ordered list; server replaces). Add `shelf.updated_at` + `shelf.owner_id`
  server-side and `shelves.updatedAt` + `shelves.needsPush` app-side.
- **`physical_copy`** — LWW on a new `updated_at`; deletes need tombstones like
  books (reuse the `deletion` table with a `kind` column, or add
  `deletion_copy`; prefer **adding `kind TEXT NOT NULL DEFAULT 'book'`** to
  `deletion` so one endpoint carries all tombstones — note this changes
  `/api/deletions`'s response, so version it per #6).
- **`loan`** — append-mostly history. Sync by id with LWW on `returned_at`;
  never delete a loan on pull unless tombstoned (history is the point).
- The **physical-layout tables stay out of row-level sync** (§0.5 does not
  include them). The copies they *reference* becoming synced means a pull can
  now create copies a placement can point at — that is what #47's layout fetch
  builds on. *(Rev 2: layouts do travel now, but as published documents — §K —
  never as synced rows.)*

Endpoints: `/api/shelves`, `/api/copies`, `/api/loans` (list with `?cursor=`,
`PUT /{id}` upsert, `DELETE /{id}`), plus their rows in the pull/push loops of
`sync_service.dart`. Extend `schema_parity.rs` with the three tables the moment
they become synced.

**Change — alternative: remove them (Option B).** If cross-device shelves and
loans are explicitly *not* wanted, add `0007_drop_unused_tables.sql` dropping
`shelf_book`, `shelf`, `loan`, `physical_copy`, and say so in `DESIGN.md`'s data
model ("these live only on the device"). This is honest and cheap, but it closes
the door on multi-device loan tracking.

**Do not** leave the third state (tables present, unused, undocumented).

**Recommendation.** Option A, split into three commits (shelves first — smallest
and most visible; then copies; then loans). Sequence it **after #6** so the
response-shape changes ride a version negotiation.

**Rev 2 — the decision is now effectively made.** §K's layout publishing (#47)
needs a stable cross-device identity for physical copies: a room fetched on a
second device must attach its placements to *the same* copies, which only synced
`physical_copy` rows provide. So accepting §K means **Option A** for at least
`physical_copy` (and `loan`, for #49's borrow requests). Option B remains on the
table only if §K is rejected wholesale.

**Files.** `server/migrations/0007_*.sql`, `server/src/books.rs` (or new
`server/src/shelves.rs`, `physical.rs`), `server/src/lib.rs` (routes),
`server/tests/schema_parity.rs`, `app/lib/data/database.dart`,
`app/lib/server/server_client.dart`, `app/lib/server/sync_service.dart`.

**Tests.** `api.rs` RBAC coverage for the new endpoints (a viewer can read a
shared book's copies but not edit them); `sync_service_test.dart` round-trips a
shelf with ordering, a copy, and an open→returned loan; `e2e_sync.sh` grows a
shelf assertion.

**Commits:** `Both: sync custom shelves`, `Both: sync physical copies`,
`Both: sync loan history`

### 5. Cross-device reading position, without putting it on the book row

**Effort M · app + server · server schema change (new table only)**

**Problem.** §0.6. Reading state is deliberately off the LWW clock — the fix in
plan 2 §A1 that stopped "opening a book" from clobbering console edits. That
decision is right and must stand. But once the phone and the desktop hold the
same book, "resume where I left off" across devices is the most obvious missing
convenience, and the current design has no seam for it.

**Change.** A **separate, additive, per-device** channel — never part of the
book upsert:

```sql
-- server, new table; NOT in schema_parity (it has no app-table counterpart)
CREATE TABLE reading_progress (
  book_id    TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
  user_id    TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
  device_id  TEXT NOT NULL,          -- opaque, app-generated, stable per install
  progress   REAL,                   -- 0..1
  page       INTEGER,
  scroll     REAL,                   -- EPUB in-chapter fraction (see #23)
  updated_at TEXT NOT NULL,
  PRIMARY KEY (book_id, user_id, device_id)
);
```

- `GET /api/reading-progress?cursor=` / `PUT /api/reading-progress/{book_id}`.
- Per-`(user, device)` rows mean **no conflict resolution at all**: each device
  writes only its own row and reads the others. The app shows "You were on
  page 214 on *desktop* — jump there?" rather than silently overwriting local
  position. That prompt is the feature; a silent merge would be worse.
- **Opt-in** (Preferences → "Sync reading position"), default **off**, because it
  publishes reading behaviour to the server — a privacy change from today's
  guarantee. Document it in `DESIGN.md` next to the app-local-only list, which
  should now read "reading state is app-local; an *optional*, separate
  per-device channel can mirror position — see #5".
- The app stores `deviceId` (a UUID) in `SharedPreferences` on first run and a
  human label (hostname / device model) for the prompt.
- `readerNotes` and `sourceMetadata` **stay local, always** — no channel, no
  opt-in. They are personal and per-import respectively.

**Files.** new `server/migrations/0008_reading_progress.sql`, new
`server/src/reading.rs`, `server/src/lib.rs`, `app/lib/settings/app_settings.dart`,
`app/lib/server/sync_service.dart`, `app/lib/book_detail/read_button.dart`
(the "jump there?" prompt).

**Tests.** `api.rs`: device A's row is invisible in device B's write path and
visible in its read; two devices never conflict. App: a unit test that the
prompt appears only when the remote row is strictly ahead.

**Commit:** `Both: optional cross-device reading position`

### 6. Version the API and add a capability handshake

**Effort S · server + app · no schema change**

**Problem.** §0.13. `/api/books` has already changed shape twice (the
`{server_now, books}` envelope, the enriched `authors[]`/`file_count`), each time
guarded by an ad-hoc "does the client send `cursor`?" heuristic. #3 and #4 add
more shape changes. With Android shipping, app and server versions will genuinely
drift — a phone that hasn't updated in three months will talk to a rebuilt
server.

**Change.**

1. Add `GET /api/capabilities` (unauthenticated, cacheable):
   ```json
   { "server_version": "0.5.0", "sync_protocol": 2,
     "features": ["delta_pull", "shelf_sync", "reading_progress",
                  "content_search", "mail"] }
   ```
   Build it from `env!("CARGO_PKG_VERSION")` and compile-time/config flags (mail
   is on only when SMTP is configured — the app can then show or hide "Forgot
   password?" honestly).
2. The app fetches it once per connect, caches it on `ServerConnection`, and
   **feature-gates** optional sync phases instead of catching 404s. When
   `sync_protocol` is newer than the app knows, show one clear line: "This server
   is newer than the app — update Vellum to sync everything."
3. Mount the existing routes **also** under `/api/v1/*` (a `Router::nest` with
   the same handlers, zero duplication), make the app prefer `/api/v1`, and keep
   the unprefixed paths as a permanent alias for OPDS readers and existing public
   links. Document that unprefixed = v1 forever.

**Files.** `server/src/lib.rs`, new `server/src/capabilities.rs`,
`app/lib/server/server_client.dart`, `app/lib/server/connection_store.dart`,
`app/lib/server/server_page.dart` (show server version on the connected card).

**Tests.** `api.rs`: capabilities shape; a v1-prefixed and an unprefixed call are
equivalent. App: `server_client` test that an unknown feature disables its phase.

**Commit:** `Both: /api/capabilities + /api/v1 alias`

### 7. Push in batches; stop paying a round-trip per book

**Effort M · server + app · no schema change**

**Problem.** Push is one `PUT /api/books/{id}` per dirty book. First sync of a
1,000-book library is 1,000 sequential HTTPS requests (blobs are already
parallelised at 4; metadata is not). Over a LAN that's tolerable; over a VPN with
80 ms RTT it is ~80 s of pure latency before a single byte of PDF moves.

**Change.** Add `POST /api/books:batch` taking `{ books: [BookUpsert, …] }`
(cap at, say, 200 per request via the existing per-route body limit) and
returning per-item results:

```json
{ "results": [ {"id": "…", "status": "updated"},
               {"id": "…", "status": "skipped_older"},
               {"id": "…", "status": "error", "message": "…"} ] }
```

- Apply each item with **exactly** the existing `upsert` logic (extract the
  per-book body of `books::upsert` into a function both call) so LWW semantics
  and the no-op skip are shared, not re-implemented.
- Wrap each batch in one transaction? **No** — one failing row would roll back
  199 good ones. Per-item, best-effort, with the results array; that matches the
  existing `SyncIssue` model.
- App side: chunk dirty books, map each `error` to a `SyncIssue`, clear
  `needsPush` only for `updated`/`skipped_older`. Feature-gate on
  `capabilities.features` containing `batch_upsert` (#6), falling back to
  per-book PUTs.

**Files.** `server/src/books.rs`, `server/src/lib.rs`,
`app/lib/server/server_client.dart`, `app/lib/server/sync_service.dart`.

**Tests.** `api.rs`: mixed batch (new / older / malformed) yields the right
per-item statuses and does not abort; `sync_service_test.dart`: chunking,
issue mapping, and the fallback path.

**Commit:** `Both: batch book upsert on push`

### 8. Live updates via Server-Sent Events

**Effort M · server + app · no schema change**

**Problem.** `DESIGN.md` lists "real-time updates" as the last piece of the sync
roadmap. Today the app learns about console edits at the next launch or manual
sync; two devices editing in the same session see stale data.

**Change.** **SSE, not WebSocket** — one-way server→client is all this needs, it
rides plain HTTP/1.1 through every reverse proxy without an upgrade dance, it
reconnects natively with `Last-Event-ID`, and axum has `Sse`/`KeepAlive` built
in. WebSocket would add a second protocol for no gain.

- `GET /api/events` (authenticated, `text/event-stream`): emits small
  invalidation hints, **not** data —
  `event: book\ndata: {"id":"…","op":"upsert","at":"…"}`. Keep-alive comment
  every 20 s.
- Fan-out with a `tokio::sync::broadcast` channel in `AppState`; every mutating
  handler publishes after commit. Filter per subscriber through the existing
  `access.rs` visibility check — **never** broadcast an id a user can't see.
- The app treats an event as "run a delta pull soon": debounce 2–5 s, coalesce,
  and reuse `SyncService`'s re-entrancy guard. **No new merge logic** — the event
  only triggers the existing pull, so LWW stays the single conflict model.
- Bounded and disposable: drop the connection on backpressure; the app falls
  back to launch/manual sync. Offline must stay a non-event (local-first).
- The console can subscribe too, so two browser tabs stay consistent.

**Files.** new `server/src/events.rs`, `server/src/lib.rs` (route + broadcast in
state), the mutating handlers, `app/lib/server/sync_service.dart` (a
`LiveSyncTrigger` alongside `AutoPusher`), `server/web/console.js`.

**Tests.** `api.rs`: a subscriber receives an event for a visible book and
**not** for an invisible one; the stream survives a keep-alive interval. App:
debounce/coalesce unit test with a fake event source.

**Commit:** `Both: live sync hints over SSE`

### 9. Content-addressed blob store

**Effort M · server (+ app) · server schema change (path column semantics)**

**Problem.** §0.16. Blobs are named by row id, so the same EPUB attached to two
books (or owned by two users) is stored twice, and a re-upload of identical bytes
writes a new file. `book_file.sha256` is already computed and stored — the
dedupe key exists and is unused.

**Change.** Store book files at `files/<sha256[0:2]>/<sha256>.<ext>` and covers at
`covers/<sha256[0:2]>/<sha256>.<ext>`:

- On upload: hash to a temp file, then **rename into place only if absent**
  (`link`/`rename` is atomic on the same filesystem; an existing target means the
  bytes are already there — discard the temp).
- `book_file.path` keeps storing the relative path, so nothing else changes; the
  traversal guard from H1 (`is_safe_rel`) still applies and now guards a
  hex-only name (tighten it to `^[0-9a-f]{2}/[0-9a-f]{64}\.[a-z0-9]+$`).
- **Deletion becomes refcounted**: only unlink when no other `book_file`
  (or `book.cover_path`) references that path. Add that check to the delete
  path and to the orphan sweep (#12).
- Migration `0009_content_addressed_blobs.sql` can't move files (SQL can't),
  so do it in Rust at startup: a one-shot **backfill** that rehashes existing
  blobs, moves them, and updates `path` — idempotent, logged, and skipped when a
  marker row in a tiny `meta(key,value)` table says it ran.
- The app's local store can follow the same scheme later; it is **not** required
  for the server win, so keep it a separate optional commit (the app already
  dedupes downloads by hash on pull).

**Files.** `server/src/blobs.rs`, `server/src/books.rs` (delete path), new
migration, a `blob_migrate` function called from `main.rs`.

**Tests.** `api.rs`: uploading identical bytes twice yields one file on disk and
two rows; deleting one book keeps the other's file; the startup backfill is
idempotent (run it twice in a test with a seeded old-layout dir).

**Commit:** `server: content-addressed, refcounted blob store`

### 10. Split `LibraryRepository` (plan 2 §28, finally)

**Effort M · app · no schema change**

**Problem.** §0.7 — 945 lines, ~45 public members, five unrelated concerns. Every
feature in §C–§E adds to it. It is also the reason `library_repository_test.dart`
is the app's biggest test file: nothing can be tested in isolation.

**Change.** Keep `LibraryRepository` as a **thin facade** (so no call site
changes in one big commit) that delegates to focused collaborators, each in its
own file, each independently constructible in tests:

| New class | Owns |
|---|---|
| `BookWriteService` | create/update/delete book, authors, genres, `needsPush`, tombstones, `revertToDefault` |
| `CoverService` | cover bytes/file/embedded/first-page, dominant colour, backfill |
| `FileService` | attach/detach files, hashing, page count, format sniffing |
| `PhysicalService` | copies, loans (and stays the seam for #4) |
| `ShelfService` | shelves + membership + ordering |
| `LibraryQueries` | the read/watch side, including #1's view-model and #2's search |

Move code, don't rewrite it: the diff should be almost pure relocation plus
constructor plumbing. Do it in **two commits** (queries out first, then writes)
so review is tractable, and do it **before** §C — otherwise every feature there
lands in the god object first and has to be moved twice.

**Files.** `app/lib/data/` (new files), `app/lib/data/library_repository.dart`
shrinks to delegation.

**Tests.** Split `library_repository_test.dart` along the same lines; the
existing assertions should survive verbatim.

**Commit:** `App: split LibraryRepository into focused services`

---

## §B. Reliability & data safety

### 11. A "library doctor" that finds and repairs inconsistencies

**Effort M · app · no schema change**

**Problem.** The library is a database *plus* a file tree, and they can diverge:
a `book_files.path` whose file was deleted by hand or lost in a partial restore,
a `cover_path` pointing at nothing (the shelf then draws a generated spine and
quietly hides the loss), blobs in `files/`/`covers/` no rows reference (dead
bytes after failed imports), `book_placements` referencing copies whose book is
gone, `local_deletions` for ids the server already forgot. Nothing detects any of
this, and there is no way for a user to answer "is my library intact?".

**Change.** Preferences → **Library health**: a scan producing a categorised
report, each category with a safe action.

| Check | Action offered |
|---|---|
| Row points at a missing file | Re-download (if connected) · detach the file row · keep and mark |
| Row points at a missing cover | Re-render from PDF first page · re-download · clear `cover_path` |
| Blob with no referencing row | Delete (show reclaimed bytes) |
| Placement whose copy/book is gone | Remove the placement |
| Duplicate file rows with the same sha256 on one book | Collapse to one |
| `local_deletions` older than N days with no server | Prune |

Rules: **read-only by default**, every destructive action confirmed and reported
by count, and the scan must be cancellable and run off the UI isolate
(`compute`) since it stats every blob. Reuse it as a post-restore verification
step (restore currently trusts the archive).

**Files.** new `app/lib/data/library_doctor.dart`,
`app/lib/settings/preferences_page.dart`, reuse `backup_service.dart`'s path
helpers.

**Tests.** new `library_doctor_test.dart` over a temp data dir: seed each defect,
assert detection, assert the repair fixes it and touches nothing else.

**Commit:** `App: library health check with guided repairs`

### 12. Server-side integrity sweep + snapshot endpoint

**Effort S · server · no schema change**

**Problem.** The server has the same divergence risk with none of the tooling,
and `DESIGN.md`'s backup advice ("back up the `.db` and the data dir together,
mind the WAL sidecars") is a manual ritual that a user will get wrong exactly
once.

**Change.**

1. **Sweep** (master-only `POST /api/admin/sweep`, plus once at startup behind
   `VELLUM_SWEEP_ON_START=1`): report rows with missing blobs and blobs with no
   rows; delete orphan blobs only when explicitly asked
   (`?delete_orphans=true`). Composes with #9's refcounting.
2. **Snapshot** (master-only `GET /api/admin/snapshot`): stream a `.tar` of
   `VACUUM INTO`-produced database copy + the data dir. `VACUUM INTO` gives a
   consistent single-file copy **without** touching the live WAL — exactly the
   footgun the docs warn about. Document `curl -O` + a cron line as the
   supported backup story, and note the response can be large (stream it, don't
   buffer).
3. `GET /api/admin/stats`: counts (books, files, users, bytes on disk), for the
   console's dashboard (#37).

**Files.** new `server/src/admin.rs`, `server/src/lib.rs`, `README.md`
(deployment/backup section), `DESIGN.md` (Deployment).

**Tests.** `api.rs`: non-master gets 403; sweep detects a seeded orphan and does
not delete it without the flag; snapshot returns a restorable archive (open the
extracted db and count rows).

**Commit:** `server: integrity sweep, stats, and snapshot endpoints`

### 13. Backups: scheduled, rotated, verifiable, optionally encrypted

**Effort M · app · no schema change**

**Problem.** `BackupService` exports on demand to one `.zip`. There is no
schedule, no rotation, no integrity check, and no encryption — yet the archive
contains the whole library including personal reader notes, and on Android it now
travels through the share sheet to wherever the user taps.

**Change.**

1. **Manifest + verify.** Write a `manifest.json` into the archive (schema
   version, created-at, app version, counts, and each blob's sha256). Add
   *Verify backup* that re-reads an archive and checks every hash without
   restoring — the only way to know a backup is good before you need it.
2. **Scheduled backups** (desktop first): Preferences → daily/weekly, a target
   directory, keep-N rotation (delete oldest beyond N). Run on app start if the
   last one is older than the interval — no background service, no new platform
   surface, and it matches how a desktop app is actually used.
3. **Optional passphrase encryption.** Encrypt the archive with AES-GCM from a
   passphrase (Argon2id-derived key; `cryptography` package). Store nothing —
   lose the passphrase, lose the backup, and say so bluntly in the UI. Keep
   plain `.zip` the default so the format stays inspectable.
4. **Incremental.** With #1's manifest, a subsequent backup can hard-link/copy
   only changed blobs into a new archive and list the rest by hash if a previous
   archive is present in the same folder. **Defer** unless full backups actually
   hurt — measure a 20 GB library first, and if it does hurt, prefer "blobs in a
   sidecar folder + small db-only archives" over an incremental format.

**Files.** `app/lib/data/backup_service.dart`,
`app/lib/settings/preferences_page.dart`, `app/pubspec.yaml` (`cryptography`).

**Tests.** `backup_service_test.dart`: manifest round-trip, verify catches a
tampered blob, rotation keeps exactly N, encrypted round-trip, wrong passphrase
fails cleanly.

**Commit:** `Backup: manifest + verify, scheduled rotation, optional encryption`

### 14. Make file import transactional

**Effort S · app · no schema change**

**Problem.** `attachFile` copies bytes then inserts a row (and cover render /
page-count updates follow). A crash, a full disk, or a cancelled import between
those steps leaves either an orphan blob or a row pointing at a partial file.
Plan 2 §A8 swept `.part`/`.tmp-*` leftovers from *sync*; the local import path
has the same hole.

**Change.** Copy to `files/<id>.<fmt>.part`, `fsync`, rename into place, **then**
insert the row inside a drift transaction that also bumps `updatedAt` /
`needsPush`; on any failure, unlink the temp and roll back. Sweep stale `.part`
files at startup (the existing sweeper can take a second directory). Same shape
for `setCoverBytes`.

**Files.** `app/lib/data/library_repository.dart` (or `FileService` after #10).

**Tests.** `library_repository_test.dart`: inject a failure after the copy and
assert no row and no leftover file; assert an interrupted `.part` is swept.

**Commit:** `App: atomic file import (temp + rename + transaction)`

---

## §C. Features — library & cataloguing

### 15. Bulk folder import (with a watched folder)

**Effort L · app · no schema change**

**Problem.** §0.11. The app's on-ramp is one book at a time. Anyone arriving with
an existing 500-PDF folder — the actual target user — cannot get started. The
console has CSV import; the app has nothing.

**Change.** An **Import folder** wizard:

1. Pick a folder; recurse; collect `*.pdf` / `*.epub`; show the count.
2. **Dry-run table** before anything is written: per file, the parsed
   `Author - Title-Publisher (Year)` guess (that parser exists server-side —
   port it to Dart in `app/lib/data/metadata.dart` and share it), the proposed
   match from the online lookup, and a status: **new** · **duplicate (same
   sha256)** · **probable duplicate (same ISBN or title+author)** · **skip**.
   Rows are editable and individually deselectable.
3. Import with a **progress + cancel** UI; each file goes through the #14
   transactional path; failures collect into a per-file report, they don't abort
   the run.
4. Cap online lookups: 1 concurrent request with a small delay (Open Library is
   a free service, and a 500-book import must not look like abuse). Offer
   **"import now, fetch metadata later"** as the default for large folders,
   backed by a resumable background enrichment pass.
5. **Watched folder** (opt-in, desktop): remember the folder and offer to import
   new files on launch. Poll on launch only — no filesystem watcher, no
   background service.

**Files.** new `app/lib/import/` (`folder_import_page.dart`,
`import_plan.dart`, `filename_metadata.dart`), `app/lib/data/metadata.dart`,
`app/lib/settings/app_settings.dart` (watched folder).

**Tests.** `filename_metadata_test.dart` (a table of real-world file names —
port the server's cases); `import_plan_test.dart` (duplicate classification by
hash / ISBN / fuzzy title); a widget test for cancel mid-run.

**Commit:** `App: bulk folder import with a dry-run plan`

### 16. Barcode / ISBN scanning (finishes build-order item 6)

**Effort M · app · no schema change**

**Problem.** §0.10. `DESIGN.md` promises barcode scanning as the natural way to
catalogue physical books; it is the last unbuilt half of build-order item 6, and
it is *the* reason to have Vellum on a phone at all.

**Change.** `mobile_scanner` (actively maintained, MLKit/AVFoundation, no
Firebase). A **Scan** action next to the FAB on Android:

- Continuous mode: scan → validate EAN-13 checksum and the ISBN prefix
  (978/979) → look up → show a compact confirm card → **keep the camera live**
  for the next book. Cataloguing a shelf is dozens of scans; a modal per book
  makes it unusable.
- A running "added N" strip with undo; duplicates flagged inline against the
  existing library (reuse #15's classifier).
- Not found online → offer the existing custom-book form pre-filled with the
  ISBN.
- Camera permission: request at first use with an inline rationale, and a manual
  ISBN entry field as the permission-denied fallback (so the feature degrades
  instead of dead-ending).
- Desktop: a plain ISBN text field, same code path.

**Files.** new `app/lib/add_book/scan_page.dart`, `app/lib/data/metadata.dart`
(ISBN validation + lookup-by-ISBN), `android/app/src/main/AndroidManifest.xml`
(camera), `app/pubspec.yaml`.

**Tests.** `isbn_test.dart` (checksum, ISBN-10↔13, non-book EANs rejected);
widget test with a fake scanner stream for the add/undo/duplicate flow.

**Commit:** `App: scan ISBN barcodes to add books`

### 17. Series & volume tracking

**Effort M · app + server · both schemas**

**Problem.** A library of trilogies and long-running series currently sorts by
title, so *The Two Towers* sits nowhere near *The Fellowship of the Ring*. Series
membership is metadata Open Library often supplies and Vellum throws away.

**Change.**

```sql
-- server: 0010_series.sql   (synced → add to schema_parity.rs)
CREATE TABLE series (id TEXT PRIMARY KEY, name TEXT NOT NULL UNIQUE);
ALTER TABLE book ADD COLUMN series_id TEXT REFERENCES series(id);
ALTER TABLE book ADD COLUMN series_index REAL;   -- REAL so 1.5 (novellas) works
```

Mirror in drift (`Series` table + two `Books` columns, `schemaVersion` 9). Then:

- Parse series from Open Library/Google Books when present; expose
  Series/`#` fields in the edit sheet with autocomplete over existing series.
- `ShelfSort.series` orders by `(series name, series_index, title)`, with
  series-less books last.
- The detail page shows a **series strip** ("Book 2 of 5 — you have 1, 3, 4")
  which doubles as **gap detection**: the missing volumes are the most useful
  thing this feature can tell you, and it feeds #21's wishlist.
- Console: a Series column + inline edit + a bulk "set series" action.

**Files.** `app/lib/data/database.dart`, `app/lib/data/metadata.dart`,
`app/lib/book_detail/edit_book_sheet.dart`, `app/lib/settings/shelf_sort.dart`,
`app/lib/shelf/shelf_filter.dart`, `server/migrations/0010_series.sql`,
`server/src/books.rs`, `server/src/discover.rs`,
`server/tests/schema_parity.rs`, `server/web/console.js`.

**Tests.** parity test updated; sort test for series ordering; a metadata test
that a series-bearing search result populates both columns; migration test.

**Commit:** `Both: series and volume tracking`

### 18. Reading status, rating, and finish dates

**Effort M · app · app-local schema (see the note)**

**Problem.** Vellum knows what you *own* and how far into a book you are, but not
what you **want** to read, what you **abandoned**, or what you **thought** of it
— the organising principle of every reading app, and the input to #19's stats.

**Change.** Add to `books` (app-local, no server migration — see the note):

| Column | Meaning |
|---|---|
| `status` | `unread` · `reading` · `finished` · `abandoned` · `reference` (default `unread`; `reading` is derived-then-sticky once progress > 0) |
| `rating` | 1–5, nullable |
| `startedAt`, `finishedAt` | timestamps, nullable |
| `readCount` | integer, for re-reads |

- A status chip on the detail page and a **status facet** next to the genre
  filter; a Reading / Want to read / Finished set of default views.
- Auto-transitions with a manual override, and never a silent one: opening a
  book sets `reading`; reaching >98% offers "Mark as finished" rather than
  deciding for you.
- Rating shown as five taps on the detail page; sortable.

**Note on locality.** `status`/`rating` are *judgements*, not reading mechanics,
and users will expect them on every device — but making them synced columns means
a server migration, a `schema_parity` change, and putting them on the LWW clock.
**Recommendation:** land them **app-local first** (cheap, no protocol change),
and promote them to synced columns in the same batch as #4's schema work, where
one migration can carry several columns. Write the drift columns so the promotion
is additive.

**Files.** `app/lib/data/database.dart`, `app/lib/data/library_repository.dart`,
`app/lib/book_detail/book_detail_page.dart`, `app/lib/shelf/shelf_filter.dart`,
`app/lib/main.dart` (facet).

**Tests.** repository transitions (progress → `reading`, no auto-`finished`);
filter/sort by status and rating; migration test.

**Commit:** `App: reading status, ratings, and finish dates`

### 19. Reading stats & insights

**Effort M · app · app-local schema (new table)**

**Problem.** The app already knows every page turn (`saveReadingPosition` writes
on each one) and discards all of it except the latest position. That is a
free, private, genuinely fun feature being thrown away — and unlike a cloud
tracker, it never leaves the device.

**Change.** An app-local `reading_session` table:

```dart
class ReadingSessions extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text().references(Books, #id)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime()();
  IntColumn get startPage => integer().nullable()();
  IntColumn get endPage => integer().nullable()();
}
```

- The reader opens a session on entry and closes it on exit/background,
  **coalescing** gaps under ~2 minutes so a phone call doesn't fragment the
  record. Cap writes: one row per session, not per page turn.
- An **Insights** page: pages/day sparkline, current + longest streak, books
  finished per month, average pages per session, genre split of finished books,
  a heat-map calendar of reading days.
- Keep the charts hand-drawn with `CustomPaint` or a single small dependency —
  do **not** add a heavy charting package for six views; and follow the existing
  colour scheme rather than inventing a palette.
- **Local-only, permanently** — this is behavioural data. Add a "Clear reading
  history" button, and include the table in backups.

**Files.** `app/lib/data/database.dart`, new `app/lib/stats/` (`insights_page.dart`,
`stats_queries.dart`, `charts.dart`), `app/lib/reader/*` (session hooks),
`app/lib/app_drawer.dart`.

**Tests.** `stats_queries_test.dart` over a seeded session table (streaks across
DST and month boundaries, coalescing, empty-library case).

**Commit:** `App: reading sessions and an insights page`

### 20. Open-with / share-target import (carried: plan 4 §D14)

**Effort M · app (Android) · no schema change**

**Problem.** On a phone, a PDF in Files/Gmail/Telegram cannot be sent to Vellum —
the most natural mobile import path is missing.

**Change.** Intent filters for `VIEW` and `SEND`/`SEND_MULTIPLE` of
`application/pdf` and `application/epub+zip`; handle the incoming content URI
(`receive_sharing_intent`, or a small `MethodChannel` if the dependency isn't
worth it) by **copying the stream into the data dir first** (content URIs are
transient and may vanish before the import finishes), then routing into the
existing `_acceptFile` flow with the add-book confirm sheet. Handle both cold
start (initial intent) and warm resume (intent stream). Multi-file share should
feed #15's import plan.

**Files.** `android/app/src/main/AndroidManifest.xml`, new
`app/lib/import/incoming_share.dart`, `app/lib/main.dart`.

**Tests.** Unit-test the URI→file copy with a fake channel; manual device pass
for the two intent shapes (document the steps — CI can't do this).

**Commit:** `android: import a PDF/EPUB opened or shared from another app`

### 21. Wishlist, duplicate merge, and interop import

Three cataloguing conveniences that share the metadata/dedupe machinery from #15
and are cheap once it exists. Land as three commits.

**21a. Wishlist** — *Effort S · app.* Books you want but don't own: reuse the
`books` table with `status = 'wishlist'` (#18) and no file/copy, excluded from
the shelf by default, shown in its own view, fed by #17's series-gap detection
and by ISBN scans in a shop. Converting to owned = attach a file or a copy.
**Commit:** `App: wishlist for books you don't own yet`

**21b. Duplicate detection & merge** — *Effort M · app.* A library grown by bulk
import *will* contain duplicates. Detect by (1) identical file sha256, (2) equal
ISBN, (3) fuzzy title+author (normalised, token-sorted, edit-distance
threshold). Present pairs side by side and **merge**: keep one book row, move
files/copies/placements/shelf memberships/genres/authors across, prefer
non-empty fields (user picks per conflicting field), tombstone the loser so the
merge propagates. Merging is destructive — require confirmation, and log what
moved so it can be reasoned about after the fact.
**Commit:** `App: find and merge duplicate books`

**21c. Import from Calibre / CSV / OPDS** — *Effort M · app.* Three readers over
one import-plan pipeline (#15): a **Calibre** `metadata.db` (open read-only with
drift's `NativeDatabase` on a copy, read `books`/`authors`/`data`, resolve file
paths relative to the library root — a huge on-ramp for existing users), a
**CSV/JSON** file matching the console's export shape (so console export → app
import round-trips), and an **OPDS** catalog URL (browse another OPDS server —
including a second Vellum — and pull selected entries; the OPDS *client* is a
~200-line XML walk and makes Vellum a good citizen of the ecosystem it already
serves).
**Commit:** `App: import from Calibre, CSV, or an OPDS catalog`

---

## §D. Features — reading

### 22. Annotations: bookmarks, highlights, and notes

**Effort L · app · app-local schema (new table)**

**Problem.** `readerNotes` is one free-text field per book. There is no way to
mark a page, highlight a passage, or attach a thought to a location — the core
of reading non-fiction, and the reason people keep a second app around.

**Change.** One app-local table for all three, discriminated by kind:

```dart
class Annotations extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text().references(Books, #id)();
  TextColumn get kind => text()();       // 'bookmark' | 'highlight' | 'note'
  // Location, per format. PDF: page + optional normalised rect list.
  // EPUB: chapter index + a character offset range within the chapter's text.
  IntColumn get page => integer().nullable()();
  IntColumn get chapter => integer().nullable()();
  TextColumn get locator => text().nullable()();  // JSON: rects / offsets
  TextColumn get quotedText => text().nullable()();
  TextColumn get note => text().nullable()();
  IntColumn get color => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
}
```

- **PDF**: `pdfrx` exposes text selection; store the page plus normalised rects
  and re-draw them as an overlay.
- **EPUB**: the in-house parser gives chapter text; store `(chapter,
  startOffset, endOffset)` against the **extracted plain text**, which is stable
  as long as the parser is — write down that dependency, and version the locator
  JSON so a parser change can migrate instead of orphaning annotations. (Full
  EPUB CFI is the standards-correct answer and is disproportionate here.)
- An **annotations panel** per book (jump to, edit, delete) and a global
  "everything I highlighted" view.
- **Export to Markdown** per book or library-wide — a highlight nobody can get
  out of the app is a highlight held hostage.
- **Local-only** initially (like `readerNotes`). If they ever sync, they need
  their own table + endpoint, not the book row (same shape as #5).

**Files.** `app/lib/data/database.dart`, new `app/lib/reader/annotations/`
(`annotation_store.dart`, `annotation_layer.dart`, `annotations_panel.dart`,
`markdown_export.dart`), `reader_page.dart`, `epub_reader_page.dart`.

**Tests.** locator round-trip per format; export golden file; a migration test.

**Commit:** `App: bookmarks, highlights, and notes in the readers`

### 23. Reader comfort: typography, themes, navigation, in-book search

**Effort M · app · app-local settings only**

**Problem.** §0.8. The EPUB reader has no typography controls at all (fixed
font, size, measure, background) and resumes only to a chapter's top (plan 4
§E15, still open). The PDF reader has no TOC, no in-book search, no rotation, no
night mode. These are the difference between "renders books" and "readable for
two hours".

**Change.** One `ReaderSettings` (persisted, shared where it makes sense):

- **EPUB**: font family (bundled serif/sans/dyslexic-friendly), size, line
  height, max line length, margins, text align; themes light/sepia/grey/dark
  (sepia and dark are the ones people ask for); paged **or** scrolled mode; a
  TOC drawer from the OPF spine; **in-chapter scroll restore** — persist a scroll
  fraction in a new app-local column, restore it after first layout, and keep
  chapter index as the coarse anchor (plan 4 §E15 closed here).
- **PDF**: night mode (invert with white-point correction, not a naive
  invert — inverted photos look awful), fit width/page/two-page spread, rotation,
  page-thumbnail strip, **text search with result navigation** (`pdfrx` supports
  it), and a page-number jump field.
- **Both**: keep-screen-awake toggle, tap-zone or volume-key page turns on
  Android, brightness slider, and a distraction-free mode (hide chrome on tap).
- Respect system text scale: reader controls set the *book's* type, not the UI's.

**Files.** new `app/lib/reader/reader_settings.dart` + a settings sheet,
`reader_page.dart`, `epub_reader_page.dart`, `app/lib/data/database.dart`
(scroll fraction column).

**Tests.** settings persistence; a widget test that the chapter reopens at the
saved fraction; golden-ish test for theme application.

**Commit:** `Reader: typography, themes, TOC, search, and scroll restore`

### 24. Read-aloud (TTS)

**Effort M · app · no schema change**

**Problem.** No audio path. For long non-fiction, commuting, or a visual
impairment this is the difference between usable and not — and the EPUB parser
already produces exactly what a TTS engine needs: clean chapter text.

**Change.** `flutter_tts` over the current chapter's extracted text: play/pause,
speed, voice picker, sentence-level highlight synced to the utterance callback,
auto-advance to the next chapter, and a media notification on Android so it
survives the screen locking. **EPUB only** at first — PDF needs text extraction
with reading-order heuristics, which is a separate problem; say so in the UI
rather than shipping something that reads two-column papers as gibberish.

**Files.** new `app/lib/reader/tts_controller.dart`, `epub_reader_page.dart`,
`app/pubspec.yaml`.

**Tests.** sentence-splitting unit tests (abbreviations, quotes, footnote
markers); a fake TTS engine for the advance-on-finish logic.

**Commit:** `Reader: read a chapter aloud`

### 25. Home screen: continue reading, recently added, up next

**Effort S · app · no schema change**

**Problem.** The app opens on the full shelf, alphabetical. The two things a
returning user wants — the book they're mid-way through, and what they just added
— are indistinguishable from 900 others.

**Change.** A compact, dismissible **Library header** above the shelf (or a third
bottom-nav destination if it grows): *Continue reading* (up to 3, by
`lastReadAt`, each with a progress bar and a resume tap), *Recently added*, and
— once #18 lands — *Want to read*. It must be free to build: derive it from the
same `LibraryView` (#1), never a second set of queries, and let it collapse to
nothing on an empty library.

**Files.** new `app/lib/shelf/library_header.dart`, `app/lib/main.dart`.

**Tests.** widget test: header appears with in-progress books, hides when empty,
resume navigates to the right page.

**Commit:** `App: continue-reading and recently-added strip`

### 26. Desktop: command palette and keyboard shortcuts

**Effort S · app · no schema change**

**Problem.** The desktop app is mouse-driven. Nothing responds to `Ctrl+F`,
`Ctrl+N`, `Ctrl+,`; `Esc` works only in the physical editor. For a
keyboard-first audience on the primary target platform, that's friction on every
interaction.

**Change.** A `Shortcuts`/`Actions` map at the app root: `Ctrl/Cmd+F` focus
search, `Ctrl+N` add book, `Ctrl+I` import folder (#15), `Ctrl+,` preferences,
`Ctrl+B` toggle spine/cover face, `F5`/`Ctrl+R` sync, `Esc` clear
search/selection, arrows + Enter to move along the shelf and open a book. Plus a
**`Ctrl+K` command palette** listing every action and jumping to any book by
title — one widget that makes all of the above discoverable. Show shortcuts in
tooltips, and don't bind anything a text field needs.

**Files.** new `app/lib/shortcuts.dart`, new
`app/lib/shelf/command_palette.dart`, `app/lib/main.dart`.

**Tests.** widget tests sending key events for each binding; palette filtering.

**Commit:** `Desktop: keyboard shortcuts and a command palette`

---

## §E. Features — physical library & loans

### 27. Loans that actually chase people: due dates, reminders, contacts

**Effort M · app (+ server if #4 lands) · app-local schema (see note)**

**Problem.** A loan is `(borrower, loanedAt, returnedAt)`. There is no due date,
no reminder, no contact, and no way to see at a glance that your brother has had
your Pratchett for fourteen months. Lending is one of the two reasons the
physical side exists.

**Change.** Extend `loans` with `dueAt`, `notes`, `reminderSentAt`, and an
optional `borrowerContact` (free text, or a contact-picker id later):

- Lend sheet gains a due date (with sensible presets: 2 weeks / 1 month / no
  date) and optional contact.
- The loans overview sorts by due date and badges **overdue** ones; the book's
  spine gets a subtle "on loan" marker on the shelf (an overlay in `SpineFace`,
  behind a preference so it can't spoil the shelf aesthetic).
- **Local notifications** (`flutter_local_notifications`) a day before and on the
  due date, opt-in, scheduled locally — no server, no push, and therefore no new
  privacy surface. Cancel on return.
- A **share/copy** action producing "You borrowed *Title* on <date>, due <date>"
  for a message.
- A per-borrower history view ("what has Ana had, and did she return it?").

**Note.** If #4 Option A lands, `loan` becomes a synced table and these columns
need a server migration + parity update in the same commit. If it doesn't, they
are app-local. **Decide #4 first** — this is exactly the kind of column that is
painful to promote later. *Rev 2:* #49's borrow requests create rows in this
same table on approval — land these columns first so an approved request can
carry a due date from day one.

**Files.** `app/lib/data/database.dart`, `app/lib/book_detail/lend_sheet.dart`,
`app/lib/loans/loans_page.dart`, new `app/lib/loans/reminders.dart`,
`app/lib/shelf/shelf_view.dart` (badge), `app/pubspec.yaml`.

**Tests.** overdue computation across time zones; reminder scheduling/cancelling
with a fake notification plugin; migration test.

**Commit:** `Loans: due dates, overdue badges, and reminders`

### 28. Find a physical book (and print labels for the shelf)

**Effort M · app · no schema change**

**Problem.** The physical view is a lovely map with no "you are here". Search
finds a book on the *digital* shelf; nothing answers "which shelf is my copy
on?" — the question the feature exists to answer. And a real shelf has no
labels tying it back to the app.

**Change.**

- **Locate**: from a book's detail page, *Find my copy* → opens the environment,
  pans/zooms to the placement, and pulses it. In the physical view, a search
  field filters placed books and dims the rest.
- **Room search across environments**: "in which library is this?" when several
  rooms exist, with the environment named in the result.
- **Shelf labels**: generate a printable sheet (PDF via `pdf` package, or an
  HTML page for the system print dialog) of shelf labels — name, environment,
  and optionally a QR code that deep-links back into the app (`vellum://shelf/<id>`)
  so scanning a physical shelf opens its layout.
- **Snapshot**: export the current environment as a PNG (`RepaintBoundary` →
  `toImage`) to share or print — a picture of your library is a thing people
  want to show.
- **Tidy**: select a shelf's books and auto-arrange by author/title/series (#17),
  using the existing settle geometry rather than new packing logic.

**Files.** `app/lib/physical/environment_editor_page.dart`,
`app/lib/physical/layout_repository.dart`, new
`app/lib/physical/locate.dart`, new `app/lib/physical/labels.dart`,
`app/lib/book_detail/physical_copies_section.dart`.

**Tests.** locate resolves book → copy → placement → environment (including the
several-placements case); tidy produces a stable, non-overlapping order
(reuse `settle_test.dart` helpers).

**Commit:** `Physical: find a copy, tidy a shelf, print labels`

### 29. Room realism: backdrops, furniture, and measurements

**Effort M · app · app-local schema (small)**

**Problem.** An environment is line-segment shelves floating in space. Making it
*look* like your room is what turns a diagram into something you'd open for fun,
and the model was explicitly designed to be extended this way.

**Change.**

- **Backdrop image** per environment (a photo of the wall) with an opacity slider
  and a two-point **scale calibration** (mark a known length, e.g. a door), so
  shelves can be traced over the photo at true scale. New columns on
  `physical_environments`: `backdropPath`, `backdropOpacity`, `backdropScale`,
  `backdropOffsetX/Y` — app-local, no server migration.
- **Furniture / boxes**: reuse `physical_shelves` with a `kind` column
  (`shelf` | `panel` | `label` | `divider`) rather than a new table — a bookcase
  side panel is geometrically a shelf that books don't rest on.
- **Measure tool**: drag to read a distance in cm; a ruler along the axes; snap
  to 1 cm and to other shelves' ends.
- **Fill estimate** per shelf: "42 cm of 90 cm used" from the same
  `physical_metrics` curve — the genuinely practical number when you're deciding
  whether a new book fits.

**Files.** `app/lib/data/database.dart`, `app/lib/physical/room_painter.dart`,
`app/lib/physical/environment_editor_page.dart`,
`app/lib/physical/shelf_dialogs.dart`, `app/lib/physical/physical_metrics.dart`.

**Tests.** calibration maths (pixels ↔ metres), fill estimate against a seeded
shelf, migration test.

**Commit:** `Physical: room backdrop, furniture, and measurements`

### 30. Physical inventory mode (stocktake)

**Effort S · app · no schema change**

**Problem.** The model is explicitly "reference, not inventory" (a fresh
`physical_copy` per placement) — a good decision for a visual tool. But there is
no way to walk a shelf and confirm what is actually there, which is when a
library manager earns its keep.

**Change.** A **stocktake** session over one shelf or environment: list its
placements, tick each book you physically find (or scan its barcode — #16),
then report **missing** (placed but not found) and **unplaced** (found but not on
this shelf). Result is a list plus optional actions (remove placement, move
here, mark lent). Keep the semantics unchanged: this reconciles the *map*
against reality, it does not become an inventory system.

**Files.** new `app/lib/physical/stocktake_page.dart`,
`app/lib/physical/layout_repository.dart`.

**Tests.** reconciliation set maths (found/missing/extra) over a seeded
environment.

**Commit:** `Physical: stocktake a shelf against its placements`

---

## §F. Features — server & console

### 31. Transactional email → password reset & invites (carried: plan 4 §G19)

**Effort L · server (+ app) · server schema change**

Carried **unchanged** from plan 4 §G19; restated here so this plan is
self-contained. Order matters:

1. **SMTP plumbing.** Opt-in mailer configured by env
   (`VELLUM_SMTP_HOST/PORT/USER/PASS`, `VELLUM_MAIL_FROM`), **disabled by
   default** so the LAN/local-first story is unchanged. `lettre` (async,
   STARTTLS over `rustls`, reusing the existing ring provider). Health-check the
   config at boot and log clearly when mail is off. Document Gmail via
   `smtp.gmail.com:587` + an **App Password** (needs 2FA; not the account
   password). Surface `"mail"` in #6's capabilities so the app can hide "Forgot
   password?" when mail is off.
   **Commit:** `server: opt-in SMTP mailer`
2. **Password reset.** `POST /api/auth/forgot` mints a single-use, short-TTL
   token (store only its hash, like sessions), emails
   `${PUBLIC_URL}/reset/<tok>`; `POST /api/auth/reset` consumes it and writes a
   new Argon2 hash. **Always** answer "if that email exists, a link was sent"
   (no account-existence oracle) and throttle per email **and** per IP with the
   existing limiter. A minimal `reset.html` in `web/`.
   **Commit:** `server+app: password reset by email`
3. **Invites.** Master-only `POST /api/invites` (scope like a share) mints a
   token and emails a join link; the app/console redeems it to register the
   member and apply the grant. Reuses the token pattern above.
   **Commit:** `server+app: emailed member invites`

**Notes.** Email is a new outbound-network and secret surface: strictly opt-in,
never log credentials or tokens, env-only config. New tables
(`password_reset`, `invite`) are **server-only** — not in `schema_parity.rs`.

### 32. Server-side full-text search of book contents

**Effort L · server (+ app) · server schema change (new tables)**

**Problem.** With a few hundred PDFs on the server, "which book mentions
Levenshtein?" is unanswerable. This is the one capability a server can offer
that a local-first app genuinely cannot do well (indexing gigabytes of PDFs on a
phone), so it is the strongest argument for connected mode.

**Change.**

```sql
-- server-only; not synced
CREATE TABLE book_text (
  file_id    TEXT PRIMARY KEY REFERENCES book_file(id) ON DELETE CASCADE,
  book_id    TEXT NOT NULL REFERENCES book(id) ON DELETE CASCADE,
  pages      INTEGER,
  extracted_at TEXT NOT NULL,
  status     TEXT NOT NULL          -- 'ok' | 'no_text' | 'failed' | 'skipped'
);
CREATE VIRTUAL TABLE book_text_fts USING fts5(
  body, page UNINDEXED, file_id UNINDEXED, tokenize='unicode61 remove_diacritics 2'
);
```

- **Extraction.** EPUB text comes free (it's a zip of XHTML — pure Rust). PDF
  text: try `lopdf` first; fall back to `pdftotext`/`mutool draw -F txt`
  **through the existing sandboxed shell-out** from L6 (timeout, `setrlimit`,
  bounded by `render_semaphore`) — do not add a second, weaker shell-out path.
  Record `status='no_text'` for scanned PDFs; **no OCR** (a tesseract dependency
  contradicts the single-binary rule — note it as explicitly out of scope).
- **When.** A background queue on upload, plus master-only
  `POST /api/admin/reindex`. Never on the request path — extraction of a 900-page
  PDF must not hold an upload open. Store per-page rows so hits can name a page.
- **API.** `GET /api/search?q=…&limit=…` → snippets with book id, page, and
  `snippet()` highlight, RBAC-filtered exactly like `/api/books`.
- **App.** When connected and `content_search` is advertised (#6), the shelf
  search offers a second tab, "In book contents", with per-hit "open at page N"
  jumping straight into the reader. Local search (#2) stays the default so the
  feature degrades to nothing offline.
- **Cost.** Say plainly in the docs that the index is roughly text-size and can
  be dropped and rebuilt; make it opt-in per server (`VELLUM_INDEX_TEXT=1`).

**Files.** new `server/src/text_index.rs`, new migration, `server/src/blobs.rs`
(enqueue on upload), `server/src/lib.rs`, `server/web/console.js`,
`app/lib/server/server_client.dart`, app search UI.

**Tests.** extraction of a fixture EPUB and a text PDF; a scanned PDF records
`no_text`; search results are RBAC-filtered; reindex is idempotent.

**Commit:** `server: full-text search over book contents`

### 33. Read in the browser

**Effort L · server/console · no schema change**

**Problem.** The console can manage and download but not read, so a machine
without Vellum installed can't use the library. This is also what makes a shared
link genuinely useful — "here's a link to the chapter" beats "here's a 40 MB
download".

**Change.** A `/read/{book_id}` page in the console (and, optionally, for
`share_link` tokens — with a **read-only, non-downloadable** mode as the point of
the distinction):

- **EPUB**: server extracts the spine and serves per-chapter sanitised XHTML
  (reuse #32's extraction); the page renders it with the console's own CSS. No
  new JS dependency.
- **PDF**: needs a renderer in the browser. The **CSP is `default-src 'self'`
  and the server must stay a single binary**, so a CDN copy of pdf.js is out —
  vendor pdf.js into `server/web/vendor/` and `include_str!`/`include_bytes!` it
  like the other assets, accepting ~1 MB of binary growth, **or** render pages
  server-side to images through the existing sandboxed shell-out and serve them
  as a paged view (no new JS, slower, and it works everywhere). Recommend
  **starting with server-rendered pages** for share links, and vendoring pdf.js
  only if browser reading becomes a real workflow.
- Remember position in `localStorage` (per browser); do not touch #5's channel.

**Files.** `server/web/` (new `read.html`, `read.js`), `server/src/web.rs`,
`server/src/blobs.rs`.

**Tests.** `api.rs`: chapter endpoint is access-checked; a `max_uses` share link
isn't consumed by reading (decide and document: reading a link should probably
**not** burn a one-time *download*).

**Commit:** `server: read EPUBs (and share links) in the browser`

### 34. OPDS: search, facets, and OPDS 2.0

**Effort S · server · no schema change**

**Problem.** `/opds` is a flat acquisition feed. Every real e-reader client
expects **search** (an OpenSearch description) and some navigation structure; a
1,000-book flat feed is unusable on a Kobo.

**Change.** Add a navigation root (By author / By genre / By group / Recent /
All), an OpenSearch descriptor at `/opds/search.xml` with
`/opds/search?q=`, paging via `rel="next"` links, `thumbnail` links pointing at
the cached cover thumbnails already implemented, and `<updated>`/ETag so clients
can cache. Optionally serve **OPDS 2.0 JSON** at `/opds/v2` behind content
negotiation (cheap: the same aggregation, different serialisation) — and once
#32 exists, wire OPDS search to it for full-text results.

**Files.** `server/src/opds.rs`, `server/src/lib.rs`.

**Tests.** `api.rs`: feed validates against the OPDS relations we claim; search
honours RBAC; paging links round-trip.

**Commit:** `server: OPDS search, navigation feeds, and paging`

### 35. Console: scale, saved views, and an activity log

**Effort M · console (+ server) · no schema change (audit table optional)**

**Problem.** The console is the primary management surface and loads the entire
library into the DOM (§0.4). It also has no memory of how you like to look at
the library, and no record of what changed — with several members editing, "who
deleted that book?" has no answer.

**Change.**

- **Server-side paging** on top of #3, with a virtualised (windowed) table body
  so 10k rows scroll at 60 fps; move search/sort/filter to query params so the
  server does the work.
- **Saved views**: name a filter+column+sort combination, keep them in
  `localStorage` (server-side later if wanted), one click to switch.
- **Bulk progress**: *Fetch metadata* over 500 books needs a progress bar,
  per-item results, and a cancel — today it's a spinner and hope.
- **Activity log**: an optional server-only `audit` table (actor, action, target,
  timestamp) written by mutating handlers, shown as a console page and filtered
  per user. Cheap insurance for a shared library; keep it opt-in
  (`VELLUM_AUDIT=1`) and bounded (rotate beyond N rows).
- **Token hygiene** (§0.12): keep the bearer token in memory + `sessionStorage`
  rather than `localStorage` so a stolen-XSS token dies with the tab; the CSP
  already blocks the obvious exfiltration paths, so this is defence in depth,
  not a fix for a known hole.

**Files.** `server/web/console.js`, `console.css`, `server/src/books.rs`, new
`server/src/audit.rs` + migration.

**Tests.** `api.rs`: paged/sorted/filtered queries; audit rows written for
create/update/delete and readable only by the master.

**Commit:** `console: server-side paging, saved views, activity log`

### 36. Deployment as a product: Docker, systemd, releases

**Effort M · ci + docs · no code change**

**Problem.** §0.15. "Self-hosted" currently means "install Rust and run
`cargo run`". No image, no unit file, no binary release — the single-static-binary
advantage is real and entirely unexploited, and every self-hoster's first
question ("is there a compose file?") has the answer "no".

**Change.**

1. **Multi-stage `Dockerfile`** (build with the Rust image, ship on
   `debian:stable-slim` — *not* scratch, because the optional PDF CLIs are the
   point of the fallback; install `poppler-utils` for `pdftoppm`/`pdftotext`).
   Non-root user, `VOLUME` for the data dir, `HEALTHCHECK` on `/health`.
2. **`docker-compose.yml`** with Vellum + Caddy doing automatic TLS, and
   `VELLUM_PUBLIC_URL` wired correctly — the deployment `DESIGN.md` already
   recommends, made copy-pasteable.
3. **systemd unit** (`packaging/vellum-server.service`) with
   `ProtectSystem=strict`, `NoNewPrivileges`, a dedicated user, and
   `ReadWritePaths` for the data dir.
4. **Release workflow**: on a tag, build Linux `x86_64`/`aarch64` (musl static
   where possible), Windows, macOS server binaries + the Android AAB/APKs +
   the Linux desktop bundle; attach to a GitHub Release with checksums. Add
   `--version`/`--help` to the server binary (it has neither).
5. **App packaging**: Flatpak manifest and/or AppImage for Linux desktop, MSIX
   for Windows — at least document the current `flutter build linux` +
   `install-dev.sh` story as the interim.
6. A **`docs/DEPLOYMENT.md`** consolidating the env-var table (currently spread
   across `DESIGN.md` and `README.md`), TLS options, backup (#12), and upgrade
   notes.

**Files.** new `Dockerfile`, `docker-compose.yml`, `packaging/`,
`.github/workflows/release.yml`, `docs/DEPLOYMENT.md`, `server/src/main.rs`.

**Tests.** CI builds the image and runs `/health` against it; the e2e script can
run against the container instead of a local `cargo run`.

**Commit:** `Deploy: Docker image, compose with TLS, systemd unit, releases`

### 37. Observability: request ids, spans, and a small dashboard

**Effort S · server · no schema change**

**Problem.** §0.14. When a sync misbehaves in the field, there is no way to
correlate the app's `SyncIssue` with a server log line; failures are opaque on
both sides.

**Change.** A `tower_http::trace::TraceLayer` with a per-request id (accept an
inbound `X-Request-Id`, else generate one, echo it back, and include it in
`AppError` responses so a user can paste it into an issue). Structured spans for
the interesting handlers (upload, pull, render, extract) with durations. A
`RUST_LOG`-documented default. `GET /api/admin/stats` (#12) plus a small
**console dashboard**: library counts, disk usage, recent errors, sync activity.
Skip Prometheus/OpenTelemetry unless asked — for a personal server, logs plus a
stats endpoint are the right size.

**Files.** `server/src/lib.rs`, `server/src/error.rs`, `server/src/main.rs`,
`server/web/console.js`, `server/Cargo.toml`.

**Tests.** `api.rs`: an inbound request id is echoed; an error body carries it.

**Commit:** `server: request ids, tracing spans, stats dashboard`

---

## §G. Platform & polish

### 38. Localization scaffolding

**Effort M · app · no schema change**

**Problem.** §0.9. Every string is an inline English literal across ~50 files.
Retrofitting i18n after another 20 features is materially harder than doing it
now, and Android distribution makes it a real request.

**Change.** Add `flutter_localizations` + `gen_l10n`, an `l10n.yaml`, and
`lib/l10n/app_en.arb` as the template. Migrate **incrementally**: convert one
feature area per commit (start with the shelf and the add-book flow), and add a
lint-ish CI grep that fails on new raw user-facing `Text('…')` in migrated
directories only. Use ICU plurals/dates properly (`intl`) — the app currently
hand-builds strings like `'$n issue${n == 1 ? '' : 's'}'`, which no other
language survives. Ship English only at first; the scaffolding is the deliverable.

**Files.** `app/pubspec.yaml`, `l10n.yaml`, `app/lib/l10n/`, then per-area.

**Tests.** a widget test pumping `locale: Locale('en')` and asserting a looked-up
string; CI runs `flutter gen-l10n` and fails on drift.

**Commit:** `App: localization scaffolding (en)`

### 39. Theming: seed colour, shelf materials, spine typography

**Effort S · app · no schema change**

**Problem.** The theme is one hardcoded leather-brown seed
(`main.dart:61`) with light/dark following the system. The app's whole identity is
visual, and the user can change the wallpaper but not the app.

**Change.** Preferences → **Appearance**: theme mode (system/light/dark) —
currently not user-selectable at all; a seed-colour picker with a few curated
presets (leather, ink, forest, slate) plus custom; optional Material You dynamic
colour on Android (`dynamic_color`); shelf material (wood tones, metal, glass —
extending the existing wallpaper mechanism); and spine typography (a couple of
bundled display faces, plus a title-size/spine-width nudge). Keep every choice in
`AppSettingsStore` and make sure the spine palette (`spine_style.dart`) derives
from the active scheme rather than assuming brown.

**Files.** `app/lib/settings/preferences_page.dart`,
`app/lib/settings/app_settings.dart`, `app/lib/main.dart`,
`app/lib/shelf/spine_style.dart`, `app/lib/settings/wallpaper.dart`.

**Tests.** settings persistence; a golden test of a spine under two seeds.

**Commit:** `App: appearance settings — theme, seed colour, shelf material`

### 40. Android: background sync, quick actions, and a widget

**Effort M · app (Android) · no schema change**

**Problem.** Sync happens at launch and on a debounce while the app is open. On a
phone that means the library is stale whenever you actually pick it up, and
nothing brings you back into it.

**Change.** `workmanager` periodic sync (default off, **Wi-Fi + charging only**,
with a manual "sync now"); app shortcuts (long-press the launcher icon → Scan a
book, Continue reading, Add book); a home-screen widget showing the
continue-reading book with its cover and progress. Keep every one of these
optional and silent on failure — a local-first app must never nag about being
offline. Battery-conscious defaults are the whole design here.

**Files.** `app/lib/server/background_sync.dart`, Android manifest +
`shortcuts.xml`, a widget provider (Kotlin) + `home_widget`, `app/pubspec.yaml`.

**Tests.** unit-test the scheduling policy (constraints, backoff); manual device
pass for the widget.

**Commit:** `android: optional background sync, shortcuts, and a widget`

### 41. Onboarding and empty states

**Effort S · app · no schema change**

**Problem.** First run is an empty shelf and an "Add book" FAB. Nothing tells a
new user that they can import a folder, scan a barcode, connect a server, or
build a room — the four things that make the app worth having.

**Change.** A three-card first-run flow (skippable, never modal-blocking):
*Import your books* (folder / scan / one at a time) → *Connect a server?*
(optional, "you can skip this forever") → *Set up a room?*. Then better empty
states everywhere: the physical tab, loans, shelves and search each get one line
of what-to-do-next copy and a primary action, matching the shelf's existing
empty state (`main.dart:443–465`), which is the model to copy.

**Files.** new `app/lib/onboarding/`, `app/lib/main.dart`,
`app/lib/physical/physical_libraries_page.dart`, `app/lib/loans/loans_page.dart`.

**Tests.** widget test: shown once, dismissible, not shown again; each empty
state renders its action.

**Commit:** `App: first-run onboarding and better empty states`

### 42. Accessibility, round two

**Effort S · app · no schema change**

**Problem.** Plan 4 §B landed spine/cover semantics, icon labels and 48 dp
targets. Not yet done: focus traversal order (plan 4 §6 was only partly
addressed), the physical canvas is a `CustomPaint` with no accessible
representation at all, and no screen-reader pass has been run on the readers or
the sharing screens.

**Change.** `FocusTraversalGroup`/`FocusOrder` for the two-pane detail page and
the physical toolbar; a **semantic list alternative** for the physical canvas
("Shelf 2: 14 books — <titles>") since a drag-and-drop canvas can never be
directly navigable; announce sync progress and completion via
`SemanticsService.announce`; a large-text pass over the reader settings and
sharing pages; and document a manual TalkBack/Orca checklist in
`docs/ACCESSIBILITY.md` so this doesn't drift again.

**Files.** `app/lib/book_detail/book_detail_page.dart`,
`app/lib/physical/environment_editor_page.dart`, `app/lib/server/server_page.dart`,
`app/lib/reader/*`, new `docs/ACCESSIBILITY.md`.

**Tests.** extend `a11y_semantics_test.dart`: focus order, canvas alternative
present, announcements fire.

**Commit:** `A11y: focus order, canvas alternative, sync announcements`

---

## §H. Testing & tooling

### 43. Migration tests from every historical schema version

**Effort S · app · no schema change**

**Problem.** `migration_test.dart` covers some paths, and `onUpgrade` is
carefully idempotent, but there is no test that a **v1** database still opens at
v8 — and that is exactly the upgrade an early user will perform. Drift ships the
tooling for this and it isn't wired up.

**Change.** `dart run drift_dev schema dump` a snapshot per version into
`app/test/drift_schemas/`, generate the step-by-step verifier
(`drift_dev schema generate`), and add a test that migrates v1→N, v2→N, … and
runs `validateDatabaseSchema`. Include **data** fixtures for the interesting
ones: v7→v8 (the genre-merge data migration) and any future data migration.

**Files.** `app/test/migration_test.dart`, `app/test/drift_schemas/`, `ci.yml`.

**Commit:** `App: verified migrations from every schema version`

### 44. Property/fuzz tests for the sync state machine

**Effort M · app + server · no schema change**

**Problem.** LWW + tombstones + `needsPush` + a server cursor is a state machine
with a lot of interleavings, tested today by example. The failure mode of a bug
here is **silent data loss** — the one class of bug this project can least
afford.

**Change.** A model-based test: a fake server (`server_client` interface) plus a
generated sequence of operations (local edit, remote edit, local delete, remote
delete, pull, push, offline gap, clock skew, interrupted transfer) checked
against a reference model implementing the intended semantics. Shrink failures to
a minimal trace. Plus a **round-trip fuzz** of the DTO layer (arbitrary book →
JSON → server → pull → book) asserting nothing is lost or mangled, which also
guards the app-local-only columns from accidentally becoming synced.

**Files.** new `app/test/sync_model_test.dart`, a `FakeServer` test double.

**Commit:** `App: model-based tests for the sync state machine`

### 45. Performance harness and a synthetic large library

**Effort S · app + ci · no schema change**

**Problem.** Plan 4 §F18 bounded the cover backfill, but "does the shelf stay at
60 fps with 5,000 books?" is still answered by intuition. There is no seeded
large library to test any of §A against.

**Change.** A `scripts/seed_library.dart` generating N books with covers of
realistic sizes, authors, genres, shelves and placements; a documented profiling
recipe (`flutter run --profile` + timeline capture) with target numbers (frame
build < 8 ms, first shelf paint < 500 ms at 5k books); and a CI job that runs the
data-layer benchmarks (query timings, not frame times) and fails on a large
regression. Do this **before** #1/#2 so their benefit is measurable rather than
asserted.

**Files.** new `scripts/seed_library.dart`, new
`app/test/benchmark/library_bench.dart`, `docs/PERFORMANCE.md`, `ci.yml`.

**Commit:** `Tooling: synthetic library seeder and query benchmarks`

### 46. Server test depth: RBAC matrix and `sqlx` compile-time checks

**Effort M · server · no schema change**

**Problem.** `api.rs` covers happy paths and the fixed vulnerabilities. Access
control — the security-critical part — is not covered as a **matrix**, and every
query is a runtime `query_as` string, so a typo or a schema drift is a 500 at
run time rather than a compile error.

**Change.**

1. A table-driven RBAC test: {master, owner, editor-share, viewer-share,
   group-share, unrelated user, anonymous} × {read, list, edit, delete, cover,
   file, group, share, link} → expected status. One table, one loop; every future
   endpoint adds a row. This is the highest-value test in the repo.
2. Adopt `sqlx::query!`/`query_as!` with **offline mode** (`cargo sqlx prepare`,
   commit `.sqlx/`, CI checks it's current) so queries are verified against the
   schema at compile time. Migrate incrementally, module by module; it also makes
   #4's new tables safer to add.

**Files.** `server/tests/api.rs`, new `server/tests/rbac.rs`, `server/src/*.rs`,
`.sqlx/`, `ci.yml`.

**Commits:** `server: RBAC matrix test`, `server: compile-checked queries (sqlx offline)`

---

## §K. The physical library goes online (added in rev 2)

Today the three layout tables (`physical_environments`, `physical_shelves`,
`book_placements`) are app-local **by design** — `DESIGN.md` says "none of this
touches the server or sync; it's a per-device view of a real room". Rev 2
deliberately revises that: a room you spent an evening arranging should be able
to (a) travel to your other devices, and (b) be **shown to other people** —
"here is my library, this is where everything is" — with access managed like
everything else on the server. When #47 lands, amend `DESIGN.md`'s
"Local-only" paragraph and the ground-rules list accordingly.

**The model: publish a document, don't sync rows.** Two candidate designs were
considered:

- *Row-level LWW sync* of the three tables, like books. Rejected: a canvas
  edited concurrently on two devices produces row-interleaved nonsense under
  LWW (half of one arrangement, half of another, books floating mid-air —
  per-row merge is semantically wrong for a spatial layout even though it is
  right for independent book records). It also drags three more tables into the
  cursor/tombstone machinery for no benefit, since a layout is edited as a
  whole.
- ***Whole-document publish/fetch*** with a revision counter — **chosen**. An
  environment serialises to one JSON document; *Publish* uploads it, *Update*
  fetches it; a stale publish is detected (not merged) and the user picks
  overwrite-or-refresh. This matches how people actually treat a room
  arrangement (one person rearranges, then shows the result), keeps the
  local-first editing loop untouched, adds **no new conflict semantics** (§J's
  no-merge rule extends naturally: document-level last-publish-wins with an
  explicit prompt), and gives the "public library" story through the existing
  share machinery.

Dependencies: **#4 Option A** (synced `physical_copy`, and `loan` for #49) and
ideally **#6** (capabilities flag `layouts`) first.

### 47. Publish & fetch physical layouts

**Effort L · app + server · server schema (new table) + app-local columns**

**Problem.** A layout lives and dies on one device: rebuild the room on the
desktop and the phone never sees it; reinstall and it's gone (backup aside); and
there is no way to show anyone your library's arrangement at all.

**Change.**

1. **Document format.** `layout_doc` v1 (versioned JSON, written down in
   `docs/`): environment meta (name), `shelves[]` (endpoints + label + kind),
   `placements[]` (`copy_id`, `book_id`, `x`, `y`, `rotation`, and the
   **resolved** width/height in metres). Geometry only — **no book metadata**
   (no titles, authors, covers) inside the doc, so the document itself can never
   leak more than rectangle positions; viewers resolve books through RBAC (#48).
   Dimensions are baked in at publish time so a viewer without the book's page
   count still renders a to-scale room.
2. **Server.**
   ```sql
   -- 00XX_layouts.sql — server-only; NOT in schema_parity (document store,
   -- not a mirrored app table)
   CREATE TABLE layout (
     id           TEXT PRIMARY KEY,      -- the environment's UUID, app-minted
     owner_id     TEXT NOT NULL REFERENCES app_user(id) ON DELETE CASCADE,
     name         TEXT NOT NULL,
     revision     INTEGER NOT NULL,      -- bumps on every accepted publish
     doc          TEXT NOT NULL,         -- layout_doc JSON
     published_at TEXT NOT NULL
   );
   ```
   Endpoints: `GET /api/layouts` (mine + shared with me), `GET
   /api/layouts/{id}`, `PUT /api/layouts/{id}` carrying `base_revision` —
   **409 when `base_revision != revision`** (another device published in
   between), `DELETE /api/layouts/{id}` (owner only). Cap `doc` size (a room is
   a few hundred KB at most; reject megabytes).
3. **Sharing.** Extend `share.scope` with `'layout'` (`scope_id` = layout id),
   `viewer` only for now (`editor` would imply concurrent canvas editing —
   explicitly out of scope, see §J). The publish dialog offers **"also share
   this room's books"**, which creates/refreshes a book group `Room: <name>`
   containing the placed books and a viewer share of it — book visibility rides
   the **existing** group/share RBAC instead of a new leak path, and revoking is
   the normal share UI.
4. **App.** Two app-local columns on `physical_environments`
   (`serverRevision`, `needsPublish` — no server migration for these). The
   Physical libraries page gets per-environment **Publish** / **Update from
   server** actions with a dirty badge; fetch applies the doc in one
   transaction: upsert shelves/placements by id, delete local rows absent from
   the doc, and attach placements to the synced copies from #4A (minting a
   local copy only for a `copy_id` the pull hasn't delivered — same "reference,
   not inventory" semantics as today). On a 409: "This room was updated from
   another device — fetch theirs or overwrite?".
5. Feature-gate on `capabilities.features` containing `layouts` (#6).

**Files.** new `server/migrations/00XX_layouts.sql`, new
`server/src/layouts.rs`, `server/src/shares.rs` (scope), `server/src/lib.rs`,
new `app/lib/physical/layout_doc.dart` (serialise/apply),
`app/lib/physical/physical_libraries_page.dart`, `app/lib/data/database.dart`
(two app-local columns), `app/lib/server/server_client.dart`,
`docs/` (the doc-format spec).

**Tests.** doc round-trip (serialise → apply on a blank device → identical
geometry); 409 on stale revision; RBAC (a non-shared user can't fetch);
size cap; `sync`/publish re-entrancy (reuse `SyncService`'s guard).

**Commit:** `Both: publish and fetch physical room layouts`

### 48. Room viewer in the console + public room links

**Effort M · server/console · server schema (share_link kind)**

**Problem.** A published layout (#47) is only viewable by another Vellum app.
The people you'd most want to show a room to — family, a friend borrowing a
book, anyone with a browser — have nothing to look at, and the console can't
render the very thing the server now stores.

**Change.**

- A **read-only room view** in the console (`/room/{layout_id}`): render the doc
  as inline SVG — shelf lines and placement rectangles from the doc's geometry,
  spine fills from the cover thumbnails the server already caches for books the
  viewer can see, **neutral untitled spines for books they can't** (the doc
  carries no metadata to leak, so redaction is structural, not best-effort).
  Pan/zoom, hover for title, click through to the book detail when visible. No
  new JS dependency; it's rectangles.
- **Public room links**: add `kind TEXT NOT NULL DEFAULT 'book'` to
  `share_link` so a link can point at a layout; `/p/{token}` renders the same
  SVG view. Books show as anonymous spines **unless** the owner also ticked
  "share this room's books" (#47) — the public page then shows title/cover for
  exactly that group, nothing else. Expiry/revocation ride the existing link
  machinery unchanged.
- OPDS stays out of this; a room is not a feed.

**Files.** `server/src/web.rs`, new `server/web/room.js` (or inline in a
`room.html`), `server/src/shares.rs`, `server/migrations/00XX_link_kind.sql`,
`server/web/console.js` (a "View room" entry in a new Layouts list).

**Tests.** `api.rs`: redaction — a viewer sees geometry for every placement but
metadata only for RBAC-visible books; a public link with the group shared shows
titles, without it shows none; link expiry applies.

**Commit:** `console: rendered room view + public room links`

### 49. Borrow requests — closing the public-library loop

**Effort M · server + app + console · server schema (new table)**

**Problem.** Someone browsing your shared room (#48) can see the book they want
on your shelf — and then has to leave the app and text you. The lending
workflow the physical side exists for stops one step short of actually being a
library.

**Change.** A `borrow_request` table (server-only): requester, book (and
optionally the specific copy), status `pending → approved | declined |
cancelled`, a free-text note each way, timestamps. Flow:

- A signed-in user with visibility of a physical book (via any share) gets
  **Request to borrow** on the book/room view (console + app).
- The owner sees pending requests badged in the app's loans page and the
  console; **approve** pre-fills the existing lend sheet (borrower name from
  the requester's account, due date per #27) and creates the loan; **decline**
  sends the note back. The requester sees status changes on their next
  sync/visit — in-app only for now; email rides #31 later, gated on the same
  mailer.
- Anonymous public-link viewers do **not** get the button (no account to hold a
  request); the page says who to ask instead.
- Rate-limit per requester; owners can turn the feature off per share
  ("viewing only").

**Files.** new `server/migrations/00XX_borrow_requests.sql`, new
`server/src/borrow.rs`, `server/src/lib.rs`, `server/web/console.js`,
`app/lib/loans/loans_page.dart`, `app/lib/book_detail/lend_sheet.dart`,
`app/lib/server/server_client.dart`.

**Tests.** `api.rs`: request requires visibility; approve creates a loan and
closes the request atomically; a declined request can't be re-approved;
rate-limit. App: badge count and the approve→lend-sheet flow.

**Commit:** `Both: borrow requests on shared physical books`

### 50. One source of truth for a copy's location

**Effort S · app · no schema change**

**Problem.** `physical_copy.location` is free text ("living room, shelf 3")
written at add time, while a placement records where the copy *actually* sits
on the canvas. They drift apart the first time a book is dragged, and the
detail page shows the stale string.

**Change.** When a copy has a placement, **derive** its displayed location from
it — environment name + nearest shelf label ("Living room · Shelf 2") — shown
as a chip on the detail page that jumps into #28's locate view; keep the free
text only for unplaced copies (label it "location note"). Recompute on
placement change via the existing watch streams; don't write the derived string
back into the column (derived data stays derived — same rule as spine colours).

**Files.** `app/lib/book_detail/physical_copies_section.dart`,
`app/lib/physical/layout_repository.dart` (a `locationOf(copyId)` query).

**Tests.** derived location follows a placement move; unplaced copy falls back
to the note; deleted environment degrades gracefully.

**Commit:** `Physical: derive a copy's location from its placement`

### 51. Condition photos for physical copies

**Effort S · app · app-local schema (one table)**

**Problem.** `physical_copy.condition` is one word of free text. When a book
goes out on loan (#27) — or comes back — there is no record of what state it
was in, which is the thing you actually argue about.

**Change.** An app-local `copy_photos` table (`id`, `copyId`, `path`,
`takenAt`, `caption`); photos live in the data dir and ride backups. Camera or
picker from the copy's section on the detail page; the lend sheet offers an
optional "photograph before lending" step that attaches the shot to the loan's
start date. Local-only (photo blobs are exactly the sync weight #4A shouldn't
take on by accident); revisit only if asked.

**Files.** `app/lib/data/database.dart`, `app/lib/book_detail/physical_copies_section.dart`,
`app/lib/book_detail/lend_sheet.dart`, `app/pubspec.yaml` (`image_picker`).

**Tests.** migration; photo rows cascade with copy deletion; backup includes
the photo dir.

**Commit:** `Physical: condition photos on copies`

---

## §L. Rev-2 additions outside §K's theme

Two items that came out of the rev-2 pass but belong to other groups
thematically (§B and §D); numbered here to keep the numbering append-only.

### 52. Trash: a grace period before a delete is forever

**Effort M · app (+ server optional) · app-local schema (one column)**

**Problem.** Deleting a book is immediate and tombstoned — correct for sync,
brutal for a mis-click. The confirm dialog is the only guard, and #21b's merge
and the console's bulk delete both raise the stakes: one wrong selection
removes dozens of books, files included, with no way back but a backup restore.

**Change.** Soft-delete first: `deletedAt` (app-local column) marks a book as
trashed — hidden from every view and query (#1's view-model filters it once,
centrally), files kept, **no tombstone written yet**. A *Trash* screen under
Preferences lists trashed books with restore; a sweep (on launch) hard-deletes
anything trashed > 30 days, which is when the existing delete path — tombstone,
blob removal, `local_deletions` — actually runs. "Delete now" in the trash
skips the wait. Sync interplay is the one subtlety: a trashed book must **stop
pushing** (it's neither dirty nor deleted server-side until the grace expires)
— exactly the kind of interleaving #44's model test should cover. Console
parity (a server-side `deleted_at` + trash filter) is optional and can follow.

**Files.** `app/lib/data/database.dart`, `app/lib/data/library_repository.dart`
(or `BookWriteService` after #10), a small trash page,
`app/lib/server/sync_service.dart` (skip trashed in push).

**Tests.** trashed books vanish from views but keep files; restore round-trips;
the sweep tombstones and pushes the deletion; a trashed book never pushes.

**Commit:** `App: trash with a 30-day grace before permanent delete`

### 53. Send a book to an e-reader by email

**Effort S · server (+ app) · no schema change**

**Problem.** OPDS covers readers that can browse a catalog, but the most common
e-reader path is Amazon's send-to-Kindle email (Kobo and Pocketbook have the
same). Once #31's SMTP mailer exists, the server can deliver a book to a device
in one click — today the user downloads the file and forwards it by hand.

**Change.** `POST /api/books/{id}/send` `{ file_id, to }`: attaches the file
(EPUB — Kindle accepts EPUB since 2022; enforce the recipient-size cap and
surface the mailer's error cleanly), subject per the target service's
convention. Per-user saved destination addresses ("my Kindle") in a small
prefs blob; a **Send to device** action on the console detail view and the
app's book toolbar (visible only when `capabilities.features` has `mail`, #6).
Rate-limit like metadata search. Document the sender-allowlist step (Amazon
requires approving the from-address) in #31's mail docs.

**Files.** `server/src/mail.rs` (from #31), `server/src/books.rs` or a small
`send.rs`, `server/web/console.js`, `app/lib/book_detail/read_button.dart`
area, `docs/` (mail setup).

**Tests.** `api.rs` with a stub mailer: RBAC (only a visible book can be sent),
size cap, rate limit; the app hides the action without the `mail` capability.

**Commit:** `server+app: send a book to an e-reader by email`

---

## §I. Suggested sequencing

Five phases. Each is independently shippable and leaves the tree green.

**Phase 1 — foundations (do first).** #45 (measure before optimising) → #10
(split the repository) → #1 (view-model) → #2 (FTS search) → #3 (server list
scoping/paging) → #6 (API version + capabilities) → #43 (migration tests).
*Why first:* every feature phase is cheaper afterwards, and #6 is a prerequisite
for changing response shapes without breaking a phone in someone's pocket.

**Phase 2 — decide the sync boundary.** #4 (shelves/copies/loans — **Option A,
now required by §K**; still decide before #18 and #27, whose columns land
differently either way) → #5 (cross-device reading position) → #7 (batch push)
→ #44 (sync model tests).

**Phase 3 — the on-ramp (highest user value per hour).** #15 (folder import) →
#16 (barcode scanning) → #20 (share-target) → #21b (duplicate merge) → #25
(continue reading) → #41 (onboarding). *Why:* these are what make a new user's
first hour succeed, and #15/#16 finish the last unbuilt promise in
`DESIGN.md`'s build order.

**Phase 4 — depth.** #22 (annotations) → #23 (reader comfort, closes plan 4
§E15) → #18 (status/rating) → #19 (insights) → #17 (series) → #27 (loans with
due dates) → #28 (find a copy) → #50 (derived copy location) → #51 (condition
photos) → #11 (library doctor) → #13 (backup hardening).

**Phase 5 — server as a product.** #36 (Docker/systemd/releases) → #31 (SMTP →
reset → invites) → #32 (content search) → #35 (console scale) → #37
(observability) → #34 (OPDS) → #12 (sweep/snapshot) → #46 (RBAC matrix, sqlx
offline) → #33 (browser reading).

**Phase 6 — the physical library online (§K; needs #4A and #6 from Phase 2).**
#47 (publish/fetch layouts) → #48 (console room view + public room links) →
#49 (borrow requests — after #27 so approvals carry due dates).

**Interleave anywhere:** #14 (atomic import — small and strictly a fix), #26
(shortcuts), #39 (theming), #42 (a11y round two), #9 (content-addressed blobs),
#8 (SSE), #29/#30 (physical depth), #38 (l10n — earlier is cheaper), #40
(Android background), #52 (trash — best right after #10, before #21b raises the
delete stakes), #53 (send-to-e-reader — anytime after #31's mailer).

**If only one thing gets done:** #15 (bulk folder import). Everything else
improves a library the user already managed to enter; #15 is why they'd have one.

---

## §J. Out of scope / deliberately rejected

Written down so they don't get re-proposed:

- **Field-level merge / CRDTs.** Rejected July 2026 and reaffirmed here.
  Row-level LWW by `updated_at` with tombstones is the final conflict model for a
  personal library. #5 sidesteps it with per-device rows rather than merging, and
  that is the pattern for any future per-device data.
- **Row-level sync / concurrent editing of the physical canvas.** *(Rev 2.)*
  Considered for §K and rejected: per-row LWW on a spatial layout merges two
  arrangements into neither, and a collaborative canvas (editor shares on
  layouts, live cursors) is a different product. #47's whole-document publish
  with a revision check — stale publish prompts, never merges — is the final
  model; one arranger at a time is the intended use.
- **A hosted/SaaS Vellum.** Multi-tenant hosting changes the threat model, the
  backup story, and the licence conversation. Self-hosted only.
- **DRM, or any store integration.** Vellum manages files you have.
- **OCR on the server.** Tesseract or an ML model contradicts the
  single-static-binary rule; #32 records `no_text` for scanned PDFs and stops
  there. A user who needs OCR can run it before importing.
- **A second (native) mobile codebase.** One Flutter codebase, as per goals.
- **A state-management rewrite** (Riverpod/BLoC across the app). #1 and #10 get
  the actual benefit — one stream, testable services — without a framework
  migration. Revisit only if the widget tree genuinely becomes unmanageable.
- **A charting dependency** for #19. Six charts do not justify the weight;
  `CustomPaint` matches the app's hand-drawn aesthetic anyway.
- **Social features** (following, public profiles, shared reviews). The sharing
  model (accounts, groups, links) is deliberately as far as this goes.
- **Cloud metadata beyond Open Library / Google Books.** More sources means more
  keys, quotas, and terms; revisit only if match quality is measurably bad.
- **Per-field push of derived data** (dominant colour, thumbnails, extracted
  text). Derived data is recomputed where it's needed and never bumps the sync
  clock — an existing rule worth keeping explicit.
