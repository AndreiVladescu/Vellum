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

    test('restsOnShelf identifies a shelf\'s riders (for shelf-edit carry)', () {
      const on = SettleBox(x: 0.5, y: 1.0, w: 0.1, h: 0.2);
      const above = SettleBox(x: 0.5, y: 1.6, w: 0.1, h: 0.2);
      const beside = SettleBox(x: 3.0, y: 1.0, w: 0.1, h: 0.2);
      expect(restsOnShelf(on, shelf), isTrue);
      expect(restsOnShelf(above, shelf), isFalse, reason: 'different height');
      expect(restsOnShelf(beside, shelf), isFalse, reason: 'no x-overlap');
    });
  });

  // --- Settle bounds: books stay on their shelf (was BACKLOG). ---

  test('a book nudged sideways is clamped to stay within the shelf', () {
    // Shelf [0, 1]. A book fills [0, 0.3]; a 0.1-wide book dropped overlapping
    // it is shoved right to 0.3 — and stays within the shelf, not past its end.
    final r = settle(
      x: 0.25,
      y: 1.02,
      w: 0.1,
      h: 0.2,
      shelves: [shelfAt(1.0, 0, 1.0)],
      others: const [SettleBox(x: 0.0, y: 1.0, w: 0.3, h: 0.2)],
    );
    expect(r.onSurface, isTrue);
    expect(r.x, closeTo(0.3, 1e-9));
    expect(r.x + 0.1, lessThanOrEqualTo(1.0 + 1e-9), reason: 'within the shelf');
  });

  test('a book that cannot fit the shelf falls through instead of floating', () {
    // The shelf [0, 1] is nearly full ([0, 0.95]); a 0.1 book has no room. It no
    // longer floats past the shelf end — with nothing below, it is not placed.
    final r = settle(
      x: 0.9,
      y: 1.02,
      w: 0.1,
      h: 0.2,
      shelves: [shelfAt(1.0, 0, 1.0)],
      others: const [SettleBox(x: 0.0, y: 1.0, w: 0.95, h: 0.2)],
    );
    expect(r.onSurface, isFalse);
  });

  test('a book that cannot fit the shelf lands on a lower surface', () {
    // Same full high shelf, but an empty lower shelf [0, 2] at y = 0.5 catches
    // the book instead of it floating past the high shelf's end.
    final r = settle(
      x: 0.9,
      y: 1.02,
      w: 0.1,
      h: 0.2,
      shelves: [shelfAt(1.0, 0, 1.0), shelfAt(0.5, 0, 2)],
      others: const [SettleBox(x: 0.0, y: 1.0, w: 0.95, h: 0.2)],
    );
    expect(r.onSurface, isTrue);
    expect(r.y, closeTo(0.5, 1e-9));
  });
}
