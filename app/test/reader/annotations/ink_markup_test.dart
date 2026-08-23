// Writing on a page, and where it lands (8/23 requests: a pen, and typed text
// alongside it).
//
// The property that matters is that a mark is stored in the *page's* own
// coordinates, not the screen's: the same stroke has to sit on the same word at
// every zoom level and on every device. So the round-trip through the page
// rectangle is pinned here, along with the eraser's reach and the versioned
// JSON that lets a future format degrade to "shows nothing" instead of
// "shows nonsense".
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/annotations/ink_markup.dart';

InkStroke _stroke(List<Offset> points, {int color = 0xFF2F80ED}) =>
    InkStroke(points: points, color: color, width: 0.004);

void main() {
  group('page coordinates', () {
    const page = Rect.fromLTWH(100, 50, 400, 600);

    test('a point on screen becomes a fraction of the page', () {
      expect(toPageFraction(const Offset(300, 350), page), const Offset(0.5, 0.5));
      expect(toPageFraction(const Offset(100, 50), page), Offset.zero);
      expect(toPageFraction(const Offset(500, 650), page), const Offset(1, 1));
    });

    test('and back again, wherever the page happens to be drawn', () {
      const fraction = Offset(0.25, 0.75);
      expect(fromPageFraction(fraction, page), const Offset(200, 500));

      // The same mark, on a page drawn twice as large and somewhere else —
      // which is what zooming in, or opening the book on a desktop, does.
      const zoomed = Rect.fromLTWH(-200, 0, 800, 1200);
      final onScreen = fromPageFraction(fraction, zoomed);
      expect(toPageFraction(onScreen, zoomed), fraction,
          reason: 'the page is the coordinate system, not the screen');
    });

    test('a page with no size is refused rather than dividing by zero', () {
      expect(toPageFraction(Offset.zero, Rect.zero), isNull);
    });
  });

  group('the JSON', () {
    test('round-trips strokes and text', () {
      final markup = InkMarkup(
        strokes: [
          _stroke(const [Offset(0.1, 0.2), Offset(0.15, 0.25)]),
        ],
        texts: const [
          InkText(
            at: Offset(0.3, 0.4),
            text: 'see ch. 4',
            color: 0xFF000000,
            size: 0.02,
          ),
        ],
      );

      final back = InkMarkup.decode(markup.encode())!;
      expect(back.strokes.single.points, hasLength(2));
      expect(back.strokes.single.points.first, const Offset(0.1, 0.2));
      expect(back.strokes.single.color, 0xFF2F80ED);
      expect(back.texts.single.text, 'see ch. 4');
      expect(back.texts.single.at, const Offset(0.3, 0.4));
    });

    test('is smaller than the obvious encoding', () {
      // A stroke is hundreds of numbers; a flat list is why a page of scribble
      // is kilobytes rather than tens of them.
      final long = _stroke([
        for (var i = 0; i < 200; i++) Offset(i / 200, i / 400),
      ]);
      expect(InkMarkup(strokes: [long]).encode().length, lessThan(4000));
    });

    test('a format from a newer reader shows nothing rather than nonsense', () {
      expect(InkMarkup.decode('{"v":99,"strokes":[]}'), isNull);
    });

    test('damage is not a crash', () {
      expect(InkMarkup.decode('not json'), isNull);
      expect(InkMarkup.decode(''), isNull);
      expect(InkMarkup.decode(null), isNull);
      expect(InkMarkup.decode('{"v":1,"strokes":"nope"}')?.strokes, isEmpty);
    });

    test('an empty page encodes to something that decodes back empty', () {
      final back = InkMarkup.decode(const InkMarkup().encode())!;
      expect(back.isEmpty, isTrue);
    });

    test('a stroke with one point survives — a dot is a mark', () {
      final back = InkMarkup.decode(
        InkMarkup(strokes: [_stroke(const [Offset(0.5, 0.5)])]).encode(),
      )!;
      expect(back.strokes.single.points, hasLength(1));
    });
  });

  group('the eraser', () {
    test('takes a whole stroke, not a piece of one', () {
      final markup = InkMarkup(strokes: [
        _stroke(const [Offset(0.1, 0.1), Offset(0.9, 0.1)]),
        _stroke(const [Offset(0.1, 0.9), Offset(0.9, 0.9)]),
      ]);

      final left = markup.erasedAt(const Offset(0.5, 0.1), 0.02);
      expect(left.strokes, hasLength(1));
      expect(left.strokes.single.points.first.dy, 0.9,
          reason: 'the other line is untouched');
    });

    test('catches a line between two recorded points', () {
      // A fast pen leaves its points far apart; an eraser that only tested
      // those would pass straight through the middle of the line.
      final markup = InkMarkup(strokes: [
        _stroke(const [Offset(0, 0), Offset(1, 1)]),
      ]);
      expect(markup.erasedAt(const Offset(0.5, 0.5), 0.01).strokes, isEmpty);
    });

    test('misses what it is not near', () {
      final markup = InkMarkup(strokes: [
        _stroke(const [Offset(0.1, 0.1), Offset(0.2, 0.2)]),
      ]);
      expect(markup.erasedAt(const Offset(0.8, 0.8), 0.02).strokes, hasLength(1));
    });

    test('rubs out text as well', () {
      const markup = InkMarkup(texts: [
        InkText(at: Offset(0.5, 0.5), text: 'hm', color: 0, size: 0.02),
      ]);
      expect(markup.erasedAt(const Offset(0.5, 0.5), 0.02).texts, isEmpty);
      expect(markup.erasedAt(const Offset(0.1, 0.1), 0.02).texts, hasLength(1));
    });
  });

  group('undo', () {
    test('takes back the last thing added', () {
      final markup = InkMarkup(strokes: [
        _stroke(const [Offset(0.1, 0.1)]),
        _stroke(const [Offset(0.2, 0.2)]),
      ]);
      final once = markup.withoutLast();
      expect(once.strokes, hasLength(1));
      expect(once.strokes.single.points.single, const Offset(0.1, 0.1));
    });

    test('on an empty page does nothing at all', () {
      expect(const InkMarkup().withoutLast().isEmpty, isTrue);
    });
  });
}
