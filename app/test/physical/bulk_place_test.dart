import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/physical/bulk_place.dart';

void main() {
  group('freeGaps', () {
    test('an empty shelf is one gap', () {
      expect(
        freeGaps(left: 0, right: 0.9, occupied: const []),
        [(start: 0.0, end: 0.9)],
      );
    });

    test('subtracts what is already there', () {
      final gaps = freeGaps(
        left: 0,
        right: 1.0,
        occupied: const [(start: 0.2, end: 0.4)],
      );
      expect(gaps, [(start: 0.0, end: 0.2), (start: 0.4, end: 1.0)]);
    });

    test('merges overlapping occupants and ignores order', () {
      // An overfull shelf really does have overlapping books, and they arrive
      // in placement order rather than left to right.
      final gaps = freeGaps(
        left: 0,
        right: 1.0,
        occupied: const [
          (start: 0.5, end: 0.7),
          (start: 0.1, end: 0.3),
          (start: 0.25, end: 0.55),
        ],
      );
      expect(gaps, [(start: 0.0, end: 0.1), (start: 0.7, end: 1.0)]);
    });

    test('clips occupants that hang off either end', () {
      final gaps = freeGaps(
        left: 0.2,
        right: 0.8,
        occupied: const [(start: -1, end: 0.3), (start: 0.7, end: 5)],
      );
      expect(gaps, [(start: 0.3, end: 0.7)]);
    });

    test('a full shelf has no gaps', () {
      expect(
        freeGaps(left: 0, right: 1, occupied: const [(start: 0, end: 1)]),
        isEmpty,
      );
    });
  });

  group('packOntoShelf', () {
    test('lays a batch out left to right from the shelf start', () {
      final r = packOntoShelf(
        shelfLeft: 0,
        shelfRight: 1.0,
        widths: const [0.03, 0.04, 0.02],
      );
      expect(r.unplaced, isEmpty);
      expect(r.placed.map((p) => p.x).toList(), [0.0, 0.03, 0.07]);
    });

    test('fills a hole before running on to the end', () {
      // The point of packing from the gaps: a book removed from the middle
      // leaves room, and the next batch should use it.
      final r = packOntoShelf(
        shelfLeft: 0,
        shelfRight: 1.0,
        widths: const [0.05],
        occupied: const [(start: 0.0, end: 0.2), (start: 0.3, end: 0.9)],
      );
      expect(r.placed.single.x, closeTo(0.2, 1e-9));
    });

    test('skips a book too wide for any gap and keeps going', () {
      final r = packOntoShelf(
        shelfLeft: 0,
        shelfRight: 1.0,
        widths: const [0.5, 0.05],
        occupied: const [(start: 0.1, end: 0.9)],
      );
      // Two 0.1 m gaps: the atlas fits neither, the paperback takes the first.
      expect(r.unplaced, [0]);
      expect(r.placed.single, (index: 1, x: 0.0));
    });

    test('reports every book that did not fit', () {
      final r = packOntoShelf(
        shelfLeft: 0,
        shelfRight: 0.1,
        widths: const [0.04, 0.04, 0.04, 0.04],
      );
      expect(r.placed.length, 2);
      expect(r.unplaced, [2, 3]);
    });

    test('a divider splits the shelf into sections it will not pack across',
        () {
      // The upright at 0.5 is occupied space like any other, so a book that
      // would have straddled it goes into the next section instead.
      final r = packOntoShelf(
        shelfLeft: 0,
        shelfRight: 1.0,
        widths: const [0.48, 0.05],
        occupied: const [(start: 0.5, end: 0.518)],
      );
      expect(r.placed[0].x, closeTo(0.0, 1e-9));
      expect(r.placed[1].x, closeTo(0.518, 1e-9),
          reason: 'packed through the divider instead of past it');
    });

    test('a book with no known thickness is reported, not stacked at zero', () {
      final r = packOntoShelf(
        shelfLeft: 0,
        shelfRight: 1.0,
        widths: const [0.0, 0.03],
      );
      expect(r.unplaced, [0]);
      expect(r.placed.single.index, 1);
    });

    test('a reversed shelf span is read the same way round', () {
      final r = packOntoShelf(
        shelfLeft: 1.0,
        shelfRight: 0.0,
        widths: const [0.03],
      );
      expect(r.placed.single.x, closeTo(0.0, 1e-9));
    });
  });
}
