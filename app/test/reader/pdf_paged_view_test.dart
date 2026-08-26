// Keeping the viewport inside one page.
//
// This is what makes paged mode paged: pdfrx lays every page out in one tall
// strip whatever the mode, so without this the toggle changes nothing you can
// see.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/pdf_paged_view.dart';

/// Three A4-ish pages stacked with a gap, the way pdfrx lays a document out.
final _pages = [
  const Rect.fromLTWH(0, 0, 600, 800),
  const Rect.fromLTWH(0, 810, 600, 800),
  const Rect.fromLTWH(0, 1620, 600, 800),
];

void main() {
  _sidewaysPan();
  group('picking the page', () {
    test('the one the viewport is sitting on', () {
      expect(nearestPage(_pages, const Offset(300, 400)), 0);
      expect(nearestPage(_pages, const Offset(300, 1210)), 1);
      expect(nearestPage(_pages, const Offset(300, 2020)), 2);
    });

    test('dragging past the seam settles onto the next one', () {
      // The last row of page 1, then the first row of page 2.
      expect(nearestPage(_pages, const Offset(300, 800)), 0);
      expect(nearestPage(_pages, const Offset(300, 810)), 1);
    });

    test('the gap between pages belongs to whichever is closer', () {
      expect(nearestPage(_pages, const Offset(300, 805)), 0);
      expect(nearestPage(_pages, const Offset(300, 809)), 1);
    });

    test('a short page next to a tall one still owns its own rows', () {
      // Distance to the page *centres* alone would hand the short page's last
      // rows to the tall one, and the viewport would jump off the page you are
      // reading. Containment settles it.
      final mixed = [
        const Rect.fromLTWH(0, 0, 600, 1600), // a foldout
        const Rect.fromLTWH(0, 1610, 600, 200), // a half-empty last page
      ];
      expect(nearestPage(mixed, const Offset(300, 1800)), 1);
    });
  });

  group('clamping the viewport', () {
    const window = Size(600, 400); // half a page tall

    test('leaves a centre that is already inside alone', () {
      const centre = Offset(300, 400);
      expect(
        clampToPage(centre: centre, page: _pages[0], viewport: window),
        centre,
      );
    });

    test('will not let the page above scroll into view', () {
      // Scrolled up towards page 1 while page 2 is the one in hand: the top of
      // the window stops at the top of page 2.
      final out =
          clampToPage(centre: const Offset(300, 700), page: _pages[1], viewport: window);
      expect(out.dy, 810 + 200, reason: 'the window sits flush with the top');
    });

    test('will not let the page below scroll into view', () {
      final out =
          clampToPage(centre: const Offset(300, 2000), page: _pages[1], viewport: window);
      expect(out.dy, 1610 - 200);
    });

    test('still scrolls freely *within* a page taller than the window', () {
      for (final y in [1010.0, 1200.0, 1400.0]) {
        final out =
            clampToPage(centre: Offset(300, y), page: _pages[1], viewport: window);
        expect(out.dy, y, reason: 'a tall page has to stay readable');
      }
    });

    test('a page smaller than the window is centred, not clamped', () {
      // Zoomed out until the whole page fits: there is nothing to slide, and
      // clamping would ask for a range whose ends have crossed over.
      const zoomedOut = Size(1200, 1600);
      final out =
          clampToPage(centre: const Offset(0, 0), page: _pages[1], viewport: zoomedOut);
      expect(out, _pages[1].center);
    });

    test('holds both axes, so a wide page cannot drift sideways', () {
      final out = clampToPage(
        centre: const Offset(-500, 400),
        page: _pages[0],
        viewport: const Size(200, 400),
      );
      expect(out.dx, 100);
      expect(out.dy, 400);
    });
  });
}

// Panning sideways, and where it has to stop (8/26 report: "when zoomed to
// almost the edge of the book, I can still pan left and right… you may only pan
// when there's a page to move").
//
// pdfrx's own clamp holds the *document*, which is laid out with margins — so
// it allowed dragging on past the paper until there was background on both
// sides. The page is the limit instead.
void _sidewaysPan() {
  group('panning sideways in continuous mode', () {
    const page = Rect.fromLTWH(100, 0, 400, 600);

    test('a page wider than the window slides, as far as its edges', () {
      // Window showing 200 of the page's 400: the centre may travel from
      // left+100 to right-100 and no further.
      expect(
        clampToPageHorizontally(centreX: 150, page: page, viewportWidth: 200),
        200,
        reason: 'the left edge of the paper meets the left of the window',
      );
      expect(
        clampToPageHorizontally(centreX: 900, page: page, viewportWidth: 200),
        400,
      );
      expect(
        clampToPageHorizontally(centreX: 300, page: page, viewportWidth: 200),
        300,
        reason: 'and in between it is left alone',
      );
    });

    test('a page narrower than the window does not move at all', () {
      // The reported case: background on both sides, and dragging still
      // scrolled it.
      for (final attempt in [0.0, 300.0, 1200.0]) {
        expect(
          clampToPageHorizontally(
              centreX: attempt, page: page, viewportWidth: 900),
          page.center.dx,
          reason: 'nothing to slide onto, so it is pinned: $attempt',
        );
      }
    });

    test('a window exactly the width of the page is pinned too', () {
      expect(
        clampToPageHorizontally(centreX: 250, page: page, viewportWidth: 400),
        page.center.dx,
      );
    });
  });
}
