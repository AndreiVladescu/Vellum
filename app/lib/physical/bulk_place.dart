/// Packing a batch of books onto one shelf (the bulk-add flow).
///
/// Kept pure — no Flutter, no database — for the same reason `settle.dart` is:
/// "does this run of books fit, and where do they go" is fiddly arithmetic that
/// deserves tests of its own, separate from a canvas.
///
/// **Why not just call `settle` in a loop.** `settle` answers "I dropped this
/// book *here*, where does it end up", which is the right question for a drag
/// and the wrong one for a batch: dropping forty books at the same point makes
/// each one shove the last, the nudge picks whichever side is nearer, and the
/// result is order-dependent mush. Filling a shelf is the other question —
/// *where is there room* — so this works from the gaps instead.
library;

import 'dart:math' as math;

/// A stretch of shelf with nothing on it, in world metres.
typedef ShelfGap = ({double start, double end});

/// Something already occupying part of the shelf: a book resting on it, or an
/// upright crossing it (a side panel, a divider — books can't be packed
/// through one, which is exactly what makes a divider mean something).
typedef Occupied = ({double start, double end});

/// Where one book of the batch went.
typedef Placement = ({int index, double x});

/// The result of [packOntoShelf]: what fitted, and what didn't.
///
/// [unplaced] holds indices into the original `widths` list rather than a
/// count, so the caller can name the books that were left out. Reporting them
/// is not optional — silently dropping half a batch is how someone ends up
/// believing books are on a shelf that isn't holding them.
typedef PackResult = ({List<Placement> placed, List<int> unplaced});

/// Fits books of the given [widths], in order, into the free space on a shelf
/// running from [shelfLeft] to [shelfRight].
///
/// Books go into the **first gap they fit**, left to right, which fills holes
/// left by earlier removals before running on to the end. A book wider than
/// every remaining gap is skipped and reported; the batch carries on, because
/// one oversized atlas should not stop the other thirty-nine going up.
PackResult packOntoShelf({
  required double shelfLeft,
  required double shelfRight,
  required List<double> widths,
  List<Occupied> occupied = const [],
  double epsilon = 0.0005,
}) {
  final left = math.min(shelfLeft, shelfRight);
  final right = math.max(shelfLeft, shelfRight);
  final gaps = freeGaps(left: left, right: right, occupied: occupied);

  final placed = <Placement>[];
  final unplaced = <int>[];
  for (var i = 0; i < widths.length; i++) {
    final w = widths[i];
    // A zero-width book (no thickness known, no page count) would otherwise
    // "fit" anywhere and stack invisibly at one x.
    if (w <= 0) {
      unplaced.add(i);
      continue;
    }
    final g = gaps.indexWhere((gap) => gap.end - gap.start >= w - epsilon);
    if (g < 0) {
      unplaced.add(i);
      continue;
    }
    placed.add((index: i, x: gaps[g].start));
    final consumed = (start: gaps[g].start + w, end: gaps[g].end);
    if (consumed.end - consumed.start <= epsilon) {
      gaps.removeAt(g);
    } else {
      gaps[g] = consumed;
    }
  }
  return (placed: placed, unplaced: unplaced);
}

/// The free stretches of `[left, right]` once [occupied] is subtracted.
///
/// Overlapping and out-of-order occupants are handled by merging first, so the
/// caller can hand over whatever it found without sorting it: books on a
/// shelf are in placement order, not left-to-right, and an overfull shelf has
/// genuinely overlapping ones.
List<ShelfGap> freeGaps({
  required double left,
  required double right,
  required List<Occupied> occupied,
  double epsilon = 0.0005,
}) {
  final clipped = <Occupied>[
    for (final o in occupied)
      if (math.max(o.start, left) < math.min(o.end, right) - epsilon)
        (start: math.max(o.start, left), end: math.min(o.end, right)),
  ]..sort((a, b) => a.start.compareTo(b.start));

  final merged = <Occupied>[];
  for (final o in clipped) {
    if (merged.isNotEmpty && o.start <= merged.last.end + epsilon) {
      merged[merged.length - 1] =
          (start: merged.last.start, end: math.max(merged.last.end, o.end));
    } else {
      merged.add(o);
    }
  }

  final gaps = <ShelfGap>[];
  var cursor = left;
  for (final o in merged) {
    if (o.start - cursor > epsilon) gaps.add((start: cursor, end: o.start));
    cursor = math.max(cursor, o.end);
  }
  if (right - cursor > epsilon) gaps.add((start: cursor, end: right));
  return gaps;
}
