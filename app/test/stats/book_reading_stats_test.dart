// The numbers behind "Your reading" on the book page (v1.3.1).
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/stats/book_reading_stats.dart';

ReadingSession _s(DateTime start, int minutes, {int? from, int? to}) =>
    ReadingSession(
      id: 's${start.microsecondsSinceEpoch}',
      bookId: 'b1',
      startedAt: start,
      endedAt: start.add(Duration(minutes: minutes)),
      startPage: from,
      endPage: to,
      needsPush: false,
    );

void main() {
  test('no sittings, no section', () {
    expect(BookReading.of(const []), isNull);
  });

  test('time, sittings and the first and last day', () {
    final r = BookReading.of([
      // Deliberately out of order: the result must not depend on it.
      _s(DateTime(2026, 7, 3, 21), 40, from: 50, to: 90),
      _s(DateTime(2026, 7, 1, 9), 20, from: 1, to: 50),
      _s(DateTime(2026, 7, 3, 23, 50), 30), // runs past midnight
    ])!;
    expect(r.minutes, 90);
    expect(r.sittings, 3);
    expect(r.first, DateTime(2026, 7, 1));
    // The late sitting began on the 3rd and counts for the 3rd.
    expect(r.last, DateTime(2026, 7, 3));
  });

  test('pace is this book alone, pages over minutes', () {
    final r = BookReading.of([
      _s(DateTime(2026, 7, 1, 9), 20, from: 1, to: 41),
      _s(DateTime(2026, 7, 2, 9), 20, from: 41, to: 81),
    ])!;
    expect(r.pagesPerMinute, 2.0);
  });

  test('a pace that cannot be measured is null, not zero', () {
    // No page positions at all.
    expect(BookReading.of([_s(DateTime(2026, 7, 1), 30)])!.pagesPerMinute,
        isNull);
    // A sitting under a minute is not extrapolated.
    expect(
        BookReading.of([_s(DateTime(2026, 7, 1), 0, from: 1, to: 3)])!
            .pagesPerMinute,
        isNull);
    // Time and sittings are still reported.
    expect(BookReading.of([_s(DateTime(2026, 7, 1), 30)])!.minutes, 30);
  });

  group('minutes left', () {
    test('remaining pages over the measured pace', () {
      expect(
          BookReading.minutesLeft(pace: 2, pageCount: 300, currentPage: 100),
          100);
    });

    test('never invents one', () {
      expect(
          BookReading.minutesLeft(pace: null, pageCount: 300, currentPage: 1),
          isNull);
      expect(BookReading.minutesLeft(pace: 0, pageCount: 300, currentPage: 1),
          isNull);
      expect(
          BookReading.minutesLeft(pace: 2, pageCount: null, currentPage: 1),
          isNull);
      expect(BookReading.minutesLeft(pace: 2, pageCount: 0, currentPage: 0),
          isNull);
      expect(
          BookReading.minutesLeft(pace: 2, pageCount: 300, currentPage: null),
          isNull);
    });

    test('none at or past the end; a sliver is one minute, not zero', () {
      expect(
          BookReading.minutesLeft(pace: 2, pageCount: 300, currentPage: 300),
          isNull);
      expect(
          BookReading.minutesLeft(pace: 2, pageCount: 300, currentPage: 340),
          isNull);
      expect(
          BookReading.minutesLeft(pace: 5, pageCount: 300, currentPage: 299),
          1);
    });
  });
}
