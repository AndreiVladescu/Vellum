// Painting stored highlights into EPUB markup.
//
// Two things are being defended here. The first is that highlights *appear* at
// all — they did not, because real markup wraps lines mid-sentence and the old
// code looked for the quote literally in the HTML. The second is that the
// document survives: no <mark> written into an attribute, no wrapping twice.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/reader/annotations/annotation_locator.dart';
import 'package:vellum/reader/annotations/epub_highlight_html.dart';
import 'package:vellum/reader/annotations/highlight_palette.dart';
import 'package:vellum/reader/epub_book.dart';

Annotation _highlight({
  required String quote,
  int chapter = 0,
  int? color,
  String kind = 'highlight',
  int start = 0,
}) =>
    Annotation(
      id: 'a-$quote-$chapter-$start',
      bookId: 'b1',
      kind: kind,
      chapter: chapter,
      locator: EpubTextLocator(
        chapter: chapter,
        start: start,
        end: start + quote.length,
      ).encode(),
      quotedText: quote,
      color: color,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      needsPush: false,
    );

/// The visible text of the result, so a test can assert what the reader sees
/// without caring where the tags fell.
String _visible(String html) => stripHtml(html);

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

  test('paints a quote the markup broke across lines', () {
    // The bug this whole file exists for. An EPUB is pretty-printed, so the
    // paragraph's source has a newline and an indent in the middle of the
    // sentence while the quote — taken from stripHtml — has a single space.
    // Searching the raw markup for it found nothing, so nothing was painted.
    const html = '<p>The quick\n      brown fox\n      jumps.</p>';
    final out = withHighlights(html, [_highlight(quote: 'quick brown fox')], 0);
    expect(out, contains('<mark'));
    expect(_visible(out), contains('quick brown fox'));
    // The source's own line breaks are kept: only tags were inserted.
    expect(out, contains('quick\n      brown fox'));
  });

  test('a quote split by an inline tag is painted as adjacent marks', () {
    // Previously skipped as unplaceable. One <mark> spanning the </em> would be
    // illegal nesting, so it becomes two abutting ones, which read as a single
    // stripe.
    const html = '<p>the <em>very</em> best</p>';
    final out = withHighlights(html, [_highlight(quote: 'very best')], 0);
    expect('<mark'.allMatches(out).length, 2);
    expect(out, contains('<em><mark'));
    expect(_visible(out), 'the very best');
  });

  test('a highlight with no colour still paints, in the default', () {
    // Highlights made before there was a choice must not become invisible.
    final out =
        withHighlights('<p>hello there</p>', [_highlight(quote: 'hello')], 0);
    expect(out, contains('<mark'));
  });

  test("only this chapter's highlights are painted", () {
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
    final once =
        withHighlights('<p>alpha beta</p>', [_highlight(quote: 'alpha')], 0);
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
    expect('<mark'.allMatches(out).length, 1, reason: 'the inner one is dropped');
  });

  test('the stored offset picks which occurrence of a repeated phrase', () {
    // "the end" three times over; the highlight was made on the last one, and
    // colouring all three — or the first — is visibly the wrong sentence.
    const html = '<p>the end. and then the end. and finally the end.</p>';
    final at = stripHtml(html).lastIndexOf('the end');
    final out =
        withHighlights(html, [_highlight(quote: 'the end', start: at)], 0);
    expect('<mark'.allMatches(out).length, 1);
    expect(out, contains('finally <mark'));
  });

  test('nothing to paint returns the markup unchanged, not a rebuild', () {
    const html = '<p>hello</p>';
    expect(withHighlights(html, const [], 0), same(html));
  });

  test('a quote no longer in the chapter is skipped, not guessed at', () {
    const html = '<p>entirely different words</p>';
    final out = withHighlights(html, [_highlight(quote: 'vanished text')], 0);
    expect(out, same(html));
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

  test('an entity in the quote is matched in its decoded form', () {
    const html = '<p>Bell &amp; Sons, printers</p>';
    final out = withHighlights(html, [_highlight(quote: 'Bell & Sons')], 0);
    expect(out, contains('<mark'));
    expect(out, contains('&amp;'), reason: 'the entity is left encoded');
    expect(_visible(out), contains('Bell & Sons'));
  });

  group('the text map', () {
    // The map is the annotation offsets' coordinate system, so it has to agree
    // with stripHtml character for character — that is the contract the stored
    // offsets were written against.
    const samples = [
      '<p>The quick brown fox.</p>',
      '<p>Line one<br/>line two</p><p>Second\n   paragraph</p>',
      '<div><h1>Title</h1><p>Body &amp; more &nbsp; text</p></div>',
      '<p>a</p><p>b</p><p>c</p>',
      '  <p>   leading and trailing   </p>  ',
      '<style>p { color: red; }</style><p>after the style</p>',
      '<script>if (a > b) { x(); }</script><p>after the script</p>',
      '<p>an unclosed &lt; bracket &gt; and a &quot;quote&quot;</p>',
      '<p>the <em>very</em> best</p>',
      '<p>five < seven</p>',
      '',
    ];

    for (final html in samples) {
      test('matches stripHtml for ${html.isEmpty ? '(empty)' : html}', () {
        expect(mapHtmlText(html).text, stripHtml(html));
      });
    }

    test('every character points back at the markup it came from', () {
      const html = '<p>The quick\n  brown</p>';
      final map = mapHtmlText(html);
      final at = map.text.indexOf('brown');
      final runs = map.runsIn(at, at + 5).toList();
      expect(runs, hasLength(1));
      expect(html.substring(runs.single.start, runs.single.end), 'brown');
    });

    test('a run stops at a tag rather than swallowing it', () {
      const html = '<p>the <em>very</em> best</p>';
      final map = mapHtmlText(html);
      final runs = map.runsIn(0, map.text.length).toList();
      expect(runs, hasLength(3));
      for (final run in runs) {
        expect(html.substring(run.start, run.end), isNot(contains('<')));
      }
    });
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
