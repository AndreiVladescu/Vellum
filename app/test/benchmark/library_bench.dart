// Data-layer query benchmarks over a synthetic library — see
// docs/PERFORMANCE.md. These are regression guards (generous bounds so a
// normal CI runner never flakes), not the frame-time targets from that doc;
// measure those with `flutter run --profile` instead.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/data/seed_library.dart';
import 'package:vellum/settings/shelf_sort.dart';
import 'package:vellum/shelf/shelf_filter.dart';

const _bookCount = 3000;
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

    await _time('filterBooks() + sortBooks() over the full library', () async {
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
