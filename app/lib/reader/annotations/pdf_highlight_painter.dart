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
/// The page text is loaded lazily and cached: loading is async and the paint
/// callback is not, so a page whose text hasn't arrived yet paints nothing this
/// frame and asks for a repaint when it has. That is why a highlight can appear
/// a moment after the page does — the alternative is blocking the frame on a
/// text extraction.
class PdfHighlightPainter {
  PdfHighlightPainter({required this.onNeedsRepaint});

  /// Called when a page's text finishes loading, so the viewer repaints and
  /// the highlights actually show up.
  final VoidCallback onNeedsRepaint;

  /// Highlights by page, rebuilt whenever the annotation stream emits.
  final Map<int, List<_Mark>> _byPage = {};

  /// Page text, once loaded. A page with no text maps to null so it is asked
  /// for exactly once rather than on every frame.
  ///
  /// **Structured, not raw.** `loadText()` returns the raw extraction;
  /// `loadStructuredText()` returns the reflowed one, with lines and words
  /// composed — and the ranges `getSelectedTextRanges()` hands back index into
  /// *that*. Painting raw rects at structured offsets is why a highlight used to
  /// cover part of the phrase and then drift off it.
  final Map<int, PdfPageText?> _text = {};
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
      final bands = highlightBands(
        text.fullText,
        text.charRects,
        mark.start,
        mark.end,
      );
      for (final band in bands) {
        canvas.drawRect(
          band.toRectInDocument(page: page, pageRect: pageRect),
          paint,
        );
      }
    }
  }

  void _ensureText(PdfPage page) {
    final number = page.pageNumber;
    if (_text.containsKey(number) || _loading.contains(number)) return;
    _loading.add(number);
    page.loadStructuredText().then((text) {
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

/// One rectangle per line of the range `[start, end)` — the shape a marker
/// actually leaves.
///
/// **Why a band per line and not a rect per character.** A highlighter stains
/// the paper, not the letters: the spaces between words, and the gaps above and
/// below the glyphs, are covered too. Drawing each character's own box leaves
/// the highlight riddled with unpainted slivers wherever there is a space, a
/// thin letter or a comma — which is exactly what it looked like. So the
/// characters of each line are unioned into one band.
///
/// Lines come from the newlines in the extracted text rather than from
/// comparing rectangle positions: pdfrx already decided where the lines are when
/// it composed this text, and re-deriving that from geometry gets justified text
/// and mixed type sizes wrong.
///
/// Degenerate rectangles are ignored. A newline's box is zero-width at the left
/// margin and an unmapped glyph's is all zeros at the page origin; either one,
/// unioned in, drags the band across the whole page.
List<PdfRect> highlightBands(
  String fullText,
  List<PdfRect> charRects,
  int start,
  int end,
) {
  final lo = start.clamp(0, charRects.length);
  final hi = end.clamp(lo, charRects.length);
  final bands = <PdfRect>[];

  PdfRect? band;
  void close() {
    if (band != null) bands.add(band!);
    band = null;
  }

  for (var i = lo; i < hi; i++) {
    if (i < fullText.length && fullText.codeUnitAt(i) == 0x0a) {
      close();
      continue;
    }
    final r = charRects[i];
    if (r.width <= 0 || r.height <= 0) continue; // no glyph box to speak of
    band = band == null ? r : band!.merge(r);
  }
  close();
  return bands;
}

class _Mark {
  const _Mark({required this.start, required this.end, required this.ink});

  final int start;
  final int end;
  final Color ink;
}
