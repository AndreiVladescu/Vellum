# Performance: seeding, benchmarking, profiling

Companion to [`IMPROVEMENT_PLAN_5.md`](IMPROVEMENT_PLAN_5.md) §A45. Written
before §A1/§A2 land, so the numbers below are the *baseline* the shelf's
current four-`StreamBuilder`/Dart-substring-scan design produces — re-measure
after each of those lands rather than trusting the target numbers alone.

## Data-layer benchmarks (CI)

`app/test/benchmark/library_bench.dart` seeds a 3,000-book in-memory library
(`seedLibrary`, see below) and times the query paths §0 of plan 5 calls out:
`watchAllBooks()`, `watchAuthorsByBook()`, `watchGenresByBook()`, and
`filterBooks()`/`sortBooks()` over the full result. Each step asserts a
generous (4 s) upper bound — a regression guard against an accidental
O(n²) or a dropped index, not a frame-time target; CI runners are too
variable to assert tight numbers.

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
`driftDatabase(name: 'vellum')`) — on Linux desktop that's typically
`~/.local/share/com.avladescu.vellum/vellum.sqlite`; run the app once first if
the directory doesn't exist yet. Restore your backup afterwards.

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
