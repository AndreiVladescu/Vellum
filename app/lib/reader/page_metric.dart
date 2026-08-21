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
