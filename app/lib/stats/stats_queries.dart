import '../data/database.dart';

/// Reading statistics derived from the session log (plan 5 #19).
///
/// Every function here is **pure** over rows already fetched, for two reasons:
/// dates are where this kind of code goes wrong (DST, month ends, time zones), so
/// the arithmetic has to be testable without a database; and the insights page
/// wants several views of the same rows, which would otherwise be several queries.
class ReadingStats {
  const ReadingStats._();

  /// A calendar day in local time, as the key everything groups by.
  ///
  /// Local, not UTC: "did I read yesterday?" is a question about the reader's own
  /// day. A session that starts at 23:30 counts for the day it started.
  static DateTime dayOf(DateTime moment) {
    final local = moment.toLocal();
    return DateTime(local.year, local.month, local.day);
  }

  /// Pages read per day. A session with unknown pages contributes nothing,
  /// rather than a guess.
  static Map<DateTime, int> pagesPerDay(List<ReadingSession> sessions) {
    final out = <DateTime, int>{};
    for (final s in sessions) {
      final start = s.startPage;
      final end = s.endPage;
      if (start == null || end == null) continue;
      // Backwards movement (re-reading, jumping back) counts as zero rather than
      // negative — a day of revision shouldn't subtract from the total.
      final pages = (end - start).clamp(0, 1 << 30);
      if (pages == 0) continue;
      final day = dayOf(s.startedAt);
      out[day] = (out[day] ?? 0) + pages;
    }
    return out;
  }

  /// Minutes spent reading per day.
  static Map<DateTime, int> minutesPerDay(List<ReadingSession> sessions) {
    final out = <DateTime, int>{};
    for (final s in sessions) {
      final minutes = s.endedAt.difference(s.startedAt).inMinutes;
      if (minutes <= 0) continue;
      final day = dayOf(s.startedAt);
      out[day] = (out[day] ?? 0) + minutes;
    }
    return out;
  }

  /// Pages a minute, measured from what has actually been read.
  ///
  /// Feeds the reader's *time left* counter and the speed auto-scroll starts
  /// at, so both answer "how fast do **you** read" rather than a number someone
  /// picked. Null when there is nothing to measure from — a fresh library, or
  /// sessions that never recorded a page — because a made-up pace is worse than
  /// an absent one: it produces a confident "about 20 minutes left" that is
  /// wrong every time.
  ///
  /// Sessions shorter than a minute are dropped rather than extrapolated: a
  /// reader who opened a book, turned two pages and closed it did not read 120
  /// pages an hour.
  static double? pagesPerMinute(List<ReadingSession> sessions) {
    var pages = 0;
    var minutes = 0;
    for (final s in sessions) {
      final start = s.startPage;
      final end = s.endPage;
      if (start == null || end == null) continue;
      final read = (end - start).clamp(0, 1 << 30);
      final spent = s.endedAt.difference(s.startedAt).inMinutes;
      if (read == 0 || spent < 1) continue;
      pages += read;
      minutes += spent;
    }
    if (minutes == 0 || pages == 0) return null;
    return pages / minutes;
  }

  /// The set of days with any reading at all.
  static Set<DateTime> readingDays(List<ReadingSession> sessions) =>
      {for (final s in sessions) dayOf(s.startedAt)};

  /// The streak ending today (or yesterday), in days.
  ///
  /// Counting yesterday as still-alive is deliberate: at 9am a reader who read
  /// every evening for a month has not broken anything, and showing "0" would be
  /// both discouraging and wrong.
  static int currentStreak(Set<DateTime> days, {DateTime? today}) {
    if (days.isEmpty) return 0;
    final start = dayOf(today ?? DateTime.now());
    // Anchor on today if it has reading, else yesterday; otherwise the streak
    // really is over.
    var cursor = days.contains(start)
        ? start
        : (days.contains(_addDays(start, -1)) ? _addDays(start, -1) : null);
    if (cursor == null) return 0;
    var streak = 0;
    while (days.contains(cursor)) {
      streak++;
      cursor = _addDays(cursor!, -1);
    }
    return streak;
  }

  /// The longest run of consecutive days in the whole history.
  static int longestStreak(Set<DateTime> days) {
    if (days.isEmpty) return 0;
    final sorted = days.toList()..sort();
    var best = 1;
    var run = 1;
    for (var i = 1; i < sorted.length; i++) {
      if (sorted[i] == _addDays(sorted[i - 1], 1)) {
        run++;
        best = run > best ? run : best;
      } else {
        run = 1;
      }
    }
    return best;
  }

  /// Adds days via a *date* arithmetic that survives DST.
  ///
  /// `DateTime.add(Duration(days: 1))` adds 24 hours, which on the two clock-change
  /// days a year lands at 23:00 or 01:00 of the neighbouring day and silently
  /// breaks a streak. Constructing the date instead is exact.
  static DateTime _addDays(DateTime day, int delta) =>
      DateTime(day.year, day.month, day.day + delta);

  /// Average pages per session, over sessions that recorded page movement.
  static double averagePagesPerSession(List<ReadingSession> sessions) {
    var pages = 0;
    var counted = 0;
    for (final s in sessions) {
      final start = s.startPage;
      final end = s.endPage;
      if (start == null || end == null) continue;
      final moved = (end - start).clamp(0, 1 << 30);
      if (moved == 0) continue;
      pages += moved;
      counted++;
    }
    return counted == 0 ? 0 : pages / counted;
  }

  /// Books finished per calendar month, keyed by the first of the month.
  static Map<DateTime, int> finishedPerMonth(List<Book> books) {
    final out = <DateTime, int>{};
    for (final book in books) {
      final at = book.finishedAt;
      if (at == null) continue;
      final local = at.toLocal();
      final month = DateTime(local.year, local.month);
      out[month] = (out[month] ?? 0) + 1;
    }
    return out;
  }

  /// Genre split of finished books, most common first. A book with several
  /// genres counts once per genre — the question is "what do I finish?", not a
  /// partition.
  static List<({String genre, int count})> finishedByGenre({
    required List<Book> books,
    required Map<String, List<String>> genresByBook,
  }) {
    final counts = <String, int>{};
    for (final book in books) {
      if (book.finishedAt == null) continue;
      for (final genre in genresByBook[book.id] ?? const <String>[]) {
        counts[genre] = (counts[genre] ?? 0) + 1;
      }
    }
    final out = [
      for (final e in counts.entries) (genre: e.key, count: e.value),
    ]..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : a.genre.compareTo(b.genre);
      });
    return out;
  }

  /// A dense day-by-day series for the last [days] days, oldest first — what a
  /// sparkline and a heat map both want, with the gaps filled in as zeroes so the
  /// x-axis is time rather than "days I happened to read".
  static List<({DateTime day, int value})> dailySeries(
    Map<DateTime, int> byDay, {
    int days = 30,
    DateTime? today,
  }) {
    final end = dayOf(today ?? DateTime.now());
    return [
      for (var i = days - 1; i >= 0; i--)
        (
          day: _addDays(end, -i),
          value: byDay[_addDays(end, -i)] ?? 0,
        ),
    ];
  }

  /// Every page ever turned, across every sitting. The lifetime counterpart to
  /// [pagesPerDay] — same rule (unknown or backwards movement counts as
  /// nothing), just not broken down by day.
  static int totalPages(List<ReadingSession> sessions) {
    var total = 0;
    for (final s in sessions) {
      final start = s.startPage;
      final end = s.endPage;
      if (start == null || end == null) continue;
      total += (end - start).clamp(0, 1 << 30);
    }
    return total;
  }

  /// Every minute ever spent reading, across every sitting.
  static int totalMinutes(List<ReadingSession> sessions) {
    var total = 0;
    for (final s in sessions) {
      final minutes = s.endedAt.difference(s.startedAt).inMinutes;
      if (minutes > 0) total += minutes;
    }
    return total;
  }

  /// How many books this library has ever marked finished — not per month,
  /// just the one number a shelf of them adds up to.
  static int totalFinished(List<Book> books) =>
      books.where((b) => b.finishedAt != null).length;

  /// The single day with the most pages turned, and how many — a record to
  /// point at, not a trend to read. Null when nothing has been measured.
  static ({DateTime day, int pages})? bestDay(Map<DateTime, int> pagesPerDay) {
    if (pagesPerDay.isEmpty) return null;
    var bestDate = pagesPerDay.keys.first;
    var bestPages = pagesPerDay[bestDate]!;
    for (final entry in pagesPerDay.entries) {
      if (entry.value > bestPages) {
        bestDate = entry.key;
        bestPages = entry.value;
      }
    }
    return (day: bestDate, pages: bestPages);
  }

  /// Minutes read, bucketed by the local hour a sitting *started* in (0..23) —
  /// "when do I actually read", which nothing else here answers. A sitting
  /// that runs past the hour it started in is still counted whole against that
  /// hour, the same way a day is decided by when a sitting began rather than
  /// split across midnight.
  static List<int> minutesByHour(List<ReadingSession> sessions) {
    final out = List<int>.filled(24, 0);
    for (final s in sessions) {
      final minutes = s.endedAt.difference(s.startedAt).inMinutes;
      if (minutes <= 0) continue;
      out[s.startedAt.toLocal().hour] += minutes;
    }
    return out;
  }

  /// Minutes read per device, most first — "where do I actually read", the
  /// reason `ReadingSession.deviceLabel` is recorded at all. A sitting from
  /// before this device sent a label of itself (or synced from one that never
  /// will) is folded into one honest "Unknown device" rather than dropped or
  /// mislabelled.
  static List<({String device, int minutes})> minutesByDevice(
    List<ReadingSession> sessions,
  ) {
    final totals = <String, int>{};
    for (final s in sessions) {
      final minutes = s.endedAt.difference(s.startedAt).inMinutes;
      if (minutes <= 0) continue;
      final label = s.deviceLabel?.trim();
      final key = (label == null || label.isEmpty) ? 'Unknown device' : label;
      totals[key] = (totals[key] ?? 0) + minutes;
    }
    final out = [
      for (final e in totals.entries) (device: e.key, minutes: e.value),
    ]..sort((a, b) {
        final byMinutes = b.minutes.compareTo(a.minutes);
        return byMinutes != 0 ? byMinutes : a.device.compareTo(b.device);
      });
    return out;
  }

  /// Format split of finished books, commonest first — the same "count once
  /// per thing it has, not a partition" rule as [finishedByGenre], so a book
  /// kept as both a PDF and an EPUB counts in both. A physical-only book has
  /// no format and is silently absent, which is correct: it was never read on
  /// a screen.
  static List<({String format, int count})> finishedByFormat({
    required List<Book> books,
    required Map<String, List<String>> formatsByBook,
  }) {
    final counts = <String, int>{};
    for (final book in books) {
      if (book.finishedAt == null) continue;
      for (final format in formatsByBook[book.id] ?? const <String>[]) {
        counts[format] = (counts[format] ?? 0) + 1;
      }
    }
    final out = [
      for (final e in counts.entries) (format: e.key, count: e.value),
    ]..sort((a, b) {
        final byCount = b.count.compareTo(a.count);
        return byCount != 0 ? byCount : a.format.compareTo(b.format);
      });
    return out;
  }

  /// The total over the trailing [days] days up to and including [today] —
  /// one window of a day-by-day map, for comparing this week to the one before
  /// it without a whole second query.
  static int sumTrailingDays(
    Map<DateTime, int> byDay, {
    required int days,
    DateTime? today,
    int endOffsetDays = 0,
  }) {
    final end = dayOf(today ?? DateTime.now());
    var total = 0;
    for (var i = 0; i < days; i++) {
      total += byDay[_addDays(end, -i - endOffsetDays)] ?? 0;
    }
    return total;
  }
}
