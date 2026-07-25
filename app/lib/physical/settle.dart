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
/// horizontally. A convenience predicate over [restsOnShelf].
bool shelfHasBooks(
  SettleSegment s,
  List<SettleBox> others, {
  double tol = 0.02,
}) =>
    others.any((o) => restsOnShelf(o, s, tol: tol));

/// True when book [o] is resting on shelf [s]: its bottom at the shelf top
/// (within [tol]) and its footprint overlapping the shelf horizontally. Used to
/// pin an occupied shelf and to carry its books along when the shelf is edited.
bool restsOnShelf(SettleBox o, SettleSegment s, {double tol = 0.02}) {
  final left = math.min(s.x1, s.x2);
  final right = math.max(s.x1, s.x2);
  final top = math.max(s.y1, s.y2);
  return o.x + o.w > left && o.x < right && (o.y - top).abs() <= tol;
}

SettleResult settle({
  required double x,
  required double y,
  required double w,
  required double h,
  required List<SettleSegment> shelves,
  required List<SettleBox> others,
}) {
  const tol = 0.02; // 2 cm snap tolerance

  // Every surface under the release point (overlapping in X, at/below the
  // bottom), highest first. Shelves keep their span so the book can be clamped
  // to stay on them.
  final candidates = <({double top, bool isShelf, double left, double right})>[];
  for (final s in shelves) {
    final left = math.min(s.x1, s.x2);
    final right = math.max(s.x1, s.x2);
    final top = math.max(s.y1, s.y2);
    if (x + w > left && x < right && top <= y + tol) {
      candidates.add((top: top, isShelf: true, left: left, right: right));
    }
  }
  for (final o in others) {
    final top = o.y + o.h;
    if (x + w > o.x && x < o.x + o.w && top <= y + tol) {
      candidates.add((top: top, isShelf: false, left: o.x, right: o.x + o.w));
    }
  }
  candidates.sort((a, b) => b.top.compareTo(a.top));

  // Try to rest on each surface from highest down. Nudge out of overlaps, and
  // on a shelf keep the book within its span; if it still overlaps there (the
  // shelf is too full), fall through to the next surface below rather than
  // floating past the shelf's end.
  for (final c in candidates) {
    final by = c.top;
    var bx = x;
    for (var pass = 0; pass < 16; pass++) {
      var moved = false;
      for (final o in others) {
        final vOverlap = by < o.y + o.h - 1e-6 && by + h > o.y + 1e-6;
        final hOverlap = bx < o.x + o.w - 1e-6 && bx + w > o.x + 1e-6;
        if (vOverlap && hOverlap) {
          final pushRight = (o.x + o.w) - bx;
          final pushLeft = (bx + w) - o.x;
          bx = pushRight <= pushLeft ? o.x + o.w : o.x - w;
          moved = true;
        }
      }
      if (!moved) break;
    }
    // Clamp within the shelf, unless the book is wider than the shelf (nothing
    // sensible to clamp to — leave it centred as dropped).
    if (c.isShelf && w <= c.right - c.left) {
      bx = bx.clamp(c.left, c.right - w);
    }
    if (!_overlapsAny(bx, by, w, h, others)) {
      return SettleResult(x: bx, y: by, onSurface: true);
    }
  }
  // Nothing holds it (or no surface had room): treat as dropped in empty space.
  return SettleResult(x: x, y: 0, onSurface: false);
}

bool _overlapsAny(
  double x,
  double y,
  double w,
  double h,
  List<SettleBox> others,
) {
  for (final o in others) {
    final vOverlap = y < o.y + o.h - 1e-6 && y + h > o.y + 1e-6;
    final hOverlap = x < o.x + o.w - 1e-6 && x + w > o.x + 1e-6;
    if (vOverlap && hOverlap) return true;
  }
  return false;
}
