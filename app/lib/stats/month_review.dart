import '../data/database.dart';
import 'stats_queries.dart';

/// How one month compares with the one before, for one measure.
enum MonthTrend { more, less, same, none }

/// A comparison ready to be worded: the direction and, for more/less, the
/// whole-number percentage.
typedef MonthComparison = ({MonthTrend trend, int percent});

/// Everything the month-by-month page shows for one calendar month.
class MonthReview {
  const MonthReview({
    required this.month,
    required this.daysElapsed,
    required this.pages,
    required this.minutes,
    required this.readingDays,
    required this.best,
    required this.longestSitting,
    required this.finished,
    required this.minutesByDay,
    required this.pagesByDay,
    required this.goalDaysMet,
  });

  /// The first of the month, local time.
  final DateTime month;

  /// How many days of the month count: all of them for a past month, only
  /// those up to and including today for the current one, so "9 of 12 days"
  /// is never read against days that have not happened.
  final int daysElapsed;

  final int pages;
  final int minutes;

  /// Days with at least one sitting.
  final int readingDays;

  /// The day with the most pages (ties and page-less months fall back to
  /// minutes, then the earlier day). Null when the month has no sitting.
  final ({DateTime day, int pages, int minutes})? best;

  /// The single longest sitting, in whole minutes, with the day it began.
  final ({DateTime day, int minutes})? longestSitting;

  /// Books whose `finishedAt` falls in the month, oldest first.
  final List<Book> finished;

  final Map<DateTime, int> minutesByDay;
  final Map<DateTime, int> pagesByDay;

  /// Days of the month that reached the daily-minutes goal; null when no goal
  /// is set.
  final int? goalDaysMet;

  /// Nothing happened: no sitting and no finished book.
  bool get isEmpty => readingDays == 0 && finished.isEmpty;

  /// Whole minutes per reading day, or null with no reading day.
  int? get averageMinutesPerReadingDay =>
      readingDays == 0 ? null : (minutes / readingDays).round();
}

/// Month arithmetic and the month review (roadmap v1.3.2). Pure over rows
/// already fetched, like [ReadingStats], whose day rule it reuses: a sitting
/// belongs to the local day it started, so a sitting begun at 23:30 on the
/// last evening of a month counts for that month whole.
class MonthReviews {
  const MonthReviews._();

  /// Differences smaller than this share of the earlier month read as "about
  /// the same": a few percent either way is noise, and "3% less" would sound
  /// like a verdict on nothing.
  static const sameThreshold = 0.05;

  /// The first of [moment]'s month, in local time. Remembered per moment, as
  /// `ReadingStats.dayOf` is and for the same reason: the month page asks it
  /// of every sitting on every month it shows.
  static DateTime monthOf(DateTime moment) {
    final cached = _months[moment];
    if (cached != null) return cached;
    final local = ReadingStats.localOf(moment);
    return _months[moment] = DateTime(local.year, local.month);
  }

  static final _months = Expando<DateTime>('MonthReviews.monthOf');

  /// [month] shifted by [delta] whole months (negative goes back). Built from
  /// the parts, so it is exact across year ends and DST.
  static DateTime addMonths(DateTime month, int delta) =>
      DateTime(month.year, month.month + delta);

  static bool isLeapYear(int year) =>
      (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

  /// 28 or 29 for February, by the century rule.
  static int daysInMonth(int year, int month) {
    // Day 0 of the next month is the last day of this one.
    return DateTime(year, month + 1, 0).day;
  }

  /// Months that have a sitting, newest first, plus [today]'s month so the
  /// page always has somewhere to open. Nothing earlier than the first
  /// sitting is ever offered.
  static List<DateTime> monthsWithReading(
    List<ReadingSession> sessions, {
    required DateTime today,
  }) {
    final months = <DateTime>{
      monthOf(today),
      for (final s in sessions) monthOf(s.startedAt),
    };
    return months.toList()..sort((a, b) => b.compareTo(a));
  }

  /// The earliest month with a sitting, or [today]'s month when there is none.
  static DateTime firstMonth(
    List<ReadingSession> sessions, {
    required DateTime today,
  }) {
    var first = monthOf(today);
    for (final s in sessions) {
      final m = monthOf(s.startedAt);
      if (m.isBefore(first)) first = m;
    }
    return first;
  }

  /// Offsets of day 1 within a week row: how many blank cells precede the 1st
  /// when weeks start on [firstDayOfWeekIndex] (0 = Sunday, as
  /// `MaterialLocalizations.firstDayOfWeekIndex`).
  static int leadingBlanks(DateTime month, int firstDayOfWeekIndex) {
    final sundayZero = DateTime(month.year, month.month).weekday % 7;
    return (sundayZero - firstDayOfWeekIndex + 7) % 7;
  }

  /// Rows of weeks the month needs.
  static int weekRows(DateTime month, int firstDayOfWeekIndex) {
    final cells = leadingBlanks(month, firstDayOfWeekIndex) +
        daysInMonth(month.year, month.month);
    return (cells / 7).ceil();
  }

  /// Weekday indexes (0 = Sunday) in display order for the given first day.
  static List<int> weekdayOrder(int firstDayOfWeekIndex) =>
      [for (var i = 0; i < 7; i++) (firstDayOfWeekIndex + i) % 7];

  static MonthReview review({
    required List<ReadingSession> sessions,
    required List<Book> books,
    required DateTime month,
    required DateTime today,
    int? minuteGoal,
  }) {
    final start = DateTime(month.year, month.month);
    final total = daysInMonth(start.year, start.month);
    final todayDay = ReadingStats.dayOf(today);
    final isCurrent = monthOf(todayDay) == start;
    final elapsed = isCurrent ? todayDay.day : total;

    final inMonth = [
      for (final s in sessions)
        if (monthOf(s.startedAt) == start) s,
    ];
    final minutesByDay = ReadingStats.minutesPerDay(inMonth);
    final pagesByDay = ReadingStats.pagesPerDay(inMonth);
    final days = ReadingStats.readingDays(inMonth);

    // Best day: pages first, then minutes, then the earlier day, so a month
    // measured only in time still has a best day.
    ({DateTime day, int pages, int minutes})? best;
    for (final day in days) {
      final candidate = (
        day: day,
        pages: pagesByDay[day] ?? 0,
        minutes: minutesByDay[day] ?? 0,
      );
      final b = best;
      if (b == null ||
          candidate.pages > b.pages ||
          (candidate.pages == b.pages && candidate.minutes > b.minutes) ||
          (candidate.pages == b.pages &&
              candidate.minutes == b.minutes &&
              candidate.day.isBefore(b.day))) {
        best = candidate;
      }
    }

    ({DateTime day, int minutes})? longest;
    for (final s in inMonth) {
      final m = s.endedAt.difference(s.startedAt).inMinutes;
      if (m <= 0) continue;
      final l = longest;
      if (l == null || m > l.minutes) {
        longest = (day: ReadingStats.dayOf(s.startedAt), minutes: m);
      }
    }

    final finished = [
      for (final b in books)
        if (b.finishedAt != null && monthOf(b.finishedAt!) == start) b,
    ]..sort((a, b) => a.finishedAt!.compareTo(b.finishedAt!));

    int? met;
    if (minuteGoal != null && minuteGoal > 0) {
      met = minutesByDay.values.where((m) => m >= minuteGoal).length;
    }

    return MonthReview(
      month: start,
      daysElapsed: elapsed,
      pages: ReadingStats.totalPages(inMonth),
      minutes: ReadingStats.totalMinutes(inMonth),
      readingDays: days.length,
      best: best,
      longestSitting: longest,
      finished: finished,
      minutesByDay: minutesByDay,
      pagesByDay: pagesByDay,
      goalDaysMet: met,
    );
  }

  /// Compares [current] with [previous] for one measure.
  ///
  /// [none] when the previous figure is zero: a percentage of nothing is
  /// undefined, and "infinitely more" is not a sentence. [same] when the
  /// difference is under [sameThreshold] of the previous figure. Otherwise
  /// the percentage is rounded to a whole number; a current figure of zero
  /// against a non-zero one is honestly "100% less".
  static MonthComparison compare(int current, int previous) {
    if (previous <= 0) return (trend: MonthTrend.none, percent: 0);
    final ratio = (current - previous) / previous;
    if (ratio.abs() < sameThreshold) return (trend: MonthTrend.same, percent: 0);
    return (
      trend: ratio > 0 ? MonthTrend.more : MonthTrend.less,
      percent: (ratio.abs() * 100).round(),
    );
  }

  /// The previous month's pages and minutes over the same stretch.
  ///
  /// For the current, part-finished month this covers only the first
  /// [review.daysElapsed] days of the previous one, so day 5 of November is
  /// weighed against the first 5 days of October rather than all of it.
  static ({int pages, int minutes}) previousFigures({
    required List<ReadingSession> sessions,
    required MonthReview review,
  }) {
    final prev = addMonths(review.month, -1);
    final prevDays = daysInMonth(prev.year, prev.month);
    final upTo = review.daysElapsed < prevDays ? review.daysElapsed : prevDays;
    final window = [
      for (final s in sessions)
        if (monthOf(s.startedAt) == prev &&
            ReadingStats.dayOf(s.startedAt).day <= upTo)
          s,
    ];
    return (
      pages: ReadingStats.totalPages(window),
      minutes: ReadingStats.totalMinutes(window),
    );
  }

  /// Whether [review] is a month still in progress.
  static bool isPartial(MonthReview review) =>
      review.daysElapsed < daysInMonth(review.month.year, review.month.month);
}
