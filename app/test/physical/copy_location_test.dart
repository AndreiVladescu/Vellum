// A copy's location derived from its placement (plan 5 #50). The bug this closes
// is silent: `physical_copy.location` is typed once and never updated, so after
// the first rearrangement the detail page confidently showed the wrong shelf.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/physical/layout_repository.dart';

Future<LibraryRepository> _repo(Directory dir) async =>
    LibraryRepository.forTesting(VellumDatabase(NativeDatabase.memory()), dir);

BookPlacement _placement({required double x, required double y}) =>
    BookPlacement(
      id: 'p1',
      environmentId: 'e1',
      copyId: 'c1',
      x: x,
      y: y,
      rotation: 0,
      createdAt: DateTime(2026),
    );

PhysicalShelf _shelf({
  required String id,
  required double y,
  double x1 = 0,
  double x2 = 2,
  String? label,
}) =>
    PhysicalShelf(
      id: id,
      environmentId: 'e1',
      x1: x1,
      y1: y,
      x2: x2,
      y2: y,
      label: label,
      createdAt: DateTime(2026),
    );

void main() {
  group('nearestShelfLabel', () {
    test('picks the shelf the book stands on', () {
      final label = LayoutRepository.nearestShelfLabel(
        placement: _placement(x: 1, y: 1.0),
        shelves: [
          _shelf(id: 's1', y: 1.0, label: 'Shelf 2'),
          _shelf(id: 's2', y: 2.0, label: 'Shelf 3'),
        ],
      );
      expect(label, 'Shelf 2');
    });

    test('ignores a shelf the book does not overlap horizontally', () {
      final label = LayoutRepository.nearestShelfLabel(
        placement: _placement(x: 5, y: 1.0),
        shelves: [_shelf(id: 's1', y: 1.0, x1: 0, x2: 2, label: 'Shelf 2')],
      );
      expect(label, isNull, reason: 'a book across the room is on no shelf');
    });

    test('ignores shelves above the book', () {
      final label = LayoutRepository.nearestShelfLabel(
        placement: _placement(x: 1, y: 2.0),
        shelves: [_shelf(id: 's1', y: 1.0, label: 'Shelf above')],
      );
      expect(label, isNull);
    });

    test('the nearest shelf below wins', () {
      final label = LayoutRepository.nearestShelfLabel(
        placement: _placement(x: 1, y: 1.0),
        shelves: [
          _shelf(id: 's1', y: 3.0, label: 'Far below'),
          _shelf(id: 's2', y: 1.4, label: 'Just below'),
        ],
      );
      expect(label, 'Just below');
    });

    test('an unlabelled shelf yields no label, not an empty one', () {
      expect(
        LayoutRepository.nearestShelfLabel(
          placement: _placement(x: 1, y: 1.0),
          shelves: [_shelf(id: 's1', y: 1.0, label: '   ')],
        ),
        isNull,
      );
    });

    test('shelves drawn right-to-left still match', () {
      // x1/x2 are wherever the user dragged from and to.
      expect(
        LayoutRepository.nearestShelfLabel(
          placement: _placement(x: 1, y: 1.0),
          shelves: [_shelf(id: 's1', y: 1.0, x1: 2, x2: 0, label: 'Shelf 2')],
        ),
        'Shelf 2',
      );
    });
  });

  group('watchLocationOf', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('vellum_copy_loc'));
    tearDown(() => dir.deleteSync(recursive: true));

    test('an unplaced copy has no derived location', () async {
      final repo = await _repo(dir);
      final db = repo.db;
      await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'Dune'));
      final copyId = await repo.addPhysicalCopy('b1');

      expect(await repo.layout.watchLocationOf(copyId).first, isNull,
          reason: 'the free-text note is all there is for an unplaced copy');
    });

    test('a placed copy reports its room, and follows a move', () async {
      final repo = await _repo(dir);
      final db = repo.db;
      await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'Dune'));
      final study = await repo.layout.createEnvironment('Study');
      await repo.layout.placeBook(study, 'b1', x: 1, y: 1);
      final copyId = (await db.select(db.physicalCopies).get()).single.id;

      final located = await repo.layout
          .watchLocationOf(copyId)
          .firstWhere((l) => l != null);
      expect(located!.environmentName, 'Study');
      expect(located.display, 'Study');

      // Move it to another room: the derived location follows, because nothing
      // was ever written into the copy's own column.
      final attic = await repo.layout.createEnvironment('Attic');
      await db.customStatement(
        'UPDATE book_placements SET environment_id = ? WHERE copy_id = ?',
        [attic, copyId],
      );
      final moved = await repo.layout
          .watchLocationOf(copyId)
          .firstWhere((l) => l?.environmentName == 'Attic');
      expect(moved!.display, 'Attic');
    });

    test('the room and the shelf label combine when both are known', () async {
      final repo = await _repo(dir);
      final db = repo.db;
      await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'Dune'));
      final study = await repo.layout.createEnvironment('Living room');
      await repo.layout
          .addShelf(study, x1: 0, y1: 1.0, x2: 3, y2: 1.0, label: 'Shelf 2');
      await repo.layout.placeBook(study, 'b1', x: 1, y: 1.0);
      final copyId = (await db.select(db.physicalCopies).get()).single.id;

      final located = await repo.layout
          .watchLocationOf(copyId)
          .firstWhere((l) => l != null);
      expect(located!.display, 'Living room · Shelf 2');
    });

    test('the copy row is never rewritten — derived data stays derived',
        () async {
      final repo = await _repo(dir);
      final db = repo.db;
      await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'Dune'));
      final study = await repo.layout.createEnvironment('Study');
      await repo.layout.placeBook(study, 'b1', x: 1, y: 1);
      final copyId = (await db.select(db.physicalCopies).get()).single.id;
      await repo.layout.watchLocationOf(copyId).firstWhere((l) => l != null);

      final copy = await (db.select(db.physicalCopies)
            ..where((c) => c.id.equals(copyId)))
          .getSingle();
      expect(copy.location, isNull,
          reason: 'writing the derived string back would re-create the drift');
    });
  });
}
