import '../data/database.dart';
import 'stats_queries.dart';

/// The range control at the top of the Insights page (roadmap v1.3.2).
///
/// [standard] is what the page showed before the control existed (lifetime
/// totals next to a 30-day chart) and is the default, so nobody who never
/// touches it sees anything change. The other three put one window on every
/// range-aware section.
enum InsightsRange {
  standard,
  last30Days,
  thisYear,
  allTime;

  /// Reads a stored name; anything unknown (an older or newer build wrote it)
  /// is the default rather than an error.
  static InsightsRange parse(String? name) {
    for (final r in values) {
      if (r.name == name) return r;
    }
    return standard;
  }
}

/// Filtering by range, and per-day detail. Pure over rows already fetched,
/// with the same day rule as [ReadingStats]: a sitting belongs to the local day
/// it started, and a finished book to the local day of its `finishedAt`.
class RangeFilter {
  const RangeFilter._();

  /// The first local day inside [range], or null when it has no lower bound.
  ///
  /// "Last 30 days" is today and the 29 before it, the same 30 days the
  /// pages-a-day chart has always drawn.
  static DateTime? start(InsightsRange range, DateTime today) {
    final day = ReadingStats.dayOf(today);
    return switch (range) {
      InsightsRange.standard || InsightsRange.allTime => null,
      InsightsRange.last30Days => DateTime(day.year, day.month, day.day - 29),
      InsightsRange.thisYear => DateTime(day.year),
    };
  }

  static bool _inRange(DateTime moment, DateTime? start) =>
      start == null || !ReadingStats.dayOf(moment).isBefore(start);

  /// The sittings that began inside [range].
  static List<ReadingSession> sessions(
    List<ReadingSession> all,
    InsightsRange range,
    DateTime today,
  ) {
    final from = start(range, today);
    if (from == null) return all;
    return [
      for (final s in all)
        if (_inRange(s.startedAt, from)) s,
    ];
  }

  /// The books to count as finished inside [range]. The functions that read
  /// this list ignore a book without a `finishedAt`, so a bounded range drops
  /// them and an unbounded one passes the list through.
  static List<Book> finishedBooks(
    List<Book> all,
    InsightsRange range,
    DateTime today,
  ) {
    final from = start(range, today);
    if (from == null) return all;
    return [
      for (final b in all)
        if (b.finishedAt != null && _inRange(b.finishedAt!, from)) b,
    ];
  }

  /// How many days the pages-a-day chart spans: the 30 it always had for the
  /// default and last-30 ranges, the days since 1 January for this year, and
  /// the span from the first sitting for all time (never fewer than 30, so a
  /// young history is not stretched across the whole chart).
  static int chartDays(
    InsightsRange range,
    List<ReadingSession> all,
    DateTime today,
  ) {
    final day = ReadingStats.dayOf(today);
    switch (range) {
      case InsightsRange.standard:
      case InsightsRange.last30Days:
        return 30;
      case InsightsRange.thisYear:
        return _daysInclusive(DateTime(day.year), day);
      case InsightsRange.allTime:
        if (all.isEmpty) return 30;
        var first = ReadingStats.dayOf(all.first.startedAt);
        for (final s in all) {
          final d = ReadingStats.dayOf(s.startedAt);
          if (d.isBefore(first)) first = d;
        }
        final span = _daysInclusive(first, day);
        return span < 30 ? 30 : span;
    }
  }
}

/// What one day of reading adds up to, for the sheet a heat-map day opens.
class DayDetail {
  const DayDetail({
    required this.day,
    required this.pages,
    required this.minutes,
    required this.sittings,
    required this.books,
  });

  final DateTime day;
  final int pages;
  final int minutes;
  final int sittings;

  /// Per book read that day, most time first.
  final List<({String bookId, int minutes, int pages})> books;

  bool get isEmpty => sittings == 0;

  /// Totals use the same rules as everywhere else (unknown or backwards page
  /// movement counts as nothing; sittings under a minute add no time), so the
  /// sheet always agrees with the shade of the square it was opened from.
  static DayDetail of(List<ReadingSession> sessions, DateTime day) {
    final target = ReadingStats.dayOf(day);
    final byBook = <String, List<ReadingSession>>{};
    var count = 0;
    for (final s in sessions) {
      if (ReadingStats.dayOf(s.startedAt) != target) continue;
      count++;
      (byBook[s.bookId] ??= []).add(s);
    }
    final books = [
      for (final e in byBook.entries)
        (
          bookId: e.key,
          minutes: ReadingStats.totalMinutes(e.value),
          pages: ReadingStats.totalPages(e.value),
        ),
    ]..sort((a, b) {
        final byMinutes = b.minutes.compareTo(a.minutes);
        if (byMinutes != 0) return byMinutes;
        final byPages = b.pages.compareTo(a.pages);
        return byPages != 0 ? byPages : a.bookId.compareTo(b.bookId);
      });
    return DayDetail(
      day: target,
      pages: books.fold(0, (sum, b) => sum + b.pages),
      minutes: books.fold(0, (sum, b) => sum + b.minutes),
      sittings: count,
      books: books,
    );
  }
}

/// Days from [first] to [last], both counted, by date arithmetic rather than
/// `Duration.inDays`, which a 23-hour daylight-saving day would round down.
int _daysInclusive(DateTime first, DateTime last) =>
    DateTime.utc(last.year, last.month, last.day)
        .difference(DateTime.utc(first.year, first.month, first.day))
        .inDays +
    1;
