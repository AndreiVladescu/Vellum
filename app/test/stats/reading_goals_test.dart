// Reading goals (v1.3.1). Pure date arithmetic, so the edges are pinned here:
// year boundaries, leap years, the pace on 1 January and 31 December, goals
// that are zero or unset, days without sessions, and sittings across midnight.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/stats/reading_goals.dart';
import 'package:vellum/stats/stats_queries.dart';

Book _book(String id, {DateTime? finishedAt}) => Book(
      id: id,
      title: 'Book $id',
      readerNotesNeedsPush: false,
      statusNeedsPush: false,
      statusInferred: false,
      finishedAt: finishedAt,
      status: finishedAt == null ? 'reading' : 'finished',
      readCount: finishedAt == null ? 0 : 1,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      needsPush: false,
      syncExcluded: false,
      needsProgressPush: false,
    );

ReadingSession _session(DateTime start, int minutes) => ReadingSession(
      id: 's${start.microsecondsSinceEpoch}',
      bookId: 'b1',
      startedAt: start,
      endedAt: start.add(Duration(minutes: minutes)),
      needsPush: false,
    );

void main() {
  group('calendar', () {
    test('leap years follow the century rule', () {
      expect(ReadingGoals.isLeapYear(2024), isTrue);
      expect(ReadingGoals.isLeapYear(2026), isFalse);
      expect(ReadingGoals.isLeapYear(1900), isFalse);
      expect(ReadingGoals.isLeapYear(2000), isTrue);
      expect(ReadingGoals.daysInYear(2024), 366);
      expect(ReadingGoals.daysInYear(2026), 365);
    });

    test('day of the year at the boundaries', () {
      expect(ReadingGoals.dayOfYear(DateTime(2026, 1, 1)), 1);
      expect(ReadingGoals.dayOfYear(DateTime(2026, 12, 31)), 365);
      expect(ReadingGoals.dayOfYear(DateTime(2024, 12, 31)), 366);
      expect(ReadingGoals.dayOfYear(DateTime(2024, 3, 1)), 61);
      expect(ReadingGoals.dayOfYear(DateTime(2026, 3, 1)), 60);
      // 23:59 is still the same day.
      expect(ReadingGoals.dayOfYear(DateTime(2026, 1, 1, 23, 59)), 1);
    });
  });

  group('books finished in a year', () {
    test('counts finishedAt in that year only, once per book', () {
      final books = [
        _book('a', finishedAt: DateTime(2026, 1, 1)),
        _book('b', finishedAt: DateTime(2026, 12, 31, 23, 59)),
        _book('c', finishedAt: DateTime(2025, 12, 31, 23, 59)),
        _book('d', finishedAt: DateTime(2027, 1, 1)),
        _book('e'), // not finished
      ];
      expect(ReadingGoals.finishedInYear(books, 2026), 2);
      expect(ReadingGoals.finishedInYear(books, 2025), 1);
      expect(ReadingGoals.finishedInYear(const [], 2026), 0);
    });

    test('a re-read finished this year counts for this year', () {
      // finishedAt is overwritten when a book is finished again, so a book
      // first read in 2024 and finished again in 2026 carries the 2026 date.
      final reread = _book('r', finishedAt: DateTime(2026, 5, 2))
          .copyWith(readCount: 2);
      expect(ReadingGoals.finishedInYear([reread], 2026), 1);
      expect(ReadingGoals.finishedInYear([reread], 2024), 0);
    });
  });

  group('year pace', () {
    test('1 January expects nothing, so nobody starts behind', () {
      final p = ReadingGoals.yearPace(
          finished: 0, target: 12, today: DateTime(2026, 1, 1));
      expect(p.expected, 0);
      expect(p.difference, 0);
      expect(p.reached, isFalse);
    });

    test('31 December expects the whole target', () {
      final p = ReadingGoals.yearPace(
          finished: 10, target: 12, today: DateTime(2026, 12, 31));
      expect(p.expected, 12);
      expect(p.difference, -2);
      final leap = ReadingGoals.yearPace(
          finished: 12, target: 12, today: DateTime(2024, 12, 31));
      expect(leap.expected, 12);
      expect(leap.reached, isTrue);
    });

    test('mid-year ahead, on pace and behind', () {
      // 24 a year, 1 July 2026 is day 182: expected 11.
      final day = DateTime(2026, 7, 1);
      expect(
          ReadingGoals.yearPace(finished: 14, target: 24, today: day)
              .difference,
          3);
      expect(
          ReadingGoals.yearPace(finished: 11, target: 24, today: day)
              .difference,
          0);
      expect(
          ReadingGoals.yearPace(finished: 8, target: 24, today: day)
              .difference,
          -3);
    });

    test('a goal beaten early is reached, not merely ahead', () {
      final p = ReadingGoals.yearPace(
          finished: 13, target: 12, today: DateTime(2026, 3, 1));
      expect(p.reached, isTrue);
    });
  });

  group('minutes per day', () {
    final today = DateTime(2026, 7, 10, 15);

    test('today counts the local day, with no sessions it is zero', () {
      expect(ReadingGoals.minutesToday({}, today), 0);
      final byDay = ReadingStats.minutesPerDay([
        _session(DateTime(2026, 7, 10, 8), 20),
        _session(DateTime(2026, 7, 10, 21), 15),
        _session(DateTime(2026, 7, 9, 21), 50),
      ]);
      expect(ReadingGoals.minutesToday(byDay, today), 35);
    });

    test('a sitting across midnight belongs to the day it began', () {
      final byDay = ReadingStats.minutesPerDay([
        _session(DateTime(2026, 7, 9, 23, 40), 60),
      ]);
      expect(ReadingGoals.minutesToday(byDay, today), 0);
      expect(
          ReadingGoals.minutesToday(byDay, DateTime(2026, 7, 9, 12)), 60);
    });

    test('days met counts the last seven including today', () {
      final byDay = ReadingStats.minutesPerDay([
        _session(DateTime(2026, 7, 10, 8), 30), // today, exactly the goal
        _session(DateTime(2026, 7, 9, 8), 29), // just short
        _session(DateTime(2026, 7, 8, 8), 45),
        _session(DateTime(2026, 7, 4, 8), 30), // 6 days back: in
        _session(DateTime(2026, 7, 3, 8), 90), // 7 days back: out
      ]);
      expect(ReadingGoals.daysMet(byDay, target: 30, today: today), 3);
    });

    test('the window crosses a month and a year end', () {
      final byDay = ReadingStats.minutesPerDay([
        _session(DateTime(2025, 12, 31, 20), 30),
        _session(DateTime(2026, 1, 1, 20), 30),
      ]);
      expect(
          ReadingGoals.daysMet(byDay,
              target: 30, today: DateTime(2026, 1, 2)),
          2);
    });

    test('a zero goal is no goal and nothing meets it', () {
      final byDay = {DateTime(2026, 7, 10): 60};
      expect(ReadingGoals.daysMet(byDay, target: 0, today: today), 0);
    });
  });

  group('normalise', () {
    test('zero, negative and missing mean no goal; big numbers are capped',
        () {
      expect(ReadingGoals.normalise(null, max: 365), isNull);
      expect(ReadingGoals.normalise(0, max: 365), isNull);
      expect(ReadingGoals.normalise(-4, max: 365), isNull);
      expect(ReadingGoals.normalise(12, max: 365), 12);
      expect(ReadingGoals.normalise(9999, max: 365), 365);
    });
  });
}
