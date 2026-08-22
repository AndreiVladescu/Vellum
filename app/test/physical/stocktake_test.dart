// Stocktake reconciliation (plan 5 #30). The feature is a walk along a shelf
// with a checklist; the part that can be wrong is the set maths at the end.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/physical/layout_repository.dart';
import 'package:vellum/physical/stocktake.dart';

Book book(String id, String title) => Book(
      id: id,
      title: title,
      needsPush: true, syncExcluded: false,
      readerNotesNeedsPush: false,
      statusNeedsPush: false,
      needsProgressPush: false,
      status: 'unread',
      readCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );

PlacedBook placed(Book b, {required double x, double y = 1.0}) => (
      placement: BookPlacement(
        id: 'p-${b.id}-$x',
        environmentId: 'env',
        copyId: 'c-${b.id}-$x',
        x: x,
        y: y,
        rotation: 0,
        createdAt: DateTime(2026),
      ),
      book: b,
    );

PhysicalShelf shelf(String id, {required double y, double x1 = 0, double x2 = 3}) =>
    PhysicalShelf(
      id: id,
      environmentId: 'env',
      x1: x1,
      y1: y,
      x2: x2,
      y2: y,
      kind: 'shelf',
      anchored: true,
      createdAt: DateTime(2026),
    );

void main() {
  final dune = book('b1', 'Dune');
  final neuro = book('b2', 'Neuromancer');
  final solaris = book('b3', 'Solaris');

  test('everything found is confirmed and nothing is flagged', () {
    final result = reconcile(
      placed: [placed(dune, x: 0.1), placed(neuro, x: 0.5)],
      foundBookIds: {'b1', 'b2'},
      library: [dune, neuro],
    );
    expect([for (final c in result.confirmed) c.book.title],
        ['Dune', 'Neuromancer']);
    expect(result.missing, isEmpty);
    expect(result.unexpected, isEmpty);
    expect(result.isClean, isTrue);
  });

  test('a placed book that was not found is missing', () {
    final result = reconcile(
      placed: [placed(dune, x: 0.1), placed(neuro, x: 0.5)],
      foundBookIds: {'b1'},
      library: [dune, neuro],
    );
    expect([for (final m in result.missing) m.book.title], ['Neuromancer']);
    expect(result.isClean, isFalse);
  });

  test('a book found here but placed elsewhere says where it belongs', () {
    final result = reconcile(
      placed: [placed(dune, x: 0.1)],
      foundBookIds: {'b1', 'b3'},
      library: [dune, solaris],
      locationOf: (id) => id == 'b3' ? 'Study · Shelf 1' : null,
    );
    expect(result.unexpected, hasLength(1));
    expect(result.unexpected.single.book.title, 'Solaris');
    expect(result.unexpected.single.placedElsewhere, 'Study · Shelf 1');
    expect(result.unexpected.single.isUnplaced, isFalse);
  });

  test('a book with no placement anywhere is unexpected and unplaced', () {
    final result = reconcile(
      placed: const [],
      foundBookIds: {'b3'},
      library: [solaris],
      locationOf: (_) => null,
    );
    expect(result.unexpected.single.isUnplaced, isTrue);
  });

  test('a scan matching no book in the library is ignored, not reported', () {
    // "You own something uncatalogued" is the import flow's problem; surfacing
    // it here would bury the discrepancies a stocktake exists to show.
    final result = reconcile(
      placed: [placed(dune, x: 0.1)],
      foundBookIds: {'b1', 'unknown-isbn'},
      library: [dune],
    );
    expect(result.unexpected, isEmpty);
    expect(result.isClean, isTrue);
  });

  test('two copies of one book here are both confirmed by one sighting', () {
    // The person walking the shelf identifies a *book*. Reporting one of two
    // identical copies missing because they ticked once would be wrong far
    // more often than right.
    final result = reconcile(
      placed: [placed(dune, x: 0.1), placed(dune, x: 0.4)],
      foundBookIds: {'b1'},
      library: [dune],
    );
    expect(result.confirmed, hasLength(2));
    expect(result.missing, isEmpty);
  });

  test('nothing found at all makes every placed book missing', () {
    final result = reconcile(
      placed: [placed(dune, x: 0.1), placed(neuro, x: 0.5)],
      foundBookIds: const {},
      library: [dune, neuro],
    );
    expect(result.missing, hasLength(2));
    expect(result.confirmed, isEmpty);
    expect(result.scanned, 0);
  });

  test('an empty shelf that is also empty in reality is clean', () {
    final result = reconcile(
      placed: const [],
      foundBookIds: const {},
      library: [dune],
    );
    expect(result.isClean, isTrue);
  });

  test('results are ordered by title, so a report reads the same twice', () {
    final result = reconcile(
      placed: [placed(solaris, x: 0.1), placed(dune, x: 0.9)],
      foundBookIds: const {},
      library: [dune, solaris],
    );
    expect([for (final m in result.missing) m.book.title], ['Dune', 'Solaris']);
  });

  group('scoping to one shelf', () {
    test('only books standing on that shelf are counted', () {
      final shelves = [shelf('top', y: 2.0), shelf('bottom', y: 1.0)];
      final all = [
        placed(dune, x: 0.5, y: 2.0),
        placed(neuro, x: 1.5, y: 1.0),
        placed(solaris, x: 2.5, y: 2.0),
      ];
      final top = onShelf(shelfId: 'top', placed: all, shelves: shelves);
      expect([for (final e in top) e.book.title], ['Dune', 'Solaris']);
    });

    test('a book floating off any shelf is in no shelf-scoped count', () {
      final shelves = [shelf('top', y: 1.0, x1: 0, x2: 1)];
      final all = [placed(dune, x: 5.0, y: 1.0)];
      expect(onShelf(shelfId: 'top', placed: all, shelves: shelves), isEmpty);
    });

    test('a shelf-scoped stocktake ignores the rest of the room', () {
      final shelves = [shelf('top', y: 2.0), shelf('bottom', y: 1.0)];
      final all = [
        placed(dune, x: 0.5, y: 2.0),
        placed(neuro, x: 1.5, y: 1.0),
      ];
      final result = reconcile(
        placed: onShelf(shelfId: 'top', placed: all, shelves: shelves),
        foundBookIds: {'b1'},
        library: [dune, neuro],
      );
      expect(result.isClean, isTrue,
          reason: 'the book on the other shelf is out of scope, not missing');
    });
  });
}
