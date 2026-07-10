# Improvement plan 3

Follow-up to [`IMPROVEMENT_PLAN_2.md`](IMPROVEMENT_PLAN_2.md) (all 30 tasks
landed) and the July 2026 feature round (one-tap sync + launch auto-sync,
backup/restore, dominant-colour spines behind a preference, EPUB reader, the
two big file splits). This plan is from a fresh review of the codebase as it
stands after that work. Same ground rules as before:

- Read `CLAUDE.md` and `DESIGN.md` first. Schema changes = drift
  `schemaVersion` bump + idempotent drift migration + **new** SQL migration
  (only when the column/table is synced!) + build_runner rerun + update
  `server/tests/schema_parity.rs` when a synced table changes. App-local-only
  columns (reading state, `readerNotes`, `sourceMetadata`, `needsPush`,
  `coverEtag`) get **no** server migration.
- After every task: `cargo test && cargo clippy --all-targets -- -D warnings`
  in `server/`, `flutter analyze && flutter test` in `app/`.
- One cohesive feature per commit, short title, optional succinct bullets,
  no Co-Authored-By.

**Standing decisions — do not revisit:** conflict handling stays row-level
LWW (field-level merge was rejected; see DESIGN.md); the Android build stays
deferred until desktop is polished.

Items are grouped by theme and ordered by severity within each group.
**§A is correctness — do those first**; the rest can be cherry-picked.

---

## A. Correctness & data safety

### 1. Restore leaves a stale sync cursor (missed rows on the next pull)

**Problem.** `BackupService.restoreFrom` swaps the database, but the delta-pull
cursor lives in SharedPreferences (`sync.cursor.<baseUrl>`,
`connection_store.dart:57-70`), not in the database. Restoring a backup older
than the last pull leaves a cursor *newer* than the restored library: the next
launch auto-sync does a delta pull from that cursor and permanently skips every
book the server changed between the backup and the cursor. The restored library
silently never converges.

**Change.** Thread the app's `ServerConnection` into `PreferencesPage` (the
drawer already holds it) and, after a successful `restoreFrom` and before
`exit(0)`, clear **all** sync cursors: add
`ServerConnection.clearAllSyncCursors()` that removes every prefs key starting
with `sync.cursor.` (`_prefs.getKeys().where(...)`). Clearing all (not just the
current URL's) covers restoring a backup made while connected to a different
server. Test: unit-test the new method over a fake `SharedPreferences`
(`SharedPreferences.setMockInitialValues`).

**Commit:** `App: clear sync cursors after a restore`

### 2. Restore can race the launch auto-sync

**Problem.** `_autoSync()` (`main.dart`) runs in the background from app start.
A user who opens Preferences and restores during it closes the drift database
under a live pull — the sync throws mid-transaction into the restore's
catch-all "restart now" dialog. Not data-destructive (the swap is rename-based)
but ugly and avoidable.

**Change.** Expose `bool get isRunning => _running;` on `SyncService`, thread
the shared instance into `PreferencesPage` (same plumbing as task 1), and have
the Restore tile refuse with a snackbar ("Wait for the sync to finish") while
`isRunning`. Export is fine concurrently (`VACUUM INTO` is a consistent
snapshot) — leave it enabled.

**Commit:** `App: block restore while a sync is running`

### 3. Concurrent-sync StateError surfaces as a raw error message

**Problem.** Pressing *Sync now* while the launch auto-sync is still running
throws `StateError` out of `SyncService.sync`, which `_run`
(`server_page.dart:56-84`) catches in its generic branch and renders as
"Could not reach the server.\nBad state: a sync is already in progress".
Misleading (the server is fine) and leaks an internal message.

**Change.** In `_run`, catch `StateError` before the generic catch and set
`_error = 'A sync is already running — try again in a moment.'` (or better:
disable the buttons while `widget.sync.isRunning`, using task 2's getter, and
keep the catch as a belt-and-braces fallback).

**Commit:** `App: friendly message when a sync is already running`

### 4. EPUB-only books never get a cover

**Problem.** Cover-from-file only handles PDFs: the app's
`setCoverFromFirstPage` filters `format.equals('pdf')`
(`library_repository.dart`), and the server's `render_first_page` shells out to
PDF CLIs only (`blobs.rs`). An EPUB, however, *declares* its cover in the OPF
manifest (EPUB3 `properties="cover-image"`, EPUB2 `<meta name="cover"
content="<id>"/>`), and extracting it is just a zip read — no renderer needed.

**Change.**
- App: add `EpubBook.coverImageBytes()` (or a static
  `epubCoverBytes(File)` that stops parsing after the OPF) in
  `reader/epub_book.dart`; in `attachFile`, when a cover-less book gets an
  `.epub`, call it and `setCoverBytes` on success. Extend
  `setCoverFromFirstPage` (or add a sibling used by the same call sites,
  including the sync pull's render-and-push-back step in
  `sync_service.dart`) to fall back to the EPUB cover when there's no PDF.
- Server: add the pure-Rust `zip` crate (single-binary constraint holds — no
  shell-out), and in the upload path where `render_first_page` runs for PDFs,
  extract the declared cover image for EPUBs and store it via the existing
  cover-write path (including the thumbnail invalidation `put_cover` does).
- Tests: app — extend `epub_book_test.dart`'s builder with a cover-image
  manifest entry and assert the bytes round-trip; server — upload a minimal
  EPUB fixture in `tests/api.rs` and assert `GET /books/{id}/cover` is 200.

**Commit:** `Both: extract the declared EPUB cover image`

---

## B. Product & UX

### 5. Custom shelves (the schema exists; the UI doesn't)

**Problem.** `Shelves` and `ShelfBooks` (`database.dart:118-135`, with
`sortOrder` columns) have been in the schema since v1, DESIGN.md's data model
documents them ("manual collections/panes, with explicit book ordering"), and
the README promises "organize into panes, collections" — but no repository
method or widget touches them except `deleteBook`'s cleanup. The shelf tab is
one alphabetical list.

**Change** (app-local feature — shelves are deliberately not synced; the
server's `book_group` is a separate concept):
- Repository: `watchShelves()`, `createShelf(name)`, `renameShelf`,
  `deleteShelf` (rows only — never the books), `addToShelf(bookId, shelfId)`
  (append `sortOrder`), `removeFromShelf`, `watchBooksOnShelf(shelfId)`
  (join ordered by `shelf_books.sortOrder`).
- Shelf tab: a horizontal `ChoiceChip` row above the shelf — **All** plus each
  shelf, ending in a **+ New shelf** chip; selection filters `ShelfView`'s
  books (keep the search filter composing on top). Long-press a chip →
  rename/delete.
- Detail page: an "Add to shelf…" action (menu on the app bar or a row under
  the genres) listing shelves with checkmarks, toggling membership.
- Persist the selected shelf in `AppSettingsStore` so the tab reopens where it
  was. Tests: repository CRUD + ordering in `library_repository_test.dart`.

**Commit:** `App: custom shelves — create, fill, and browse` (repository and
UI may be two commits)

### 6. Search misses authors; genre chips are dead ends

**Problem.** The shelf search filters title/subtitle only
(`main.dart:_filter`), so typing an author finds nothing — surprising in a
library app. The detail page renders genre chips (`book_detail_page.dart`) but
they're inert.

**Change.**
- Repository: a `watchBooksWithAuthors()` stream (one join query mapped to
  `Map<String, List<String>> authorsByBookId`, drift `.watch()` per CLAUDE.md)
  — or extend the existing stream's row type. `_filter` then also matches any
  author name.
- Genres: make detail-page chips tappable — pop back to the shelf with a genre
  filter applied (simplest: a `genre:` token in the existing search field, so
  state stays in one place and the search box shows what's filtering; matching
  needs the same map trick for genres).
- Tests: filter unit tests over an in-memory repo.

**Commit:** `App: search by author, filter by genre`

### 7. Shelf sort options

**Problem.** `watchAllBooks()` hard-codes `ORDER BY title`
(`database.dart:301-303`). No way to shelve by author or year.

**Change.** A sort preference in `AppSettingsStore` (`title` — default —
`author`, `year`), surfaced as a small `PopupMenuButton` next to the shelf
search field. Sorting by author reuses task 6's authors map (first author,
locale-insensitive compare, cover-less/author-less books last). Keep the
DB query as-is and sort in the widget layer — the list is already fully
materialized for packing, and it avoids three near-identical queries.
(*Recently added* would need a `created_at` column — synced, so schema on both
sides; leave it out unless it's wanted enough to pay that cost.)

**Commit:** `App: shelf sort — title, author, year`

### 8. Loans overview (the drawer has promised it for months)

**Problem.** The drawer shows two dead "Coming soon" tiles
(`app_drawer.dart:73-84`): *Physical books* and *Loans*. Loan data and history
already exist per-copy on the detail page; there's just no cross-library view
("what's lent out right now?").

**Change.** A `LoansPage` (drawer tile goes live): one query joining active
loans (`returned_at IS NULL`) → copy → book, listed as "title — borrower,
since date" with a *Return* button (reuse `repository.returnLoan`), and a
collapsed history section beneath. Drop the *Physical books* stub tile
entirely — the bottom-nav Physical tab already owns that space.

**Commit:** `App: loans overview page, drop the stale drawer stub`

### 9. EPUB reader: resume inside the chapter, parse off the UI thread

**Problem.** Two gaps from the v1 reader (`epub_reader_page.dart`):
(a) resume lands at the top of the saved chapter — in-chapter scroll is lost;
(b) `EpubBook.open` does `readAsBytes` + zip decode + base64 image inlining on
the UI isolate, so a large EPUB janks the open animation, and re-parses on
every open.

**Change.**
- (a) No schema change needed: keep `lastReadPage` = chapter, but store the
  *global* fraction in `readingProgress`:
  `(chapterIndex + scrollFraction) / chapterCount` where `scrollFraction` is
  `offset / maxScrollExtent` (0 when unscrollable). Save on a 500 ms-debounced
  scroll listener; on restore, jump to
  `(readingProgress * count - chapterIndex).clamp(0, 1) * maxScrollExtent`
  after the first layout (`WidgetsBinding.addPostFrameCallback`). The detail
  page's "% read" label keeps working unchanged.
- (b) Move parsing into `Isolate.run` (`EpubBook` holds only strings — freely
  sendable). Cache the parsed book in a small static LRU (`bookId → EpubBook`,
  keep ~2) so reopening is instant; invalidate in `attachFile`/`deleteBook`.
- Tests: fraction round-trip math; parser already covered.

**Commit:** `App: EPUB resume-in-chapter, parse in an isolate`

### 10. Physical editor: books ride an edited shelf; settle clamps to shelf ends

**Problem.** Both carried in BACKLOG.md. Dragging an occupied shelf is pinned
(good), but *Edit shelf…* can still move one out from under its books, leaving
them floating; and the overlap resolver can nudge a book past a shelf's end,
where it hangs in the air at shelf height (`settle.dart`).

**Change.**
- Riding: in `_editShelf` (`environment_editor_page.dart`), when the edit
  moves the shelf, translate every placement resting on it (reuse the
  `shelfHasBooks` support test per book, then `updatePlacement` by the same
  delta) before the gravity pass.
- Clamping: in `settle()`, when the chosen support is a shelf segment, clamp
  the resolved x so `[x, x+w]` stays within `[x1, x2]` (skip the clamp when
  the book is wider than the shelf); if the sideways nudge can't fit the book
  on that shelf, fall through to the next surface below rather than floating.
- Tests: extend `settle_test.dart` (clamp cases) and add a
  ride-on-edit repository-level test.

**Commit:** `App: books ride shelf edits, settle clamps to shelf ends`

### 11. Honour the spine-artwork preference in the physical view

**Problem.** DESIGN.md says a book "looks the same in both views", but the
physical editor always draws cover-slice spines — `_bookVisual`
(`environment_editor_page.dart`) builds `SpineFace` without `spineArt`.

**Change.** Thread `AppSettingsStore` (already loaded in `main.dart`) through
`PhysicalLibrariesTab` → `EnvironmentEditorPage`, pass
`spineArt: settings.spineArt` to both `SpineFace` call sites (static book +
drag overlay), and wrap the canvas in the same `ListenableBuilder` pattern the
shelf tab uses so a preference change repaints.

**Commit:** `App: physical view follows the spine-artwork preference`

---

## C. Performance

### 12. Don't deflate already-compressed blobs in backups

**Problem.** `BackupService.exportTo` adds every blob at the default deflate
level. PDFs, EPUBs (zips), and JPEG/PNG covers are already compressed — the
encoder burns CPU on a multi-GB `files/` directory for ~0% size win, making
big exports needlessly slow.

**Change.** `ZipFileEncoder.addFile` takes a compression level: pass
`ZipFileEncoder.STORE` for extensions in
`{pdf, epub, jpg, jpeg, png, gif, webp, zip}` and keep deflate for the SQLite
snapshot (which compresses well). Assert in the round-trip test that a stored
`.pdf` still restores byte-identical.

**Commit:** `App: store (don't recompress) blobs in backups`

### 13. Debounced background push after edits (keep the console fresh)

**Problem.** Since one-tap sync, pushes happen only at launch or on demand. A
desktop session that edits metadata all evening leaves the server/console
stale until the next morning's launch — and `needsPush` already tracks exactly
what's outstanding.

**Change.** A small `AutoPusher` owned next to the shared `SyncService` in
`main.dart`: listen to a drift watch of `SELECT COUNT(*) WHERE needs_push = 1`
(and on `local_deletions`), debounce 60 s after the last change, then if
connected and `!sync.isRunning` run `push` (push only — pulls stay
launch/manual so a background timer never overwrites local state). Swallow
failures quietly (`needsPush` keeps them queued; the next launch sync
retries). Make it a Preferences toggle (`AppSettingsStore`, default **on**,
"Push changes automatically while connected"). Tests: fake client counts one
push for a burst of three edits.

**Commit:** `App: debounced auto-push of dirty books`

---

## D. Testing & tooling

### 14. Widget smoke tests for the main flows

**Problem.** `app/test/` covers repositories, sync, and parsers, but not one
widget: a rendering regression in the shelf, detail page, or preferences
(three screens rebuilt heavily this round) ships silently.

**Change.** `test/widgets/` with `pumpWidget` smoke tests over an in-memory
repository (the `forTesting` seam exists): (a) shelf renders N spines and
search narrows them (pump past the 150 ms debounce), (b) tapping a spine
opens the detail page (title visible), (c) preferences shows the spine-art
control only in spine mode, (d) the server page shows *Sync now* when
connected (fake `ServerConnection` with a token). No goldens — just structure
— so they don't flake across platforms/fonts.

**Commit:** `App: widget smoke tests for shelf, detail, preferences`

### 15. CI: build the Linux desktop bundle

**Problem.** CI runs `flutter analyze` + `flutter test`, which compile no
native runner: a plugin/toolchain break (exactly what a new dependency like
`flutter_secure_storage` or a bad podspec-equivalent causes) lands green and
fails on the user's machine.

**Change.** Add a job (or a step after tests) to `.github/workflows/ci.yml`:
`sudo apt-get install -y ninja-build libgtk-3-dev libsecret-1-dev` then
`flutter build linux --debug` in `app/`, with pub + build caching so it stays
in single-digit minutes. Debug (not release) — it's a compile check, not an
artifact.

**Commit:** `CI: compile the Linux desktop bundle`

### 16. Extend the e2e smoke test to the combined sync

**Problem.** `test/e2e_sync_test.dart` exercises `pull` and `push` separately;
the one-tap `sync()` path (now what users and the launch hook actually run) is
only covered by fakes.

**Change.** Add one case to the e2e test (same `VELLUM_E2E_URL` gate): device
A edits + `sync()`, device B `sync()`, assert B sees the edit **and** B's own
dirty book arrived at A after A's next `sync()` — the full loop through the
real wire format in ~15 lines.

**Commit:** `CI: e2e coverage for one-tap sync`

---

## Deferred / explicitly out of scope (carried + new)

- **Android build & barcode scanning** — deliberate: desktop polish first.
- **Field-level merge** — rejected for good; row-level LWW is the model
  (DESIGN.md). Live updates (websocket/long-poll) remain the only open sync
  idea, and only if multi-device use becomes routine.
- **`created_at` sort ("recently added")** — needs a synced column on both
  schemas; do it only if task 7's three sorts feel insufficient.
- **Cover-slice texture for generated spines** (BACKLOG) — superseded in
  spirit by the dominant-colour preference; revisit on demand.
- **OPDS pagination + OpenSearch** — still waiting for a library big enough
  to need it.
- **Scheduled automatic backups** — manual export covers the risk for now;
  reconsider once task 12 makes big exports cheap.
