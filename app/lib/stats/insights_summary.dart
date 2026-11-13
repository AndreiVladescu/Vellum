import 'dart:isolate';

import '../data/database.dart';
import 'insights_range.dart';
import 'stats_queries.dart';

/// What was fetched, before any range is applied.
class InsightsInput {
  const InsightsInput({
    required this.sessions,
    required this.books,
    required this.genresByBook,
    required this.formatsByBook,
  });

  final List<ReadingSession> sessions;
  final List<Book> books;
  final Map<String, List<String>> genresByBook;
  final Map<String, List<String>> formatsByBook;
}

/// Everything the page shows: one fetch, with a range applied.
///
/// **Follow the range:** days read, the totals (pages, time, sessions'
/// average, books finished), the best day, the pages-a-day chart, when you
/// read, where you read, and the books-finished, genre and format lists.
/// **Fixed by nature:** the streaks (a streak is a property of the whole
/// history), this week against last, the 12-week heat map, and the goals
/// (a year and a day by definition).
///
/// Holds only what it worked out, never the sittings and books it read: it is
/// made in a background isolate ([forEveryRange]) and copied back, and the
/// page already has those.
class InsightsSummary {
  InsightsSummary(InsightsInput f, InsightsRange range, DateTime today)
      : range = range {
    final allSessions = f.sessions;
    final sessions = RangeFilter.sessions(f.sessions, range, today);
    final inRange = RangeFilter.finishedBooks(f.books, range, today);
    pagesPerDay = ReadingStats.pagesPerDay(sessions);
    allPagesPerDay = ReadingStats.pagesPerDay(allSessions);
    allMinutesPerDay = ReadingStats.minutesPerDay(allSessions);
    pagesSeries = ReadingStats.dailySeries(
      pagesPerDay,
      days: RangeFilter.chartDays(range, allSessions, today),
      today: today,
    );
    heatmapSeries =
        ReadingStats.dailySeries(allMinutesPerDay, days: 84, today: today);
    allReadingDays = ReadingStats.readingDays(allSessions);
    readingDays = ReadingStats.readingDays(sessions);
    averagePages = ReadingStats.averagePagesPerSession(sessions);
    totalPages = ReadingStats.totalPages(sessions);
    totalMinutes = ReadingStats.totalMinutes(sessions);
    totalFinished = ReadingStats.totalFinished(inRange);
    hourSeries = ReadingStats.minutesByHour(sessions);
    deviceSeries = ReadingStats.minutesByDevice(sessions);
    finishedPerMonth = ReadingStats.finishedPerMonth(inRange);
    genreSplit = ReadingStats.finishedByGenre(
      books: inRange,
      genresByBook: f.genresByBook,
    );
    formatSplit = ReadingStats.finishedByFormat(
      books: inRange,
      formatsByBook: f.formatsByBook,
    );
    currentStreak = ReadingStats.currentStreak(allReadingDays, today: today);
    longestStreak = ReadingStats.longestStreak(allReadingDays);
    best = ReadingStats.bestDay(pagesPerDay);
    thisWeekPages =
        ReadingStats.sumTrailingDays(allPagesPerDay, days: 7, today: today);
    lastWeekPages = ReadingStats.sumTrailingDays(
      allPagesPerDay,
      days: 7,
      endOffsetDays: 7,
      today: today,
    );
  }

  /// Every range's summary at once, worked out in a background isolate.
  ///
  /// All of it is arithmetic over every sitting and book — tens of
  /// milliseconds for a heavy reader's history, more for a long one, which on
  /// the UI isolate was a dropped frame on opening the page and on every tap
  /// of a range chip (performance round, November 2026). Here it costs the
  /// page nothing but the spinner it already shows while fetching, and a
  /// range chip only picks one of four answers that are already there.
  ///
  /// A short history is done in place: below [backgroundFrom] sittings the
  /// whole thing takes less than starting an isolate and copying the history
  /// into it would.
  static Future<Map<InsightsRange, InsightsSummary>> forEveryRange(
    InsightsInput input,
    DateTime today,
  ) async {
    Map<InsightsRange, InsightsSummary> all() => {
          for (final range in InsightsRange.values)
            range: InsightsSummary(input, range, today),
        };
    if (input.sessions.length < backgroundFrom) return all();
    return Isolate.run(all);
  }

  static const backgroundFrom = 1000;

  final InsightsRange range;
  late final Map<DateTime, int> pagesPerDay;
  late final Map<DateTime, int> allPagesPerDay;
  late final Map<DateTime, int> allMinutesPerDay;
  late final List<({DateTime day, int value})> pagesSeries;
  late final List<({DateTime day, int value})> heatmapSeries;
  late final Set<DateTime> allReadingDays;
  late final Set<DateTime> readingDays;
  late final double averagePages;
  late final int totalPages;
  late final int totalMinutes;
  late final int totalFinished;
  late final List<int> hourSeries;
  late final List<({String device, int minutes})> deviceSeries;
  late final Map<DateTime, int> finishedPerMonth;
  late final List<({String genre, int count})> genreSplit;
  late final List<({String format, int count})> formatSplit;

  late final int currentStreak;
  late final int longestStreak;
  late final ({DateTime day, int pages})? best;
  late final int thisWeekPages;
  late final int lastWeekPages;

  List<MapEntry<DateTime, int>> get finishedMonthsNewestFirst {
    final entries = finishedPerMonth.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return entries;
  }
}
