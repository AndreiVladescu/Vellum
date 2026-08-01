/// Bookcases as a *generator*, not a container (next features #11).
///
/// **The decision this encodes.** A bookcase is not a new kind of object here.
/// It is a template that emits the shelf and panel segments it is made of, and
/// then gets out of the way. Making it a first-class row with child shelves
/// would be conceptually tidier and is a trap: it invalidates everything that
/// reasons about a flat list of segments — fill, tidy, stocktake, the printed
/// labels, the accessible room summary, the published room document, the
/// console's renderer — and it immediately raises "what happens when I drag one
/// shelf out of a bookcase", which has no good answer.
///
/// So the substrate is untouched, and the payoff is the same one the bulk book
/// add delivered a layer up: **a room built in four gestures instead of forty.**
library;

import 'dart:math' as math;

import 'room_measure.dart';

/// A segment a template wants written, in world metres.
typedef TemplateSegment = ({
  double x1,
  double y1,
  double x2,
  double y2,
  String? label,
  ShelfKind kind,
});

/// A style of bookcase, with the dimensions that make it that style.
///
/// Sizes are the real ones, because the room is drawn to scale and a bookcase
/// that is nearly right looks worse than one that is obviously stylised.
enum BookcaseStyle {
  billy(
    'Billy-style unit',
    width: 0.80,
    height: 2.02,
    shelves: 6,
    hasSides: true,
  ),
  tall(
    'Tall bookcase',
    width: 0.90,
    height: 2.30,
    shelves: 7,
    hasSides: true,
  ),
  low(
    'Low bookcase',
    width: 0.80,
    height: 1.06,
    shelves: 3,
    hasSides: true,
  ),
  cube(
    'Cube shelving',
    width: 1.47,
    height: 1.47,
    shelves: 4,
    hasSides: true,
  ),
  /// Planks on brackets: no sides, so books can run off either end.
  floating(
    'Floating shelves',
    width: 1.20,
    height: 1.20,
    shelves: 3,
    hasSides: false,
  );

  const BookcaseStyle(
    this.label, {
    required this.width,
    required this.height,
    required this.shelves,
    required this.hasSides,
  });

  final String label;

  /// Defaults, in metres — every one of them is editable before it is written.
  final double width;
  final double height;
  final int shelves;

  /// Whether the unit has uprights at its ends. They are barriers, so books
  /// stop at them rather than sliding off (the machinery dividers use).
  final bool hasSides;
}

/// The segments a bookcase of this shape is made of, with its bottom-left
/// corner at ([x], [y]).
///
/// Shelves are spaced evenly from the floor of the unit up, and the *top* of
/// the case is not a shelf — a bookcase with six shelves has six surfaces you
/// can put books on, which is what someone counting shelves in a shop means.
List<TemplateSegment> bookcaseSegments({
  required BookcaseStyle style,
  required double x,
  required double y,
  double? width,
  double? height,
  int? shelves,
  String? label,
}) {
  final w = width ?? style.width;
  final h = height ?? style.height;
  // At least one shelf, or the template produces a box with nothing in it.
  final count = math.max(1, shelves ?? style.shelves);

  final segments = <TemplateSegment>[];

  // Evenly spaced, the lowest at the base. The gap is what's left over after
  // the top shelf, so the tallest books go on the top shelf — which is where
  // they go in a real bookcase, for the same reason.
  final spacing = h / count;
  for (var i = 0; i < count; i++) {
    segments.add((
      x1: x,
      y1: y + i * spacing,
      x2: x + w,
      y2: y + i * spacing,
      // Only the whole unit is named; naming every shelf "Billy 1..6" is noise
      // on the drawing and in the printed labels.
      label: i == 0 ? label : null,
      kind: ShelfKind.shelf,
    ));
  }

  if (style.hasSides) {
    for (final sideX in [x, x + w]) {
      segments.add((
        x1: sideX,
        y1: y,
        x2: sideX,
        y2: y + h,
        label: null,
        kind: ShelfKind.panel,
      ));
    }
  }

  return segments;
}
