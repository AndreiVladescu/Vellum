// Reading statistics (plan 5 #19). Dates are where this class of code goes
// wrong, so the streak arithmetic, month boundaries and DST are pinned here — and
// separately, that a session with no page information contributes nothing rather
// than a guess.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/stats/stats_queries.dart';

ReadingSession _session({
  required DateTime start,
  Duration length = const Duration(minutes: 30),
  int? startPage,
  int? endPage,
  String bookId = 'b1',
}) =>
    ReadingSession(
      id: 'x${start.microsecondsSinceEpoch}$startPage',
      bookId: bookId,
      startedAt: start,
      endedAt: start.add(length),
      startPage: startPage,
      endPage: endPage,
    );

Book _book({DateTime? finishedAt, String id = 'b1'}) => Book(
      id: id,
      title: 'Book $id',
      finishedAt: finishedAt,
      status: finishedAt == null ? 'reading' : 'finished',
      readCount: finishedAt == null ? 0 : 1,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      needsPush: false,
      needsProgressPush: false,
    );

void main() {
  group('pages per day', () {
    test('sums page movement into local calendar days', () {
      final pages = ReadingStats.pagesPerDay([
        _session(start: DateTime(2026, 7, 1, 9), startPage: 10, endPage: 30),
        _session(start: DateTime(2026, 7, 1, 21), startPage: 30, endPage: 45),
        _session(start: DateTime(2026, 7, 2, 9), startPage: 45, endPage: 50),
      ]);
      expect(pages[DateTime(2026, 7, 1)], 35);
      expect(pages[DateTime(2026, 7, 2)], 5);
    });

    test('a session with unknown pages contributes nothing', () {
      // Better a missing bar than an invented one.
      expect(
        ReadingStats.pagesPerDay([_session(start: DateTime(2026, 7, 1))]),
        isEmpty,
      );
    });

    test('reading backwards counts as zero, not negative', () {
      final pages = ReadingStats.pagesPerDay([
        _session(start: DateTime(2026, 7, 1), startPage: 80, endPage: 40),
        _session(start: DateTime(2026, 7, 1), startPage: 40, endPage: 60),
      ]);
      expect(pages[DateTime(2026, 7, 1)], 20,
          reason: 'a day of revision must not subtract from the total');
    });

    test('a session that starts late at night counts for the day it started',
        () {
      final pages = ReadingStats.pagesPerDay([
        _session(
          start: DateTime(2026, 7, 1, 23, 30),
          length: const Duration(hours: 1),
          startPage: 1,
          endPage: 20,
        ),
      ]);
      expect(pages.keys.single, DateTime(2026, 7, 1));
    });
  });

  group('streaks', () {
    Set<DateTime> days(List<DateTime> list) =>
        {for (final d in list) ReadingStats.dayOf(d)};

    test('consecutive days ending today', () {
      final today = DateTime(2026, 7, 10, 14);
      expect(
        ReadingStats.currentStreak(
          days([
            DateTime(2026, 7, 8),
            DateTime(2026, 7, 9),
            DateTime(2026, 7, 10),
          ]),
          today: today,
        ),
        3,
      );
    });

    test('a streak ending yesterday is still alive', () {
      // At 9am, someone who read every evening for a month has broken nothing.
      final today = DateTime(2026, 7, 10, 9);
      expect(
        ReadingStats.currentStreak(
          days([DateTime(2026, 7, 8), DateTime(2026, 7, 9)]),
          today: today,
        ),
        2,
      );
    });

    test('a two-day gap ends the streak', () {
      final today = DateTime(2026, 7, 10);
      expect(
        ReadingStats.currentStreak(
          days([DateTime(2026, 7, 6), DateTime(2026, 7, 7)]),
          today: today,
        ),
        0,
      );
    });

    test('no history means no streak', () {
      expect(ReadingStats.currentStreak(const {}), 0);
      expect(ReadingStats.longestStreak(const {}), 0);
    });

    test('the longest streak is found anywhere in the history', () {
      expect(
        ReadingStats.longestStreak(days([
          DateTime(2026, 1, 1),
          DateTime(2026, 3, 1),
          DateTime(2026, 3, 2),
          DateTime(2026, 3, 3),
          DateTime(2026, 3, 4),
          DateTime(2026, 6, 1),
          DateTime(2026, 6, 2),
        ])),
        4,
      );
    });

    test('a streak crosses a month boundary', () {
      expect(
        ReadingStats.longestStreak(days([
          DateTime(2026, 1, 30),
          DateTime(2026, 1, 31),
          DateTime(2026, 2, 1),
          DateTime(2026, 2, 2),
        ])),
        4,
      );
    });

    test('a streak crosses a leap day', () {
      expect(
        ReadingStats.longestStreak(days([
          DateTime(2028, 2, 28),
          DateTime(2028, 2, 29),
          DateTime(2028, 3, 1),
        ])),
        3,
      );
    });

    test('a streak survives a daylight-saving change', () {
      // The reason day arithmetic constructs dates instead of adding 24 hours:
      // on a clock-change day, +24h lands at 23:00 or 01:00 of the neighbouring
      // day, which would silently break the run. These are the EU/US change
      // weekends; the assertion holds in any zone because both sides are built
      // as local dates.
      for (final around in [
        DateTime(2026, 3, 29),
        DateTime(2026, 10, 25),
        DateTime(2026, 11, 1),
      ]) {
        final run = days([
          DateTime(around.year, around.month, around.day - 1),
          around,
          DateTime(around.year, around.month, around.day + 1),
        ]);
        expect(ReadingStats.longestStreak(run), 3,
            reason: 'streak broken around $around');
        expect(
          ReadingStats.currentStreak(run,
              today: DateTime(around.year, around.month, around.day + 1)),
          3,
        );
      }
    });
  });

  group('averages and splits', () {
    test('average pages per session ignores sessions with no movement', () {
      final average = ReadingStats.averagePagesPerSession([
        _session(start: DateTime(2026, 7, 1), startPage: 0, endPage: 20),
        _session(start: DateTime(2026, 7, 2), startPage: 20, endPage: 40),
        _session(start: DateTime(2026, 7, 3)), // no page info
        _session(start: DateTime(2026, 7, 4), startPage: 40, endPage: 40),
      ]);
      expect(average, 20);
    });

    test('no usable sessions average to zero rather than dividing by zero', () {
      expect(ReadingStats.averagePagesPerSession(const []), 0);
      expect(
        ReadingStats.averagePagesPerSession(
            [_session(start: DateTime(2026, 7, 1))]),
        0,
      );
    });

    test('books finished are grouped by calendar month', () {
      final byMonth = ReadingStats.finishedPerMonth([
        _book(id: 'a', finishedAt: DateTime(2026, 6, 2)),
        _book(id: 'b', finishedAt: DateTime(2026, 6, 30)),
        _book(id: 'c', finishedAt: DateTime(2026, 7, 1)),
        _book(id: 'd'), // unfinished
      ]);
      expect(byMonth[DateTime(2026, 6)], 2);
      expect(byMonth[DateTime(2026, 7)], 1);
      expect(byMonth, hasLength(2));
    });

    test('the genre split counts finished books, commonest first', () {
      final split = ReadingStats.finishedByGenre(
        books: [
          _book(id: 'a', finishedAt: DateTime(2026, 6, 1)),
          _book(id: 'b', finishedAt: DateTime(2026, 6, 2)),
          _book(id: 'c'), // unfinished — must not count
        ],
        genresByBook: {
          'a': ['Science Fiction', 'Classics'],
          'b': ['Science Fiction'],
          'c': ['History'],
        },
      );
      expect(split.first, (genre: 'Science Fiction', count: 2));
      expect(split.map((s) => s.genre), isNot(contains('History')));
    });
  });

  group('daily series', () {
    test('fills gaps with zeroes so the axis is time, not activity', () {
      final series = ReadingStats.dailySeries(
        {DateTime(2026, 7, 10): 12, DateTime(2026, 7, 8): 4},
        days: 4,
        today: DateTime(2026, 7, 10, 18),
      );
      expect(series.map((e) => e.value), [0, 4, 0, 12]);
      expect(series.first.day, DateTime(2026, 7, 7));
      expect(series.last.day, DateTime(2026, 7, 10));
    });

    test('an empty history is a flat series, not an empty list', () {
      final series = ReadingStats.dailySeries(const {},
          days: 7, today: DateTime(2026, 7, 10));
      expect(series, hasLength(7));
      expect(series.every((e) => e.value == 0), true);
    });
  });

  group('recorder', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('vellum_sessions'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<LibraryRepository> seeded() async {
      final repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dir,
      );
      await repo.db
          .into(repo.db.books)
          .insert(BooksCompanion.insert(id: 'b1', title: 'Dune'));
      return repo;
    }

    test('a sitting is one row, however many pages are turned', () async {
      final repo = await seeded();
      final recorder = SessionRecorder(repo.db);
      final start = DateTime(2026, 7, 1, 20);
      await recorder.begin('b1', page: 10, now: start);
      for (var i = 1; i <= 20; i++) {
        await recorder.touch(
            page: 10 + i, now: start.add(Duration(minutes: i)));
      }
      await recorder.end(page: 30, now: start.add(const Duration(minutes: 21)));

      final rows = await repo.db.select(repo.db.readingSessions).get();
      expect(rows, hasLength(1));
      expect(rows.single.startPage, 10);
      expect(rows.single.endPage, 30);
    });

    test('a short interruption extends the same session', () async {
      // A phone call must not become a second session, or every average would
      // measure interruptions instead of reading.
      final repo = await seeded();
      final recorder = SessionRecorder(repo.db);
      final start = DateTime(2026, 7, 1, 20);
      await recorder.begin('b1', page: 1, now: start);
      await recorder.end(page: 20, now: start.add(const Duration(minutes: 30)));
      await recorder.begin('b1',
          page: 20, now: start.add(const Duration(minutes: 31)));
      await recorder.end(page: 25, now: start.add(const Duration(minutes: 45)));

      final rows = await repo.db.select(repo.db.readingSessions).get();
      expect(rows, hasLength(1));
      expect(rows.single.endPage, 25);
    });

    test('a real gap starts a new session', () async {
      final repo = await seeded();
      final recorder = SessionRecorder(repo.db);
      final start = DateTime(2026, 7, 1, 20);
      await recorder.begin('b1', page: 1, now: start);
      await recorder.end(page: 20, now: start.add(const Duration(minutes: 30)));
      await recorder.begin('b1',
          page: 20, now: start.add(const Duration(hours: 5)));
      await recorder.end(page: 40,
          now: start.add(const Duration(hours: 5, minutes: 20)));

      expect(await repo.db.select(repo.db.readingSessions).get(), hasLength(2));
    });

    test('opening a book and closing it immediately records nothing', () async {
      // Checking a cover is not reading, and a pile of zero-length rows would
      // wreck every average.
      final repo = await seeded();
      final recorder = SessionRecorder(repo.db);
      final now = DateTime(2026, 7, 1, 20);
      await recorder.begin('b1', page: 5, now: now);
      await recorder.end(page: 5, now: now.add(const Duration(seconds: 2)));

      expect(await repo.db.select(repo.db.readingSessions).get(), isEmpty);
    });

    test('clearing the history removes every session', () async {
      final repo = await seeded();
      final recorder = SessionRecorder(repo.db);
      final start = DateTime(2026, 7, 1, 20);
      await recorder.begin('b1', page: 1, now: start);
      await recorder.end(page: 30, now: start.add(const Duration(minutes: 40)));

      expect(await recorder.clearAll(), 1);
      expect(await repo.db.select(repo.db.readingSessions).get(), isEmpty);
    });

    test('sessions go when their book goes', () async {
      final repo = await seeded();
      final recorder = SessionRecorder(repo.db);
      final start = DateTime(2026, 7, 1, 20);
      await recorder.begin('b1', page: 1, now: start);
      await recorder.end(page: 30, now: start.add(const Duration(minutes: 40)));

      final book = (await repo.watchBook('b1').first)!;
      await repo.deleteBook(book);
      expect(await repo.db.select(repo.db.readingSessions).get(), isEmpty);
    });
  });
}
