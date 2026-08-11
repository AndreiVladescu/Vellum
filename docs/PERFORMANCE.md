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
