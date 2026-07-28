// Does the highlight actually reach the glass?
//
// The unit tests either side of this one prove `withHighlights` writes a
// `<mark>` and that the map points at the right words. Neither proves the
// renderer honours it — and a highlight that is correct in the markup and
// invisible on the page is exactly the bug being fixed. So this pumps the same
// widget the EPUB reader builds and reads the colour back off the text.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_widget_from_html_core/flutter_widget_from_html_core.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/reader/annotations/annotation_locator.dart';
import 'package:vellum/reader/annotations/epub_highlight_html.dart';
import 'package:vellum/reader/annotations/highlight_palette.dart';

/// Every run of text on screen with the background paint behind it.
List<({String text, Color? background})> _runs(WidgetTester tester) {
  final runs = <({String text, Color? background})>[];
  for (final rich in tester.widgetList<RichText>(find.byType(RichText))) {
    rich.text.visitChildren((span) {
      if (span is TextSpan && span.text != null) {
        runs.add((text: span.text!, background: span.style?.background?.color));
      }
      return true;
    });
  }
  return runs;
}

Annotation _highlight(String quote, {int? color}) => Annotation(
      id: 'a1',
      bookId: 'b1',
      kind: 'highlight',
      chapter: 0,
      locator:
          EpubTextLocator(chapter: 0, start: 0, end: quote.length).encode(),
      quotedText: quote,
      color: color,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      needsPush: false,
    );

void main() {
  Future<List<({String text, Color? background})>> render(
    WidgetTester tester,
    String html,
    List<Annotation> annotations,
  ) async {
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: HtmlWidget(withHighlights(html, annotations, 0)),
        ),
      ),
    );
    await tester.pump();
    return _runs(tester);
  }

  testWidgets('highlighted words are painted in the marker colour',
      (tester) async {
    final runs = await render(
      tester,
      '<p>The quick brown fox jumps.</p>',
      [_highlight('quick brown', color: HighlightColor.green.argb)],
    );

    final marked = runs.where((r) => r.background != null).toList();
    expect(marked, isNotEmpty, reason: 'nothing was painted at all');
    expect(marked.map((r) => r.text).join(), contains('quick brown'));

    final ink = marked.first.background!;
    expect(ink.r, closeTo(HighlightColor.green.color.r, 0.01));
    expect(ink.g, closeTo(HighlightColor.green.color.g, 0.01));
    expect(ink.b, closeTo(HighlightColor.green.color.b, 0.01));
    // Translucent: a marker stains the page, it doesn't cover the words.
    expect(ink.a, lessThan(1.0));
  });

  testWidgets('the rest of the paragraph is left unpainted', (tester) async {
    final runs = await render(
      tester,
      '<p>The quick brown fox jumps.</p>',
      [_highlight('quick brown')],
    );
    final plain =
        runs.where((r) => r.background == null).map((r) => r.text).join();
    expect(plain, contains('The '));
    expect(plain, contains('fox jumps.'));
  });

  testWidgets('a quote broken across the markup still shows up',
      (tester) async {
    // The pretty-printed source that used to defeat the literal search.
    final runs = await render(
      tester,
      '<p>The quick\n      brown fox\n      jumps.</p>',
      [_highlight('quick brown fox')],
    );
    final marked =
        runs.where((r) => r.background != null).map((r) => r.text).join();
    expect(marked.replaceAll(RegExp(r'\s+'), ' '), contains('quick brown fox'));
  });
}
