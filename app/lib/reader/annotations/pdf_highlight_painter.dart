import 'dart:async';
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
///
/// **Text is only ever read from a loaded page.** pdfrx opens a document
/// progressively: right after opening, every page but the first is a
/// placeholder that knows its size and nothing else. Asking a placeholder for
/// its text does not fail — it returns an *empty* text — and an empty text
/// cached for the session means that page never shows a highlight again. A
/// book reopens on the page you were reading, which is the page you annotated,
/// and that page is painted before it has loaded: the mark was "gone" after
/// leaving the book and coming back. So the painter waits for the loaded
/// instance of the page first (see [_loadedInstance]).
class PdfHighlightPainter {
  PdfHighlightPainter({required VoidCallback onNeedsRepaint})
      : _texts = PageTextCache(onLoaded: onNeedsRepaint);

  /// Highlights by page, rebuilt whenever the annotation stream emits.
  final Map<int, List<_Mark>> _byPage = {};

  /// Page text, once loaded.
  ///
  /// **Structured, not raw.** `loadText()` returns the raw extraction;
  /// `loadStructuredText()` returns the reflowed one, with lines and words
  /// composed — and the ranges `getSelectedTextRanges()` hands back index into
  /// *that*. Painting raw rects at structured offsets is why a highlight used to
  /// cover part of the phrase and then drift off it.
  ///
  /// Not dropped when pdfrx reports a page status change: that is how a page
  /// *becomes* loaded, and since nothing is cached before then there is nothing
  /// stale to drop. A different document (the reader's *Try again* builds one)
  /// does start over, see [paint].
  final PageTextCache _texts;

  /// The document the cached text belongs to.
  PdfDocument? _document;

  void dispose() => _texts.dispose();

  /// Re-reads the annotations. Only highlights and notes carry a locator worth
  /// painting; a bookmark marks a page, not a passage.
  void update(List<Annotation> annotations) {
    // A page whose text failed to extract is given another chance whenever the
    // marks change, instead of on every paint.
    _texts.retryFailed();
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

    if (!identical(_document, page.document)) {
      _document = page.document;
      _texts.reset();
    }
    final text = _texts.textFor(page.pageNumber, () => _extract(page));
    if (text == null) return; // repaints once the text is in

    for (final mark in marks) {
      final paint = markerPaint(mark.ink);
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

  /// The page's structured text, or null if the document went away first.
  Future<PdfPageText?> _extract(PdfPage page) async {
    final loaded = await _loadedInstance(page);
    return loaded?.loadStructuredText();
  }

  /// The loaded instance of [page], waiting for it if need be; null if the
  /// document is closed before that happens.
  ///
  /// pdfrx's own `ensureLoaded()` would do, but it waits on a stream that is
  /// simply closed when the document is disposed, so it never finishes and the
  /// caller hangs on a document that no longer exists. This listens for the
  /// stream ending as well.
  Future<PdfPage?> _loadedInstance(PdfPage page) {
    final number = page.pageNumber;
    final document = page.document;
    final latest = document.pages[number - 1];
    if (latest.isLoaded) return Future.value(latest);

    final done = Completer<PdfPage?>();
    late final StreamSubscription<PdfDocumentEvent> subscription;
    subscription = document.events.listen(
      (event) {
        if (event is! PdfDocumentPageStatusChangedEvent) return;
        final changed = event.changes[number]?.page;
        if (changed == null || !changed.isLoaded) return;
        subscription.cancel();
        if (!done.isCompleted) done.complete(changed);
      },
      onDone: () {
        if (!done.isCompleted) done.complete(null);
      },
    );
    return done.future;
  }
}

/// How a mark is laid on the page: the glyphs stay black through the ink and
/// only the paper takes its colour, which is what a real highlighter does.
///
/// **Modulate, not multiply.** The two give the same pixels on a page: the
/// translucent [ink] multiplied onto the page is the page times the ink laid
/// over white, and modulate with that opaque colour is exactly that product.
/// But to Impeller (Flutter's renderer, on Linux too) multiply is an
/// "advanced" blend, drawn by copying what is already on the canvas into a
/// texture and compositing it back, and that copy resampled the sharp page
/// tile pdfrx had just drawn. Every page with a visible mark went soft, by an
/// amount that changed with the zoom. Modulate is one of the plain Porter-Duff
/// blends Impeller does in a single pass, so nothing under the mark is copied.
/// It is opaque so the page keeps its alpha.
Paint markerPaint(Color ink) => Paint()
  ..color = Color.alphaBlend(ink, const Color(0xFFFFFFFF))
  ..blendMode = BlendMode.modulate;

/// Text that arrives asynchronously, keyed by page, loaded at most once per
/// page and never retried on every paint.
///
/// Kept apart from [PdfHighlightPainter] because the rules are the part worth
/// testing and they need no PDF: the painter hands in *how* to load a page, and
/// this decides when to ask, what to remember, and when to give up.
class PageTextCache {
  PageTextCache({required this.onLoaded});

  /// Called when a page's text arrives, so the viewer repaints and the
  /// highlights actually show up.
  final VoidCallback onLoaded;

  final Map<int, PdfPageText> _text = {};
  final Set<int> _loading = {};

  /// Pages whose load threw or came back null. Not asked again until
  /// [retryFailed] or [reset]: a page that cannot be read (a scan, a broken
  /// font table) would otherwise be re-extracted on every frame it is painted.
  final Set<int> _failed = {};

  /// Bumped by [reset], so a load that was in flight for the old document
  /// cannot land in the new one's cache.
  int _epoch = 0;
  bool _disposed = false;

  /// The text for [pageNumber] if it is here; otherwise null, and a load is
  /// started (once) through [load].
  ///
  /// [load] returns null for "cannot be had" — nothing is cached then, and the
  /// page is marked failed rather than retried.
  PdfPageText? textFor(int pageNumber, Future<PdfPageText?> Function() load) {
    final cached = _text[pageNumber];
    if (cached != null) return cached;
    if (_disposed || _loading.contains(pageNumber) || _failed.contains(pageNumber)) {
      return null;
    }
    _loading.add(pageNumber);
    unawaited(_fetch(pageNumber, load));
    return null;
  }

  Future<void> _fetch(int pageNumber, Future<PdfPageText?> Function() load) async {
    final epoch = _epoch;
    PdfPageText? text;
    try {
      text = await load();
    } catch (_) {
      text = null;
    }
    if (_disposed || epoch != _epoch) return; // reset() already cleared _loading
    _loading.remove(pageNumber);
    if (text == null) {
      _failed.add(pageNumber);
      return;
    }
    _text[pageNumber] = text;
    onLoaded();
  }

  /// Allows pages that failed to be asked for again.
  void retryFailed() => _failed.clear();

  /// Forgets everything, for a different document.
  void reset() {
    _epoch++;
    _text.clear();
    _loading.clear();
    _failed.clear();
  }

  void dispose() => _disposed = true;
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
