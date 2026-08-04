import 'dart:math' as math;

import 'package:flutter/material.dart';

/// The small things that stand on a shelf next to the books (next features
/// #10, stage 2).
///
/// **Drawn, not shipped.** Each prop is a handful of `Path` calls rather than
/// an image: nothing to license, nothing to bundle, no pixelation at any zoom,
/// and each one takes a colour from the room rather than bringing its own
/// lighting to argue with everything else. That last part is what usually makes
/// a decorated room look like a collage.
///
/// Deliberately a small, plain set. A shelf ornament is scenery — it should
/// read at a glance at 300 px/m and then stop asking for attention.
enum PropKind {
  statuette('Statuette', width: 0.08, height: 0.18),
  // Leaves overhang the pot, so what books must avoid is much narrower than
  // what is drawn — see `solidWidthFraction`.
  plant('Small plant', width: 0.16, height: 0.24, solidWidthFraction: 0.55),
  vase('Vase', width: 0.11, height: 0.22, solidWidthFraction: 0.8),
  clock('Clock', width: 0.13, height: 0.13),
  boxes('Stack of boxes', width: 0.22, height: 0.14),

  /// The one with a job as well as a look: books stop at it, like a divider.
  bookend('Bookend', width: 0.02, height: 0.15);

  const PropKind(
    this.label, {
    required this.width,
    required this.height,
    this.solidWidthFraction = 1.0,
  });

  final String label;

  /// Real sizes in metres. The room is drawn to scale, so a prop that is
  /// roughly the wrong size next to a paperback is immediately obvious.
  final double width;
  final double height;

  /// How much of the drawn width books actually have to keep clear.
  ///
  /// Until this existed a prop's **artwork was its collider**: the box it was
  /// painted in was the box books were pushed out of, so nothing could
  /// overhang its own footprint. A plant's leaves and a vase's shoulder are
  /// exactly the cases where that reads wrong — a book tucked under the leaves
  /// is what a real shelf looks like, and refusing it left a suspicious gap.
  ///
  /// A fraction rather than a second stored size, so it holds when a prop is
  /// resized, and needs no migration: the *drawn* footprint is still what the
  /// database keeps.
  final double solidWidthFraction;

  /// The part of a prop at [x] of [drawnWidth] that books must avoid,
  /// horizontally centred within the artwork.
  ///
  /// Centred because every prop here is drawn about its own vertical axis; a
  /// prop whose mass sat off-centre would want its own offset.
  ({double x, double w}) solidSpan(double x, double drawnWidth) {
    final w = drawnWidth * solidWidthFraction;
    return (x: x + (drawnWidth - w) / 2, w: w);
  }

  /// Whether books have to make room for it. Everything here is solid — a prop
  /// standing on a shelf takes up shelf — but naming it says why `settle` is
  /// told about them.
  bool get blocksBooks => true;

  static PropKind parse(String? raw) => values.firstWhere(
        (k) => k.name == raw,
        // An unknown kind from a newer version still occupies its space rather
        // than vanishing, which would silently let books overlap it.
        orElse: () => PropKind.boxes,
      );
}

/// Paints one prop inside the box it was given, in [color].
///
/// The box is the prop's real footprint, so everything here works in fractions
/// of it — the same shape at any zoom.
class PropArt extends StatelessWidget {
  const PropArt({super.key, required this.kind, required this.color});

  final PropKind kind;
  final Color color;

  @override
  Widget build(BuildContext context) =>
      CustomPaint(painter: _PropPainter(kind, color), size: Size.infinite);
}

class _PropPainter extends CustomPainter {
  _PropPainter(this.kind, this.color);

  final PropKind kind;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    final fill = Paint()..color = color;
    // A second, darker tone for the parts that read as "behind" or "inside".
    final shade = Paint()..color = Color.lerp(color, Colors.black, 0.25)!;
    final light = Paint()..color = Color.lerp(color, Colors.white, 0.30)!;
    final w = size.width;
    final h = size.height;

    switch (kind) {
      case PropKind.statuette:
        // A head, a tapering body, and a plinth — the least a figure can be and
        // still read as one at thumbnail size.
        canvas.drawRect(Rect.fromLTWH(0, h * 0.88, w, h * 0.12), shade);
        final body = Path()
          ..moveTo(w * 0.30, h * 0.88)
          ..lineTo(w * 0.42, h * 0.34)
          ..lineTo(w * 0.58, h * 0.34)
          ..lineTo(w * 0.70, h * 0.88)
          ..close();
        canvas.drawPath(body, fill);
        canvas.drawCircle(Offset(w * 0.5, h * 0.22), w * 0.20, fill);

      case PropKind.plant:
        final pot = Path()
          ..moveTo(w * 0.32, h)
          ..lineTo(w * 0.26, h * 0.62)
          ..lineTo(w * 0.74, h * 0.62)
          ..lineTo(w * 0.68, h)
          ..close();
        canvas.drawPath(pot, shade);
        // Three leaves, fanned. Two control points each: a leaf is a lens, and
        // a quadratic out and back is exactly that.
        for (final (dx, tipY) in [(-0.28, 0.10), (0.0, 0.02), (0.30, 0.14)]) {
          final leaf = Path()
            ..moveTo(w * 0.5, h * 0.62)
            ..quadraticBezierTo(
              w * (0.5 + dx * 1.4),
              h * 0.34,
              w * (0.5 + dx),
              h * tipY,
            )
            ..quadraticBezierTo(
              w * (0.5 + dx * 0.2),
              h * 0.34,
              w * 0.5,
              h * 0.62,
            );
          canvas.drawPath(leaf, fill);
        }

      case PropKind.vase:
        // A belly and then a *neck*: without the waist it reads as an egg.
        final vase = Path()
          ..moveTo(w * 0.32, h)
          ..cubicTo(w * 0.00, h * 0.70, w * 0.08, h * 0.34, w * 0.40, h * 0.24)
          ..cubicTo(w * 0.36, h * 0.16, w * 0.36, h * 0.12, w * 0.34, h * 0.04)
          ..lineTo(w * 0.66, h * 0.04)
          ..cubicTo(w * 0.64, h * 0.12, w * 0.64, h * 0.16, w * 0.60, h * 0.24)
          ..cubicTo(w * 0.92, h * 0.34, w * 1.00, h * 0.70, w * 0.68, h)
          ..close();
        canvas.drawPath(vase, fill);
        // The mouth, so it reads as hollow rather than as a lump.
        canvas.drawOval(
          Rect.fromLTWH(w * 0.34, 0, w * 0.32, h * 0.08),
          shade,
        );

      case PropKind.clock:
        canvas.drawCircle(Offset(w / 2, h / 2), w * 0.46, fill);
        canvas.drawCircle(Offset(w / 2, h / 2), w * 0.36, light);
        final hands = Paint()
          ..color = shade.color
          ..strokeWidth = math.max(1, w * 0.05)
          ..strokeCap = StrokeCap.round;
        canvas.drawLine(
            Offset(w / 2, h / 2), Offset(w / 2, h * 0.22), hands); // hour
        canvas.drawLine(
            Offset(w / 2, h / 2), Offset(w * 0.74, h / 2), hands); // minute

      case PropKind.boxes:
        // Two, offset, because one box is a rectangle and two are a stack.
        canvas.drawRect(Rect.fromLTWH(0, h * 0.42, w * 0.78, h * 0.58), fill);
        canvas.drawRect(
            Rect.fromLTWH(w * 0.20, 0, w * 0.80, h * 0.42), shade);
        canvas.drawLine(
          Offset(w * 0.39, h * 0.42),
          Offset(w * 0.39, h),
          Paint()
            ..color = light.color
            ..strokeWidth = math.max(1, w * 0.03),
        );

      case PropKind.bookend:
        // An L: the upright books lean on, and the foot that slides under them.
        canvas.drawRect(Rect.fromLTWH(0, 0, w, h), fill);
        canvas.drawRect(Rect.fromLTWH(0, h * 0.90, w * 2.5, h * 0.10), shade);
    }
  }

  @override
  bool shouldRepaint(covariant _PropPainter old) =>
      old.kind != kind || old.color != color;
}
