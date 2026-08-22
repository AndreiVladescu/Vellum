/// What the counter in the reader's toolbar says.
///
/// "128 / 340" is a fact about the file, and for some readers it is the wrong
/// fact: a long book announces its length on every page turn. Long-press the
/// counter to cycle, or pick one in the reader's options — the counter is the
/// control, so the thing you want to change is the thing you press.
library;

enum PageMetric {
  /// `128 / 340` — where you are and how long the book is.
  pagesOf('Page and total'),

  /// `47%` — the vaguest, and what most e-readers show.
  percent('Percent read'),

  /// `page 128` — where you are, without the book looming over it.
  pagesRead('Pages read'),

  /// `96 left` — counts down rather than up.
  pagesLeft('Pages left'),

  /// `about 40 min left`, at the pace your own sittings were read at.
  timeLeft('Time left');

  const PageMetric(this.label);

  final String label;

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
  PageMetric metric, {
  required int page,
  required int count,
  double? pagesPerMinute,
}) {
  if (count <= 0) return '$page';
  final clamped = page.clamp(1, count);
  switch (metric) {
    case PageMetric.pagesOf:
      return '$clamped / $count';
    case PageMetric.percent:
      return '${_percent(clamped, count)}%';
    case PageMetric.pagesRead:
      return 'page $clamped';
    case PageMetric.pagesLeft:
      final left = count - clamped;
      return left == 0 ? 'last page' : '$left left';
    case PageMetric.timeLeft:
      final pace = pagesPerMinute;
      if (pace == null || pace <= 0) return '${_percent(clamped, count)}%';
      final minutes = ((count - clamped) / pace).round();
      if (minutes <= 0) return 'nearly done';
      if (minutes < 60) return 'about $minutes min left';
      final hours = minutes ~/ 60;
      final rest = minutes % 60;
      // "about 2 h left" rather than "about 2 h 0 min left".
      return rest == 0
          ? 'about $hours h left'
          : 'about $hours h $rest min left';
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
String readingModeStatus({
  required int page,
  required int count,
  double? pagesPerMinute,
  String unit = 'page',
}) {
  if (count <= 0) return '$unit $page';
  final clamped = page.clamp(1, count);
  final parts = <String>[
    '$unit $clamped of $count',
    '${_percent(clamped, count)}%',
  ];
  final pace = pagesPerMinute;
  if (pace != null && pace > 0) {
    final left = pageMetricLabel(
      PageMetric.timeLeft,
      page: clamped,
      count: count,
      pagesPerMinute: pace,
    );
    // The metric's own words, minus the "about" that reads as padding in a
    // line this short.
    parts.add(left.startsWith('about ') ? left.substring(6) : left);
  }
  return parts.join('  ·  ');
}
