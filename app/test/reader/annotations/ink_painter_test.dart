// Where a piece of writing is drawn, and where you can grab it.
//
// The painter and the hit test have to agree to the pixel: a box you can see
// but cannot tap is worse than no box at all, so both ask the same measuring
// function. That agreement is what this file pins.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/annotations/ink_markup.dart';
import 'package:vellum/reader/annotations/ink_painter.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const page = Rect.fromLTWH(0, 0, 600, 900);
  const label = InkText(
    at: Offset(0.25, 0.5),
    text: 'see chapter four',
    color: 0xFF000000,
    size: 0.02,
  );

  test('a note is measured where it sits on the page', () {
    final box = textBoundsOnPage(label, page);

    expect(box.left, label.at.dx);
    expect(box.top, label.at.dy);
    expect(box.width, greaterThan(0));
    expect(box.width, lessThan(1), reason: 'page-relative, not pixels');
  });

  test('the same note is bigger on a bigger page, in pixels', () {
    final small = textBoundsOnScreen(label, const Rect.fromLTWH(0, 0, 300, 450));
    final large = textBoundsOnScreen(label, const Rect.fromLTWH(0, 0, 600, 900));

    expect(large.width, greaterThan(small.width));
  });

  test('and the same fraction of it', () {
    // Which is what makes a tap land on the words at any zoom.
    final small = textBoundsOnPage(label, const Rect.fromLTWH(0, 0, 300, 450));
    final large = textBoundsOnPage(label, const Rect.fromLTWH(0, 0, 600, 900));

    expect(large.width, closeTo(small.width, 0.02));
    expect(large.height, closeTo(small.height, 0.02));
  });

  test('a bigger size makes a bigger box', () {
    final normal = textBoundsOnPage(label, page);
    final big = textBoundsOnPage(label.copyWith(size: 0.05), page);

    expect(big.height, greaterThan(normal.height));
  });

  test('what is measured is what can be grabbed', () {
    final markup = InkMarkup(texts: [label]);
    final box = textBoundsOnPage(label, page);

    expect(
      markup.hitTest(box.center, 0.001,
          textBounds: (text) => textBoundsOnPage(text, page)),
      const InkTarget.text(0),
      reason: 'the middle of the drawn box is the middle of the tappable one',
    );
    expect(
      markup.hitTest(box.bottomRight + const Offset(0.2, 0.2), 0.001,
          textBounds: (text) => textBoundsOnPage(text, page)),
      isNull,
    );
  });

  test('a stroke knows the box it fills', () {
    const stroke = InkStroke(
      points: [Offset(0.2, 0.3), Offset(0.6, 0.1)],
      color: 1,
      width: 0.01,
    );

    final box = stroke.bounds;
    expect(box.left, lessThan(0.2), reason: 'the line has thickness');
    expect(box.right, greaterThan(0.6));
    expect(box.top, lessThan(0.1));
  });
}
