/// Backdrop calibration, the measure tool, and shelf fill (plan 5 #29).
///
/// Pure maths, no Flutter widgets and no database rows, so the parts that are
/// easy to get subtly wrong — pixels ↔ metres, "does this book fit?" — can be
/// tested without pumping a canvas.
library;

import 'dart:math' as math;

import '../data/database.dart';
import 'physical_metrics.dart';

/// What a segment in `physical_shelves` actually is (plan 5 #29).
///
/// A `kind` on the existing table rather than a second one: a bookcase side
/// panel is geometrically a shelf that books don't rest on, and the only real
/// difference is whether [holdsBooks] lets `settle` land something on it.
enum ShelfKind {
  shelf('shelf', 'Shelf', holdsBooks: true),
  panel('panel', 'Side panel', holdsBooks: false),
  divider('divider', 'Divider', holdsBooks: false),
  // Named `marker` rather than `label` so the enum value doesn't collide with
  // the field below — the stored key stays 'label', which is what the plan and
  // the schema call it.
  marker('label', 'Label', holdsBooks: false);

  const ShelfKind(this.key, this.displayName, {required this.holdsBooks});

  final String key;

  /// Shown in the shelf dialog's picker.
  final String displayName;

  /// Whether a book may come to rest on it.
  final bool holdsBooks;

  /// Unknown values read as a plain shelf: a row written by a newer version
  /// should still be *drawn*, and treating it as furniture would silently drop
  /// the books resting on it.
  static ShelfKind parse(String? raw) => values.firstWhere(
        (k) => k.key == raw,
        orElse: () => ShelfKind.shelf,
      );
}

/// The two-point backdrop calibration (plan 5 #29).
///
/// You mark a length you know — a door is 2 m, a shelf is 90 cm — and the photo
/// gets a scale. Two points rather than one number because nobody knows their
/// phone's focal length, but everybody can find something they can measure.
class BackdropCalibration {
  const BackdropCalibration({
    required this.pixelDistance,
    required this.realMetres,
  });

  /// Distance between the two marked points, in backdrop-image pixels.
  final double pixelDistance;

  /// What that distance really is, in metres.
  final double realMetres;

  /// Metres per pixel, or null when the input can't produce a scale.
  ///
  /// Both degenerate cases are rejected rather than clamped: two points on the
  /// same pixel, or "this is 0 m long", would otherwise yield a scale that
  /// makes the whole room infinitely large or infinitely small — and a wrong
  /// scale is worse than an uncalibrated photo, because it looks authoritative.
  double? get metresPerPixel {
    if (!pixelDistance.isFinite || !realMetres.isFinite) return null;
    if (pixelDistance <= 0 || realMetres <= 0) return null;
    return realMetres / pixelDistance;
  }
}

/// Pixel distance between two points on the backdrop.
double pixelDistanceBetween(double x1, double y1, double x2, double y2) =>
    math.sqrt(math.pow(x2 - x1, 2) + math.pow(y2 - y1, 2));

/// A measured distance, formatted the way someone standing at a bookcase reads
/// it: centimetres up to a metre, then metres to two decimals.
///
/// Rounded to the nearest centimetre because the input is a finger on a screen
/// — showing `43.7241 cm` would claim a precision the gesture doesn't have.
String formatDistance(double metres) {
  final abs = metres.abs();
  if (abs < 1) return '${(abs * 100).round()} cm';
  return '${abs.toStringAsFixed(2)} m';
}

/// How much of a shelf is used, and by what (plan 5 #29).
///
/// The practical number when you are standing there wondering whether one more
/// book fits — which is the question the physical view exists to answer.
class ShelfFill {
  const ShelfFill({
    required this.usedM,
    required this.lengthM,
    required this.bookCount,
  });

  final double usedM;
  final double lengthM;
  final int bookCount;

  /// 0..1, clamped: a shelf can be *over*full (books pushed past its end), and
  /// a progress bar at 1.4 would just render wrong.
  double get fraction =>
      lengthM <= 0 ? 0 : (usedM / lengthM).clamp(0.0, 1.0).toDouble();

  bool get isOverfull => usedM > lengthM + 0.001;

  double get freeM => math.max(0, lengthM - usedM);

  /// "42 cm of 90 cm used" — the sentence, not the number.
  String describe() {
    if (lengthM <= 0) return 'No length';
    final used = formatDistance(usedM);
    final total = formatDistance(lengthM);
    if (isOverfull) return '$used on a $total shelf — overfull';
    return '$used of $total used · ${formatDistance(freeM)} free';
  }
}

/// A box in world metres, where **y grows upwards**.
///
/// Deliberately not a `Rect`: Flutter's assumes screen coordinates, so its
/// `top` is the smaller y. Storing a world box in one puts the room's ceiling
/// in `rect.bottom`, which reads as a bug every time anyone looks at it — and
/// cost a test failure the first time this was written that way.
typedef WorldBox = ({double left, double right, double bottom, double top});

/// The box to outline around a selection, or null when there should be none.
///
/// Null in two cases, and the second is the interesting one:
///
/// - nothing is selected, or
/// - everything selected is **anchored**. The outline means "this will move if
///   you drag it", not "this is selected" — selection on its own does nothing,
///   while unlocked is a state you can leave something in by accident and
///   otherwise cannot see.
WorldBox? selectionBoundsOf(List<PhysicalShelf> selected) {
  if (selected.isEmpty || selected.every((s) => s.anchored)) return null;
  return (
    left: selected.map((s) => math.min(s.x1, s.x2)).reduce(math.min),
    right: selected.map((s) => math.max(s.x1, s.x2)).reduce(math.max),
    bottom: selected.map((s) => math.min(s.y1, s.y2)).reduce(math.min),
    top: selected.map((s) => math.max(s.y1, s.y2)).reduce(math.max),
  );
}

/// A shelf's name for a menu or a message.
///
/// Its label when it has one. When it doesn't, the height it sits at — because
/// a chooser listing "Unlabelled shelf" three times tells you nothing, and
/// "Shelf at 1.4 m" is what you would say pointing at the bookcase. [siblings]
/// is the rest of the room, used only to decide whether a label is ambiguous:
/// two shelves both labelled "Cookbooks" get their heights too.
String shelfName(PhysicalShelf shelf, List<PhysicalShelf> siblings) {
  final label = shelf.label?.trim();
  final height = formatDistance(math.max(shelf.y1, shelf.y2));
  if (label == null || label.isEmpty) return 'Shelf at $height';
  final sameLabel = siblings
      .where((s) => (s.label?.trim() ?? '') == label)
      .length;
  return sameLabel > 1 ? '$label ($height)' : label;
}

/// Measures how much of [shelf] its resting books take up.
///
/// Uses the same thickness curve as everything else in the physical view
/// (`PhysicalMetrics`), so the estimate and the drawing can't disagree — a
/// separate calculation here would be a second source of truth for the one
/// number the feature is about.
///
/// "Resting on" is the same test the editor already uses: the book's baseline
/// at the shelf's surface within a tolerance, and horizontally overlapping it.
ShelfFill fillOf({
  required PhysicalShelf shelf,
  required List<({BookPlacement placement, Book book})> placed,
  double tolerance = 0.02,
}) {
  final left = math.min(shelf.x1, shelf.x2);
  final right = math.max(shelf.x1, shelf.x2);
  final surface = math.max(shelf.y1, shelf.y2);

  var used = 0.0;
  var count = 0;
  for (final pb in placed) {
    final format = BookFormat.byKey(pb.placement.format);
    final thickness = PhysicalMetrics.thickness(
      pb.book,
      format: format,
      override: pb.placement.widthOverride,
    );
    final height = PhysicalMetrics.height(
      pb.book,
      format: format,
      override: pb.placement.heightOverride,
    );
    // A book lying flat presents its height along the shelf, not its spine.
    final along = pb.placement.rotation == 90 ? height : thickness;

    final restsHere = (pb.placement.y - surface).abs() <= tolerance &&
        pb.placement.x + along > left &&
        pb.placement.x < right;
    if (!restsHere) continue;
    used += along;
    count++;
  }

  return ShelfFill(usedM: used, lengthM: right - left, bookCount: count);
}

/// Whether a book of [thicknessM] would still fit on [fill]'s shelf.
///
/// Answered with a millimetre of slack: shelves are measured by hand and books
/// are not perfectly rectangular, so a "fits" that is true by 0.2 mm is a lie
/// in the only place it matters.
bool fitsOn(ShelfFill fill, double thicknessM, {double slackM = 0.001}) =>
    fill.freeM >= thicknessM + slackM;
