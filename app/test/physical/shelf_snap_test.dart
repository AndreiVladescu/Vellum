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
}
