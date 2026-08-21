// The self-scroller's arithmetic (request 8/19 #12: "calculate how many rows
// you read per second and have a self-scrolling feature").
//
// Two things are pinned here. The speed is derived from a *measured* unit — a
// page as drawn, a line as set — so zooming in slows the scroll instead of
// racing through the same words twice as fast. And the steps are proportional,
// because a tenth of a page a minute is the whole difference at the slow end
// and invisible at the fast one.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/auto_scroll.dart';

void main() {
  group('speed in pixels', () {
    test('a page a minute moves one page height a minute', () {
      final speed = autoScrollPixelsPerSecond(
        unitsPerMinute: 1,
        unitHeightPixels: 900,
      );
      expect(speed * 60, closeTo(900, 0.001));
    });

    test('four pages a minute is four times as fast', () {
      expect(
        autoScrollPixelsPerSecond(unitsPerMinute: 4, unitHeightPixels: 900),
        closeTo(
          autoScrollPixelsPerSecond(unitsPerMinute: 1, unitHeightPixels: 900) *
              4,
          0.001,
        ),
      );
    });

    test('zooming in slows it down, so the same words go past', () {
      // The caller passes the page height *as drawn*: at 2× zoom the page is
      // twice as tall on screen, so the scroll must cover twice the pixels…
      final normal =
          autoScrollPixelsPerSecond(unitsPerMinute: 3, unitHeightPixels: 900);
      final zoomed =
          autoScrollPixelsPerSecond(unitsPerMinute: 3, unitHeightPixels: 1800);
      expect(zoomed, closeTo(normal * 2, 0.001));
      // …which is the same page every twenty seconds either way.
      expect(1800 / zoomed, closeTo(900 / normal, 0.001));
    });

    test('a nonsense speed or an unmeasured page stands still', () {
      expect(
          autoScrollPixelsPerSecond(unitsPerMinute: 0, unitHeightPixels: 900),
          0);
      expect(
          autoScrollPixelsPerSecond(unitsPerMinute: -2, unitHeightPixels: 900),
          0);
      expect(
          autoScrollPixelsPerSecond(unitsPerMinute: 3, unitHeightPixels: 0), 0);
    });
  });

  group('the limits', () {
    test('hold the speed inside the slider', () {
      expect(clampAutoScrollSpeed(1000, min: 0.5, max: 30), 30);
      expect(clampAutoScrollSpeed(0.01, min: 0.5, max: 30), 0.5);
      expect(clampAutoScrollSpeed(6, min: 0.5, max: 30), 6);
    });

    test('a broken number falls back to the slowest rather than NaN', () {
      expect(clampAutoScrollSpeed(double.nan, min: 0.5, max: 30), 0.5);
    });
  });

  group('slower and faster', () {
    test('step proportionally, not by a fixed amount', () {
      final fromSlow = stepAutoScrollSpeed(1, faster: true, min: 0.5, max: 30);
      final fromFast = stepAutoScrollSpeed(20, faster: true, min: 0.5, max: 30);
      expect(fromSlow - 1, lessThan(fromFast - 20),
          reason: 'the same press means more pages a minute when already fast');
    });

    test('a press each way comes back to about where it started', () {
      final there = stepAutoScrollSpeed(4, faster: true, min: 0.5, max: 30);
      final back =
          stepAutoScrollSpeed(there, faster: false, min: 0.5, max: 30);
      expect(back, closeTo(4, 0.05));
    });

    test('never step outside the limits', () {
      expect(stepAutoScrollSpeed(30, faster: true, min: 0.5, max: 30), 30);
      expect(stepAutoScrollSpeed(0.5, faster: false, min: 0.5, max: 30), 0.5);
    });

    test('are readable numbers, not floating-point tails', () {
      var speed = 4.0;
      for (var i = 0; i < 6; i++) {
        speed = stepAutoScrollSpeed(speed, faster: true, min: 0.5, max: 30);
        expect(autoScrollSpeedLabel(speed, 'pages').length, lessThan(16),
            reason: 'a readout of "7.8125 pages/min" helps nobody');
      }
    });
  });

  group('the readout', () {
    test('names the unit each reader counts in', () {
      expect(autoScrollSpeedLabel(6, 'pages'), '6 pages/min');
      expect(autoScrollSpeedLabel(25, 'lines'), '25 lines/min');
    });

    test('keeps the detail that matters at the slow end', () {
      expect(autoScrollSpeedLabel(0.75, 'pages'), '0.75 pages/min');
      expect(autoScrollSpeedLabel(1.5, 'pages'), '1.5 pages/min');
    });

    test('drops trailing zeros', () {
      expect(autoScrollSpeedLabel(12.0, 'pages'), '12 pages/min');
      expect(autoScrollSpeedLabel(1.50, 'pages'), '1.5 pages/min');
    });
  });

  test('a stored speed is rounded, so it cannot drift across sessions', () {
    expect(roundAutoScrollSpeed(4.0000000001), 4);
    expect(roundAutoScrollSpeed(0.7777), 0.78);
  });

  test('the defaults are inside their own limits', () {
    expect(defaultAutoScrollPagesPerMinute,
        inInclusiveRange(minAutoScrollPagesPerMinute,
            maxAutoScrollPagesPerMinute));
    expect(defaultAutoScrollLinesPerMinute,
        inInclusiveRange(minAutoScrollLinesPerMinute,
            maxAutoScrollLinesPerMinute));
  });
}
