// Swipes, and the drag that should not wander sideways.
//
// Both requests are about a finger on a page, and both come down to arithmetic
// on one offset. Kept out of the reader so the answers can be checked without a
// PDF, a viewer, or a device.
import 'dart:ui';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_gestures.dart';

void main() {
  const quick = Duration(milliseconds: 200);

  group('swipes turn pages, in paged mode, when the page is not zoomed', () {
    SwipeTurn? turn(
      Offset delta, {
      Duration elapsed = quick,
      bool paged = true,
      bool resting = true,
    }) =>
        swipeTurn(
          delta: delta,
          elapsed: elapsed,
          paged: paged,
          atRestingZoom: resting,
        );

    test('up and left both go forwards', () {
      expect(turn(const Offset(0, -120)), SwipeTurn.forward);
      expect(turn(const Offset(-120, 0)), SwipeTurn.forward);
    });

    test('down and right both go back', () {
      expect(turn(const Offset(0, 120)), SwipeTurn.back);
      expect(turn(const Offset(120, 0)), SwipeTurn.back);
    });

    test('the axis that moved further is the one meant', () {
      // A swipe up that drifted right is still a swipe up.
      expect(turn(const Offset(30, -120)), SwipeTurn.forward);
      // And a swipe right that drifted up is still a swipe right.
      expect(turn(const Offset(120, -30)), SwipeTurn.back);
    });

    test('a short drag is not a swipe', () {
      expect(turn(const Offset(0, -40)), isNull);
      expect(turn(const Offset(40, 0)), isNull);
    });

    test('a slow drag is not a swipe', () {
      expect(
        turn(const Offset(0, -200), elapsed: const Duration(seconds: 2)),
        isNull,
        reason: 'that is repositioning the page, not flicking it over',
      );
    });

    test('continuous mode keeps its scrolling', () {
      expect(turn(const Offset(0, -200), paged: false), isNull);
    });

    test('a zoomed page keeps its panning', () {
      expect(
        turn(const Offset(0, -200), resting: false),
        isNull,
        reason: 'otherwise there is no way to see the rest of a zoomed page',
      );
    });

    test('exactly at the threshold counts', () {
      expect(turn(const Offset(0, -swipeDistance)), SwipeTurn.forward);
      expect(turn(Offset(0, -swipeDistance + 0.1)), isNull);
    });
  });

  group('the axis lock', () {
    test('waits until the drag has gone somewhere', () {
      expect(axisDecided(const Offset(3, 5)), false,
          reason: 'every drag looks diagonal in its first few pixels');
      expect(axisDecided(const Offset(0, axisDecisionDistance)), true);
    });

    test('locks a clearly vertical drag', () {
      expect(isVerticalDrag(const Offset(5, 100)), true);
    });

    test('leaves a diagonal drag alone', () {
      expect(
        isVerticalDrag(const Offset(60, 100)),
        false,
        reason: 'deliberate diagonal panning has to stay possible',
      );
    });

    test('leaves a horizontal drag alone', () {
      expect(isVerticalDrag(const Offset(100, 5)), false);
    });

    test('two to one is the line', () {
      expect(isVerticalDrag(const Offset(50, 101)), true);
      expect(isVerticalDrag(const Offset(50, 100)), false);
    });
  });
}
