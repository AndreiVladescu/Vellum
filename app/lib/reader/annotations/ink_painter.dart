import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../data/database.dart';
import 'annotation_store.dart';
import 'ink_markup.dart';

/// How big the rotate-and-resize handle is drawn, in view pixels. Also what the
/// reader treats as "close enough" when a finger goes down on it.
const handleRadius = 9.0;

/// The text as it will be laid out on a page drawn at [pageRect].
///
/// One place, because the painter and the hit test have to agree to the pixel:
/// a box you can see but cannot tap is worse than no box.
TextPainter textPainterFor(InkText text, Rect pageRect) => TextPainter(
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

/// The unrotated box a piece of text fills, in view pixels.
Rect textBoundsOnScreen(InkText text, Rect pageRect) {
  final painter = textPainterFor(text, pageRect);
  final size = painter.size;
  painter.dispose();
  return Rect.fromLTWH(0, 0, size.width, size.height);
}

/// The same box in page-relative coordinates, anchored where the text is —
/// what [InkMarkup.hitTest] wants.
Rect textBoundsOnPage(InkText text, Rect pageRect) {
  final box = textBoundsOnScreen(text, pageRect);
  if (pageRect.width <= 0 || pageRect.height <= 0) return Rect.zero;
  return Rect.fromLTWH(
    text.at.dx,
    text.at.dy,
    box.width / pageRect.width,
    box.height / pageRect.height,
  );
}

/// Draws what has been written on a page (8/23 request).
///
/// A `pagePaintCallback`, like [PdfHighlightPainter], and for the same reason:
/// the marks are stored in the page's own coordinates, so the only canvas they
/// mean anything on is the page's. That also makes zoom free — the viewer
/// scales the page, and the writing goes with it, at the right thickness.
class InkPainter {
  /// The marks of each page, rebuilt whenever the annotation stream emits.
  final Map<int, InkMarkup> _byPage = {};

  /// What is selected, if anything, and on which page — drawn with a box
  /// round it so it is obvious what a drag is about to move.
  int? selectedPage;
  InkTarget? selected;

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
      final painter = textPainterFor(text, pageRect);
      final origin = fromPageFraction(text.at, pageRect);
      if (text.rotation == 0) {
        painter.paint(canvas, origin);
      } else {
        // Turned about its own anchor, so moving a note and turning it are
        // independent: the corner you placed stays where you put it.
        canvas
          ..save()
          ..translate(origin.dx, origin.dy)
          ..rotate(text.rotation);
        painter.paint(canvas, Offset.zero);
        canvas.restore();
      }
      painter.dispose();
    }
    if (page.pageNumber == selectedPage) _paintSelection(canvas, pageRect, markup);
  }

  /// A dashed-looking box round the selected mark, plus the corner handle that
  /// turns and resizes a piece of text.
  void _paintSelection(ui.Canvas canvas, Rect pageRect, InkMarkup markup) {
    final target = selected;
    if (target == null) return;
    final outline = Paint()
      ..color = const Color(0xFF2F80ED)
      ..strokeWidth = 1.5
      ..style = PaintingStyle.stroke;

    switch (target.kind) {
      case InkTargetKind.stroke:
        if (target.index >= markup.strokes.length) return;
        final box = markup.strokes[target.index].bounds;
        canvas.drawRect(
          Rect.fromPoints(
            fromPageFraction(box.topLeft, pageRect),
            fromPageFraction(box.bottomRight, pageRect),
          ).inflate(4),
          outline,
        );
      case InkTargetKind.text:
        if (target.index >= markup.texts.length) return;
        final text = markup.texts[target.index];
        final box = textBoundsOnScreen(text, pageRect);
        final origin = fromPageFraction(text.at, pageRect);
        canvas
          ..save()
          ..translate(origin.dx, origin.dy)
          ..rotate(text.rotation)
          ..drawRect(
            Rect.fromLTWH(0, 0, box.width, box.height).inflate(3),
            outline,
          )
          // The handle: drag it to turn the note and to make it bigger or
          // smaller, which is one gesture on paper and should be one here.
          ..drawCircle(
            Offset(box.width + 3, box.height + 3),
            handleRadius,
            Paint()..color = const Color(0xFF2F80ED),
          )
          ..restore();
    }
  }
}
