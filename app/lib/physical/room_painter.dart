import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:flutter/foundation.dart' show ValueListenable, setEquals;
import 'package:flutter/material.dart';

import '../data/database.dart';
import 'room_measure.dart';

/// How tall the skirting board is, in metres. Shared with the editor, which
/// stands a new bookcase on top of it — a bookcase whose bottom shelf is buried
/// in the skirting is the giveaway that the two were drawn by different people.
const skirtingMetres = 0.09;

/// Paints the room behind the placed books: an optional backdrop photo, a faint
/// metre grid, the floor line, and every segment drawn according to its kind
/// (plan 5 #29) — a plank for a shelf, a thin upright for a panel or divider,
/// bare text for a label.
class RoomPainter extends CustomPainter {
  RoomPainter({
    required this.shelves,
    required this.origin,
    required this.scale,
    required this.line,
    required this.plank,
    required this.label,
    this.draggingShelfId,
    required this.shelfDelta,
    this.backdrop,
    this.backdropOpacity = 0.5,
    this.backdropScale,
    this.backdropOffset = Offset.zero,
    this.measureFrom,
    this.measureTo,
    this.measureColor,
    this.wallColor,
    this.floorColor,
    this.surfaces = true,
    this.highlightIds = const {},
  }) : super(repaint: shelfDelta);

  final List<PhysicalShelf> shelves;

  /// The room photo, already decoded. Null when the room has none.
  final ui.Image? backdrop;
  final double backdropOpacity;

  /// Metres per backdrop pixel, from the two-point calibration. Null means the
  /// photo has never been calibrated — it is still drawn, at one pixel per
  /// centimetre, so it can be *seen* while being lined up rather than being
  /// invisible until the maths is done.
  final double? backdropScale;

  /// Where the photo's top-left sits, in world metres.
  final Offset backdropOffset;

  /// The measure tool's endpoints in world metres, while a measurement is in
  /// progress (plan 5 #29).
  final Offset? measureFrom;
  final Offset? measureTo;
  final Color? measureColor;
  final Offset origin;
  final double scale;
  final Color line;
  final Color plank;
  final Color label;

  // ---- the room's own surfaces (next features #10) ------------------------
  //
  // A room drawn as segments on a grid reads as a diagram. Wall, floor,
  // skirting and a contact shadow under each plank are what make it read as a
  // room instead — the cheapest third of the cosmetics work by a distance.
  //
  // Null colours mean "let the theme decide", which is what every room created
  // before this had.
  final Color? wallColor;
  final Color? floorColor;

  /// Whether to draw the floor, skirting and shelf shadows at all. Off returns
  /// the plain grid, for anyone who preferred it.
  final bool surfaces;

  /// Segments to outline: the bookcase just added or selected, or the parts
  /// being picked for a new group. Shown on the segments themselves rather than
  /// as a box around them, because a bookcase is its parts.
  final Set<String> highlightIds;
  final String? draggingShelfId;
  // A live drag offset for [draggingShelfId]; drives repaints without rebuilding
  // the widget while a shelf is dragged.
  final ValueListenable<Offset> shelfDelta;

  Offset _w2s(Offset w) =>
      Offset(origin.dx + w.dx * scale, origin.dy - w.dy * scale);

  @override
  void paint(Canvas canvas, Size size) {
    // The photo goes first, under everything: it is a tracing aid, and anything
    // drawn beneath the grid and the shelves would be hidden by them.
    if (surfaces) _paintWallAndFloor(canvas, size);
    _paintBackdrop(canvas);

    // Faint metre grid.
    final grid = Paint()
      ..color = line.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    final leftWorld = (0 - origin.dx) / scale;
    final rightWorld = (size.width - origin.dx) / scale;
    for (var x = leftWorld.floorToDouble(); x <= rightWorld; x += 1) {
      final sx = origin.dx + x * scale;
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), grid);
    }
    final bottomWorld = (origin.dy - size.height) / scale;
    final topWorld = origin.dy / scale;
    for (var y = bottomWorld.floorToDouble(); y <= topWorld; y += 1) {
      final sy = origin.dy - y * scale;
      canvas.drawLine(Offset(0, sy), Offset(size.width, sy), grid);
    }

    // Floor (world y = 0).
    final floor = Paint()
      ..color = line
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, origin.dy), Offset(size.width, origin.dy), floor);

    if (surfaces) _paintSurfaces(canvas, size);

    // Segments, drawn by kind (the one being dragged is shifted live).
    final plankPaint = Paint()..color = plank.withValues(alpha: 0.85);
    final structurePaint = Paint()..color = plank.withValues(alpha: 0.45);
    for (final s in shelves) {
      final d = s.id == draggingShelfId ? shelfDelta.value : Offset.zero;
      final p1 = _w2s(Offset(s.x1 + d.dx, s.y1 + d.dy));
      final p2 = _w2s(Offset(s.x2 + d.dx, s.y2 + d.dy));
      final left = math.min(p1.dx, p2.dx);
      final right = math.max(p1.dx, p2.dx);
      final top = math.min(p1.dy, p2.dy);
      final bottom = math.max(p1.dy, p2.dy);
      final kind = ShelfKind.parse(s.kind);

      switch (kind) {
        case ShelfKind.shelf:
          canvas.drawRect(
              Rect.fromLTWH(left, top, right - left, 5), plankPaint);
        case ShelfKind.panel:
        case ShelfKind.divider:
          // Structure reads as an upright: a bookcase side is defined by the
          // *span* between its endpoints, which for these is usually vertical.
          canvas.drawRect(
            Rect.fromLTRB(left, top, math.max(right, left + 3),
                math.max(bottom, top + 3)),
            structurePaint,
          );
        case ShelfKind.marker:
          break; // text only — see below
      }

      if (highlightIds.contains(s.id)) {
        canvas.drawRect(
          Rect.fromLTRB(left - 3, top - 3, math.max(right, left + 3) + 3,
                  math.max(bottom, top + 3) + 3)
              .inflate(1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = label,
        );
      }

      final name = s.label;
      if (name != null && name.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: name,
            style: TextStyle(
              color: label,
              fontSize: kind == ShelfKind.marker ? 13 : 11,
              fontWeight:
                  kind == ShelfKind.marker ? FontWeight.w600 : FontWeight.normal,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(left + 2, top + (kind == ShelfKind.marker ? -4 : 7)));
      }
    }

    _paintMeasure(canvas);
  }

  /// Wall above the floor line, floor below it. Drawn before the backdrop, so a
  /// room with a photo of its actual wall still gets one over the top.
  void _paintWallAndFloor(Canvas canvas, Size size) {
    final wall = wallColor;
    final ground = floorColor;
    if (wall == null && ground == null) return;
    final horizon = origin.dy.clamp(0.0, size.height);
    if (wall != null) {
      canvas.drawRect(
        Rect.fromLTRB(0, 0, size.width, horizon),
        Paint()..color = wall,
      );
    }
    if (ground != null) {
      canvas.drawRect(
        Rect.fromLTRB(0, horizon, size.width, size.height),
        Paint()..color = ground,
      );
    }
  }

  /// The skirting board, and a soft contact shadow under every plank.
  ///
  /// The shadow is drawn by the room rather than baked into anything, so every
  /// object in it — a shelf now, a prop later — sits on the same imagined light.
  /// That consistency does more for the picture than the shadow itself.
  void _paintSurfaces(Canvas canvas, Size size) {
    // Skirting: a band above the floor line, in metres so it scales with zoom.
    final skirtingPx = skirtingMetres * scale;
    if (skirtingPx > 2) {
      canvas.drawRect(
        Rect.fromLTRB(0, origin.dy - skirtingPx, size.width, origin.dy),
        Paint()..color = plank.withValues(alpha: 0.16),
      );
      canvas.drawLine(
        Offset(0, origin.dy - skirtingPx),
        Offset(size.width, origin.dy - skirtingPx),
        Paint()
          ..color = line.withValues(alpha: 0.6)
          ..strokeWidth = 1,
      );
    }

    for (final s in shelves) {
      if (!ShelfKind.parse(s.kind).holdsBooks) continue;
      final d = s.id == draggingShelfId ? shelfDelta.value : Offset.zero;
      final p1 = _w2s(Offset(s.x1 + d.dx, s.y1 + d.dy));
      final p2 = _w2s(Offset(s.x2 + d.dx, s.y2 + d.dy));
      final left = math.min(p1.dx, p2.dx);
      final right = math.max(p1.dx, p2.dx);
      final top = math.max(p1.dy, p2.dy);
      // Under the plank, fading down — the contact shadow of a board with a
      // wall behind it.
      final rect = Rect.fromLTRB(left, top, right, top + math.max(3, 0.04 * scale));
      canvas.drawRect(
        rect,
        Paint()
          ..shader = ui.Gradient.linear(
            rect.topLeft,
            rect.bottomLeft,
            [
              const Color(0x33000000),
              const Color(0x00000000),
            ],
          ),
      );
    }
  }

  void _paintBackdrop(Canvas canvas) {
    final image = backdrop;
    if (image == null || backdropOpacity <= 0) return;
    // Uncalibrated: a centimetre per pixel, which is roughly a phone photo of a
    // wall and puts the image on screen at a workable size to line up.
    final metresPerPixel = backdropScale ?? 0.01;
    final topLeft = _w2s(backdropOffset);
    final width = image.width * metresPerPixel * scale;
    final height = image.height * metresPerPixel * scale;
    canvas.drawImageRect(
      image,
      Rect.fromLTWH(0, 0, image.width.toDouble(), image.height.toDouble()),
      Rect.fromLTWH(topLeft.dx, topLeft.dy, width, height),
      Paint()..color = Color.fromRGBO(255, 255, 255, backdropOpacity.clamp(0, 1)),
    );
  }

  void _paintMeasure(Canvas canvas) {
    final from = measureFrom;
    final to = measureTo;
    if (from == null || to == null) return;
    final colour = measureColor ?? plank;
    final a = _w2s(from);
    final b = _w2s(to);
    final paint = Paint()
      ..color = colour
      ..strokeWidth = 2;
    canvas.drawLine(a, b, paint);
    // End caps, so a short measurement is still visibly a measurement.
    for (final point in [a, b]) {
      canvas.drawCircle(point, 4, paint);
    }

    final metres = (to - from).distance;
    final tp = TextPainter(
      text: TextSpan(
        text: formatDistance(metres),
        style: TextStyle(
          color: colour,
          fontSize: 13,
          fontWeight: FontWeight.w600,
        ),
      ),
      textDirection: TextDirection.ltr,
    )..layout();
    final mid = Offset((a.dx + b.dx) / 2, (a.dy + b.dy) / 2);
    tp.paint(canvas, mid + const Offset(8, -18));
  }

  @override
  bool shouldRepaint(covariant RoomPainter old) =>
      old.wallColor != wallColor ||
      old.floorColor != floorColor ||
      old.surfaces != surfaces ||
      !setEquals(old.highlightIds, highlightIds) ||
      old.shelves != shelves ||
      old.origin != origin ||
      old.scale != scale ||
      old.draggingShelfId != draggingShelfId ||
      old.backdrop != backdrop ||
      old.backdropOpacity != backdropOpacity ||
      old.backdropScale != backdropScale ||
      old.backdropOffset != backdropOffset ||
      old.measureFrom != measureFrom ||
      old.measureTo != measureTo;
  // shelfDelta drives repaints via `repaint:` (a Listenable), so it's not
  // compared here.
}
