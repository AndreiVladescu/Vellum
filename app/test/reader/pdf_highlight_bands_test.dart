// The shape a PDF highlight leaves on the page.
//
// This is the arithmetic behind "the highlight only covers part of the text":
// a marker stains a continuous band, and drawing one box per character leaves
// it perforated wherever a space, a comma or a thin letter is.
import 'package:flutter_test/flutter_test.dart';
import 'package:pdfrx/pdfrx.dart';
import 'package:vellum/reader/annotations/pdf_highlight_painter.dart';

/// One character box on a line whose baseline sits at [bottom].
/// PDF coordinates: the origin is bottom-left and y points up.
PdfRect _char(double left, double right, {double bottom = 100}) =>
    PdfRect(left, bottom + 10, right, bottom);

/// A glyph the extractor had no box for. PDFium reports these for spaces and
/// for characters it cannot map; unioned in, they drag the band to the page
/// origin and paint a stripe across the whole page.
const _nothing = PdfRect(0, 0, 0, 0);

void main() {
  test('a line becomes one band, spaces and all', () {
    // "ab cd": the space carries no box, so a per-character highlight would
    // show a gap right through the middle of the phrase.
    final rects = [
      _char(10, 20),
      _char(20, 30),
      _nothing,
      _char(40, 50),
      _char(50, 60),
    ];
    final bands = highlightBands('ab cd', rects, 0, 5);
    expect(bands, hasLength(1));
    expect(bands.single.left, 10);
    expect(bands.single.right, 60, reason: 'the gap is covered, not skipped');
  });

  test('a wrapped selection is one band per line, not one huge box', () {
    // Unioning across the line break would paint the margins either side and
    // the space between the lines — a block, not a highlight.
    final rects = [
      _char(400, 500, bottom: 200), // end of the first line
      _nothing, // the newline itself
      _char(50, 150, bottom: 100), // start of the second
    ];
    final bands = highlightBands('a\nb', rects, 0, 3);
    expect(bands, hasLength(2));
    expect(bands.first.bottom, 200);
    expect(bands.last.bottom, 100);
    expect(bands.last.left, 50);
  });

  test('the band covers the full line height, not just one glyph', () {
    // A capital and a comma on the same line: the band has to clear both, or
    // the descender pokes out below the ink.
    final rects = [
      PdfRect(10, 118, 22, 100), // T
      PdfRect(22, 104, 28, 94), // ,
    ];
    final bands = highlightBands('T,', rects, 0, 2);
    expect(bands, hasLength(1));
    expect(bands.single.top, 118);
    expect(bands.single.bottom, 94);
  });

  test('boxless characters never drag the band to the page origin', () {
    final bands = highlightBands('a b', [_char(10, 20), _nothing, _nothing], 0, 3);
    expect(bands, hasLength(1));
    expect(bands.single.left, 10);
    expect(bands.single.bottom, 100);
  });

  test('nothing to paint where the range holds no glyphs', () {
    expect(highlightBands('  ', [_nothing, _nothing], 0, 2), isEmpty);
  });

  test('a range past the end of the page is clamped, not thrown', () {
    // Stored offsets outlive the document they were made against: a file
    // replaced by a shorter edition must not crash the reader.
    final bands = highlightBands('ab', [_char(10, 20), _char(20, 30)], 1, 900);
    expect(bands, hasLength(1));
    expect(bands.single.left, 20);
    expect(highlightBands('ab', [_char(10, 20)], 5, 9), isEmpty);
  });
}
