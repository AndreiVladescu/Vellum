import 'dart:math' as math;

import 'package:flutter/foundation.dart' show ValueListenable;
import 'package:flutter/material.dart';

import '../data/database.dart';

/// Paints the room behind the placed books: a faint metre grid, the floor
/// line, and every shelf as a plank (with its optional label).
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
  }) : super(repaint: shelfDelta);

  final List<PhysicalShelf> shelves;
  final Offset origin;
  final double scale;
  final Color line;
  final Color plank;
  final Color label;
  final String? draggingShelfId;
  // A live drag offset for [draggingShelfId]; drives repaints without rebuilding
  // the widget while a shelf is dragged.
  final ValueListenable<Offset> shelfDelta;

  Offset _w2s(Offset w) =>
      Offset(origin.dx + w.dx * scale, origin.dy - w.dy * scale);

  @override
  void paint(Canvas canvas, Size size) {
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

    // Shelves as planks (the one being dragged is shifted live).
    final plankPaint = Paint()..color = plank.withValues(alpha: 0.85);
    for (final s in shelves) {
      final d = s.id == draggingShelfId ? shelfDelta.value : Offset.zero;
      final p1 = _w2s(Offset(s.x1 + d.dx, s.y1 + d.dy));
      final p2 = _w2s(Offset(s.x2 + d.dx, s.y2 + d.dy));
      final left = math.min(p1.dx, p2.dx);
      final right = math.max(p1.dx, p2.dx);
      final top = math.min(p1.dy, p2.dy);
      canvas.drawRect(Rect.fromLTWH(left, top, right - left, 5), plankPaint);
      final name = s.label;
      if (name != null && name.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: name,
            style: TextStyle(color: label, fontSize: 11),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(left + 2, top + 7));
      }
    }
  }

  @override
  bool shouldRepaint(covariant RoomPainter old) =>
      old.shelves != shelves ||
      old.origin != origin ||
      old.scale != scale ||
      old.draggingShelfId != draggingShelfId;
  // shelfDelta drives repaints via `repaint:` (a Listenable), so it's not
  // compared here.
}
