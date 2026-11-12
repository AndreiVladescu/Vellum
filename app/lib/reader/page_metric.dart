/// What the counter in the reader's toolbar says.
///
/// "128 / 340" is a fact about the file, and for some readers it is the wrong
/// fact: a long book announces its length on every page turn. Long-press the
/// counter to cycle, or pick one in the reader's options — the counter is the
/// control, so the thing you want to change is the thing you press.
library;

import '../l10n/gen/app_localizations.dart';

enum PageMetric {
  /// `128 / 340` — where you are and how long the book is.
  pagesOf,

  /// `47%` — the vaguest, and what most e-readers show.
  percent,

  /// `page 128` — where you are, without the book looming over it.
  pagesRead,

  /// `96 left` — counts down rather than up.
  pagesLeft,

  /// `about 40 min left`, at the pace your own sittings were read at.
  timeLeft;

  /// The next one along, for the long-press.
  PageMetric get next => PageMetric.values[(index + 1) % PageMetric.values.length];

  static PageMetric parse(String? raw) =>
      PageMetric.values.where((m) => m.name == raw).firstOrNull ??
      PageMetric.pagesOf;
}

/// The counter's text.
///
/// [pagesPerMinute] comes from the reader's own recorded sittings and is null
/// until there are enough of them. Rather than invent a pace, *time left* falls
/// back to the percentage: an honest coarser answer beats a confident wrong
/// one, and the reader can see it is not a time.
String pageMetricLabel(
  L10n l10n,
  PageMetric metric, {
  required int page,
  required int count,
  double? pagesPerMinute,
}) {
  if (count <= 0) return '$page'; // i18n-ignore
  final clamped = page.clamp(1, count);
  switch (metric) {
    case PageMetric.pagesOf:
      return l10n.readerCounterPagesOf(clamped, count);
    case PageMetric.percent:
      return l10n.readerCounterPercent(_percent(clamped, count));
    case PageMetric.pagesRead:
      return l10n.readerCounterPage(clamped);
    case PageMetric.pagesLeft:
      final left = count - clamped;
      return left == 0
          ? l10n.readerCounterLastPage
          : l10n.readerCounterLeft(left);
    case PageMetric.timeLeft:
      final pace = pagesPerMinute;
      if (pace == null || pace <= 0) {
        return l10n.readerCounterPercent(_percent(clamped, count));
      }
      final minutes = ((count - clamped) / pace).round();
      if (minutes <= 0) return l10n.readerCounterNearlyDone;
      if (minutes < 60) return l10n.readerCounterAboutMinutes(minutes);
      final hours = minutes ~/ 60;
      final rest = minutes % 60;
      // "about 2 h left" rather than "about 2 h 0 min left".
      return rest == 0
          ? l10n.readerCounterAboutHours(hours)
          : l10n.readerCounterAboutHoursMinutes(hours, rest);
  }
}

int _percent(int page, int count) => ((page / count) * 100).round();

/// The line shown in the corner while the chrome is hidden (requests 8/19 #5
/// and #6: "see the page number, progress, hours till you finish the book…",
/// and "only in reading mode, since you'd see that on the top bar otherwise").
///
/// Everything the toolbar would have said, in one short line, because the
/// toolbar is gone: where you are, how far through, and — when the reader's own
/// pace has been measured — how much is left. Nothing here is invented: with no
/// measured pace the line is simply shorter.
///
/// [unit] is `'chapter'` for an EPUB and anything else for a page.
String readingModeStatus(
  L10n l10n, {
  required int page,
  required int count,
  double? pagesPerMinute,
  String unit = 'page',
}) {
  if (count <= 0) return l10n.readerStatusOnly(unit, page);
  final clamped = page.clamp(1, count);
  final parts = <String>[
    l10n.readerStatusOf(unit, clamped, count),
    l10n.readerStatusPercent(_percent(clamped, count)),
  ];
  final pace = pagesPerMinute;
  if (pace != null && pace > 0) {
    // The same wording as the counter, minus the "about" that reads as padding
    // in a line this short.
    final minutes = ((count - clamped) / pace).round();
    if (minutes <= 0) {
      parts.add(l10n.readerCounterNearlyDone);
    } else if (minutes < 60) {
      parts.add(l10n.readerStatusMinutes(minutes));
    } else {
      final hours = minutes ~/ 60;
      final rest = minutes % 60;
      parts.add(rest == 0
          ? l10n.readerStatusHours(hours)
          : l10n.readerStatusHoursMinutes(hours, rest));
    }
  }
  return parts.join('  ·  ');
}
