import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/physical/settle.dart';

/// A horizontal shelf at height [y] spanning [left]..[right].
SettleSegment shelfAt(double y, double left, double right) =>
    SettleSegment(x1: left, y1: y, x2: right, y2: y);

void main() {
  test('a book dropped above a shelf settles onto the shelf top', () {
    final r = settle(
      x: 0.5,
      y: 1.4, // released well above the shelf
      w: 0.05,
      h: 0.2,
      shelves: [shelfAt(1.0, 0, 2)],
      others: const [],
    );
    expect(r.onSurface, isTrue);
    expect(r.y, closeTo(1.0, 1e-9));
    expect(r.x, closeTo(0.5, 1e-9)); // nothing to nudge against
  });

  test('a book stacks on top of another book', () {
    final r = settle(
      x: 0.52,
      y: 1.3,
      w: 0.05,
      h: 0.2,
      shelves: [shelfAt(1.0, 0, 2)],
      others: const [SettleBox(x: 0.5, y: 1.0, w: 0.1, h: 0.2)],
    );
    expect(r.onSurface, isTrue);
    expect(r.y, closeTo(1.2, 1e-9)); // sits on the other book's top (1.0 + 0.2)
  });

  test('a book with nothing beneath it is not on any surface', () {
    final r = settle(
      x: 5.0, // beyond the shelf's right end
      y: 1.05,
      w: 0.05,
      h: 0.2,
      shelves: [shelfAt(1.0, 0, 2)],
      others: const [],
    );
    expect(r.onSurface, isFalse);
  });

  group('shelfHasBooks', () {
    final shelf = shelfAt(1.0, 0, 2);

    test('is false for an empty shelf', () {
      expect(shelfHasBooks(shelf, const []), isFalse);
    });

    test('is true when a book rests on the shelf top', () {
      expect(
        shelfHasBooks(shelf, const [SettleBox(x: 0.5, y: 1.0, w: 0.1, h: 0.2)]),
        isTrue,
      );
    });

    test('ignores a book on a different shelf (different height)', () {
      expect(
        shelfHasBooks(shelf, const [SettleBox(x: 0.5, y: 1.6, w: 0.1, h: 0.2)]),
        isFalse,
      );
    });

    test('ignores a book that does not overlap horizontally', () {
      expect(
        shelfHasBooks(shelf, const [SettleBox(x: 3.0, y: 1.0, w: 0.1, h: 0.2)]),
        isFalse,
      );
    });
  });

  // --- Known bugs, pinned as tests (see docs/BACKLOG.md "Settle bounds"). ---
  // When fixed, flip these expectations deliberately.

  test('BACKLOG: nudging out of an overlap can push a book past the shelf end',
      () {
    // The shelf ends at x = 1.0. A book fills most of it; a second book dropped
    // overlapping is shoved right, past the shelf's end, yet keeps the shelf
    // height (it "floats" beyond the shelf rather than being clamped).
    final r = settle(
      x: 0.9,
      y: 1.02,
      w: 0.1,
      h: 0.2,
      shelves: [shelfAt(1.0, 0, 1.0)],
      others: const [SettleBox(x: 0.0, y: 1.0, w: 0.95, h: 0.2)],
    );
    expect(r.onSurface, isTrue);
    expect(r.y, closeTo(1.0, 1e-9));
    expect(r.x, closeTo(0.95, 1e-9)); // pushed to the other book's right edge
    // Bug: the book now extends past the shelf's right end (1.0).
    expect(r.x + 0.1, greaterThan(1.0));
  });
}
