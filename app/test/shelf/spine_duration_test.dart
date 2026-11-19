// Spine thickness for an audiobook with no page count: about thirty pages an
// hour, clamped the way page counts are. Pure, so no widgets here.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/shelf/spine_style.dart';

int _hours(num h) => (h * 3600000).round();

void main() {
  test('thirty pages an hour', () {
    expect(SpineStyle.pagesForDuration(_hours(10)), 300);
    expect(SpineStyle.pagesForDuration(_hours(1)), 30);
    expect(SpineStyle.pagesForDuration(_hours(0.5)), 15);
  });

  test('no usable length gives no estimate', () {
    expect(SpineStyle.pagesForDuration(null), isNull);
    expect(SpineStyle.pagesForDuration(0), isNull);
    expect(SpineStyle.pagesForDuration(-5), isNull);
  });

  test('the width follows the same curve and clamp as page counts', () {
    expect(SpineStyle.widthForPages(220), closeTo(41.14, 0.01));
    expect(SpineStyle.widthForPages(10), 34.0, reason: 'never thinner');
    expect(SpineStyle.widthForPages(100000), 62.0, reason: 'never wider');
  });

  group('effectiveWidth', () {
    const stored = 41.0; // what a page-less book's style was baked with

    test('a book with no pages is sized from its audio', () {
      final w = SpineStyle.effectiveWidth(stored: stored, audioMs: _hours(20));
      expect(w, SpineStyle.widthForPages(600));
      expect(w, greaterThan(stored));
    });

    test('a long book stops at the widest spine, a short one at the thinnest',
        () {
      expect(SpineStyle.effectiveWidth(stored: stored, audioMs: _hours(200)),
          62.0);
      expect(SpineStyle.effectiveWidth(stored: stored, audioMs: _hours(1)),
          34.0);
    });

    test('a real page count wins over the estimate', () {
      expect(
        SpineStyle.effectiveWidth(
            stored: stored, pageCount: 300, audioMs: _hours(40)),
        stored,
      );
    });

    test('no audio, or audio with no length, keeps the stored width', () {
      expect(SpineStyle.effectiveWidth(stored: stored), stored);
      expect(SpineStyle.effectiveWidth(stored: stored, audioMs: 0), stored);
    });
  });
}
