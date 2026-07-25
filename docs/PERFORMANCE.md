# Performance: seeding, benchmarking, profiling

Companion to [`IMPROVEMENT_PLAN_5.md`](IMPROVEMENT_PLAN_5.md) §A45. Written
before §A1/§A2 land, so the numbers below are the *baseline* the shelf's
current four-`StreamBuilder`/Dart-substring-scan design produces — re-measure
after each of those lands rather than trusting the target numbers alone.

## Data-layer benchmarks (CI)

`app/test/benchmark/library_bench.dart` seeds a 3,000-book in-memory library
(`seedLibrary`, see below) and times the query paths §0 of plan 5 calls out:
`watchAllBooks()`, `watchAuthorsByBook()`, `watchGenresByBook()`, and
`filterBooks()`/`sortBooks()` — both one pass and a 20-rebuild burst. The
burst is the number that matters: §0.1/§0.2's actual complaint is that
today's four nested `StreamBuilder`s re-run filter+sort over the whole
library on *every* independent emission, so a single pass looks fine in any
harness and still costs real frames on a phone during a burst of shelf
mutations (e.g. a folder import). §A1/§A2 should visibly beat the burst
number, not the one-pass number. Each step asserts a generous upper bound (4 s,
16 s for the burst) — a regression guard against an accidental O(n²) or a
dropped index, not a frame-time target; CI runners are too variable to assert
tight numbers.

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
resolves to the XDG `DOCUMENTS` user directory, typically `~/Documents`, so
the file is usually `~/Documents/vellum.sqlite` — but XDG config can move
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

**Known remaining cost: subscription churn on every rebuild.** `main.dart`
calls `watchLibrary(...)` fresh inside `build()`, so typing in the search box
(debounced 150ms) creates a brand-new combined stream each time — all six
underlying queries re-run on subscribe, not just the ones the changed
parameter actually affects. Measured on the same 3,000-book library:
successive fresh `watchLibrary(query: …)` subscriptions (simulating a
keystroke) land in the **20–70ms range**, not the ~180ms of the pre-fix
design — the six queries execute back-to-back rather than through the old
single `asyncMap` chain, so this is not the same class of problem. It's also
not new: the pre-#A1 code created `watchAuthorsByBook()`/`watchGenresByBook()`
fresh in `build()` too. Left as-is because #A2 (FTS5) changes the query's
`WHERE` clause shape anyway; if a profile run shows this costing frames,
the fix is caching the four params-independent sub-streams (authors, genres,
shelves, allGenres) instead of recreating them per `watchLibrary()` call.
