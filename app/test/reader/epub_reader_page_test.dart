// The EPUB reader's position encoding (plan 5 #23, which closes plan 4 §E15's
// in-chapter scroll restore).
//
// The saved form is one *global* fraction across the whole book plus the 1-based
// chapter in `lastReadPage`; reopening turns that back into "chapter N, this far
// down". Getting the arithmetic wrong reopens a long chapter at the wrong place —
// the exact complaint §E15 was filed about — so both directions are pinned here.
//
// Deliberately **not** a widget test. Driving the reader end to end means driving
// `HtmlWidget` (a third-party renderer) and an EPUB parse that normally runs in a
// background isolate, neither of which `testWidgets` can pump to completion; two
// attempts at it hung rather than failing. The arithmetic above is where the
// regression risk actually lives, and it is pure — so it is tested directly, and
// the visual result (theme, typography, restored offset) is a manual check listed
// in docs/BACKLOG.md.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/epub_reader_page.dart';

void main() {
  group('position encoding (plan 4 §E15)', () {
    test('a global fraction splits into chapter and in-chapter fraction', () {
      // 0.75 of two chapters = 1.5 → chapter index 1, halfway down.
      final at = epubPositionFrom(
          progress: 0.75, lastReadPage: 2, chapterCount: 2);
      expect(at.chapter, 1);
      expect(at.fraction, closeTo(0.5, 1e-9));
    });

    test('the saved chapter wins over what the fraction implies', () {
      // A stale fraction (say the book was re-parsed with more chapters) must
      // not move the reader to a different chapter than the one saved.
      final at = epubPositionFrom(
          progress: 0.99, lastReadPage: 1, chapterCount: 4);
      expect(at.chapter, 0);
      expect(at.fraction, 1.0, reason: 'clamped into the saved chapter');
    });

    test('an unread book starts at the top of chapter one', () {
      final at = epubPositionFrom(
          progress: null, lastReadPage: null, chapterCount: 3);
      expect((at.chapter, at.fraction), (0, 0.0));
    });

    test('a chapter beyond the book is clamped', () {
      final at = epubPositionFrom(
          progress: 1.0, lastReadPage: 99, chapterCount: 3);
      expect(at.chapter, 2);
    });

    test('an empty book degrades instead of dividing by zero', () {
      final at = epubPositionFrom(
          progress: 0.5, lastReadPage: 1, chapterCount: 0);
      expect((at.chapter, at.fraction), (0, 0.0));
      expect(epubGlobalProgress(chapter: 0, chapterCount: 0, fraction: 0.5), 0);
    });

    test('the two directions round-trip', () {
      for (final (chapter, count, fraction) in [
        (0, 1, 0.0),
        (0, 4, 0.25),
        (2, 4, 0.5),
        (3, 4, 1.0),
      ]) {
        final global = epubGlobalProgress(
            chapter: chapter, chapterCount: count, fraction: fraction);
        final back = epubPositionFrom(
            progress: global, lastReadPage: chapter + 1, chapterCount: count);
        expect(back.chapter, chapter);
        expect(back.fraction, closeTo(fraction, 1e-9));
      }
    });
  });

}
