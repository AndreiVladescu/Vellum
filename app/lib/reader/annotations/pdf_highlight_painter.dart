import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:pdfrx/pdfrx.dart';

import '../../data/database.dart';
import 'annotation_locator.dart';
import 'annotation_store.dart';
import 'highlight_palette.dart';

/// Draws stored highlights onto the PDF page, like a marker over the text.
///
/// **Why this is a painter and not a widget.** The stored locator is a
/// character *range* in pdfrx's extracted text; turning it into something you
/// can see means asking the page for the rectangle of each character and
/// painting over them. That has to happen in page coordinates, on the same
/// canvas as the page, which is exactly what `pagePaintCallbacks` is for.
///
/// The page text is loaded lazily and cached: `loadText()` is async and the
/// paint callback is not, so a page whose text hasn't arrived yet paints
/// nothing this frame and asks for a repaint when it has. That is why a
/// highlight can appear a moment after the page does — the alternative is
/// blocking the frame on a text extraction.
class PdfHighlightPainter {
  PdfHighlightPainter({required this.onNeedsRepaint});

  /// Called when a page's text finishes loading, so the viewer repaints and
  /// the highlights actually show up.
  final VoidCallback onNeedsRepaint;

  /// Highlights by page, rebuilt whenever the annotation stream emits.
  final Map<int, List<_Mark>> _byPage = {};

  /// Page text, once loaded. A page with no text maps to null so it is asked
  /// for exactly once rather than on every frame.
  final Map<int, PdfPageRawText?> _text = {};
  final Set<int> _loading = {};

  bool _disposed = false;

  void dispose() => _disposed = true;

  /// Re-reads the annotations. Only highlights and notes carry a locator worth
  /// painting; a bookmark marks a page, not a passage.
  void update(List<Annotation> annotations) {
    _byPage.clear();
    for (final a in annotations) {
      if (a.kind != AnnotationKind.highlight.name &&
          a.kind != AnnotationKind.note.name) {
        continue;
      }
      final locator = AnnotationLocator.decode(a.locator);
      if (locator is! PdfTextLocator) continue;
      _byPage.putIfAbsent(locator.page, () => []).add(
            _Mark(
              start: locator.start,
              end: locator.end,
              ink: HighlightColor.inkFor(a.color),
            ),
          );
    }
  }

  /// The `pagePaintCallbacks` entry.
  void paint(ui.Canvas canvas, Rect pageRect, PdfPage page) {
    final marks = _byPage[page.pageNumber];
    if (marks == null || marks.isEmpty) return;

    final text = _text[page.pageNumber];
    if (text == null) {
      _ensureText(page);
      return; // repaints once the text is in
    }

    for (final mark in marks) {
      final paint = Paint()
        ..color = mark.ink
        // Multiply keeps the glyphs readable through the ink instead of
        // washing them out, which is what a real highlighter does.
        ..blendMode = BlendMode.multiply;
      for (final rect in _rectsFor(text, mark, page, pageRect)) {
        canvas.drawRect(rect, paint);
      }
    }
  }

  /// The character rectangles a mark covers, merged per line.
  ///
  /// Merged because one rect per character produces hundreds of overlapping
  /// draws whose seams show as vertical banding at low alpha — a highlight
  /// should look like one stroke, not like each letter was coloured separately.
  Iterable<Rect> _rectsFor(
    PdfPageRawText text,
    _Mark mark,
    PdfPage page,
    Rect pageRect,
  ) sync* {
    final rects = text.charRects;
    final start = mark.start.clamp(0, rects.length);
    final end = mark.end.clamp(start, rects.length);
    Rect? run;
    for (var i = start; i < end; i++) {
      final r = rects[i].toRectInDocument(page: page, pageRect: pageRect);
      if (r.isEmpty) continue;
      if (run == null) {
        run = r;
        continue;
      }
      // Same line, near enough to be contiguous: extend the run. The vertical
      // test is what stops a wrapped selection joining into one huge block.
      final sameLine = (r.top - run.top).abs() < run.height * 0.6;
      if (sameLine && r.left <= run.right + run.height * 0.6) {
        run = run.expandToInclude(r);
      } else {
        yield run;
        run = r;
      }
    }
    if (run != null) yield run;
  }

  void _ensureText(PdfPage page) {
    final number = page.pageNumber;
    if (_text.containsKey(number) || _loading.contains(number)) return;
    _loading.add(number);
    page.loadText().then((text) {
      _loading.remove(number);
      if (_disposed) return;
      _text[number] = text;
      onNeedsRepaint();
    }).catchError((_) {
      _loading.remove(number);
      // A page whose text can't be extracted (a scan) simply shows no
      // highlights — there was nothing to select on it in the first place.
    });
  }
}

class _Mark {
  const _Mark({required this.start, required this.end, required this.ink});

  final int start;
  final int end;
  final Color ink;
}
