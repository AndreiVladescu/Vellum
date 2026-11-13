// Year in review (roadmap v1.3.5): the pure computation. Pins the year
// boundary rule, the best-month tie-break, streaks, empty years, top lists
// and the previous-year figures.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/stats/month_review.dart';
import 'package:vellum/stats/year_review.dart';

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
  test('an empty year is empty and has no best month or sitting', () {
    final r = YearReviews.review(sessions: [], books: [], year: 2026);
    expect(r.isEmpty, isTrue);
    expect(r.bestMonth, isNull);
    expect(r.longestSitting, isNull);
    expect(r.longestStreak, 0);
    expect(r.minutesByMonth, everyElement(0));
    expect(r.goalBooks, isNull);
    expect(r.goalReached, isNull);
  });

  test('only the year asked for counts; a sitting belongs to its start day',
      () {
    final r = YearReviews.review(
      sessions: [
        // Begun on New Year's Eve and running into 2027: still 2026.
        _s(DateTime(2026, 12, 31, 23, 30), 60, from: 1, to: 11),
        _s(DateTime(2027, 1, 1, 10), 30, from: 11, to: 21),
        _s(DateTime(2025, 12, 31, 22), 30, from: 1, to: 6),
      ],
      books: [],
      year: 2026,
    );
    expect(r.minutes, 60);
    expect(r.pages, 10);
    expect(r.readingDays, 1);
    expect(r.bestMonth?.month, 12);
    expect(r.longestSitting?.minutes, 60);
    expect(r.longestSitting?.day, DateTime(2026, 12, 31));
  });

  test('longest streak runs within the year; best month is the busiest', () {
    final r = YearReviews.review(
      sessions: [
        _s(DateTime(2026, 3, 1, 20), 30),
        _s(DateTime(2026, 3, 2, 20), 30),
        _s(DateTime(2026, 3, 3, 20), 30),
        _s(DateTime(2026, 3, 10, 20), 30),
        _s(DateTime(2026, 5, 1, 20), 30),
        _s(DateTime(2026, 5, 2, 20), 30),
        _s(DateTime(2026, 5, 3, 20), 30),
        _s(DateTime(2026, 5, 4, 20), 20),
      ],
      books: [],
      year: 2026,
    );
    expect(r.longestStreak, 4);
    expect(r.minutesByMonth[2], 120);
    expect(r.minutesByMonth[4], 110);
    expect(r.bestMonth?.month, 3);
  });

  test('equal months: more pages wins, then the earlier month', () {
    final r = YearReviews.review(
      sessions: [
        _s(DateTime(2026, 2, 1, 20), 30, from: 1, to: 11),
        _s(DateTime(2026, 4, 1, 20), 30, from: 1, to: 21),
        _s(DateTime(2026, 6, 1, 20), 30, from: 1, to: 21),
      ],
      books: [],
      year: 2026,
    );
    expect(r.bestMonth?.month, 4);
  });

  test('finished books, top authors and genres, goal', () {
    final a = _book('a', finishedAt: DateTime(2026, 6, 1));
    final b = _book('b', finishedAt: DateTime(2026, 2, 1));
    final c = _book('c', finishedAt: DateTime(2026, 9, 1));
    final d = _book('d', finishedAt: DateTime(2025, 9, 1));
    final e = _book('e'); // not finished
    final r = YearReviews.review(
      sessions: [],
      books: [a, b, c, d, e],
      year: 2026,
      authorsByBook: {
        'a': ['Le Guin'],
        'b': ['Le Guin', 'Le Guin'],
        'c': ['Clarke'],
        'd': ['Clarke'],
        'e': ['Clarke'],
      },
      genresByBook: {
        'a': ['Sci-fi'],
        'b': ['Sci-fi', 'Classic'],
        'c': ['Essay'],
      },
      bookGoal: 3,
    );
    expect(r.isEmpty, isFalse);
    expect(r.finished.map((x) => x.id), ['b', 'a', 'c']);
    expect(r.topAuthors.first, (name: 'Le Guin', count: 2));
    expect(r.topAuthors.length, 2);
    expect(r.topGenres.map((g) => g.name), ['Sci-fi', 'Classic', 'Essay']);
    expect(r.goalReached, isTrue);
    final short =
        YearReviews.review(sessions: [], books: [a], year: 2026, bookGoal: 3);
    expect(short.goalReached, isFalse);
    expect(
        YearReviews.review(sessions: [], books: [], year: 2026, bookGoal: 0)
            .goalBooks,
        isNull);
  });

  test('years offered: those with activity plus this year, newest first', () {
    final years = YearReviews.yearsWithActivity(
      sessions: [_s(DateTime(2023, 5, 1), 10)],
      books: [_book('a', finishedAt: DateTime(2024, 5, 1))],
      today: DateTime(2026, 11, 13),
    );
    expect(years, [2026, 2024, 2023]);
  });

  test('previous-year figures feed the comparison', () {
    final sessions = [
      _s(DateTime(2025, 4, 1, 20), 100, from: 1, to: 101),
      _s(DateTime(2026, 4, 1, 20), 150, from: 1, to: 151),
    ];
    final prev =
        YearReviews.previousFigures(sessions: sessions, books: [], year: 2026);
    expect(prev.minutes, 100);
    expect(prev.pages, 100);
    expect(prev.readingDays, 1);
    final cmp = MonthReviews.compare(150, prev.minutes);
    expect(cmp.trend, MonthTrend.more);
    expect(cmp.percent, 50);
    expect(
        YearReviews.previousFigures(sessions: [], books: [], year: 2026).books,
        0);
  });
}
