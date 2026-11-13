// The EPUB reader's paged mode (roadmap v1.4.0): where pages start, and how a
// saved position maps onto them.
//
// Pure arithmetic over measured lines — the render-tree side is deliberately
// thin, because driving HtmlWidget under testWidgets hangs (docs/BACKLOG.md).
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/epub_pagination.dart';

/// [count] lines of [height], one under the other from [from].
List<LineSpan> lines(int count, double height, {double from = 0}) => [
      for (var i = 0; i < count; i++)
        (top: from + i * height, bottom: from + (i + 1) * height),
    ];

void main() {
  group('paginate', () {
    test('a chapter shorter than a page is one page', () {
      expect(
        paginate(lines: lines(5, 20), pageHeight: 400, contentHeight: 100),
        [0],
      );
    });

    test('pages end between lines, never through one', () {
      // 30px lines on a 100px page: a plain cut at 100 would slice line 4
      // (90–120), so the page ends at 90 and the next starts there.
      final starts =
          paginate(lines: lines(10, 30), pageHeight: 100, contentHeight: 300);
      expect(starts, [0, 90, 180, 270]);
    });

    test('lines that fit exactly need no snapping', () {
      final starts =
          paginate(lines: lines(10, 25), pageHeight: 100, contentHeight: 250);
      expect(starts, [0, 100, 200]);
    });

    test('a picture that would be cut moves whole to the next page', () {
      final content = [
        ...lines(3, 20), // 0–60
        (top: 60.0, bottom: 150.0), // a picture
        ...lines(3, 20, from: 150), // 150–210
      ];
      final starts =
          paginate(lines: content, pageHeight: 100, contentHeight: 210);
      expect(starts.take(2), [0, 60]);
    });

    test('something taller than a page is cut, and pagination moves on', () {
      final starts = paginate(
        lines: [(top: 0, bottom: 350)],
        pageHeight: 100,
        contentHeight: 350,
      );
      expect(starts, [0, 100, 200, 300]);
    });

    test('of overlapping things crossing the edge, the highest decides', () {
      // A table row: two cells' lines at different heights both cross 100.
      final starts = paginate(
        lines: [
          (top: 0, bottom: 80),
          (top: 85, bottom: 110),
          (top: 92, bottom: 115),
        ],
        pageHeight: 100,
        contentHeight: 150,
      );
      expect(starts, [0, 85]);
    });

    test('lines arrive in any order', () {
      final shuffled = lines(10, 30).reversed;
      expect(
        paginate(lines: shuffled, pageHeight: 100, contentHeight: 300),
        [0, 90, 180, 270],
      );
    });

    test('every page shows only whole lines', () {
      final content = lines(97, 23.7);
      final height = 97 * 23.7;
      final starts =
          paginate(lines: content, pageHeight: 311, contentHeight: height);
      for (var i = 0; i < starts.length; i++) {
        final end = i + 1 < starts.length ? starts[i + 1] : height;
        expect(end - starts[i], lessThanOrEqualTo(311 + 1e-9));
        for (final line in content) {
          final cut = line.top < end - 0.5 && line.bottom > end + 0.5;
          expect(cut, isFalse, reason: 'page $i cuts a line at $end');
        }
      }
    });
  });

  group('ChapterPages', () {
    // Pages start at 0, 90, 180, 270 in a 300px chapter on a 100px page.
    final pages = ChapterPages.of(
      lines: lines(10, 30),
      pageHeight: 100,
      contentHeight: 300,
    );

    test('page for an offset', () {
      expect(pages.count, 4);
      expect(pages.pageAt(0), 0);
      expect(pages.pageAt(89), 0);
      expect(pages.pageAt(90), 1);
      expect(pages.pageAt(299), 3);
    });

    test('a page shows down to where the next begins', () {
      expect(pages.visibleHeight(0), 90);
      expect(pages.visibleHeight(3), 100, reason: 'the last page is open');
    });

    test('scroll fractions round-trip through every page', () {
      for (var page = 0; page < pages.count; page++) {
        final fraction = pages.scrollFractionOf(page);
        expect(pages.pageForScrollFraction(fraction), page);
      }
    });

    test('the scroll fraction is the one scrolled mode saves', () {
      // Scrolled mode stores offset / (content - viewport); page 2 starts at
      // 180 of a 200px range.
      expect(pages.scrollFractionOf(2), closeTo(0.9, 1e-9));
      expect(pages.scrollFractionOf(3), 1, reason: 'the end reads as the end');
      expect(pages.pageForScrollFraction(0), 0);
      expect(pages.pageForScrollFraction(1), 3);
    });

    test('a scrolled position opens on the page holding its top line', () {
      // Scrolled to 150px of 200: the top line (150–180) is on page 1.
      expect(pages.pageForScrollFraction(0.75), 1);
    });

    test('a content fraction survives a change of page height', () {
      // On page 2 (starts at 180), then the toolbar hides and pages grow.
      final anchor = AtContentFraction(pages.contentFractionOf(2));
      final taller = ChapterPages.of(
        lines: lines(10, 30),
        pageHeight: 130,
        contentHeight: 300,
      );
      expect(taller.starts, [0, 120, 240]);
      // 180 is on the page starting at 120: the text read stays on screen.
      expect(taller.pageFor(anchor), 1);
    });

    test('a single page has no range to scroll', () {
      final one =
          ChapterPages.of(lines: lines(2, 30), pageHeight: 100, contentHeight: 60);
      expect(one.count, 1);
      expect(one.scrollFractionOf(0), 0);
      expect(one.pageForScrollFraction(1), 0);
      expect(one.progressOf(0), 1);
    });

    test('progress through the chapter', () {
      expect(pages.progressOf(0), 0);
      expect(pages.progressOf(3), 1);
    });

    test('equal paginations compare equal', () {
      final again = ChapterPages.of(
        lines: lines(10, 30),
        pageHeight: 100,
        contentHeight: 300,
      );
      expect(again, pages);
      expect(again.hashCode, pages.hashCode);
    });
  });

  test('a paragraph\'s run boxes merge into lines', () {
    final merged = mergeIntoLines([
      (top: 0, bottom: 20),
      (top: 2, bottom: 18), // a bold run on the same line
      (top: 20, bottom: 40), // the next line, touching
      (top: 41, bottom: 60),
    ]);
    expect(merged, [
      (top: 0.0, bottom: 20.0),
      (top: 20.0, bottom: 40.0),
      (top: 41.0, bottom: 60.0),
    ]);
  });
}
