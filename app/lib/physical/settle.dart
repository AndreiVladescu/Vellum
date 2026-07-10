import 'dart:math' as math;

/// A book's footprint for packing: a bottom-left origin `(x, y)` with width [w]
/// (spine thickness) and height [h], all in metres.
class SettleBox {
  const SettleBox({
    required this.x,
    required this.y,
    required this.w,
    required this.h,
  });

  final double x;
  final double y;
  final double w;
  final double h;
}

/// A flat resting surface between two points (metres). Horizontal in practice,
/// but two endpoints allow angling later.
class SettleSegment {
  const SettleSegment({
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
  });

  final double x1;
  final double y1;
  final double x2;
  final double y2;
}

/// Where a dragged book comes to rest. [onSurface] is false when nothing (no
/// shelf or book) was under it — the caller treats that as "dropped into empty
/// space" (and typically removes the placement).
class SettleResult {
  const SettleResult({
    required this.x,
    required this.y,
    required this.onSurface,
  });

  final double x;
  final double y;
  final bool onSurface;
}

/// Resolve where a dragged book of size [w]×[h], released at (`x`, `y`), comes
/// to rest among [shelves] and [others]: drop it onto the highest shelf or
/// book-top beneath it (within its horizontal span), then nudge it sideways out
/// of any overlaps. A plain packing heuristic — no physics engine.
///
/// This is pure (no Flutter/database types) so the packing rules can be unit
/// tested in isolation; the environment editor adapts its models to it.
/// True when any book in [others] is resting on shelf [s] — its bottom at the
/// shelf's top (within [tol]) and its footprint overlapping the shelf
/// horizontally. Used to pin a shelf that still holds books.
bool shelfHasBooks(
  SettleSegment s,
  List<SettleBox> others, {
  double tol = 0.02,
}) {
  final left = math.min(s.x1, s.x2);
  final right = math.max(s.x1, s.x2);
  final top = math.max(s.y1, s.y2);
  for (final o in others) {
    if (o.x + o.w > left && o.x < right && (o.y - top).abs() <= tol) {
      return true;
    }
  }
  return false;
}

SettleResult settle({
  required double x,
  required double y,
  required double w,
  required double h,
  required List<SettleSegment> shelves,
  required List<SettleBox> others,
}) {
  var bx = x;
  var by = y;
  const tol = 0.02; // 2 cm snap tolerance

  // Vertical: highest shelf/book surface at or just below the bottom,
  // overlapping in X. Null means nothing is under the book.
  double? surface;
  for (final s in shelves) {
    final left = math.min(s.x1, s.x2);
    final right = math.max(s.x1, s.x2);
    final top = math.max(s.y1, s.y2);
    if (bx + w > left &&
        bx < right &&
        top <= by + tol &&
        (surface == null || top > surface)) {
      surface = top;
    }
  }
  for (final o in others) {
    final top = o.y + o.h;
    if (bx + w > o.x &&
        bx < o.x + o.w &&
        top <= by + tol &&
        (surface == null || top > surface)) {
      surface = top;
    }
  }
  final onSurface = surface != null;
  by = surface ?? 0;

  // Horizontal: shove out of overlaps with books at the same height.
  for (var pass = 0; pass < 16; pass++) {
    var moved = false;
    for (final o in others) {
      final ox = o.x, oy = o.y;
      final vOverlap = by < oy + o.h - 1e-6 && by + h > oy + 1e-6;
      final hOverlap = bx < ox + o.w - 1e-6 && bx + w > ox + 1e-6;
      if (vOverlap && hOverlap) {
        final pushRight = (ox + o.w) - bx;
        final pushLeft = (bx + w) - ox;
        bx = pushRight <= pushLeft ? ox + o.w : ox - w;
        moved = true;
      }
    }
    if (!moved) break;
  }
  return SettleResult(x: bx, y: by, onSurface: onSurface);
}
