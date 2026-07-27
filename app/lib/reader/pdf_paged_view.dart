/// Keeping the viewport inside a single page, for the reader's paged mode.
///
/// **Why a clamp and not a different layout.** pdfrx lays a document out as one
/// tall strip and scrolls it; there is no "show me only page 4" switch. But a
/// paged reader is not really about how the pages are stored — it is about never
/// being able to see two at once and never coming to rest across a seam. Pinning
/// the viewport inside the current page's rectangle gives exactly that, and
/// leaves everything else pdfrx does (zoom, selection, search) untouched.
///
/// Scrolling within a page is deliberately still allowed: a page taller than the
/// window has to be readable, and "one page at a time" was never a promise that
/// the page fits.
library;

import 'dart:ui';

/// The page [centre] is on — the one it is inside, or failing that the nearest.
///
/// Found rather than remembered: every jump — a search hit, a bookmark, the
/// page-number box — moves the viewport directly, and an anchor the reader held
/// onto would drag it straight back. Asking where the viewport actually is
/// means a jump lands and a drag past the seam settles onto the next page.
///
/// Containment first, distance only for the gaps between pages: comparing
/// distances alone puts the crossover halfway between two page *centres*, which
/// is somewhere inside the taller page when the two differ in size.
int nearestPage(List<Rect> pages, Offset centre) {
  var best = 0;
  var bestDistance = double.infinity;
  for (var i = 0; i < pages.length; i++) {
    final page = pages[i];
    if (centre.dy >= page.top && centre.dy <= page.bottom) return i;
    final distance = (page.center - centre).distanceSquared;
    if (distance < bestDistance) {
      bestDistance = distance;
      best = i;
    }
  }
  return best;
}

/// [centre] pulled back inside [page].
///
/// [viewport] is the visible area in *document* units — the widget's size
/// divided by the zoom — so the clamp holds the page's edges against the edges
/// of the window rather than against its middle.
///
/// An axis where the viewport is the larger of the two is centred instead of
/// clamped: there is nothing to slide, and clamping would produce an empty range
/// whose ends contradict each other.
Offset clampToPage({
  required Offset centre,
  required Rect page,
  required Size viewport,
}) {
  double axis(double value, double lo, double hi, double half, double middle) {
    if (hi - lo <= half * 2) return middle;
    return value.clamp(lo + half, hi - half);
  }

  return Offset(
    axis(centre.dx, page.left, page.right, viewport.width / 2, page.center.dx),
    axis(centre.dy, page.top, page.bottom, viewport.height / 2, page.center.dy),
  );
}
