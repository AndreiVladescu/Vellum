// Data-layer query benchmarks over a synthetic library — see
// docs/PERFORMANCE.md. These are regression guards (generous bounds so a
// normal CI runner never flakes), not the frame-time targets from that doc;
// measure those with `flutter run --profile` instead.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_queries.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/data/seed_library.dart';
import 'package:vellum/settings/shelf_sort.dart';
import 'package:vellum/shelf/shelf_filter.dart';

// Kept modest since #A2's FTS5 triggers fire per insert: seeding 3,000 books
// went from ~220ms to ~3.7s locally (docs/PERFORMANCE.md), and CI's
// write-heavy SQLite performance is more variable than a desktop's — 1,000 is
// still enough library to catch an O(n^2) or a dropped index on the
// *read*-path timings this bench actually cares about.
const _bookCount = 1000;
// Regression guard, not a perf target: generous so a loaded CI runner never
// flakes, tight enough to catch an accidental O(n^2) or a dropped index.
const _maxStepMillis = 4000;

void main() {
  test('seed + query a $_bookCount-book library within budget', () async {
    final dir = Directory.systemTemp.createTempSync('vellum_bench');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repo = await LibraryRepository.forTesting(
      VellumDatabase(NativeDatabase.memory()),
      dir,
    );
    final db = repo.db;

    // Seeding is not the thing under test; a loose bound only catches a real
    // seeder regression.
    await _time(
      'seed $_bookCount books',
      () => seedLibrary(db, count: _bookCount),
      budgetMillis: _maxStepMillis * 4,
    );

    final books = await _time(
      'watchAllBooks()',
      () => repo.watchAllBooks().first,
    );
    expect(books.length, _bookCount);

    final authorsByBook = await _time(
      'watchAuthorsByBook()',
      () => repo.watchAuthorsByBook().first,
    );
    final genresByBook = await _time(
      'watchGenresByBook()',
      () => repo.watchGenresByBook().first,
    );

    await _time('filterBooks() + sortBooks(), one pass', () async {
      final filtered = filterBooks(
        books: books,
        query: 'the',
        authorsByBook: authorsByBook,
        genresByBook: genresByBook,
      );
      sortBooks(
        books: filtered,
        sort: ShelfSort.author,
        authorsByBook: authorsByBook,
      );
    });

    // §0.1/§0.2's actual problem isn't one pass — it's that today's four
    // nested StreamBuilders re-run filter+sort over the *whole* library on
    // every one of their independent emissions. 20 passes stands in for a
    // burst of shelf mutations (e.g. a folder import), so this is the number
    // §A1/§A2's view-model + FTS work should visibly beat, not the one-pass
    // figure above.
    const rebuildBurst = 20;
    await _time(
      'filterBooks() + sortBooks(), $rebuildBurst-rebuild burst',
      () async {
        for (var i = 0; i < rebuildBurst; i++) {
          final filtered = filterBooks(
            books: books,
            query: 'the',
            authorsByBook: authorsByBook,
            genresByBook: genresByBook,
          );
          sortBooks(
            books: filtered,
            sort: ShelfSort.author,
            authorsByBook: authorsByBook,
          );
        }
      },
      budgetMillis: _maxStepMillis * 4,
    );

    // §A1/§A2's actual deliverable: watchLibrary() does the filter+sort (and,
    // for free text, the FTS5 match) in SQL instead of the Dart burst above.
    // A fresh subscription each time (not one long-lived stream) matches how
    // main.dart actually calls it — a new stream object per build() — so
    // this is the number that should beat the burst figure above, not an
    // idealized steady-state number.
    final queries = LibraryQueries(db);
    await _time(
      'watchLibrary(query: "the"), $rebuildBurst fresh subscriptions',
      () async {
        for (var i = 0; i < rebuildBurst; i++) {
          await queries.watchLibrary(query: 'the', sort: ShelfSort.author).first;
        }
      },
      budgetMillis: _maxStepMillis * 4,
    );
  }, timeout: const Timeout(Duration(minutes: 2)));
}

Future<T> _time<T>(
  String label,
  Future<T> Function() run, {
  int budgetMillis = _maxStepMillis,
}) async {
  final stopwatch = Stopwatch()..start();
  final result = await run();
  stopwatch.stop();
  // ignore: avoid_print
  print('  $label: ${stopwatch.elapsedMilliseconds} ms');
  expect(
    stopwatch.elapsedMilliseconds,
    lessThan(budgetMillis),
    reason: '$label took ${stopwatch.elapsedMilliseconds} ms, '
        'budget is $budgetMillis ms',
  );
  return result;
}
