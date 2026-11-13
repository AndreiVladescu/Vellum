import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';

import '../l10n/gen/app_localizations.dart';
import 'duration_label.dart';
import 'year_review.dart';

/// The shareable picture of a year (roadmap v1.3.5): a fixed-size card with
/// the reading numbers and the year, and nothing else (no titles of books, no
/// names, no library name).
///
/// It is drawn from the current theme's colour scheme, so it reads well in
/// light and dark. Its size and text scale are fixed so the saved picture
/// looks the same whatever the window or the system font size.
class YearCard extends StatelessWidget {
  const YearCard({super.key, required this.review});

  final YearReview review;

  /// Logical size of the card; [captureYearCard] renders it at a higher
  /// pixel ratio for a sharp PNG.
  static const size = Size(360, 520);

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final textTheme = Theme.of(context).textTheme;
    final fg = scheme.onPrimaryContainer;
    final best = review.bestMonth;

    // The numbers under the big one: label above, value below.
    final facts = <({String label, String value})>[
      (label: l10n.insightsPagesRead, value: '${review.pages}'), // i18n-ignore
      (label: l10n.monthTimeRead, value: formatMinutes(l10n, review.minutes)),
      (label: l10n.insightsDaysRead, value: '${review.readingDays}'), // i18n-ignore
      (
        label: l10n.insightsLongestStreak,
        value: l10n.insightsDaysShort(review.longestStreak)
      ),
      if (best != null)
        (
          label: l10n.yearBestMonth,
          value: l10n.yearMonthName(DateTime(review.year, best.month)),
        ),
    ];

    return MediaQuery(
      // Ignore the system font scale: the card is a picture.
      data: MediaQuery.of(context).copyWith(textScaler: TextScaler.noScaling),
      child: Semantics(
        container: true,
        label: l10n.yearPictureSemantics(
          '${review.year}', // i18n-ignore
          '${review.booksFinished} ${l10n.yearCardBooks(review.booksFinished)}', // i18n-ignore
          review.pages,
          formatMinutes(l10n, review.minutes),
        ),
        child: ExcludeSemantics(
          child: SizedBox.fromSize(
            size: size,
            child: DecoratedBox(
              decoration: BoxDecoration(
                color: scheme.primaryContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              child: Padding(
                padding: const EdgeInsets.all(28),
                child: DefaultTextStyle.merge(
                  style: TextStyle(color: fg),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        crossAxisAlignment: CrossAxisAlignment.baseline,
                        textBaseline: TextBaseline.alphabetic,
                        children: [
                          Flexible(
                            child: Text(
                              l10n.yearTitle,
                              overflow: TextOverflow.ellipsis,
                              style: textTheme.titleMedium
                                  ?.copyWith(color: fg.withValues(alpha: 0.8)),
                            ),
                          ),
                          Text(
                            l10n.yearHeading('${review.year}'), // i18n-ignore
                            style: textTheme.titleLarge?.copyWith(
                                color: fg, fontWeight: FontWeight.bold),
                          ),
                        ],
                      ),
                      const SizedBox(height: 20),
                      Text(
                        '${review.booksFinished}', // i18n-ignore
                        style: textTheme.displayMedium?.copyWith(
                          color: fg,
                          fontWeight: FontWeight.bold,
                          height: 1,
                        ),
                      ),
                      Text(
                        l10n.yearCardBooks(review.booksFinished),
                        style: textTheme.titleMedium?.copyWith(color: fg),
                      ),
                      const SizedBox(height: 20),
                      _MonthBars(
                        values: review.minutesByMonth,
                        color: scheme.primary,
                        faint: fg.withValues(alpha: 0.15),
                      ),
                      const Spacer(),
                      Wrap(
                        spacing: 24,
                        runSpacing: 14,
                        children: [
                          for (final f in facts)
                            SizedBox(
                              width: 130,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    f.value,
                                    style: textTheme.titleLarge?.copyWith(
                                        color: fg,
                                        fontWeight: FontWeight.w600),
                                  ),
                                  Text(
                                    f.label,
                                    style: textTheme.bodySmall?.copyWith(
                                        color: fg.withValues(alpha: 0.8)),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Twelve bars, one per month, scaled to the busiest month. A month without
/// reading keeps a thin stub so the row still reads as twelve months.
class _MonthBars extends StatelessWidget {
  const _MonthBars({
    required this.values,
    required this.color,
    required this.faint,
  });

  final List<int> values;
  final Color color;
  final Color faint;

  @override
  Widget build(BuildContext context) {
    final maxValue = values.fold<int>(0, (m, v) => v > m ? v : m);
    return SizedBox(
      height: 56,
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (var i = 0; i < values.length; i++) ...[
            if (i > 0) const SizedBox(width: 6),
            Expanded(
              child: FractionallySizedBox(
                heightFactor: maxValue == 0 || values[i] == 0
                    ? 0.04
                    : (values[i] / maxValue).clamp(0.08, 1.0),
                child: DecoratedBox(
                  decoration: BoxDecoration(
                    color: values[i] == 0 ? faint : color,
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// Renders the widget under [boundaryKey] (a `RepaintBoundary`) to PNG bytes.
///
/// `RenderRepaintBoundary.toImage` rasterises that subtree on its own, which
/// is how a widget becomes a picture without a screenshot. [pixelRatio] 3
/// makes the 360x520 card a 1080x1560 image.
Future<Uint8List> captureYearCard(
  GlobalKey boundaryKey, {
  double pixelRatio = 3,
}) async {
  final boundary =
      boundaryKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
  final ui.Image image = await boundary.toImage(pixelRatio: pixelRatio);
  try {
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    return data!.buffer.asUint8List();
  } finally {
    image.dispose();
  }
}
