# Performance: seeding, benchmarking, profiling

Companion to [`IMPROVEMENT_PLAN_5.md`](IMPROVEMENT_PLAN_5.md) §A45. Written
before §A1/§A2 land, so the numbers below are the *baseline* the shelf's
current four-`StreamBuilder`/Dart-substring-scan design produces — re-measure
after each of those lands rather than trusting the target numbers alone.

## Data-layer benchmarks (CI)

`app/test/benchmark/library_bench.dart` seeds a 1,000-book in-memory library
(`seedLibrary`, see below; kept modest since §A2's triggers make seeding
itself expensive — see that finding below) and times the query paths §0 of
plan 5 calls out: `watchAllBooks()`, `watchAuthorsByBook()`,
`watchGenresByBook()`, `filterBooks()`/`sortBooks()` (one pass and a
20-rebuild burst), and `watchLibrary()` itself (20 fresh subscriptions, since
that's how `main.dart` actually calls it — see the §A1 finding below on why
that framing matters). Each step asserts a generous upper bound — a
regression guard against an accidental O(n²) or a dropped index, not a
frame-time target; CI runners are too variable to assert tight numbers.

**The "should visibly beat the burst number" framing from when this doc was
written (before §A1/§A2 landed) turned out to be wrong, and it's worth
saying so rather than quietly dropping it.** `watchLibrary()`'s 20-fresh-
subscription cost does **not** beat the old Dart burst at the sizes this
bench actually tests (1,000–8,000 books) — see the §A1 finding for the
numbers and why. The real win is elsewhere: no more 4x redundant rebuilds
per mutation, sub-linear (not linear) scaling as the library grows, and an
FTS5 index that doesn't degrade with library size the way a Dart substring
scan does. None of that shows up as "the burst number went down" in a
1,000-book benchmark.

Run it directly:

```sh
cd app && flutter test test/benchmark/library_bench.dart
```

## Seeding a synthetic library

`app/lib/data/seed_library.dart` generates deterministic, reasonably
realistic books/authors/genres/shelves (no covers, no physical layout — not
what §A's queries touch). It's a plain function over a `VellumDatabase`, used
by the benchmark above and by the on-disk tool below.

### Generating a large on-disk library for manual profiling

`database.dart` pulls in `drift_flutter`, which needs the Flutter engine's
`dart:ui` — so a seeding script can't run under plain `dart run` (it fails to
even compile outside a Flutter-hosted process). Instead it runs as a
`flutter test` file, skipped by default:

```sh
cd app
SEED_LIBRARY_COUNT=5000 flutter test test/tool/seed_library_tool.dart
# writes /tmp/vellum_seed/vellum.sqlite (override with SEED_LIBRARY_OUT)
```

To profile the real app against it: quit the app, back up your real
database, then copy the seeded file over it. The default location is
`<ApplicationDocumentsDirectory>/vellum.sqlite` (drift_flutter's
`driftDatabase(name: 'vellum')`) — **not** the app-support directory covers
and files live under (`LibraryRepository.open` uses a different
`path_provider` call for those). On Linux desktop, `getApplicationDocumentsDirectory`
resolves to the application-support directory, so the file is
`~/.local/share/app.vellum.Vellum/vellum.sqlite` — but XDG config can move
that, so if it's not there: `find ~ -maxdepth 3 -name vellum.sqlite`. Run the
app once first if the file doesn't exist yet. Restore your backup afterwards.

## Profiling recipe

```sh
cd app && flutter run --profile -d linux
```

Open DevTools' Performance view, record a timeline while scrolling the shelf
and typing a search query, and check against:

- Frame build time **< 8 ms** (keeps 120 Hz possible; well under the 16 ms
  budget for 60 Hz).
- First shelf paint **< 500 ms** at 5,000 books, cold start.

If either regresses, `library_bench.dart`'s per-query timings (printed even
when the test passes — run with `-r expanded`) usually point at which query
grew, before reaching for the profiler.

## The profiling run (before every release)

The recipe above needs someone at DevTools reading a timeline. This is the
same idea as a job: one command that seeds a large library, drives the real
app in profile mode through what people actually do, and writes numbers that
can be diffed against the last release's.

```sh
cd app
tool/perf_run.sh                      # Linux desktop: GUI scenarios + cold starts
tool/perf_run.sh --label before-fix   # name a run
tool/perf_run.sh --android            # the one connected device or emulator
tool/perf_run.sh --headless           # in Xephyr; see "the display" below
PERF_ONLY=shelf,room tool/perf_run.sh --only gui   # iterate on one area
tool/perf_run.sh diff ~/.cache/vellum-perf/runs/<a> ~/.cache/vellum-perf/runs/<b>
```

**What it seeds** (`lib/data/seed_profiling.dart`, cached per shape under
`~/.cache/vellum-perf/seed-<key>/`): 4,000 books, 65% with covers — a tenth
of those the 900 × 1,200 PNG page renders old PDF imports left, the rest
~130 KB JPEGs — half with a file (a real EPUB, or a one-page PDF), 4,000
reading sittings over three years with the last fortnight always read in,
2,000 highlights/notes/bookmarks, 700 physical copies, 150 loans (a quarter
still out), and a room of three bookcases holding 400 placed books. Statuses,
ratings, wishlist entries and a few books in the trash are mixed in; every
cover's dominant colour is already extracted, as the startup backfill leaves a
library that has been opened before. `PERF_BOOKS`, `PERF_SESSIONS`, ... change
the shape. Covers and files are symbolic links to a few dozen source files, so
a seeded library is ~35 MB on disk; the app reads through them like any file,
which makes every measurement a warm-page-cache one.

**What it measures.** `integration_test/perf_test.dart`, under
`flutter drive --profile`, against a fresh copy of the seeded library:

| Scenario | What happens |
|---|---|
| `startup` | the four loads, then the app, until a spine is on screen |
| `shelf_spines_cold/warm/hot` | 12,000 px of shelf at 2,000 px/s: no thumbnails yet, thumbnails but an empty image cache, everything decoded |
| `shelf_spines_colour` | the same with the dominant-colour spine artwork |
| `shelf_covers_cold/warm`, `shelf_list` | the other two shelf views |
| `book_detail_open` | tap a covered spine, the pull-out animation, the detail page |
| `search_typing` | four queries typed at ~11 characters a second |
| `insights_open/scroll/range` | Reading insights, scrolled through, every range chip tapped |
| `month_open/navigate` | the month page, four months back |
| `room_open/pan/zoom` | the furnished room, dragged and wheel-zoomed |
| `preferences_open/scroll` | Preferences |

Each gets wall-clock milliseconds (`shown_ms` until it is there, `settled_ms`
until frames stop), the engine's own frame timings (`FrameTiming`: frames,
`jank_frames` over the 16.7 ms budget, build and raster p50/p90/p99/max), the
image cache (peak while it ran, and after) and the resident set. A full
timeline per scenario is recorded too; with `PERF_KEEP_TIMELINES=1` it is kept
for Perfetto (ui.perfetto.dev). The timeline buffer is a ring, so for the long
scrolls it holds only the last frames — the frame numbers above come from
`FrameTiming`, which sees every frame.

**Cold start** is `integration_test/startup_probe.dart`, built as the app and
launched six times (the first a warm-up): process start to the first line of
Dart, to the first frame, to the first frame with a spine on it (built and
rasterised), and the resident set then and four seconds later.

**Where results go** — never into the repository:
`~/.cache/vellum-perf/runs/<date>-<commit>[-label]/summary.md` (tables),
`summary.json` (one flat `scenario.metric` map, what `diff` compares), plus
the raw `gui/metrics.json`, `startup.jsonl` and logs. `runs/latest` points at
the newest.

**Safety.** The app is pointed at the run's directory through
`XDG_DATA_HOME`/`XDG_CONFIG_HOME`, and both entry points refuse to start unless
`XDG_DATA_HOME` is a profiling directory — and refuse any library holding books
the seeder did not make — so the real library is never opened. The script
stops the app however it exits. On Android the test seeds the app's own
storage on first run (2,000 books), and refuses a device whose library holds
anything else.

**The display must be awake.** A compositor stops drawing a window it cannot
show: with the monitor asleep, frames arrive about once a second and every GUI
number is meaningless. The script refuses to start with the monitor off (a
locked screen with the monitor on is fine), and the report marks any scenario
that drew far fewer frames than its length allows, without those frames being
slow, as **starved — not valid**. `--headless` runs in Xephyr instead, which
needs no screen but renders with Mesa's llvmpipe: its raster times are the
CPU's, several times the GPU's, so use it to compare two builds, never to
quote raster numbers.

**What is in CI and what is not.** GUI timings swing ±25% between runs on the
same machine (a busy core, the GPU's clock) — too noisy for a pass/fail line,
so the profiling run is a manual step before a release, in
[`DEVELOPER.md`](../DEVELOPER.md#cutting-a-release). What CI gets is the cheap
deterministic part: `library_bench.dart` as before, the seeder's own test
(`seed_profiling_test.dart`, so a schema change cannot quietly break the run),
`flutter analyze` over `integration_test/`, and the benchmarks the fixes below
added, each with a generous budget.

## §A1 finding: keep reading-state writes cheap on the shelf stream

`saveReadingPosition`/`saveEpubPosition` write to `books` on every page turn,
and reading progress isn't part of what the shelf filters or sorts by — but
drift's stream invalidation is table-level, not column-level, so any `books`
write still invalidates a stream that reads that table. Measured on a
3,000-book library (`watchLibrary`, `LibraryQueries`):

| Design | Cost per `books`-table write |
|---|---|
| Old: `watchAllBooks()` re-emits, Dart `filterBooks`/`sortBooks` re-runs | ~3.4 ms |
| `watchLibrary` as one `customSelect` re-fetching authors/genres/shelves too | ~180 ms |
| `watchLibrary` as independently-invalidating streams (shipped) | ~28 ms |

The shipped version combines separate streams for the filtered/sorted books,
`watchAuthorsByBook`, `watchGenresByBook`, shelves, and `allGenres`
(`_combine6` in `library_queries.dart`) specifically so a reading-position
write only re-runs the books query, not the authors/genres joins. The
remaining ~28ms (vs. the old 3.4ms) is the SQL `ORDER BY` plus its
per-row correlated subqueries (author-sort, `hasFile`) over the whole scope,
inherent to filtering/sorting in SQL — bound this further only if a profile
run shows it actually costing frames on the reading path.

**Subscription churn on every rebuild — measured, then fixed.** `main.dart`
calls `watchLibrary(...)` fresh inside `build()`, so typing in the search box
(debounced 150ms) creates a brand-new combined stream each time. Before the
fix below, all six underlying queries re-ran on every subscribe, not just the
ones the changed parameter actually affects — on a 1,000-book library, 20
fresh subscriptions cost **~294ms** (worse than the ~40ms the old Dart burst
cost at the same size). `LibraryQueries` now caches the four
parameter-independent sources (`watchAuthorsByBook`, `watchGenresByBook`,
shelves, `allGenres`) behind `_Cached<T>` — subscribed once, lazily, kept
alive for the app's lifetime, replaying the last value to each new listener —
so a fresh `watchLibrary()` call only re-runs the one query that's actually
parameter-dependent. That brought 20 fresh subscriptions down to **~175ms**
at 1,000 books: real, but still short of the old path's ~40ms, because the
remaining cost is the filtered/sorted books query itself (SQL round-trip +
correlated subqueries for author-sort and `hasFile`), which must vary with
the query text and so can't be cached away. At 8,000 books the gap
*narrows*, not widens: old path ~318ms/20 (≈16ms/iteration, scaling roughly
linearly with library size, as a Dart scan would), new path ~954ms/20
(≈48ms/iteration, ≈3x the old cost per keystroke rather than 1,000-book's
≈4.4x) — sub-linear scaling against the old path's linear scaling. In real
usage the 150ms debounce means this is one query per pause in typing, not 20
back-to-back, so ~48ms even at 8,000 books is comfortably sub-frame and not
user-perceptible; the crossover point where the new path is *faster* in
absolute terms is somewhere past what a personal library realistically
reaches. Re-measure this if the library-size assumption changes materially
(e.g. #35's server-scale content search implies much larger n).

## §A2 finding: the FTS5 triggers cost write-path time, not read-path

`book_search`'s triggers fire on every `books`/`book_authors`/`book_genres`
insert, each running a correlated subquery to recompute the affected book's
`authors`/`genres` text. This shows up in `seedLibrary`'s own cost: seeding
3,000 books went from ~220ms to **~3.7s** once the triggers landed — a write-
path cost, invisible to `watchLibrary`'s read-path numbers above. Still well
inside the benchmark's budget (seeding isn't the thing under test there), but
worth knowing before #15 (bulk folder import): importing a few hundred books
one at a time will each pay this per-row trigger cost. If that turns out to
matter in practice, batch the author/genre link inserts per book inside one
transaction (already how `seedLibrary` and the repository's write paths
work) rather than reaching for a wholesale index-maintenance redesign first.

## 2026-08-02 round: three candidates measured, one kept

Prompted by "make the application run faster", with no particular slowness
reported. The first finding is the one worth leading with: **at the size a real
library actually reaches, the app is already fast**, and the profile says so.
Measured on the development machine, Linux desktop, `--profile`:

| | |
|---|---|
| Cold start to first frame | **146–183 ms** (five runs; that spread *is* the noise floor) |
| The four `main()` loads before `runApp` | 42–50 ms of it |
| `watchLibrary()`, 1,000 books, 20 fresh subscriptions | 148 ms (≈7 ms each) |
| The development library it was measured against | 87 books |

So there was no hot spot to remove, and the honest result of the round is three
candidate optimisations, of which **two were reverted for showing no measurable
gain**. They are written down because each one is plausible enough that someone
will suggest it again.

### Kept: memoised `SpineStyle.fromJson`

`fromJson` does a `jsonDecode` plus six hex parses, and is called from three
paths that re-decode the same unchanged strings every build: `ShelfView`'s row
packing (inside a `LayoutBuilder`, so every rebuild, over *every* book), each
visible spine drawing itself, and the physical room drawing every placed book
through `SpineFace`. It is now memoised on the stored JSON string — which is
also the cache key, so an edited book rewrites the string and misses the cache
by itself, and no invalidation is needed.

In isolation this is a large win: at 2,000 books a cold pass costs **8.8 ms**
and a warm rebuild **0.34 ms** — 7.6× cheaper than the 2.6 ms measured before
(`test/benchmark/spine_style_bench.dart`).

End to end on the shelf it is worth **1–3%** (`shelf_scroll_bench.dart`, 3,000
books: 735→713 ms first build, 85.2→84.1 ms per scroll step), because decoding
was never the dominant cost — building thirty-odd spine widgets per row is. It
was kept for being a strict improvement with a clear mechanism on a path the
physical room hits per frame, not because it transformed anything.

*One correctness trap, in case the cache is ever reworked:* the failure path
falls back to `generate(title:)`, whose result depends on the **title** rather
than on the string being decoded. Caching that under the JSON key hands every
book with the same corrupt style the first book's colours. Only successful
decodes go in the cache; `spine_style_test.dart` pins this.

### Reverted: parallelising the four `main()` loads

`LibraryRepository.open` (23 ms) and `ServerConnection.load` (13 ms, an OS
keychain read over D-Bus) look independent, so starting all three futures
together and awaiting them afterwards should have saved ~13 ms of a ~150 ms
start. It saves nothing:

| | |
|---|---|
| Sequential | 47, 50, 42 ms |
| Parallel | 50, 47, 48 ms |

They are platform-channel calls, and the platform thread services those
serially — Dart-level concurrency does not overlap work that is queued behind a
single channel. A first run *did* read 37 ms against a sequential 48 ms, which
looked like a win until it was repeated; one sample was noise.

### Reverted: `itemExtent` on the shelf's `ListView`

Every shelf row is exactly `175 + 14 + 26` px, so the list can take a fixed
`itemExtent` and compute scroll geometry arithmetically instead of measuring
rows. Measured at 3,000 books: 785→794 ms first build, 86.4→88.3 ms per scroll
step — no difference either way. `ListView.builder` already builds only the
visible rows, so the extent arithmetic it saves was never a meaningful share of
the frame, and the change adds a constant that silently clips the shelves if it
ever stops matching the row it describes.

### A benchmark that measures nothing looks exactly like a fast one

`shelf_scroll_bench.dart` first reported the spine cache as worth 0%. The books
it built had `spineStyle == null`, which takes `fromJson`'s null early-return —
the decode path under test never ran. Any benchmark over `Book` fixtures has to
set the fields whose handling it is timing; a flat result is a reason to check
the fixture before believing it.

## 2026-10 round: what the earlier benchmarks could not see

Every benchmark above seeds books with **no covers and no files** (`seedLibrary`
says so). That is exactly where this round's costs were — the checklist is in
[`BACKLOG.md`](BACKLOG.md#performance-round-october-2026). Measurements below
are on a copy of the development library (94 books, 25 MB of covers, 2.4 GB of
files) padded to 5,000 books with one file each.

### #1 Indexes on the app's foreign-key columns (schema v38)

The app schema had no secondary index at all — only the primary keys' implicit
ones. `EXPLAIN QUERY PLAN` on `watchLibrary`'s books query showed the
`has_file` subquery as `SCAN bf`: all of `book_files`, once per book. It runs on
every `books` write, and a page turn is a `books` write.

| `watchLibrary` books query, 5,000 books + 5,000 files | |
|---|---|
| Before | 396 ms |
| After (`idx_book_files_book` and friends) | 18 ms |

The same was true of every lookup by a foreign key — copies by book, loans by
copy, annotations and sittings by book, a room's shelves and placements. All
sixteen are declared with `@TableIndex`, so `createAll` builds them on a fresh
install and `_ensureIndexes` adds them on upgrade. `library_queries_test.dart`
pins the query plans, since a dropped index is otherwise invisible until a
library is big enough to feel it. App-local: the server has its own.

`watchDirtyCount` was checked too and left alone — 1 ms unindexed at 5,000.

### #2 WAL journal for the app database

The app used SQLite's default rollback journal, so every commit paid two fsyncs
— and a page turn is a commit (the reading position). The server has run WAL
from the start. 200 single-row position writes on the development disk (ext4,
NVMe):

| Journal | 200 writes | Per write |
|---|---|---|
| Rollback (`DELETE`) | 2,380–2,700 ms | ~12 ms |
| WAL + `synchronous = NORMAL` | 25–35 ms | ~0.15 ms |

Set in `DriftNativeOptions.setup`, so it applies on the database isolate every
time the file opens — including Android's background-sync isolate, which is the
one other writer and the reason for the `busy_timeout`. Backups were already
WAL-safe (`VACUUM INTO`, and a restore deletes the sidecars).
`database_location_test.dart` opens the real connection and pins all three
pragmas.

### #3 Cover thumbnails

Spines asked Flutter for the cover at decode height via `cacheHeight`, which
still reads and inflates the whole file first. A rendered PDF page was stored as
a 908×1200 PNG of up to 1.7 MB — eleven of them were 13 MB of the development
library's 25 MB of covers.

Now `CoverImage` (the provider behind every spine, face-out cover and placed
book in the room) reads `covers/thumbs/<id>-h<height>.jpg` when there is a
current one. On a miss it decodes the cover exactly as before and has the
thumbnail made in a background isolate, at most four at a time — so the first
look at a cold shelf costs what it always did, and every later one is cheaper.
A thumbnail is current while it is no older than its cover, and the cache key
carries the cover's modified time and size, so a rewritten cover can't be
served stale, whichever of the many cover-writing paths rewrote it.

All 92 covers of the development library decoded at 512 px (the 2× spine
bucket), Flutter's own codecs:

| | Bytes read | Decode, all 92 |
|---|---|---|
| Covers, `cacheHeight: 512` | 25.3 MB | 738–755 ms |
| Thumbnails | 4.7 MB | 201–219 ms |

Making all 92 thumbnails took 3.5 s in a debug-mode test (four isolates), once.

New PDF covers are JPEG (q90) instead of PNG, encoded in an isolate: the
development library's PNG covers average **1,188 KB as PNG, 287 KB as JPEG**,
which every sync, backup and server-side thumbnail pays. Existing PNG covers
are left as they are — rewriting them would change every one of their bytes,
and with them the server's copy and every other device's.

*Not done, worth knowing:* a spine shows only the left edge of its cover but
decodes all of it. A thumbnail of just the left strip would render identically
only while the strip is at least as wide, relative to its height, as the spine's
box — narrower, and `BoxFit.cover` switches to scaling by width and crops the
top and bottom. So it needs strips in a few widths (a quarter, a half of the
height), the box's aspect passed down to pick one, the full thumbnail past the
widest, and a pixel-comparison test to prove the spines unchanged. The gain is
smaller than it first looks: about 2.8× less decoded memory for a typical spine
(a quarter-height strip against a 0.7-aspect cover), 1.4× for a wide one, and
nothing on the first view of a cover, which still decodes the original. Worth
it if Android's 48 MB image cache turns out to be the limit in practice.

Backup *export* has the shape verify had: with a passphrase it encrypts the
whole archive on the UI isolate. The zip and encryption could move to an
isolate; the `VACUUM INTO` snapshot can't, since it goes through the app's own
database connection.

### #4 Covers stop crossing the wire for nothing

A push sent the cover of every dirty book, whatever had changed about it. The
server rewrote the file and bumped the book's `updated_at`, and its cover ETag
was a weak size+mtime tag that the rewrite changed — so a title fix made every
other device re-fetch the book *and* download the cover again, and the device
that made the edit downloaded its own upload back on the next pull. The
development library's covers average 275 KB, a rendered PDF page up to 1.7 MB:
that much up, and that much down per other device, per edited book.

- **Server:** the cover ETag is the SHA-256 of the bytes (`content_etag`),
  remembered against the file's size and mtime so a `304` still only `stat`s.
  `put_cover` answers with it, and re-uploading the stored bytes is a no-op: no
  write, no `updated_at` bump.
- **App:** before uploading, the push hashes the cover in a background isolate
  and skips it when the hash equals `coverEtag` — the server's tag for the copy
  we last downloaded or uploaded. An upload stores the tag it answers with.

An older server answers without a tag, which keeps that pairing on the old
always-upload behaviour. The first pull after a server upgrade downloads each
cover once more, since every stored weak tag stops matching.

`e2e_sync_test.dart` pins it over the real wire: after one device's cover
upload, a title edit on the other device sends no cover, and the first device
revalidates with a `304` instead of downloading. With the app-side check
disabled the test sees the upload.

### #5 A push no longer downloads the library

To skip uploading files the server already holds, every push with a dirty book
fetched `GET /api/books` — the whole library, files included — and read the
hashes off it. On a server seeded with 5,000 books that listing is **4.4 MB**
and 0.4 s of server time (debug build), and an auto-push after a single edit
paid all of it.

Now only books with local files are asked about at all, and up to twenty of
them ask with one `GET /api/books/<id>/files` each — after their metadata push,
so a book new to the server is there to be asked about. Past twenty (a first
sync, a bulk import) the one listing is still the cheaper way, and is what runs.

`auto_pusher_test.dart` had used that listing as its count of push runs; it now
counts `push()` calls directly.

### #6 A pull sends its requests together

A pull asked for each list in turn — books, then each kind's deletions and rows,
the personal lists, the profile — each waiting for the one before. None depends
on another's answer (they all take the previous cursor), so `_PullRequests` now
sends every list the sync's scope will read at once, and the pull awaits each
where it used to send it: rows are still applied in foreign-key order, books
before the shelves, copies and annotations that name them.

A no-change pull, full scope, 50 ms of simulated latency per request:

| | Requests | Wall time |
|---|---|---|
| One at a time | 15 | 862 ms |
| Together | 15 | 136 ms |

On a phone's 100 ms or more, that is the difference between a sync that feels
instant and one that doesn't. `sync_service_test.dart` pins it by counting
requests in flight at once (10 or more; it was 1). A request that fails before
the pull reaches it is held until it does, so failures are still reported where
they were — and a 404 from a server without the personal tables is still read
as "not supported yet".

### #7 Gzip on JSON responses

The server sent every response uncompressed. `src/gzip.rs` gzips JSON bodies
over 1 KB when the request accepts it — dart:io sends `Accept-Encoding: gzip`
and inflates by itself, as browsers do for the console, so the app needed no
change. Covers and files are left alone: they are compressed already and are
served with byte ranges. It is the outermost layer, so `request_id` still sees
error bodies as plain JSON.

| `GET /api/books`, 5,000 books, release build | On the wire |
|---|---|
| Before | 4.38 MB |
| Gzip (`Compression::fast`) | 273 KB |

That is synthetic data, and generous: the development library's real metadata
compresses **3.3×** (65 KB → 20 KB), since real descriptions differ and hashes
and ids don't compress. Server time was unchanged on localhost (0.14–0.17 s
either way). The app's real client was checked against it: it asked for gzip,
got 273 KB, and parsed all 5,000 books.

A small middleware on `flate2` (already compiled in via `lopdf` and `png`)
rather than `tower-http`'s `CompressionLayer`, for the same reason
`observability.rs` gives for its request ids.

### #8 Hashing and EPUB parsing off the UI isolate

Every imported file is hashed (the duplicate check, and what sync dedupes on).
The folder and catalogue scans did it one file at a time on the UI isolate;
attaching a file and writing a backup did the same through a byte stream. Now
all of it goes through `sha256OfFileInBackground`, and the scans run
`backgroundSlots` files at once.

`background_work.dart` holds the one pool every background isolate comes from —
cover thumbnails (#3) and hashes alike — so together they never take more than
one core short of the machine, four at most.

40 of the development library's book files, 1.1 GB, debug build:

| | Wall time | Worst gap in a 16 ms ticker |
|---|---|---|
| One at a time, UI isolate | 10.4 s | 22 ms |
| Four background isolates | 4.0 s | 17 ms |

The old loop yielded every 64 KB, so it rarely blocked a frame outright — its
cost was ten seconds of the UI isolate's CPU, which every frame shared with it.
That is now zero, and the scan finishes 2.6× sooner.

A cancelled scan checks as each file starts *and* as it finishes: with four in
flight, a cancel otherwise lands mid-hash and the scan would finish and report
them all.

The local content indexer's EPUB pass (unzip, parse, flatten every chapter) now
runs in an isolate too; it runs at startup, while the shelf is drawn.

**Verifying a backup** followed in a second commit: the whole check — the
encryption test, decrypting (Argon2, then every byte), unzipping, hashing each
entry — moved into one background isolate, since it hashes in-memory archive
entries rather than files. A 300 MB archive, with a 16 ms ticker on the UI
isolate:

| | Wall time | Ticks | Worst gap |
|---|---|---|---|
| Before | 2.65 s | 1 | 2,653 ms — frozen throughout |
| After | 2.71 s | 165 | 46 ms |

At the development library's 2.4 GB that was a ~20-second freeze.

### #9 The EPUB reader stops rewriting its chapter on every rebuild

The chapter handed to `HtmlWidget` is the book's markup with night mode's
colours stripped and the highlights painted in — both rewrites of the whole
chapter, done in the reader page's `build`, so on *every* rebuild: a selection
appearing, the chrome toggling, a bookmark. `HtmlWidget` itself only re-parses
when the string or text style changes by value, so the cost was the rewrite plus
a character-by-character comparison that found nothing new.

The development library's largest chapter is 8 MB of HTML (EPUB images arrive
inlined as data URIs). Per rebuild, debug build:

| | Per rebuild |
|---|---|
| `withoutBookColours` (night mode) | 26 ms |
| `mapHtmlText` (inside `withHighlights`, when the chapter has any) | 115 ms |
| `HtmlWidget` comparing the new string with the old | 15 ms |
| Cached (`ChapterMarkup`), all of the above | **0.05 ms** |

`ChapterMarkup` keeps the last result keyed by chapter, night mode, ink colour
and the annotation list's identity — the page replaces that list whenever
annotations change and never edits it in place — and hands back the very same
string, which compares with itself instantly. Its first build of a chapter costs
what every build used to.

*Not done:* `HtmlWidget` still lays out a whole chapter at once. Its
`RenderMode.listView` builds lazily, but conflicts with `SelectionArea` and with
restoring the reading position by scroll offset — worth trying only with a
profile of a long chapter in hand.

## 2026-11 round: what the profiling run found

The first rounds measured queries; this one measured frames. The profiling run
above, on the development machine (Linux, Radeon RX 6700-class GPU, Impeller
on OpenGL ES, 1280 × 800 window), seeded library of 4,000 books, v1.3.4 plus
the profiling run (523886d), load average ~1.3:

| | median | |
|---|---:|---|
| Cold start → first frame | 399 ms | the shelf's *empty* state |
| Cold start → first frame with spines | 632 ms | rasterised at 695 |
| Shelf, spines, 6 s scroll | 65–72 of ~377 frames janky | raster p90 20 ms, build p90 4 ms |
| Shelf, dominant-colour spines | 75 janky | raster p90 19 ms |
| Shelf, face-out covers / list | 0 / 0 janky | raster p90 7.9 / 2.1 ms |
| Opening a book | 57 ms to the page, settled at 383 | |
| Search, last keystroke → results | 157–203 ms | 150 of it the debounce |
| Insights, open | 234 ms | one 120 ms frame |
| Insights, a range chip | 246–313 ms | 123–160 ms frames |
| Month page, one month back | 431–443 ms | 71–76 ms frames |
| Room, pan / wheel zoom | 124 of 124 / 68 of 82 frames janky | raster p90 69 / 148 ms |
| Preferences, open | 47 ms, settled at 339 | |
| Resident set, after the whole run | 1.06 GB | 100 MB of it the image cache's desktop cap |

(A first baseline on 92a4b16, before v1.3.4's pdfrx upgrade, read the same
within noise: spines 72–77 janky, first shelf frame 596 ms.)

Ranked by what a user meets: the shelf is the app's home and janked a fifth of
its frames; the room was unusable to pan on a large room; insights and the
month page hitch visibly on every tap; start-up shows "your shelf is empty" for
a fifth of a second on every launch. Search, opening a book and Preferences are
fine.

### The raster lab: what a spine costs to draw

Build times were small everywhere; raster times were not, and `RepaintBoundary`
does not help on Impeller, which has no raster cache — so the question was
which *drawing operation* costs. A scratch integration test filled the screen
with 27 × 4 spine-sized boxes of one kind each and scrolled (raster ms per
frame, mean / p90):

| Each box draws | mean | p90 |
|---|---:|---:|
| a flat colour | 1.8 | 2.2 |
| a 3-stop horizontal `LinearGradient` (rounded or not) | 16–18 | 21–23 |
| a 2-stop gradient | 17.6 | 23.4 |
| the cover-slice shading (a constant translucent gradient) | 17.4 | 22.1 |
| the title, rotated | 2.3 | 2.5 |
| the title with its blurred shadow | 5.0 | 12.9 |
| a cover image (`BoxFit.cover`) | 2.0 | 2.5 |
| the same in a `ClipRRect` | 2.9 | 3.6 |
| `InkWell` + `Tooltip` | 2.2 | 2.6 |
| a gradient pre-drawn into a 256 × 1 image, `drawImageRect` | 2.2–2.6 | 2.3–7.0 |
| the same image as an `ImageShader` on the rounded rect | 20.9 | 46.2 |
| a whole pre-rendered spine bitmap (`RawImage`) | 2.1 | 2.7 |

So it was never the covers, the text layout or the decode: it was the
**gradient** every spine is shaded with — a hundred of them a frame at ~0.15 ms
each. The text shadow is the second cost, a quarter the size.

### #1 Spines shade from a strip image, not a gradient — kept

`GradientStrip` draws each ramp once into a 256 × 1 image (the same gradient,
by the same engine) and `drawImageRect`s it over the box; the generated spine's
rounded top is a clip, drawn without a second anti-aliasing pass so a
fractional right edge is not lightened twice. Strips are cached by their
colours (512 at most, 1 KB each — the dominant-colour artwork gives covered
books a colour each). `gradient_strip_test.dart` paints every spine shape both
ways at fractional widths and compares pixels: at most 1–2 levels apart in any
channel, mean 0.3, corners included.

| Shelf scroll, 6 s | janky frames | raster p90 | raster p99 |
|---|---:|---:|---:|
| Cover-slice spines, before | 65–72 | 20.0–20.3 ms | 23.8–24.0 ms |
| after | 0–1 | 6.8–6.9 ms | 8.6–9.4 ms |
| Dominant-colour spines, before | 75 | 19.1 ms | 22.6 ms |
| after | 0 | 3.7 ms | 4.2 ms |
| Room pan, before / after | 124 / 118 of ~124 | 69 / 54 ms | 80 / 63 ms |
| Room zoom, before / after | 68 / 61 of ~90 | 148 / 52 ms | 528 / 147 ms |

Both on v1.3.4, same machine, same hour. (On 92a4b16 the same change read
72–77 → 0–1 janky frames.)

The first attempt painted the strip through an `ImageShader` on the rounded
rectangle, to keep one draw: it barely moved the shelf (raster p90 21→19 ms,
jank 75→52) and measured *worse* than the gradient in the lab (46 ms p90), so
it was replaced before committing.

### #2 Insights and the month page stop converting dates on every frame — kept

Every statistic groups sittings by local day, and `ReadingStats.dayOf` turned
an instant into a local date — a time-zone lookup — each time it was asked.
The insights page asked about every sitting a dozen times over, in `build`, so
opening the page and every range chip cost one frame of 120–160 ms at 4,000
sittings; the month page did the same per month, and also rebuilt its two
database streams in `build`, re-reading every sitting and book on each step.

- `dayOf`, `MonthReviews.monthOf` and a new `ReadingStats.localOf` remember
  their answer per `DateTime` object in an `Expando` (it does not keep the
  sittings alive; a new fetch starts afresh).
- `InsightsSummary` (moved out of the page so it can be benchmarked) is worked
  out for all four ranges at once, in a background isolate once a history has
  1,000 sittings or more — smaller ones in place, where starting an isolate
  would cost more. A range chip now picks one of four finished answers.
- The month page builds its streams once.

`test/benchmark/insights_bench.dart` (in CI, generous budgets), JIT:

| 4,000 sittings | before | after |
|---|---:|---:|
| one range's summary | 103–154 ms | 17–62 ms (the first pays the conversions) |
| all four, in the background | — | 106 ms wall, off the UI isolate |
| four months reviewed | 101 ms | 26 ms |
| 16,000 sittings, one range | 394–605 ms | 54–165 ms |

On the profiling run (v1.3.4 + #1):

| | before | after |
|---|---:|---:|
| Insights open: worst frame | 120 ms | 5.9 ms |
| Insights open: page shown | 234–244 ms | 296 ms (the isolate; behind the spinner) |
| A range chip: frame p90 / p99 | 123 / 160 ms | 14 / 19 ms |
| Month page open: worst frame | 79 ms | 29 ms |
| A month back: frame p90, janky frames | 70 ms, 12 of 55 | 0.2 ms, 0 of 119 |

The one thing that got slower is the page appearing, by ~55 ms, while the
spinner it always showed is up — traded for no dropped frame at all.

### Reverted: asking for the shelf before the first frame

Between the first frame (~400 ms) and the first frame with spines (~630 ms) the
page shows the *empty-library* state, because `watchLibrary`'s first answer is
not in yet: cold, it costs ~180 ms (authors join 73, genres 21, the books query
83, against 15/5/30 warm). The idea: start that query in `main` right after the
repository opens, while the profile and server loads wait on the platform, and
hand the answer to the page's `StreamBuilder` as `initialData` through a small
"last view per arguments" cache in `LibraryQueries`.

Fifteen interleaved cold starts of each build against the same library (the
machine was busy — load 20–30 — so interleaving, not medians across runs, is
what makes the two comparable):

| | first frame | first shelf frame | frames before the shelf |
|---|---:|---:|---:|
| Without | 542 [412–1421] ms | 887 [694–2717] ms | 3 [2–3] |
| With | 566 [427–1263] ms | 904 [718–2353] ms | 2 [2–3] |

No gain. The warm-up does not finish before the first frame, and the page's
own subscription then runs the books query a second time on the same database
isolate, so the shelf arrives no sooner. Reverted. Two things stay true and are
worth a later look: the empty-library page ("add your first book") really is
on screen for a fifth of a second at every launch of a full library — showing
nothing until the first answer would be a visual fix rather than a speed-up —
and the cold query is dominated by mapping ~4,000 full `Book` rows when the
shelf needs a handful of columns.

### Finding, not fixed: the room is the title shadow

After #1 the room still janks while panning (118 of ~124 frames). The same
room with the spine title's blurred shadow switched off, as an experiment:

| Room | janky frames | raster p90 | raster p99 | build p90 |
|---|---:|---:|---:|---:|
| pan, as shipped | 120 of 125 | 58 ms | 74 ms | 22 ms |
| pan, no title shadow | 23 of 126 | 13 ms | 23 ms | 19 ms |
| zoom, as shipped | 57 of 92 | 56 ms | 98 ms | 44 ms |
| zoom, no title shadow | 54 of 88 | 18 ms | 65 ms | 35 ms |

(Load average 13–16 during these.) A room of 400 placed books draws 400 blurred
titles a frame; the shelf draws ~100, where the lab put the shadow at +3 ms
mean, +10 ms p90 — no longer janking after #1, but the largest raster cost
left. What remains in the room after that is *build*: every pan frame
`setState`s the editor and rebuilds all 400 books (14–20 ms). Both are the
next things to do here, in that order: draw the shadow from a cached image
(below), then move panning into a `Transform` so a pan rebuilds nothing.

### The spine ideas, measured

**Spine strips** (a pre-cut thumbnail of only the cover's left slice). Not
done, and not worth doing yet. The shelf's raster time was identical with no
thumbnails, with thumbnails, and with every cover already decoded (cold / warm
/ hot: 20.3 / 20.0 / 20.0 ms p90); an image draw costs what a flat colour does
(lab: 2.0 against 1.8 ms); and a 6-second scroll through the 4,000-book shelf
peaked at 20 MB of decoded images at 1280 × 800. Decoding is not where the time
or memory goes on the desktop. The 2.8× memory saving the October analysis
estimated still stands for phones, where the image cache is capped at 48 MB —
measure `shelf_spines_*.image_cache_peak_mb` on the emulator before building
it.

**Pre-rendered spines** (rasterise each whole spine once into a bitmap). The
lab says a bitmap spine costs 2.1 ms a screen against 17 for the gradient
spines it would have replaced — but #1 got the shelf from 20 to 7 ms p90 with
no bitmaps, no memory and no resampling, and with 0–1 janky frames there is
nothing left on the shelf for bitmaps to win. Their trap is real, too: a spine
is a fractional number of pixels wide, so its bitmap is drawn resampled, which
softens the title. Where pre-rendering *is* the answer is the part #1 could not
touch: the **title shadow**, the room's whole raster cost. Rendering only the
blurred shadow into an image (keyed by the displayed title, font size, text
scale and pixel ratio) and drawing the crisp title over it live keeps the text
exact — a blur survives resampling — and would take the room from ~58 to
~13 ms p90.

**Spine metadata** (anything computed per build that could be stored). Nothing
worth storing: `SpineStyle.fromJson` is already memoised, the shelf's build p90
is 4 ms, and the rotated title's layout costs nothing measurable (lab: 2.3 ms a
screen with titles against 1.8 without). The dominant colour is already stored.

### Not measured this round

- **Android on a real phone.** See "Android baseline" below: the one run so
  far is on the emulator.
- **The reader.** Out of scope while pdfrx was being upgraded; the profiling
  run has no reader scenario yet. Opening a book's file is the obvious next one
  to add.
- **Memory over time.** The resident set climbs from ~210 MB to ~1.05 GB over
  a run; 100 MB is the desktop image cache's cap and some is the recorded
  timelines, but nobody has separated the rest. Worth a run with
  `PERF_ONLY` per area and the timeline off.

### Android baseline (emulator, 2026-11-15)

`tool/perf_run.sh --android` on the Pixel 6 AVD (`vellum_test`, Android 14,
x86_64, **software GL** — swiftshader — on a 16-core host), profile build,
the 2,000-book seeded library, commit 8af55f4. **A baseline for comparing later
emulator runs, not a phone number**: raster times are the host CPU's, and
every scenario reads as janky (200–340 frames, 160–270 "jank") for that reason.
Build times are the more honest column, since the Dart side runs as AOT on the
host's cores, which are faster than a phone's.

| scenario | build p50 / p90 / p99 ms | raster p90 / p99 ms | rss MB |
|---|---:|---:|---:|
| shelf, spines cold | 1.3 / 4.0 / 14.3 | 42 / 70 | 342 |
| shelf, spines warm | 1.2 / 2.6 / 4.5 | 27 / 33 | 380 |
| shelf, spines hot | 1.1 / 2.5 / 4.2 | 24 / 29 | 403 |
| shelf, covers cold | 1.2 / 2.3 / 6.4 | 29 / 44 | 474 |
| shelf, list | 1.7 / 2.7 / 4.3 | 21 / 23 | 512 |
| Insights open (shown / settled) | 0.2 / 1.9 / 26.6 | 43 / 132 | 556 |
| Insights scroll | 0.5 / 2.3 / 11.3 | 25 / 110 | 585 |
| Insights range chip | 1.1 / 14.4 / 22.2 | 23 / 24 | 584 |
| month page open | 0.3 / 1.3 / 20.6 | 53 / 189 | 581 |
| Preferences open | 0.3 / 1.3 / 12.6 | 45 / 151 | 704 |
| room open | 5.1 / 49.6 / 49.6 | 688 / 688 | 694 |
| room pan | 16.8 / 37.2 / 75.2 | 867 / 1166 | 798 |

- **Start-up.** First frame 62 ms and first shelf frame 453 ms inside the
  profiling test (a warm engine). The cold-start probe (`startup_probe.dart`,
  six launches) printed nothing on the emulator — the six launches all read
  "no result" — so there is no cold-start number yet; a plain
  `am start -W` of the profile build's launcher activity took 1.8 s.
- **Shelf scroll.** Build stays under 5 ms at p90 in every view; the frame
  budget is spent on raster, which this emulator cannot price. Image cache peak
  is 99.9 MB with spines and 61 MB with the list — the 48 MB phone cap in
  `main()` is not applied in the test binary, so `image_cache_peak_mb` here says
  what the shelf *asks* for, not what a phone keeps.
- **Insights.** Opens in 231 ms shown / 498 ms settled; the range chip switches
  in 65–83 ms, but its build p90 (14 ms) is still the highest of the screens,
  as on desktop.
- **The room** is the outlier on both axes (build p90 50 ms, resident set
  to 905 MB over the run); the title shadow and the 400 placed books on a
  pan are the open items below.
- **Search typing:** 129–157 ms per query on 2,000 books.
- **Fix to the script.** `flutter drive` on Android needs `--no-dds` or the
  test's timeline connection is refused ("Failed to connect to VM Service");
  `perf_run.sh` now passes it for `--android`. The app on the device must also
  be one the seeder made: after a manual session, `adb uninstall` it first, or
  the guard refuses to profile.

### Next, in the order they would pay

1. ~~**The title shadow from a cached image**~~ — done, see "The room round"
   below.
2. ~~**Pan the room with a `Transform`**~~ — done, see "The room round" below.
3. **No empty-library page while the library is still loading** — a visual
   fix for the fifth of a second it flashes at every launch of a full library.
4. **A narrower shelf query**: the shelf maps every column of ~4,000 `Book`
   rows (descriptions included) on the UI isolate; the cold first answer is
   ~180 ms.
5. **The generated face-out cover's diagonal gradient** (covers view raster
   p90 ~8 ms; no jank today, but the same Impeller cost as the spines had).
   A diagonal ramp does not survive a non-uniform stretch, so the strip trick
   does not transfer as is.
6. **The insights range chip still builds a 14–19 ms frame** — the page
   itself, now that the arithmetic is gone. Check `HeatmapGrid` first.
7. **Measure Android on a real phone** (the emulator baseline is above, and
   its cold-start probe needs a look), then decide on spine strips from its
   `image_cache_peak_mb`; add a reader scenario; separate the resident-set
   growth over a run.

## The room round (2026-11-20): panning and zooming the physical room

The two room items at the top of the list above, plus what the measurements
put next. **Measured headless**: the user was logged out, so `perf_run.sh
--headless` ran Xephyr nested in a private Xvfb — Mesa's llvmpipe, **software
rendering**. Raster times below are the CPU's, several times the GPU's (the
GPU numbers above are the ones to quote); they compare two builds on the same
machine, nothing more. Build times and wall times are the real Dart side.
`PERF_ONLY=room tool/perf_run.sh --headless --only gui`, 1280 × 720 at 1×, the
seeded library (4,000 books, 400 placed in the room), base 885b1dc, load
average 3–7 (other work on the machine).

The pan scenario is 120 pointer moves, each waiting for its frame, so its
**wall time** is the plainest reading of how a drag feels.

### #1 The title shadow is drawn once, from an image — kept

`CachedTextShadow` (`lib/shelf/text_shadow_cache.dart`) wraps the cover
spine's title. The first time a title is painted it lays the same paragraph out
again with a transparent fill and the shadow in its style, records it, and
`toImageSync`s it at the device pixel ratio: the engine's own shadow, alone, in
an image the size of the title plus three sigmas of blur. From then on the
title paints that image (one textured quad) and the crisp text over it, live,
as before. Images are shared by key — text, style, text scale, pixel ratio,
shadow, and where the ellipsis falls (the boxes of the laid-out text, so a
zoom that does not move the cut-off reuses the image) — in a 16 MB LRU; each
spine keeps a clone of its own, so the cache never pulls one out from under a
frame. A paragraph that overflowed clips its shadow to its own box, and so does
the image.

Zooming moves most titles' ellipsis on every step, and drawing 400 new shadows
a frame cost more than the blur did (zoom build p90 44 → 65 ms in a first
attempt). So a spine whose cut-off moved keeps showing its previous shadow
(same title, same glyphs up to the ellipsis, clipped to the box) until the
cut-off has held still for a frame, and at most 24 are redrawn a frame; one
more frame is always asked for, so the last ones land after the zoom stops.

`text_shadow_cache_test.dart` (Roboto from the SDK, so the shadow follows real
glyphs): on whole pixels the cached shadow is **the same pixels** (max 0–1
levels at 1×, 2× and 2.75×). Where a spine puts it — rotated, centred, at a
fractional position — the image is resampled between device pixels, which
moves the blur by under half a pixel: at most 7 levels at the steepest part of
its edge, mean under 0.5, nothing in the title itself. A zoom sweep and a
resized-in-place spine are compared the same way; mid-zoom, before the refresh,
a stale shadow differs by up to ~50 levels near the ellipsis for a frame or so.

| Room, headless | before | after |
|---|---:|---:|
| pan: wall for 120 moves | 15.2–16.1 s | 4.8 s |
| pan: raster p90 / p99 | 170–183 / 218–221 ms | 47–49 / 53–55 ms |
| pan: build p90 | 19 ms | 20–22 ms (unchanged: see #2) |
| zoom: wall for 80 wheel steps | 8.1–8.2 s | 5.8–6.4 s |
| zoom: raster p90 | 195–223 ms | 72–78 ms |
| zoom: build p90 | 44–49 ms | 50–55 ms |

Shelf, the same headless runs (the shadow is only on cover-slice spines), two
interleaved rounds of each:

| Shelf scroll, 6 s | before | after |
|---|---:|---:|
| spines cold: raster p90 / build p90 | 26.3–26.5 / 4.4–4.7 ms | 22.1–22.7 / 4.6 ms |
| spines warm | 25.5–26.0 / 4.6–4.7 ms | 22.3–22.7 / 4.2–4.4 ms |
| spines hot | 25.8–26.1 / 4.7 ms | 22.6–22.8 / 4.5–4.6 ms |
| dominant colour (no shadow drawn) | 22.4–23.2 / 4.0–4.1 ms | 22.6–22.8 / 4.2–4.3 ms |

(The shelf numbers are from the end of the round, with #2 and #3 in too; those
touch only the room.) Not slower; the cover spines a little faster.

### #2 The room pans by a transform — kept

Every pan frame used to `setState` the editor, which rebuilt and laid out all
400 placed books to move them by a few pixels. Now the camera's origin is a
`ValueNotifier`: the props, the books and the dragged-book overlay sit in one
layer (`Transform.translate` over a `RepaintBoundary`) positioned in
origin-free coordinates, and a pan only sets the notifier. The transform moves
the layer, and `RoomPainter` takes the same notifier as a `repaint` listenable
(the grid, floor and planks are drawn relative to the screen, so it still
repaints — it is cheap). A pinch that changes the scale still rebuilds, as it
must: the books change size. Hit-testing was already done in world
coordinates from the gesture, so selection, book drags, shelf drags and the
edit gestures go through unchanged. `room_camera_test.dart` drives the real
page: a pan moves the books exactly by the drag and hands back the *same*
`SpineFace` widget objects (the old code fails that), a wheel zoom grows the
books by 10 %, a tap selects, the selected book drags along its shelf and is
saved there, and an unanchored shelf drags with its books riding on it.

Per-book `RepaintBoundary`s stay: one boundary for the whole layer instead
measured worse (pan raster p90 86 against 48 ms, in one noisy run).

| Room, headless | #1 | #1 + #2 |
|---|---:|---:|
| pan: build p90 / p99 | 20–22 / 32–36 ms | **1.2–1.3** / 4.5–14 ms |
| pan: raster p90 | 47–49 ms | 47.5 ms (software: the same pictures) |
| pan: wall for 120 moves | 4.8 s | 4.1 s |
| zoom: build p90 | 50–55 ms | 52–57 ms (unchanged: see #3) |

(A second run of #1 + #2, at a load spike, read 6.7 s and 120 ms raster for
the pan; the build p90 read 1.3 ms in both.)

### #3 A zoom step reuses the books' widgets, and the streams are made once — kept

After #2 the zoom was what remained: every wheel step rebuilds the page, and
the timeline put a step at ~10 ms of layout and ~7 ms of build (headless).
Two things in that build were waste:

- `_bookVisual` built each book's subtree (`SpineFace`, its clip, image,
  shading, title, the selection outline) afresh on every rebuild. It now hands
  back the same widget object while nothing it shows has changed — placement,
  book, selected, pulsing, dimmed, spine artwork, colours — so Flutter skips the
  subtree and only lays out the resized box. Selecting a book still rebuilds
  that book (the test checks its outline appears).
- The page's three `StreamBuilder`s were given `repo.layout.watch…()` *calls*
  in `build`, so each rebuild handed them new streams: they resubscribed, the
  queries ran again (the books one joins every placement to its book), and
  the answer rebuilt the page once more. They are made once, in the state.

A scratch widget benchmark (JIT, 400 books on 8 shelves, 120 wheel steps, the
time of each `pump`): 66 ms a step before, 49 with the widget reuse alone, 73
with the streams alone, **39 with both** — the streams only show once the
rebuild they trigger is the expensive part.

| Room, headless | #1 + #2 | #1 + #2 + #3 |
|---|---:|---:|
| zoom: build p50 / p90 / p99 | 30–36 / 52–57 / 59–71 ms | 25 / 42 / 52 ms |
| zoom: wall for 80 wheel steps | 6.1–6.4 s | 5.3 s |
| pan: build p90 | 1.2–1.3 ms | 0.9 ms |

### Where the room stands, headless, start to end

| Room (400 books), headless, software GL | 885b1dc | after #1–#3 |
|---|---:|---:|
| pan: wall for 120 moves | 15.2–16.1 s | 4.2 s |
| pan: raster p90 | 170–183 ms | 48 ms |
| pan: build p90 | 19 ms | 0.9 ms |
| zoom: wall for 80 wheel steps | 8.1–8.2 s | 5.3 s |
| zoom: raster p90 / p99 | 195–223 / 569–687 ms | 98 / 173 ms |
| zoom: build p90 | 44–49 ms | 42 ms |

**Not measured: the GPU.** The display was off for the whole round, so no
run used the real GPU; the November numbers above (pan raster p90 58 ms with
the shadow, 13 without) say where a desktop GPU should land, but that is
expected, not measured. Nor Android (no emulator this round).

### Next, for the room

1. **Measure #1–#3 on the GPU** (`PERF_ONLY=room,shelf tool/perf_run.sh --only
   gui` with the display awake) and on the Android emulator, whose pan build
   p90 was 37 ms.
2. **The zoom is layout-bound now** (~40 ms build p90 headless): each step lays
   out 400 spines again, titles included, because their size changed. The way
   past that is to scale the room's layer while a wheel or pinch burst is
   running and lay it out once when it stops — but titles would grow and
   shrink with the zoom and then snap back to their size, which changes how a
   zoom looks; a decision, not just a fix.
3. **The rest of the pan's raster** is the 400 books' own drawing (cover image,
   shading strip, scrim, title, shadow image). Measure on the GPU before
   anything else; per-book layers were kept because merging them measured worse.

## Room memory (Linux; Android pending KVM)

The Android emulator run showed the room taking the resident set to ~905 MB.
`/dev/kvm` was missing this round (the module is not loaded and loading it
needs a password), so this was measured on Linux instead: `PERF_ONLY=room
tool/perf_run.sh --headless --only gui`, a private Xvfb as the parent display,
software GL (llvmpipe), 1x pixel ratio, 4,000-book library with 400 placed
books. **Resident-set numbers here are not a phone's**: on a phone the textures
are GPU memory (`dumpsys meminfo` "Graphics"), here they are ordinary process
memory. What carries over is *which part of the app* holds it. Load on the
machine varied between runs (load average 5–28), so frame times are noisy and
only rss is compared. The Android follow-up is
`tool/emulator.sh run vellum_test -- <script>` around
`PERF_ONLY=room tool/perf_run.sh --android`, sampling
`adb shell dumpsys meminfo app.vellum.Vellum` every few seconds.

### What the run now records

- `PERF_PHONE_CACHE=1` applies `main()`'s phone image cache (48 MB, 200
  images) to the test binary; on Android it is applied automatically. **This
  changes the Android baseline** (before, the test ran with the 100 MB desktop
  cache: image cache peak 99.9 MB), separately from any fix.
- `PERF_SMAPS=1` (Linux) adds the anonymous / file / shared split of the
  resident set and the biggest mappings, from `/proc/self/smaps`.
- Every scenario records `shadow_cache_mb` / `shadow_cache_entries` and
  `cover_loads` (covers read and decoded, by decode height).

### Where the memory is (room only, phone image cache, MB)

| | start-up | room open | after pan | after zoom |
|---|---:|---:|---:|---:|
| resident set | 467 | 722 | 765 | **1195** |
| anonymous (native + Dart) | 322 | 576 | 620 | 1049 |
| of it Dart heap | 103 | 145 | 180 | 227 |
| of it other anonymous (engine, textures, malloc) | 109 | 320 | 321 | 673 |
| image cache (decoded covers) | 0 | 4.8 | 4.8 | 2.1 (peak 48) |
| shadow cache | 0 | 3.9 | 3.9 | 10.6 (856 images) |

The two things the brief guessed are small: the **decoded covers are tiny**
(the room's 260 live covers decode to 4.8 MB: they come from thumbnails at 64
px high and bucketed, `CoverImage` already decodes at display size) and the
**shadow images are ~4 MB** (10.6 MB mid-zoom; `Image.clone` shares pixels, so
the per-box handles cost nothing — the cache's byte count is the real figure).
The seeded room has no backdrop photo. What grows is native anonymous memory:
+200 MB opening the room and +350 MB over the zoom.

Taking things out, one at a time (room only, resident set at open / after zoom):

| variant | open | after zoom |
|---|---:|---:|
| as it is (phone cache) | 667 | 1137 |
| no per-book `RepaintBoundary` | 684 | 1168 |
| no title shadow | 686 | 1092 |
| no title shadow, no cover images | 566 | **662** |

So the covers account for ~430 MB of the zoom's growth, the shadows ~45–100,
and the boundaries nothing. The zoom decodes 2,000 covers in 80 steps
(`cover_loads`: 630 at 256 px, 520 at 128, 520 at 64, 336 at 512), because the
spines cross decode-height buckets, and the decoded bitmaps are uploaded as
textures and freed again; the image cache itself never holds more than its
48 MB. Memory that comes and goes this fast and is not given back is the
allocator/GL texture pool, which is why no number inside Dart sees it.

### Changes

| | result |
|---|---|
| Room backdrop decoded at most 2048 px on the long side (`decodeBackdrop`), the painter and the calibration dialog scale by the photo's original size | A 12 MP photo held 48 MB for as long as the room was open; now ≤ 16 MB. Not visible in these numbers (no backdrop in the seeded room); covered by `room_backdrop_decode_test`. **Kept.** |
| `TextShadowCache` clears on `didHaveMemoryPressure` (boxes keep the image they show, so no frame loses a shadow) | Costs nothing until the system asks; test added. **Kept.** |
| Phone image cache in the profiling test binary | Baseline fix, not an optimisation: room zoom image cache peak 100 -> 48 MB; the resident set did not move (1310 -> 1357, within noise), which says the cache is not what holds it. **Kept** (the run now matches what a phone keeps). |

### Tried and dropped

- **Culling the books outside the screen** (build only the viewport plus a
  screen's margin; rebuild when a pan runs out of margin): resident set after
  the zoom 1196 against 1137 for the control. The 400 books are not what the
  zoom is spending on; the books that are visible, resizing, are. Dropped, it
  adds a rebuild during a pan.
- **A bigger image cache entry limit** (1,000 instead of 200): after-zoom 1154
  against 1137, loads unchanged. Dropped.
- **One `RepaintBoundary` fewer per book**: see above, no change in memory.
  (The earlier round measured the single-layer variant worse in raster.)
- **Half-octave decode buckets** (a bucket at most 41 % over the spine instead
  of 100 %): not run. `spine_decode_height_test` pins that a whole pinch stays
  in one bucket, and finer buckets would split a pinch into several decodes —
  more churn, which is what the zoom is paying for.

### Not done / next

The remaining lever is what a zoom decodes: crossing a bucket reloads and
re-uploads every visible spine's cover, ~2,000 loads for the scenario. Either
hold the bucket for the length of a gesture (decode again once it stops, as the
shadow cache already waits for a cut-off to hold still), or make the thumbnail a
*slice* — a spine shows the left quarter of the cover and the rest of each
bitmap is memory nobody sees. Both need the Android numbers first: if graphics
memory on the phone is flat across the zoom, this is a software-GL artefact and
the 905 MB had another cause (the shelf scenarios before it were already at
704 MB on the emulator).

The shelf's code was not touched (its scenarios ran in the same two Linux runs
and read as the earlier ones); the frame times in them are not comparable
between runs at this load.
