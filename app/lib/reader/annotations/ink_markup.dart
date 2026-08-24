/// What is written on a page: pen strokes and typed labels (8/23 requests —
/// "a pen writing feature, so you can draw on the pdf", and "some text writing
/// on top of the pdf, with the drawing, would be nicer").
///
/// **Everything here is page-relative.** A stroke is stored as fractions of the
/// page rectangle — 0,0 is the page's top-left corner and 1,1 its bottom-right
/// — never as pixels on screen. Pixels are a fact about one zoom level on one
/// device; the same mark has to land on the same word at every zoom, on a phone
/// and on a monitor, so the page itself is the coordinate system. Text sizes
/// are fractions of the page *height* for the same reason.
///
/// The JSON is versioned like [AnnotationLocator] is, and for the same reason:
/// a reader that meets a format it doesn't understand must show nothing rather
/// than misread it.
library;

import 'dart:convert';
import 'dart:math' as math;
import 'dart:ui';

/// One continuous line, from the pen going down to it coming up.
class InkStroke {
  const InkStroke({
    required this.points,
    required this.color,
    required this.width,
  });

  /// Page-relative points, in order. Kept as a flat list in the JSON (`p`)
  /// because a stroke is hundreds of numbers and `[[x,y],[x,y]]` doubles the
  /// punctuation for nothing.
  final List<Offset> points;

  final int color;

  /// Stroke width as a fraction of the page height, so a line drawn on a phone
  /// is the same thickness *on the page* when the same page is opened on a
  /// desktop.
  final double width;

  Map<String, dynamic> toJson() => {
        'c': color,
        'w': width,
        'p': [
          for (final p in points) ...[
            _round(p.dx),
            _round(p.dy),
          ],
        ],
      };

  /// The same stroke, picked up and put down [by] (page-relative).
  InkStroke movedBy(Offset by) => InkStroke(
        points: [for (final p in points) p + by],
        color: color,
        width: width,
      );

  /// The box it occupies, for drawing a selection around it.
  Rect get bounds {
    var rect = Rect.fromCircle(center: points.first, radius: width);
    for (final point in points.skip(1)) {
      rect = rect.expandToInclude(
          Rect.fromCircle(center: point, radius: width));
    }
    return rect;
  }

  static InkStroke? fromJson(Map<String, dynamic> json) {
    final flat = json['p'];
    if (flat is! List || flat.length < 2) return null;
    final points = <Offset>[];
    for (var i = 0; i + 1 < flat.length; i += 2) {
      final x = (flat[i] as num?)?.toDouble();
      final y = (flat[i + 1] as num?)?.toDouble();
      if (x == null || y == null) continue;
      points.add(Offset(x, y));
    }
    if (points.isEmpty) return null;
    return InkStroke(
      points: points,
      color: (json['c'] as num?)?.toInt() ?? 0xFF000000,
      width: (json['w'] as num?)?.toDouble() ?? 0.003,
    );
  }
}

/// A few words dropped on the page, anchored at their top-left corner.
class InkText {
  const InkText({
    required this.at,
    required this.text,
    required this.color,
    required this.size,
    this.rotation = 0,
  });

  /// Where the text starts — its top-left corner before rotation, and the point
  /// it turns about.
  final Offset at;
  final String text;
  final int color;

  /// Font size as a fraction of the page height.
  final double size;

  /// Turn, in radians, clockwise about [at]. Zero is level with the page, which
  /// is what an absent value in the JSON means — a note written before this
  /// existed is a level one.
  final double rotation;

  InkText movedBy(Offset by) => copyWith(at: at + by);

  InkText copyWith({
    Offset? at,
    String? text,
    int? color,
    double? size,
    double? rotation,
  }) =>
      InkText(
        at: at ?? this.at,
        text: text ?? this.text,
        color: color ?? this.color,
        size: size ?? this.size,
        rotation: rotation ?? this.rotation,
      );

  Map<String, dynamic> toJson() => {
        'x': _round(at.dx),
        'y': _round(at.dy),
        's': size,
        'c': color,
        't': text,
        // Absent when level, which is most of them: a note that was never
        // turned should not cost four bytes in every page of writing.
        if (rotation != 0) 'r': _round(rotation),
      };

  static InkText? fromJson(Map<String, dynamic> json) {
    final text = json['t'];
    if (text is! String || text.trim().isEmpty) return null;
    return InkText(
      at: Offset(
        (json['x'] as num?)?.toDouble() ?? 0,
        (json['y'] as num?)?.toDouble() ?? 0,
      ),
      text: text,
      color: (json['c'] as num?)?.toInt() ?? 0xFF000000,
      size: (json['s'] as num?)?.toDouble() ?? 0.02,
      rotation: (json['r'] as num?)?.toDouble() ?? 0,
    );
  }
}

/// Everything written on one page.
class InkMarkup {
  const InkMarkup({this.strokes = const [], this.texts = const []});

  static const version = 1;

  final List<InkStroke> strokes;
  final List<InkText> texts;

  bool get isEmpty => strokes.isEmpty && texts.isEmpty;

  InkMarkup withStroke(InkStroke stroke) =>
      InkMarkup(strokes: [...strokes, stroke], texts: texts);

  InkMarkup withText(InkText text) =>
      InkMarkup(strokes: strokes, texts: [...texts, text]);

  /// Drops whatever was added last — one undo, whichever tool made it. Which
  /// of the two lists to shorten is not recorded, so the *last* item of either
  /// is taken by convention: text is added one piece at a time and strokes in a
  /// flurry, and taking the newest text first matches what a hand just did.
  InkMarkup withoutLast() {
    if (texts.isNotEmpty) {
      return InkMarkup(strokes: strokes, texts: texts.sublist(0, texts.length - 1));
    }
    if (strokes.isNotEmpty) {
      return InkMarkup(
          strokes: strokes.sublist(0, strokes.length - 1), texts: texts);
    }
    return this;
  }

  /// Which mark is under [at], if any — the nearest one, so overlapping marks
  /// pick the one whose line you actually touched.
  ///
  /// Text is measured by the caller, since only the reader knows how wide a
  /// string is at a given size: [textBounds] comes from the painter, which has
  /// the font. Null means empty page, or a tap on nothing.
  InkTarget? hitTest(
    Offset at,
    double radius, {
    required Rect Function(InkText text) textBounds,
  }) {
    // Text first: it sits on top of the strokes when drawn, so it is what you
    // meant if the two overlap.
    for (var i = texts.length - 1; i >= 0; i--) {
      if (_containsRotated(texts[i], at, textBounds(texts[i]))) {
        return InkTarget.text(i);
      }
    }
    for (var i = strokes.length - 1; i >= 0; i--) {
      if (_strokeTouches(strokes[i], at, radius)) return InkTarget.stroke(i);
    }
    return null;
  }

  /// The same markup with one mark replaced. Out-of-range indices are ignored
  /// rather than thrown on: a selection can outlive the thing it pointed at
  /// when a sync arrives mid-drag.
  InkMarkup replacingStroke(int index, InkStroke stroke) {
    if (index < 0 || index >= strokes.length) return this;
    final next = [...strokes]..[index] = stroke;
    return InkMarkup(strokes: next, texts: texts);
  }

  InkMarkup replacingText(int index, InkText text) {
    if (index < 0 || index >= texts.length) return this;
    final next = [...texts]..[index] = text;
    return InkMarkup(strokes: strokes, texts: next);
  }

  InkMarkup without(InkTarget target) => switch (target.kind) {
        InkTargetKind.stroke => target.index < 0 || target.index >= strokes.length
            ? this
            : InkMarkup(
                strokes: [...strokes]..removeAt(target.index),
                texts: texts,
              ),
        InkTargetKind.text => target.index < 0 || target.index >= texts.length
            ? this
            : InkMarkup(
                strokes: strokes,
                texts: [...texts]..removeAt(target.index),
              ),
      };

  /// Everything except what the eraser touched at [at], within [radius] (both
  /// page-relative). A stroke goes whole: half a pen line is not a thing anyone
  /// asked for, and rubbing at one is how you get a mess.
  InkMarkup erasedAt(Offset at, double radius) => InkMarkup(
        strokes: [
          for (final stroke in strokes)
            if (!_strokeTouches(stroke, at, radius)) stroke,
        ],
        texts: [
          for (final text in texts)
            if ((text.at - at).distance > radius + text.size) text,
        ],
      );

  String encode() => jsonEncode({
        'v': version,
        if (strokes.isNotEmpty) 'strokes': [for (final s in strokes) s.toJson()],
        if (texts.isNotEmpty) 'texts': [for (final t in texts) t.toJson()],
      });

  /// Null for anything this reader cannot read: a newer format, or damage.
  static InkMarkup? decode(String? raw) {
    if (raw == null || raw.isEmpty) return null;
    try {
      final json = jsonDecode(raw);
      if (json is! Map<String, dynamic>) return null;
      if ((json['v'] as num?)?.toInt() != version) return null;
      // Each list is read on its own: damage to the strokes should not throw
      // away the text that survived it.
      final strokes = json['strokes'];
      final texts = json['texts'];
      return InkMarkup(
        strokes: [
          for (final s in (strokes is List ? strokes : const []))
            if (s is Map<String, dynamic>) ?InkStroke.fromJson(s),
        ],
        texts: [
          for (final t in (texts is List ? texts : const []))
            if (t is Map<String, dynamic>) ?InkText.fromJson(t),
        ],
      );
    } catch (_) {
      return null;
    }
  }
}

/// Which of the two kinds of mark a selection points at.
enum InkTargetKind { stroke, text }

/// A mark on a page, by kind and position in its list.
///
/// An index rather than an id: the page is one row and one payload, edited as a
/// whole, so there is nothing for an id to survive. The index is only ever held
/// for the length of a gesture, and every method that takes one ignores an
/// index that no longer exists.
class InkTarget {
  const InkTarget(this.kind, this.index);

  const InkTarget.stroke(this.index) : kind = InkTargetKind.stroke;
  const InkTarget.text(this.index) : kind = InkTargetKind.text;

  final InkTargetKind kind;
  final int index;

  @override
  bool operator ==(Object other) =>
      other is InkTarget && other.kind == kind && other.index == index;

  @override
  int get hashCode => Object.hash(kind, index);

  @override
  String toString() => '${kind.name} $index';
}

/// Whether [at] falls inside a text's box, allowing for the turn it was given.
///
/// The point is rotated *back* about the anchor rather than the box being
/// rotated forward: a rectangle test is exact, and a rotated-rectangle test is
/// four half-plane tests that get the corners subtly wrong.
bool _containsRotated(InkText text, Offset at, Rect bounds) {
  if (text.rotation == 0) return bounds.contains(at);
  final local = rotateAbout(at, text.at, -text.rotation);
  return bounds.contains(local);
}

/// [point] turned by [radians] about [origin].
Offset rotateAbout(Offset point, Offset origin, double radians) {
  final sin = math.sin(radians);
  final cos = math.cos(radians);
  final d = point - origin;
  return origin +
      Offset(d.dx * cos - d.dy * sin, d.dx * sin + d.dy * cos);
}

/// Whether the eraser at [at] catches any part of [stroke].
///
/// Point-to-segment distance rather than point-to-point: a fast pen leaves
/// points far apart, and testing only the recorded points lets the eraser pass
/// straight through the middle of a long line.
bool _strokeTouches(InkStroke stroke, Offset at, double radius) {
  final reach = radius + stroke.width;
  if (stroke.points.length == 1) {
    return (stroke.points.first - at).distance <= reach;
  }
  for (var i = 0; i + 1 < stroke.points.length; i++) {
    if (_distanceToSegment(at, stroke.points[i], stroke.points[i + 1]) <=
        reach) {
      return true;
    }
  }
  return false;
}

double _distanceToSegment(Offset p, Offset a, Offset b) {
  final ab = b - a;
  final lengthSquared = ab.dx * ab.dx + ab.dy * ab.dy;
  if (lengthSquared == 0) return (p - a).distance;
  var t = ((p - a).dx * ab.dx + (p - a).dy * ab.dy) / lengthSquared;
  t = t.clamp(0.0, 1.0);
  return (p - (a + ab * t)).distance;
}

/// Four decimal places: a page is a few thousand points across, so this is
/// finer than the paper, and it keeps a page of scribble to a sane size.
double _round(double v) => (v * 10000).roundToDouble() / 10000;

/// Converts a point on screen to its page-relative position, given where the
/// page is drawn. Returns null for a point outside the page — a pen stroke that
/// wanders into the margin stops at the edge rather than being stored as a
/// coordinate no page can hold.
Offset? toPageFraction(Offset onScreen, Rect pageOnScreen) {
  if (pageOnScreen.width <= 0 || pageOnScreen.height <= 0) return null;
  return Offset(
    (onScreen.dx - pageOnScreen.left) / pageOnScreen.width,
    (onScreen.dy - pageOnScreen.top) / pageOnScreen.height,
  );
}

/// The inverse: where a page-relative point lands on screen (or on the page's
/// own canvas, which is the same arithmetic).
Offset fromPageFraction(Offset fraction, Rect pageOnScreen) => Offset(
      pageOnScreen.left + fraction.dx * pageOnScreen.width,
      pageOnScreen.top + fraction.dy * pageOnScreen.height,
    );
