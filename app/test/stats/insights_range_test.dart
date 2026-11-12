// The Insights range control and the per-day detail (roadmap v1.3.2). Pure
// date arithmetic, so the edges are pinned here: the 30-day window's first and
// last day, the year boundary, the length of the "this year" and "all time"
// charts, a sitting started just before midnight, and the day sheet's totals.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/stats/insights_range.dart';

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

ReadingSession _s(
  DateTime start,
  int minutes, {
  String book = 'b1',
  int? from,
  int? to,
}) =>
    ReadingSession(
      id: 's${start.microsecondsSinceEpoch}$book',
      bookId: book,
      startedAt: start,
      endedAt: start.add(Duration(minutes: minutes)),
      startPage: from,
      endPage: to,
      needsPush: false,
    );

void main() {
  final today = DateTime(2026, 11, 12, 15);

  group('range', () {
    test('an unknown stored value is the default', () {
      expect(InsightsRange.parse(null), InsightsRange.standard);
      expect(InsightsRange.parse('nonsense'), InsightsRange.standard);
      expect(InsightsRange.parse('thisYear'), InsightsRange.thisYear);
      for (final r in InsightsRange.values) {
        expect(InsightsRange.parse(r.name), r);
      }
    });

    test('where each range starts', () {
      expect(RangeFilter.start(InsightsRange.standard, today), isNull);
      expect(RangeFilter.start(InsightsRange.allTime, today), isNull);
      expect(RangeFilter.start(InsightsRange.thisYear, today),
          DateTime(2026, 1, 1));
      // Today and the 29 days before it: 30 days.
      expect(RangeFilter.start(InsightsRange.last30Days, today),
          DateTime(2026, 10, 14));
    });

    test('the 30-day window crosses a month and a year end', () {
      expect(
          RangeFilter.start(InsightsRange.last30Days, DateTime(2026, 1, 10)),
          DateTime(2025, 12, 12));
    });

    test('sittings: the first day of the window is in, the day before is out',
        () {
      final inside = _s(DateTime(2026, 10, 14, 0, 5), 10);
      final outside = _s(DateTime(2026, 10, 13, 23, 55), 10);
      final result = RangeFilter.sessions(
          [inside, outside], InsightsRange.last30Days, today);
      expect(result, [inside]);
    });

    test('this year starts at midnight on 1 January', () {
      final jan1 = _s(DateTime(2026, 1, 1, 0, 1), 10);
      final dec31 = _s(DateTime(2025, 12, 31, 23, 59), 10);
      final result =
          RangeFilter.sessions([jan1, dec31], InsightsRange.thisYear, today);
      expect(result, [jan1]);
    });

    test('the default and all time keep every sitting', () {
      final all = [_s(DateTime(2020, 3, 1), 10), _s(DateTime(2026, 11, 1), 10)];
      expect(RangeFilter.sessions(all, InsightsRange.standard, today), all);
      expect(RangeFilter.sessions(all, InsightsRange.allTime, today), all);
    });

    test('finished books follow the finish date, and unfinished ones drop out',
        () {
      final a = _book('a', finishedAt: DateTime(2026, 11, 1));
      final b = _book('b', finishedAt: DateTime(2026, 3, 1));
      final c = _book('c', finishedAt: DateTime(2025, 12, 31, 23, 59));
      final d = _book('d');
      final books = [a, b, c, d];
      expect(RangeFilter.finishedBooks(books, InsightsRange.last30Days, today),
          [a]);
      expect(RangeFilter.finishedBooks(books, InsightsRange.thisYear, today),
          [a, b]);
      expect(
          RangeFilter.finishedBooks(books, InsightsRange.allTime, today), books);
      expect(
          RangeFilter.finishedBooks(books, InsightsRange.standard, today), books);
    });

    test('chart length: 30 by default, since 1 January for the year', () {
      expect(RangeFilter.chartDays(InsightsRange.standard, [], today), 30);
      expect(RangeFilter.chartDays(InsightsRange.last30Days, [], today), 30);
      // 12 November 2026 is day 316 of a 365-day year.
      expect(RangeFilter.chartDays(InsightsRange.thisYear, [], today), 316);
      // 1 January is a one-day chart; in a leap year 31 December is day 366.
      expect(
          RangeFilter.chartDays(
              InsightsRange.thisYear, [], DateTime(2026, 1, 1, 9)),
          1);
      expect(
          RangeFilter.chartDays(
              InsightsRange.thisYear, [], DateTime(2024, 12, 31, 9)),
          366);
    });

    test('all time spans from the first sitting, never under 30 days', () {
      expect(RangeFilter.chartDays(InsightsRange.allTime, [], today), 30);
      final young = [_s(DateTime(2026, 11, 5), 10)];
      expect(RangeFilter.chartDays(InsightsRange.allTime, young, today), 30);
      final old = [
        _s(DateTime(2026, 11, 5), 10),
        _s(DateTime(2025, 11, 12), 10),
      ];
      // 12 Nov 2025 to 12 Nov 2026, both counted.
      expect(RangeFilter.chartDays(InsightsRange.allTime, old, today), 366);
    });
  });

  group('day detail', () {
    test('adds up one local day and ignores the neighbours', () {
      final sessions = [
        _s(DateTime(2026, 11, 4, 9), 20, from: 1, to: 11),
        _s(DateTime(2026, 11, 4, 21), 40, book: 'b2', from: 5, to: 35),
        _s(DateTime(2026, 11, 3, 23, 50), 30, from: 11, to: 21),
        _s(DateTime(2026, 11, 5, 0, 10), 30, from: 21, to: 31),
      ];
      final d = DayDetail.of(sessions, DateTime(2026, 11, 4, 12));
      expect(d.day, DateTime(2026, 11, 4));
      expect(d.sittings, 2);
      expect(d.minutes, 60);
      expect(d.pages, 40);
      expect(d.isEmpty, isFalse);
      // The longer book first.
      expect([for (final b in d.books) b.bookId], ['b2', 'b1']);
      expect(d.books.first.minutes, 40);
      expect(d.books.first.pages, 30);
    });

    test('a sitting that runs past midnight stays on the day it started', () {
      final sessions = [_s(DateTime(2026, 11, 4, 23, 30), 60, from: 1, to: 6)];
      expect(DayDetail.of(sessions, DateTime(2026, 11, 4)).minutes, 60);
      expect(DayDetail.of(sessions, DateTime(2026, 11, 5)).isEmpty, isTrue);
    });

    test('unknown pages count as nothing, not a guess', () {
      final sessions = [_s(DateTime(2026, 11, 4, 9), 20)];
      final d = DayDetail.of(sessions, DateTime(2026, 11, 4));
      expect(d.pages, 0);
      expect(d.minutes, 20);
      expect(d.sittings, 1);
    });

    test('a day with no reading is empty', () {
      final d = DayDetail.of([], DateTime(2026, 11, 4));
      expect(d.isEmpty, isTrue);
      expect(d.books, isEmpty);
      expect(d.minutes, 0);
    });

    test('equal books order by pages, then id, so the list is stable', () {
      final sessions = [
        _s(DateTime(2026, 11, 4, 9), 20, book: 'b', from: 1, to: 5),
        _s(DateTime(2026, 11, 4, 10), 20, book: 'a', from: 1, to: 5),
        _s(DateTime(2026, 11, 4, 11), 20, book: 'c', from: 1, to: 9),
      ];
      final d = DayDetail.of(sessions, DateTime(2026, 11, 4));
      expect([for (final b in d.books) b.bookId], ['c', 'a', 'b']);
    });
  });
}
