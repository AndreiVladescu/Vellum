/// The arithmetic behind the EPUB reader's paged mode (roadmap v1.4.0).
///
/// **How paged mode works.** The chapter is laid out exactly as scrolled mode
/// lays it out — one tall column, by the same `HtmlWidget` — and a page is a
/// window onto that column. Turning a page moves the window; nothing is laid
/// out again. What this file decides is *where the windows start*: a page
/// can't simply be "the next viewport height down", because that cuts through
/// whichever line straddles the bottom edge. So each page ends at the top of
/// the first line that would not fit whole, and the next page starts there.
///
/// Everything here is pure — lines in, page starts out — so it is unit tested
/// without a renderer (`test/reader/epub_pagination_test.dart`). Driving
/// `HtmlWidget` under `testWidgets` hangs (docs/BACKLOG.md), which is why the
/// render-tree side (`paged_chapter.dart`) is kept to measuring and nothing
/// else.
library;

import 'dart:math' as math;

/// Something on the page that must not be cut: one line of text, or a picture.
/// Vertical extent only, in the chapter column's coordinates.
typedef LineSpan = ({double top, double bottom});

/// Lines closer than this to a cut count as touching it, not crossing it —
/// layout produces fractional offsets, and a line whose bottom sits a hair
/// past the edge is not visibly cut.
const _epsilon = 0.5;

/// Where each page of a chapter starts, as offsets down the laid-out column.
///
/// [lines] need not be sorted or disjoint — a table's cells overlap, and a
/// picture inside a line overlaps the line. A page ends at [pageHeight] below
/// its start unless something crosses that edge; then it ends at the *top* of
/// the highest thing crossing it, so that thing starts the next page whole.
///
/// Something taller than a page can't be kept whole, and is ignored when
/// choosing the break (the text inside it, measured separately, still is). A
/// break is never allowed to leave a page empty: if snapping would, the page
/// is cut at the edge instead, so pagination always moves forward.
List<double> paginate({
  required Iterable<LineSpan> lines,
  required double pageHeight,
  required double contentHeight,
}) {
  if (pageHeight <= 0 || contentHeight <= pageHeight + _epsilon) {
    return const [0];
  }
  // Only what fits on a page can be moved to the next one whole.
  final keepable = [
    for (final line in lines)
      if (line.bottom - line.top <= pageHeight &&
          line.bottom > line.top &&
          line.top >= 0)
        line,
  ]..sort((a, b) => a.top.compareTo(b.top));

  final starts = <double>[0];
  var start = 0.0;
  // Index of the first line whose top is below the current page start; lines
  // above it can never cross a later cut, because everything kept is shorter
  // than a page.
  var from = 0;
  while (start + pageHeight < contentHeight - _epsilon) {
    final cut = start + pageHeight;
    while (from < keepable.length && keepable[from].top <= start + _epsilon) {
      from++;
    }
    var breakAt = cut;
    for (var i = from; i < keepable.length; i++) {
      final line = keepable[i];
      if (line.top >= cut - _epsilon) break; // sorted: nothing further crosses
      if (line.bottom > cut + _epsilon) breakAt = math.min(breakAt, line.top);
    }
    // At least a pixel of progress, or a page of one tall thing would loop.
    if (breakAt <= start + 1) breakAt = cut;
    starts.add(breakAt);
    start = breakAt;
  }
  return starts;
}

/// Where the paged view should be inside a chapter, before the chapter has
/// been laid out — which is why it is not simply a page number.
sealed class PageAnchor {
  const PageAnchor();
}

/// A position as scrolled mode stores it: how far the *top of the screen* is
/// through the scrollable range (`offset / (contentHeight - viewport)`).
///
/// This is what reading positions are saved and synced as, so a position from
/// scrolled mode, from another device, from search or from an annotation
/// arrives as one of these.
class AtScrollFraction extends PageAnchor {
  const AtScrollFraction(this.fraction);
  final double fraction;

  @override
  bool operator ==(Object other) =>
      other is AtScrollFraction && other.fraction == fraction;
  @override
  int get hashCode => fraction.hashCode;
}

/// A position as a proportion of the chapter's laid-out height.
///
/// What a page turn records. Unlike a scroll fraction it does not depend on
/// the page height, so showing or hiding the toolbar — which changes the page
/// height but not the text — keeps the same text at the top of the page rather
/// than sliding back by a fraction of a screen.
class AtContentFraction extends PageAnchor {
  const AtContentFraction(this.fraction);
  final double fraction;

  @override
  bool operator ==(Object other) =>
      other is AtContentFraction && other.fraction == fraction;
  @override
  int get hashCode => fraction.hashCode;
}

/// One chapter, cut into pages for one page size.
class ChapterPages {
  ChapterPages({
    required this.starts,
    required this.pageHeight,
    required this.contentHeight,
    this.ready = true,
  }) : assert(starts.isNotEmpty);

  /// Lays a chapter out: [paginate] plus everything needed to answer
  /// questions about the result.
  factory ChapterPages.of({
    required Iterable<LineSpan> lines,
    required double pageHeight,
    required double contentHeight,
    bool ready = true,
  }) =>
      ChapterPages(
        starts: paginate(
          lines: lines,
          pageHeight: pageHeight,
          contentHeight: contentHeight,
        ),
        pageHeight: pageHeight,
        contentHeight: contentHeight,
        ready: ready,
      );

  /// Offsets down the column where each page begins. Always starts with 0.
  final List<double> starts;
  final double pageHeight;
  final double contentHeight;

  /// False while the chapter is still being built (a long chapter is parsed
  /// off the UI isolate) — the column is then a placeholder, and its "one
  /// page" is not the chapter's. Page turns wait for it.
  final bool ready;

  int get count => starts.length;

  /// The page showing [offset] — the last one starting at or above it.
  int pageAt(double offset) {
    var lo = 0, hi = starts.length - 1;
    while (lo < hi) {
      final mid = (lo + hi + 1) >> 1;
      if (starts[mid] <= offset + _epsilon) {
        lo = mid;
      } else {
        hi = mid - 1;
      }
    }
    return lo;
  }

  /// How much of the column page [page] shows: down to where the next page
  /// starts, so the line that didn't fit is not drawn half-cut at the bottom.
  double visibleHeight(int page) {
    final i = page.clamp(0, count - 1);
    if (i == count - 1) return pageHeight;
    return starts[i + 1] - starts[i];
  }

  /// The scrolled-mode fraction for [page]: what is saved, so that switching
  /// modes, or reopening on another device, lands on the same text.
  double scrollFractionOf(int page) {
    final range = contentHeight - pageHeight;
    if (range <= 0) return 0;
    final i = page.clamp(0, count - 1);
    // The last page always reads as the end: its start is below the point
    // where scrolled mode would stop, so the division alone overshoots.
    if (i == count - 1) return 1;
    return (starts[i] / range).clamp(0.0, 1.0);
  }

  /// The proportion of the column above [page].
  double contentFractionOf(int page) {
    if (contentHeight <= 0) return 0;
    return (starts[page.clamp(0, count - 1)] / contentHeight).clamp(0.0, 1.0);
  }

  /// The page a scrolled-mode fraction falls on. The inverse of
  /// [scrollFractionOf]: every page's own fraction maps back to it.
  int pageForScrollFraction(double fraction) {
    final range = contentHeight - pageHeight;
    if (range <= 0 || count == 1) return 0;
    if (fraction >= 1 - 1e-9) return count - 1;
    return pageAt(fraction.clamp(0.0, 1.0) * range);
  }

  int pageFor(PageAnchor anchor) => switch (anchor) {
        AtScrollFraction(:final fraction) => pageForScrollFraction(fraction),
        AtContentFraction(:final fraction) =>
          pageAt(fraction.clamp(0.0, 1.0) * contentHeight),
      };

  /// How far through the chapter [page] is, for a progress bar: 0 on the
  /// first page, 1 on the last.
  double progressOf(int page) =>
      count <= 1 ? 1 : page.clamp(0, count - 1) / (count - 1);

  @override
  bool operator ==(Object other) =>
      other is ChapterPages &&
      other.pageHeight == pageHeight &&
      other.contentHeight == contentHeight &&
      other.ready == ready &&
      _sameStarts(other.starts, starts);

  @override
  int get hashCode =>
      Object.hash(pageHeight, contentHeight, ready, Object.hashAll(starts));

  static bool _sameStarts(List<double> a, List<double> b) {
    if (a.length != b.length) return false;
    for (var i = 0; i < a.length; i++) {
      if (a[i] != b[i]) return false;
    }
    return true;
  }
}

/// Merges the boxes a paragraph reports for its text into whole lines.
///
/// A line made of several runs (a bold word, a link) comes back as several
/// boxes at the same height; what pagination needs is the line.
List<LineSpan> mergeIntoLines(Iterable<LineSpan> boxes) {
  final sorted = boxes.toList()..sort((a, b) => a.top.compareTo(b.top));
  final lines = <LineSpan>[];
  for (final box in sorted) {
    if (lines.isNotEmpty && box.top < lines.last.bottom - _epsilon) {
      final last = lines.removeLast();
      lines.add((top: last.top, bottom: math.max(last.bottom, box.bottom)));
    } else {
      lines.add(box);
    }
  }
  return lines;
}
