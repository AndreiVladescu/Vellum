import '../data/database.dart';
import 'stats_queries.dart';

/// Everything the year-in-review page and its picture show for one calendar
/// year (roadmap v1.3.5).
class YearReview {
  const YearReview({
    required this.year,
    required this.pages,
    required this.minutes,
    required this.readingDays,
    required this.longestStreak,
    required this.bestMonth,
    required this.longestSitting,
    required this.finished,
    required this.minutesByMonth,
    required this.topAuthors,
    required this.topGenres,
    required this.goalBooks,
  });

  final int year;
  final int pages;
  final int minutes;

  /// Days with at least one sitting.
  final int readingDays;

  /// Longest run of consecutive reading days inside the year (a run that
  /// began in December of the year before counts from 1 January).
  final int longestStreak;

  /// The month (1-12) with the most minutes (ties: more pages, then the
  /// earlier month). Null when the year has no sitting.
  final ({int month, int minutes, int pages})? bestMonth;

  /// The single longest sitting, in whole minutes, with the day it began.
  final ({DateTime day, int minutes})? longestSitting;

  /// Books whose `finishedAt` falls in the year, oldest first.
  final List<Book> finished;

  /// Twelve entries, January first.
  final List<int> minutesByMonth;

  /// Most-finished authors and genres, at most [YearReviews.topCount] each.
  final List<({String name, int count})> topAuthors;
  final List<({String name, int count})> topGenres;

  /// The books-a-year goal, or null when none is set.
  final int? goalBooks;

  /// Nothing happened: no sitting and no finished book.
  bool get isEmpty => readingDays == 0 && finished.isEmpty;

  int get booksFinished => finished.length;

  /// Whether the books goal was reached; null with no goal.
  bool? get goalReached =>
      goalBooks == null ? null : booksFinished >= goalBooks!;
}

/// The same measures for another year, for the comparison lines.
typedef YearFigures = ({int books, int pages, int minutes, int readingDays});

/// Year arithmetic and the year review. Pure over rows already fetched, like
/// `MonthReviews`, and it uses the same day rule: a sitting belongs to the
/// local day it started.
class YearReviews {
  const YearReviews._();

  static const topCount = 3;

  /// Years that have a sitting or a finished book, newest first, plus
  /// [today]'s year so the page always has somewhere to open.
  static List<int> yearsWithActivity({
    required List<ReadingSession> sessions,
    required List<Book> books,
    required DateTime today,
  }) {
    final years = <int>{
      today.toLocal().year,
      for (final s in sessions) s.startedAt.toLocal().year,
      for (final b in books)
        if (b.finishedAt != null) b.finishedAt!.toLocal().year,
    };
    return years.toList()..sort((a, b) => b.compareTo(a));
  }

  static YearReview review({
    required List<ReadingSession> sessions,
    required List<Book> books,
    required int year,
    Map<String, List<String>> authorsByBook = const {},
    Map<String, List<String>> genresByBook = const {},
    int? bookGoal,
  }) {
    final inYear = [
      for (final s in sessions)
        if (s.startedAt.toLocal().year == year) s,
    ];
    final days = ReadingStats.readingDays(inYear);
    final minutesByDay = ReadingStats.minutesPerDay(inYear);
    final pagesByDay = ReadingStats.pagesPerDay(inYear);

    final minutesByMonth = List<int>.filled(12, 0);
    final pagesByMonth = List<int>.filled(12, 0);
    for (final e in minutesByDay.entries) {
      minutesByMonth[e.key.month - 1] += e.value;
    }
    for (final e in pagesByDay.entries) {
      pagesByMonth[e.key.month - 1] += e.value;
    }
    ({int month, int minutes, int pages})? best;
    for (var i = 0; i < 12; i++) {
      if (minutesByMonth[i] == 0 && pagesByMonth[i] == 0) continue;
      final b = best;
      // Strict comparisons, so an earlier month wins a tie.
      if (b == null ||
          minutesByMonth[i] > b.minutes ||
          (minutesByMonth[i] == b.minutes && pagesByMonth[i] > b.pages)) {
        best =
            (month: i + 1, minutes: minutesByMonth[i], pages: pagesByMonth[i]);
      }
    }

    ({DateTime day, int minutes})? longest;
    for (final s in inYear) {
      final m = s.endedAt.difference(s.startedAt).inMinutes;
      if (m <= 0) continue;
      final l = longest;
      if (l == null || m > l.minutes) {
        longest = (day: ReadingStats.dayOf(s.startedAt), minutes: m);
      }
    }

    final finished = [
      for (final b in books)
        if (b.finishedAt != null && b.finishedAt!.toLocal().year == year) b,
    ]..sort((a, b) => a.finishedAt!.compareTo(b.finishedAt!));

    return YearReview(
      year: year,
      pages: ReadingStats.totalPages(inYear),
      minutes: ReadingStats.totalMinutes(inYear),
      readingDays: days.length,
      longestStreak: ReadingStats.longestStreak(days),
      bestMonth: best,
      longestSitting: longest,
      finished: finished,
      minutesByMonth: minutesByMonth,
      topAuthors: _top(finished, authorsByBook),
      topGenres: _top(finished, genresByBook),
      goalBooks: bookGoal != null && bookGoal > 0 ? bookGoal : null,
    );
  }

  /// Names counted once per finished book, most common first (ties by name).
  static List<({String name, int count})> _top(
    List<Book> finished,
    Map<String, List<String>> namesByBook,
  ) {
    final counts = <String, int>{};
    for (final book in finished) {
      // A set, so a book that lists one name twice still counts once.
      for (final name in (namesByBook[book.id] ?? const <String>[]).toSet()) {
        counts[name] = (counts[name] ?? 0) + 1;
      }
    }
    final out = [
      for (final e in counts.entries) (name: e.key, count: e.value),
    ]..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : a.name.compareTo(b.name);
      });
    return out.take(topCount).toList();
  }

  /// The headline figures of the year before [year], for `MonthReviews.compare`.
  static YearFigures previousFigures({
    required List<ReadingSession> sessions,
    required List<Book> books,
    required int year,
  }) {
    final prev = review(sessions: sessions, books: books, year: year - 1);
    return (
      books: prev.booksFinished,
      pages: prev.pages,
      minutes: prev.minutes,
      readingDays: prev.readingDays,
    );
  }
}
