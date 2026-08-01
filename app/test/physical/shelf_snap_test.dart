import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/physical/shelf_snap.dart';

void main() {
  // A bookcase 0.8 m wide, sides running from the plinth to 2 m.
  const sides = <Upright>[
    (x: 0.0, bottom: 0.1, top: 2.1),
    (x: 0.8, bottom: 0.1, top: 2.1),
  ];

  test('a shelf dropped roughly inside snaps to span the bookcase', () {
    final span = snapBetweenUprights(
      left: 0.03,
      right: 0.77,
      y: 1.0,
      uprights: sides,
    );
    expect(span, isNotNull);
    expect(span!.left, closeTo(0.0, 1e-9));
    expect(span.right, closeTo(0.8, 1e-9));
  });

  test('a shelf nowhere near the uprights is left alone', () {
    expect(
      snapBetweenUprights(left: 3.0, right: 3.9, y: 1.0, uprights: sides),
      isNull,
    );
  });

  test('one end close and the other far snaps neither', () {
    // Snapping one end and leaving the other is worse than snapping neither,
    // because the result looks deliberate.
    expect(
      snapBetweenUprights(left: 0.02, right: 2.4, y: 1.0, uprights: sides),
      isNull,
    );
  });

  test('an upright that does not reach the shelf is not one of its sides', () {
    const shortLeft = <Upright>[
      (x: 0.0, bottom: 0.1, top: 0.5), // stops below
      (x: 0.8, bottom: 0.1, top: 2.1),
    ];
    expect(
      snapBetweenUprights(left: 0.03, right: 0.77, y: 1.0, uprights: shortLeft),
      isNull,
    );
  });

  test('a shelf resting on top of an upright does not snap to it', () {
    // y is exactly the panel's top: the shelf is above the bookcase, not in it.
    expect(
      snapBetweenUprights(left: 0.03, right: 0.77, y: 2.1, uprights: sides),
      isNull,
    );
  });

  test('a divider gives a shelf a half-width bay to snap into', () {
    const withDivider = <Upright>[
      (x: 0.0, bottom: 0.1, top: 2.1),
      (x: 0.4, bottom: 0.1, top: 2.1),
      (x: 0.8, bottom: 0.1, top: 2.1),
    ];
    final span = snapBetweenUprights(
      left: 0.42,
      right: 0.78,
      y: 1.0,
      uprights: withDivider,
    );
    expect(span!.left, closeTo(0.4, 1e-9));
    expect(span.right, closeTo(0.8, 1e-9));
  });

  test('fewer than two crossing uprights cannot make a span', () {
    expect(
      snapBetweenUprights(
        left: 0.0,
        right: 0.8,
        y: 1.0,
        uprights: const [(x: 0.0, bottom: 0.1, top: 2.1)],
      ),
      isNull,
    );
  });

  group('dragSegment', () {
    test('a dragged divider keeps its height', () {
      // The regression, in one line: the old code wrote the resting height into
      // y1 *and* y2, so a divider placed by hand with a real height became a
      // single point the first time it was dragged.
      final moved = dragSegment(
        x1: 0.4,
        y1: 0.1,
        x2: 0.4,
        y2: 1.5,
        delta: const Offset(0.2, 0.3),
        holdsBooks: false,
      );
      expect(moved.y1, closeTo(0.4, 1e-9));
      expect(moved.y2, closeTo(1.8, 1e-9));
      expect(moved.y2 - moved.y1, closeTo(1.4, 1e-9), reason: 'height lost');
      expect(moved.x1, closeTo(0.6, 1e-9));
      expect(moved.x2, closeTo(0.6, 1e-9));
    });

    test('an upright never snaps, however close the others are', () {
      // Snapping is a shelf spanning a bay. A divider dragged next to a panel
      // must not be stretched across to it.
      final moved = dragSegment(
        x1: 0.05,
        y1: 0.1,
        x2: 0.05,
        y2: 2.0,
        delta: Offset.zero,
        holdsBooks: false,
        uprights: sides,
      );
      expect(moved.x1, closeTo(0.05, 1e-9));
      expect(moved.x2, closeTo(0.05, 1e-9));
    });

    test('a flat shelf still moves and still snaps', () {
      final moved = dragSegment(
        x1: 0.03,
        y1: 1.0,
        x2: 0.77,
        y2: 1.0,
        delta: const Offset(0, 0.2),
        holdsBooks: true,
        uprights: sides,
      );
      expect(moved.y1, closeTo(1.2, 1e-9));
      expect(moved.y2, closeTo(1.2, 1e-9));
      expect(moved.x1, closeTo(0.0, 1e-9), reason: 'should have snapped left');
      expect(moved.x2, closeTo(0.8, 1e-9), reason: 'should have snapped right');
    });

    test('a shelf dragged well away from any bookcase just moves', () {
      final moved = dragSegment(
        x1: 3.0,
        y1: 1.0,
        x2: 3.9,
        y2: 1.0,
        delta: const Offset(0.1, -0.1),
        holdsBooks: true,
        uprights: sides,
      );
      expect(moved.x1, closeTo(3.1, 1e-9));
      expect(moved.x2, closeTo(4.0, 1e-9));
      expect(moved.y1, closeTo(0.9, 1e-9));
    });
  });
}
