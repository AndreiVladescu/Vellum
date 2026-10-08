import 'dart:ui' show Color;

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/reader/annotations/annotation_locator.dart';
import 'package:vellum/reader/annotations/epub_highlight_html.dart';
import 'package:vellum/reader/chapter_markup.dart';
import 'package:vellum/reader/epub_book.dart';
import 'package:vellum/reader/night_mode.dart';

// The reader page rewrote its chapter on every rebuild — ~150 ms on an 8 MB
// chapter (performance round #9). `identical` is the point of these: an equal
// string still costs the HtmlWidget a character-by-character compare.
void main() {
  const chapter = EpubChapter(
    title: 'One',
    html: '<p style="color: #222; margin: 1em">It was a bright cold day.</p>',
  );
  const ink = Color(0xFFEEEEEE);

  Annotation highlight(String quote) => Annotation(
        id: 'a1',
        bookId: 'b1',
        kind: 'highlight',
        chapter: 0,
        locator: EpubTextLocator(chapter: 0, start: 0, end: quote.length).encode(),
        quotedText: quote,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        needsPush: false,
      );

  String show(ChapterMarkup markup, {bool dark = true, List<Annotation> notes = const []}) =>
      markup.of(chapter, index: 0, darkPage: dark, ink: ink, annotations: notes);

  test('a rebuild with nothing changed gets the very same string back', () {
    final markup = ChapterMarkup();
    final notes = [highlight('bright cold day')];
    final first = show(markup, notes: notes);
    expect(identical(show(markup, notes: notes), first), isTrue);
  });

  test('is what the reader computed before, not an approximation', () {
    final notes = [highlight('bright cold day')];
    expect(
      show(ChapterMarkup(), notes: notes),
      withHighlights(withoutBookColours(chapter.html), notes, 0, ink: ink),
    );
    expect(show(ChapterMarkup(), dark: false), chapter.html,
        reason: 'a light page with no highlights is the chapter as it is');
  });

  test('a new annotation list, or night mode, remakes it', () {
    final markup = ChapterMarkup();
    final plain = show(markup);
    expect(plain, isNot(contains('<mark')));

    final marked = show(markup, notes: [highlight('bright cold day')]);
    expect(marked, contains('<mark'), reason: 'the list is new, so is the markup');

    final light = show(markup, dark: false);
    expect(light, contains('color: #222'),
        reason: 'the book keeps its colours on a light page');
  });
}
