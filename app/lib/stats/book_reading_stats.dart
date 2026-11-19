import '../data/database.dart';
import 'stats_queries.dart';

/// What one audiobook's listening sittings add up to ("Your listening" on the
/// book page): time and the day of the latest one. Wall-clock time, so an hour
/// at 1.5x is an hour; no pages, pace or time left, which are about reading.
class BookListening {
  const BookListening({required this.minutes, required this.last});

  final int minutes;

  /// The local calendar day of the latest listening sitting.
  final DateTime last;

  /// Null when [sessions] holds no listening sitting. Reading sittings in the
  /// list are ignored, so either mix can be passed in.
  static BookListening? of(List<ReadingSession> sessions) {
    final listened = [
      for (final s in sessions)
        if (s.kind == 'listen') s,
    ];
    if (listened.isEmpty) return null;
    var last = listened.first.startedAt;
    for (final s in listened) {
      if (s.startedAt.isAfter(last)) last = s.startedAt;
    }
    return BookListening(
      minutes: ReadingStats.totalMinutes(listened),
      last: ReadingStats.dayOf(last),
    );
  }
}

/// What one book's sittings add up to (roadmap v1.3.1, "Your reading" on the
/// book page). Pure over rows already fetched, like [ReadingStats], which it
/// reuses so the numbers here are the same numbers the reader and the Insights
/// page show.
class BookReading {
  const BookReading({
    required this.minutes,
    required this.sittings,
    required this.first,
    required this.last,
    required this.pagesPerMinute,
  });

  /// Total time over every sitting, in whole minutes.
  final int minutes;
  final int sittings;

  /// The local calendar days of the earliest and latest sitting, by the day
  /// each *began* (the app's rule for attributing a sitting to a day).
  final DateTime first;
  final DateTime last;

  /// Pages a minute for this book alone, or null when it cannot be measured
  /// (no page movement recorded, or only sittings under a minute). Null is
  /// "unknown", never zero.
  final double? pagesPerMinute;

  /// Null when [sessions] is empty: a book with no recorded sitting has no
  /// "Your reading" to show.
  static BookReading? of(List<ReadingSession> all) {
    // Reading sittings only: listening has its own block ([BookListening]) and
    // must not add minutes, sittings or dates here.
    final sessions = [
      for (final s in all)
        if (s.kind == 'read') s,
    ];
    if (sessions.isEmpty) return null;
    var first = sessions.first.startedAt;
    var last = first;
    for (final s in sessions) {
      if (s.startedAt.isBefore(first)) first = s.startedAt;
      if (s.startedAt.isAfter(last)) last = s.startedAt;
    }
    return BookReading(
      minutes: ReadingStats.totalMinutes(sessions),
      sittings: sessions.length,
      first: ReadingStats.dayOf(first),
      last: ReadingStats.dayOf(last),
      pagesPerMinute: ReadingStats.pagesPerMinute(sessions),
    );
  }

  /// Minutes left in the book at its owner's own pace, or null when there is
  /// nothing honest to say.
  ///
  /// Mirrors the reader's page counter, which falls back to a percentage
  /// rather than invent a pace: no estimate without a measured [pace], a
  /// [pageCount], and a [currentPage] to count from, and none once the end
  /// has been reached. A tiny remainder still says one minute rather than
  /// zero, so the line never reads "about 0m".
  static int? minutesLeft({
    required double? pace,
    required int? pageCount,
    required int? currentPage,
  }) {
    if (pace == null || pace <= 0) return null;
    if (pageCount == null || pageCount <= 0) return null;
    if (currentPage == null) return null;
    final left = pageCount - currentPage;
    if (left <= 0) return null;
    final minutes = (left / pace).round();
    return minutes < 1 ? 1 : minutes;
  }
}
