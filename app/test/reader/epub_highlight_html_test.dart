// Painting stored highlights into EPUB markup.
//
// The risk here is not "does it colour the text" — it is corrupting the
// document: writing a <mark> into an attribute, or wrapping a quote twice.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/reader/annotations/annotation_locator.dart';
import 'package:vellum/reader/annotations/epub_highlight_html.dart';
import 'package:vellum/reader/annotations/highlight_palette.dart';

Annotation _highlight({
  required String quote,
  int chapter = 0,
  int? color,
  String kind = 'highlight',
}) =>
    Annotation(
      id: 'a-$quote-$chapter',
      bookId: 'b1',
      kind: kind,
      chapter: chapter,
      locator: EpubTextLocator(chapter: chapter, start: 0, end: quote.length)
          .encode(),
      quotedText: quote,
      color: color,
      createdAt: DateTime(2026),
    );

void main() {
  test('wraps the quote in a coloured mark', () {
    final out = withHighlights(
      '<p>The quick brown fox.</p>',
      [_highlight(quote: 'quick brown', color: HighlightColor.green.argb)],
      0,
    );
    expect(out, contains('<mark style="background-color:rgba('));
    expect(out, contains('>quick brown</mark>'));
    // Translucent, so the glyphs read through it rather than being covered.
    expect(out, contains(',0.42)'));
  });

  test('a highlight with no colour still paints, in the default', () {
    // Highlights made before there was a choice must not become invisible.
    final out = withHighlights('<p>hello there</p>', [_highlight(quote: 'hello')], 0);
    expect(out, contains('<mark'));
  });

  test('only this chapter\'s highlights are painted', () {
    final out = withHighlights(
      '<p>alpha beta</p>',
      [_highlight(quote: 'alpha', chapter: 3)],
      0,
    );
    expect(out, isNot(contains('<mark')));
  });

  test('never writes into a tag or an attribute', () {
    // The corruption this prevents: replacing text inside alt="" would put a
    // <mark> in an attribute and break the document from there on.
    const html = '<img alt="quick brown" src="x.png"><p>quick brown fox</p>';
    final out = withHighlights(html, [_highlight(quote: 'quick brown')], 0);
    expect(out, contains('alt="quick brown"'), reason: 'attribute untouched');
    expect('<mark'.allMatches(out).length, 1, reason: 'only the body text');
  });

  test('is idempotent — a second pass does not nest marks', () {
    final once = withHighlights('<p>alpha beta</p>', [_highlight(quote: 'alpha')], 0);
    final twice = withHighlights(once, [_highlight(quote: 'alpha')], 0);
    expect('<mark'.allMatches(twice).length, 1);
  });

  test('a quote containing another is wrapped first, not split', () {
    // Wrapping the short one first would break the long one's match, and you
    // would silently lose the highlight you actually made.
    final out = withHighlights(
      '<p>the quick brown fox</p>',
      [
        _highlight(quote: 'quick'),
        _highlight(quote: 'quick brown fox'),
      ],
      0,
    );
    expect(out, contains('>quick brown fox</mark>'));
  });

  test('markup it cannot place is left alone rather than mangled', () {
    // A quote straddling an inline tag isn't found as one string. Skipping is
    // the honest outcome — it is what happened before highlights were painted
    // at all, and the panel still lists it.
    const html = '<p>the <em>very</em> best</p>';
    final out = withHighlights(html, [_highlight(quote: 'very best')], 0);
    expect(out, html);
  });

  test('nothing to paint returns the markup unchanged, not a rebuild', () {
    const html = '<p>hello</p>';
    expect(withHighlights(html, const [], 0), same(html));
  });

  test('a too-short quote is not placed', () {
    // Two characters would match all over the page and colour the wrong words.
    final out = withHighlights('<p>a b c</p>', [_highlight(quote: 'b')], 0);
    expect(out, isNot(contains('<mark')));
  });

  test('notes are painted too — a note is a highlight with words attached', () {
    final out = withHighlights(
      '<p>alpha beta</p>',
      [_highlight(quote: 'alpha', kind: 'note')],
      0,
    );
    expect(out, contains('<mark'));
  });

  group('the palette', () {
    test('offers four presets and survives an unknown stored colour', () {
      expect(HighlightColor.values, hasLength(4));
      expect(HighlightColor.fromArgb(null), HighlightColor.fallback);
      expect(HighlightColor.fromArgb(0x00ABCDEF), HighlightColor.fallback);
      expect(
        HighlightColor.fromArgb(HighlightColor.blue.argb),
        HighlightColor.blue,
      );
    });

    test('ink is translucent so text stays readable under it', () {
      for (final c in HighlightColor.values) {
        expect(c.inkColor.a, lessThan(1.0));
        expect(c.color.a, 1.0, reason: 'the stored identity is opaque');
      }
    });
  });
}
