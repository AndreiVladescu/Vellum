import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../data/database.dart';
import 'annotation_store.dart';
import 'ink_markup.dart';

/// Draws what has been written on a page (8/23 request).
///
/// A `pagePaintCallback`, like [PdfHighlightPainter], and for the same reason:
/// the marks are stored in the page's own coordinates, so the only canvas they
/// mean anything on is the page's. That also makes zoom free — the viewer
/// scales the page, and the writing goes with it, at the right thickness.
class InkPainter {
  /// The marks of each page, rebuilt whenever the annotation stream emits.
  final Map<int, InkMarkup> _byPage = {};

  /// A page being rubbed out right now, and what is left of it.
  ///
  /// Held here rather than written straight to the database: an eraser dragged
  /// across a scribbled page fires a pointer event every few milliseconds, and
  /// each one would otherwise re-encode the whole page and write it. The page
  /// paints from this while the finger is down, and the result is stored once
  /// when it lifts.
  int? pendingPage;
  InkMarkup? pending;

  void adopt(List<Annotation> annotations) {
    _byPage.clear();
    for (final a in annotations) {
      if (AnnotationKind.parse(a.kind) != AnnotationKind.ink) continue;
      final page = a.page;
      final markup = InkMarkup.decode(a.ink);
      if (page == null || markup == null) continue;
      _byPage[page] = markup;
    }
  }

  InkMarkup markupOf(int page) => _byPage[page] ?? const InkMarkup();

  /// What the page looks like right now — the stored marks, or what is left of
  /// them mid-erase.
  InkMarkup _paintable(int page) =>
      page == pendingPage ? (pending ?? markupOf(page)) : markupOf(page);

  void paint(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    final markup = _paintable(page.pageNumber);
    if (markup.isEmpty) return;
    for (final stroke in markup.strokes) {
      final paint = Paint()
        ..color = Color(stroke.color)
        ..strokeWidth = (stroke.width * pageRect.height).clamp(0.5, 64.0)
        ..strokeCap = StrokeCap.round
        ..strokeJoin = StrokeJoin.round
        ..style = PaintingStyle.stroke
        ..isAntiAlias = true;
      final points = [
        for (final p in stroke.points) fromPageFraction(p, pageRect),
      ];
      if (points.length == 1) {
        // A dot: a zero-length line draws nothing with a stroke paint.
        canvas.drawCircle(points.first, paint.strokeWidth / 2,
            Paint()..color = paint.color);
        continue;
      }
      final path = Path()..moveTo(points.first.dx, points.first.dy);
      for (final point in points.skip(1)) {
        path.lineTo(point.dx, point.dy);
      }
      canvas.drawPath(path, paint);
    }
    for (final text in markup.texts) {
      final painter = TextPainter(
        text: TextSpan(
          text: text.text,
          style: TextStyle(
            color: Color(text.color),
            fontSize: (text.size * pageRect.height).clamp(4.0, 400.0),
            height: 1.1,
          ),
        ),
        textDirection: TextDirection.ltr,
      )..layout(maxWidth: pageRect.width);
      painter.paint(canvas, fromPageFraction(text.at, pageRect));
      painter.dispose();
    }
  }
}
