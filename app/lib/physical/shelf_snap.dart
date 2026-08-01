/// Snapping a shelf between the uprights it sits inside.
///
/// A shelf dragged into a bookcase should end up *spanning* that bookcase, not
/// floating a centimetre short of one side. Doing it by eye at 300 px/m means
/// being wrong by a few millimetres every time, and a shelf that doesn't quite
/// reach its side panel is exactly the thing you notice afterwards.
///
/// Pure, like `settle` and `bulk_place`, so the arithmetic can be tested
/// without a canvas.
library;

import 'dart:math' as math;
import 'dart:ui' show Offset;

/// Where a dragged segment ends up: its endpoints after the move, with the
/// snap applied if one was found.
typedef DraggedSegment = ({double x1, double y1, double x2, double y2});

/// Moves a segment by [delta] and snaps it between uprights when it is a shelf
/// that landed inside a bookcase.
///
/// **Both y's are shifted, never equalised.** Writing the resting height into
/// y1 *and* y2 looks harmless — for a flat shelf they are equal already — and
/// collapses an upright to a single point. That is exactly what dragging a
/// divider used to do to it: placed by hand it had a height, dragged once it
/// became a dot.
DraggedSegment dragSegment({
  required double x1,
  required double y1,
  required double x2,
  required double y2,
  required Offset delta,
  required bool holdsBooks,
  List<Upright> uprights = const [],
}) {
  final surface = math.max(y1, y2) + delta.dy;
  final snapped = holdsBooks
      ? snapBetweenUprights(
          left: math.min(x1, x2) + delta.dx,
          right: math.max(x1, x2) + delta.dx,
          y: surface,
          uprights: uprights,
        )
      : null;
  return (
    x1: snapped?.left ?? x1 + delta.dx,
    y1: y1 + delta.dy,
    x2: snapped?.right ?? x2 + delta.dx,
    y2: y2 + delta.dy,
  );
}

/// An upright the shelf could snap to: a side panel or a divider.
typedef Upright = ({double x, double bottom, double top});

/// The span a shelf should take, in world metres.
typedef Span = ({double left, double right});

/// The nearest pair of uprights bracketing a shelf at ([left], [right]) resting
/// at height [y], or null when there is nothing sensible to snap to.
///
/// Both ends must find an upright within [tolerance], and both uprights must
/// actually cross the shelf's height — a panel that stops below the shelf is
/// not one of its sides. Requiring *both* is the point: snapping one end and
/// leaving the other is worse than snapping neither, because it looks
/// deliberate.
Span? snapBetweenUprights({
  required double left,
  required double right,
  required double y,
  required List<Upright> uprights,
  double tolerance = 0.12,
}) {
  final crossing = [
    for (final u in uprights)
      // A shelf resting exactly at a panel's top edge is not inside it.
      if (u.bottom <= y + 1e-9 && u.top > y + 1e-9) u,
  ];
  if (crossing.length < 2) return null;

  Upright? nearest(double to) {
    Upright? best;
    var bestGap = double.infinity;
    for (final u in crossing) {
      final gap = (u.x - to).abs();
      if (gap < bestGap) {
        bestGap = gap;
        best = u;
      }
    }
    return bestGap <= tolerance ? best : null;
  }

  final a = nearest(left);
  final b = nearest(right);
  if (a == null || b == null) return null;
  // Both ends finding the *same* upright means the shelf is tiny and sitting on
  // top of one; there is no span to snap to.
  if ((a.x - b.x).abs() < 1e-9) return null;
  return (left: math.min(a.x, b.x), right: math.max(a.x, b.x));
}
