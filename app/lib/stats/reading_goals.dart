import '../data/database.dart';
import 'stats_queries.dart';

/// Reading goals (roadmap v1.3.1): the arithmetic only.
///
/// Two optional goals, both off by default: **books finished this calendar
/// year** and **minutes read per day**. Everything here is pure over rows
/// already fetched, like [ReadingStats], so the date edge cases (1 January,
/// 31 December, leap years, midnight) are testable without a database or a
/// widget.
class ReadingGoals {
  const ReadingGoals._();

  /// Quick picks offered next to "no goal" and a free number.
  static const bookPresets = [12, 24, 52];
  static const minutePresets = [15, 30, 60];

  /// Upper bounds for the free number. A book a day and a full day of
  /// reading are already past anything meant seriously; the bound is there so
  /// a typo cannot store a number the progress bar divides by.
  static const maxBooks = 365;
  static const maxMinutes = 1440;

  /// A stored or typed goal made safe: zero, negative and missing all mean
  /// "no goal" (null), and anything above [max] is clamped to it.
  static int? normalise(int? value, {required int max}) {
    if (value == null || value <= 0) return null;
    return value > max ? max : value;
  }

  static bool isLeapYear(int year) =>
      (year % 4 == 0 && year % 100 != 0) || year % 400 == 0;

  static int daysInYear(int year) => isLeapYear(year) ? 366 : 365;

  /// 1 for 1 January up to 365 (366 in a leap year) for 31 December. Built
  /// from the dates rather than from `Duration.inDays`, which a daylight-saving
  /// day (23 hours) would round down a day.
  static int dayOfYear(DateTime date) {
    final local = date.toLocal();
    final start = DateTime.utc(local.year);
    final day = DateTime.utc(local.year, local.month, local.day);
    return day.difference(start).inDays + 1;
  }

  /// Books finished in [year], one per book.
  ///
  /// **Re-reads.** `finishedAt` is stamped each time a book is marked
  /// finished (the previous date is overwritten) and cleared when it moves
  /// back out of "finished", while `readCount` only ever grows. So a book
  /// finished in 2025 and finished again in 2026 carries a 2026 date and
  /// counts for 2026; the year goal asks "what did I finish this year", and
  /// the re-read answers it. A book counts once however many times it was
  /// finished within the year, because there is only one date to read, and a
  /// re-read in progress (status moved back to reading, date cleared) is not
  /// counted until it is finished again. The cost is that last year's tally
  /// loses a book that has since been re-read; it is the only way to count
  /// from one date, and the monthly list on the same page behaves identically.
  static int finishedInYear(List<Book> books, int year) {
    var count = 0;
    for (final book in books) {
      final at = book.finishedAt;
      if (at == null) continue;
      if (at.toLocal().year == year) count++;
    }
    return count;
  }

  /// How the year is going against an even pace.
  ///
  /// The even pace is `target * dayOfYear / daysInYear`, rounded down, so
  /// 1 January expects almost nothing (never a book "behind" before the year
  /// has started) and 31 December expects the whole target. [difference] is
  /// finished minus expected: positive is ahead, negative behind, zero on
  /// pace. [reached] is true once the target is met, whatever the date.
  static ({int expected, int difference, bool reached}) yearPace({
    required int finished,
    required int target,
    required DateTime today,
  }) {
    final local = today.toLocal();
    final expected =
        target * dayOfYear(local) ~/ daysInYear(local.year);
    return (
      expected: expected,
      difference: finished - expected,
      reached: finished >= target,
    );
  }

  /// Minutes read on the local day of [today] (zero when none).
  ///
  /// [minutesPerDay] is [ReadingStats.minutesPerDay]: a sitting counts whole
  /// toward the day it *started*, so one that runs past midnight is not split.
  static int minutesToday(Map<DateTime, int> minutesPerDay, DateTime today) =>
      minutesPerDay[ReadingStats.dayOf(today)] ?? 0;

  /// How many of the last [days] days (today included) reached [target]
  /// minutes. A target of zero or less is "no goal" and nothing meets it.
  static int daysMet(
    Map<DateTime, int> minutesPerDay, {
    required int target,
    required DateTime today,
    int days = 7,
  }) {
    if (target <= 0) return 0;
    final end = ReadingStats.dayOf(today);
    var met = 0;
    for (var i = 0; i < days; i++) {
      final day = DateTime(end.year, end.month, end.day - i);
      if ((minutesPerDay[day] ?? 0) >= target) met++;
    }
    return met;
  }
}
