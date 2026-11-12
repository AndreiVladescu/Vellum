// Month by month (roadmap v1.3.2). Pure date arithmetic, so the edges are
// pinned here: month lengths, leap Februaries, the part-finished current
// month, sittings across midnight and month ends, the finished-book rule, the
// comparison thresholds and the calendar's week alignment.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/stats/heatmap_grid.dart';
import 'package:vellum/stats/month_review.dart';

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
  group('month arithmetic', () {
    test('days in month, including February in leap and non-leap years', () {
      expect(MonthReviews.daysInMonth(2026, 1), 31);
      expect(MonthReviews.daysInMonth(2026, 4), 30);
      expect(MonthReviews.daysInMonth(2026, 2), 28);
      expect(MonthReviews.daysInMonth(2024, 2), 29);
      expect(MonthReviews.daysInMonth(1900, 2), 28);
      expect(MonthReviews.daysInMonth(2000, 2), 29);
      expect(MonthReviews.daysInMonth(2026, 12), 31);
    });

    test('addMonths crosses year ends both ways', () {
      expect(MonthReviews.addMonths(DateTime(2026, 1), -1), DateTime(2025, 12));
      expect(MonthReviews.addMonths(DateTime(2026, 12), 1), DateTime(2027, 1));
      expect(MonthReviews.addMonths(DateTime(2026, 3), -14), DateTime(2025, 1));
    });

    test('months offered: those with a sitting plus this one, newest first',
        () {
      final today = DateTime(2026, 11, 12);
      final sessions = [
        _s(DateTime(2026, 8, 3, 20), 30),
        _s(DateTime(2026, 8, 30, 20), 30),
        _s(DateTime(2026, 5, 1, 7), 10),
      ];
      expect(MonthReviews.monthsWithReading(sessions, today: today),
          [DateTime(2026, 11), DateTime(2026, 8), DateTime(2026, 5)]);
      expect(MonthReviews.firstMonth(sessions, today: today), DateTime(2026, 5));
      expect(MonthReviews.firstMonth([], today: today), DateTime(2026, 11));
    });
  });

  group('review', () {
    final today = DateTime(2026, 11, 12, 15);

    test('a past month counts all its days; the current one only so far', () {
      final sessions = [_s(DateTime(2026, 10, 5, 20), 30, from: 1, to: 11)];
      final past = MonthReviews.review(
        sessions: sessions,
        books: const [],
        month: DateTime(2026, 10),
        today: today,
      );
      final current = MonthReviews.review(
        sessions: sessions,
        books: const [],
        month: DateTime(2026, 11),
        today: today,
      );
      expect(past.daysElapsed, 31);
      expect(MonthReviews.isPartial(past), isFalse);
      expect(current.daysElapsed, 12);
      expect(MonthReviews.isPartial(current), isTrue);
    });

    test('totals, best day, longest sitting and averages', () {
      final sessions = [
        _s(DateTime(2026, 10, 1, 9), 20, from: 1, to: 11), // 10 pages
        _s(DateTime(2026, 10, 1, 21), 45, from: 11, to: 41), // 30 pages
        _s(DateTime(2026, 10, 9, 8), 30, from: 41, to: 61), // 20 pages
        _s(DateTime(2026, 9, 30, 23), 90, from: 1, to: 99), // other month
      ];
      final r = MonthReviews.review(
        sessions: sessions,
        books: const [],
        month: DateTime(2026, 10),
        today: today,
      );
      expect(r.pages, 60);
      expect(r.minutes, 95);
      expect(r.readingDays, 2);
      expect(r.best!.day, DateTime(2026, 10, 1));
      expect(r.best!.pages, 40);
      expect(r.best!.minutes, 65);
      expect(r.longestSitting, (day: DateTime(2026, 10, 1), minutes: 45));
      expect(r.averageMinutesPerReadingDay, 48); // 47.5 rounds up
      expect(r.isEmpty, isFalse);
    });

    test('a sitting that starts on the last evening stays in that month', () {
      final sessions = [
        _s(DateTime(2026, 10, 31, 23, 30), 60, from: 1, to: 6),
      ];
      final oct = MonthReviews.review(
        sessions: sessions,
        books: const [],
        month: DateTime(2026, 10),
        today: today,
      );
      final nov = MonthReviews.review(
        sessions: sessions,
        books: const [],
        month: DateTime(2026, 11),
        today: today,
      );
      expect(oct.minutes, 60);
      expect(nov.isEmpty, isTrue);
    });

    test('best day falls back to minutes when no pages were recorded', () {
      final sessions = [
        _s(DateTime(2026, 10, 2, 9), 10),
        _s(DateTime(2026, 10, 3, 9), 50),
      ];
      final r = MonthReviews.review(
        sessions: sessions,
        books: const [],
        month: DateTime(2026, 10),
        today: today,
      );
      expect(r.pages, 0);
      expect(r.best!.day, DateTime(2026, 10, 3));
    });

    test('a finished book counts in the month of its finishedAt', () {
      final books = [
        _book('a', finishedAt: DateTime(2026, 10, 31, 23, 59)),
        _book('b', finishedAt: DateTime(2026, 11, 1)),
        _book('c', finishedAt: DateTime(2026, 10, 2)),
        _book('d'),
      ];
      final oct = MonthReviews.review(
        sessions: const [],
        books: books,
        month: DateTime(2026, 10),
        today: today,
      );
      expect([for (final b in oct.finished) b.id], ['c', 'a']);
      // No sitting, but a finished book: not an empty month.
      expect(oct.isEmpty, isFalse);
      expect(oct.readingDays, 0);
      expect(oct.averageMinutesPerReadingDay, isNull);
    });

    test('a month with nothing in it is empty', () {
      final r = MonthReviews.review(
        sessions: const [],
        books: const [],
        month: DateTime(2026, 10),
        today: today,
      );
      expect(r.isEmpty, isTrue);
      expect(r.best, isNull);
      expect(r.longestSitting, isNull);
    });

    test('goal days: those at or over the target; null with no goal', () {
      final sessions = [
        _s(DateTime(2026, 10, 1, 9), 30),
        _s(DateTime(2026, 10, 2, 9), 29),
        _s(DateTime(2026, 10, 3, 9), 20),
        _s(DateTime(2026, 10, 3, 21), 15), // 35 together
      ];
      MonthReview with_(int? goal) => MonthReviews.review(
            sessions: sessions,
            books: const [],
            month: DateTime(2026, 10),
            today: today,
            minuteGoal: goal,
          );
      expect(with_(30).goalDaysMet, 2);
      expect(with_(null).goalDaysMet, isNull);
      expect(with_(0).goalDaysMet, isNull);
    });
  });

  group('comparison', () {
    test('a previous month with nothing is "none", never a division', () {
      expect(MonthReviews.compare(50, 0).trend, MonthTrend.none);
      expect(MonthReviews.compare(0, 0).trend, MonthTrend.none);
    });

    test('under 5% either way is the same', () {
      expect(MonthReviews.compare(100, 100).trend, MonthTrend.same);
      expect(MonthReviews.compare(104, 100).trend, MonthTrend.same);
      expect(MonthReviews.compare(96, 100).trend, MonthTrend.same);
    });

    test('5% and over is more or less, with a rounded percentage', () {
      final more = MonthReviews.compare(105, 100);
      expect(more.trend, MonthTrend.more);
      expect(more.percent, 5);
      final less = MonthReviews.compare(90, 100);
      expect(less.trend, MonthTrend.less);
      expect(less.percent, 10);
      expect(MonthReviews.compare(112, 100).percent, 12);
      expect(MonthReviews.compare(300, 100).percent, 200);
    });

    test('nothing read against something is honestly 100% less', () {
      final c = MonthReviews.compare(0, 40);
      expect(c.trend, MonthTrend.less);
      expect(c.percent, 100);
    });

    test('the current month is weighed against the same days before', () {
      final sessions = [
        _s(DateTime(2026, 10, 3, 9), 30, from: 1, to: 11),
        _s(DateTime(2026, 10, 20, 9), 60, from: 11, to: 61),
        _s(DateTime(2026, 11, 2, 9), 30, from: 1, to: 11),
      ];
      final today = DateTime(2026, 11, 5);
      final r = MonthReviews.review(
        sessions: sessions,
        books: const [],
        month: DateTime(2026, 11),
        today: today,
      );
      final f = MonthReviews.previousFigures(sessions: sessions, review: r);
      // Only 1-5 October: the sitting on the 20th is not a fair comparison.
      expect(f.minutes, 30);
      expect(f.pages, 10);

      final full = MonthReviews.review(
        sessions: sessions,
        books: const [],
        month: DateTime(2026, 11),
        today: DateTime(2026, 12, 1),
      );
      final ff = MonthReviews.previousFigures(sessions: sessions, review: full);
      expect(ff.minutes, 90);
    });

    test('a short previous month does not run past its end', () {
      final sessions = [_s(DateTime(2026, 2, 27, 9), 30, from: 1, to: 11)];
      final r = MonthReviews.review(
        sessions: sessions,
        books: const [],
        month: DateTime(2026, 3),
        today: DateTime(2026, 3, 31),
      );
      final f = MonthReviews.previousFigures(sessions: sessions, review: r);
      expect(f.minutes, 30);
    });
  });

  group('calendar layout', () {
    // 1 November 2026 is a Sunday; 1 October 2026 a Thursday.
    test('weeks starting on Sunday', () {
      expect(MonthReviews.leadingBlanks(DateTime(2026, 11), 0), 0);
      expect(MonthReviews.leadingBlanks(DateTime(2026, 10), 0), 4);
      expect(MonthReviews.weekRows(DateTime(2026, 11), 0), 5);
      expect(MonthReviews.weekRows(DateTime(2026, 10), 0), 5);
    });

    test('weeks starting on Monday', () {
      expect(MonthReviews.leadingBlanks(DateTime(2026, 11), 1), 6);
      expect(MonthReviews.leadingBlanks(DateTime(2026, 10), 1), 3);
      expect(MonthReviews.weekRows(DateTime(2026, 11), 1), 6);
    });

    test('weeks starting on Saturday', () {
      expect(MonthReviews.leadingBlanks(DateTime(2026, 11), 6), 1);
      expect(MonthReviews.leadingBlanks(DateTime(2026, 10), 6), 5);
    });

    test('rows needed: four, five and six', () {
      // February 2026 starts on a Sunday and has 28 days: exactly 4 rows.
      expect(MonthReviews.weekRows(DateTime(2026, 2), 0), 4);
      expect(MonthReviews.weekRows(DateTime(2026, 2), 1), 5);
      // A 31-day month starting on Saturday needs 6 rows (Sunday start).
      expect(MonthReviews.weekRows(DateTime(2025, 6), 0), 5);
      expect(MonthReviews.weekRows(DateTime(2026, 8), 0), 6);
    });

    test('weekday order rotates from the first day', () {
      expect(MonthReviews.weekdayOrder(0), [0, 1, 2, 3, 4, 5, 6]);
      expect(MonthReviews.weekdayOrder(1), [1, 2, 3, 4, 5, 6, 0]);
      expect(MonthReviews.weekdayOrder(6), [6, 0, 1, 2, 3, 4, 5]);
    });
  });

  group('heat map geometry', () {
    test('row-major (a calendar): seven to a row', () {
      const l = HeatmapLayout(count: 35, rows: 5, columns: 7, rowMajor: true);
      expect(l.position(0), (col: 0, row: 0));
      expect(l.position(8), (col: 1, row: 1));
      expect(l.indexAt(1, 1), 8);
      expect(l.indexAt(7, 0), -1);
      expect(l.indexAt(0, 5), -1);
    });

    test('column-major (weeks as columns): seven to a column', () {
      const l = HeatmapLayout(count: 84, rows: 7, columns: 12, rowMajor: false);
      expect(l.position(8), (col: 1, row: 1));
      expect(l.indexAt(1, 1), 8);
      expect(l.indexAt(11, 6), 83);
    });

    test('a point resolves to the square under it, gap included', () {
      const l = HeatmapLayout(count: 35, rows: 5, columns: 7, rowMajor: true);
      expect(l.indexAtPoint(const Offset(1, 1), 40), 0);
      expect(l.indexAtPoint(const Offset(79, 41), 40), 8);
      expect(l.indexAtPoint(const Offset(-1, 5), 40), -1);
      expect(l.indexAtPoint(const Offset(5, 500), 40), -1);
    });

    test('arrow moves stop at the edge and at blanks', () {
      const l = HeatmapLayout(count: 35, rows: 5, columns: 7, rowMajor: true);
      bool filled(int i) => i >= 4; // four blanks before the 1st
      expect(l.move(4, 1, 0, filled), 5);
      expect(l.move(4, -1, 0, filled), 4);
      expect(l.move(4, 0, -1, filled), 4);
      expect(l.move(4, 0, 1, filled), 11);
      expect(l.move(34, 1, 0, filled), 34);
    });
  });
}
