import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_queries.dart';
import 'package:vellum/data/shelf_service.dart';

void main() {
  test('custom shelves: create, fill in order, browse, and delete', () async {
    final db = VellumDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final shelves = ShelfService(db);
    final queries = LibraryQueries(db);

    for (final id in ['b1', 'b2', 'b3']) {
      await db.into(db.books).insert(BooksCompanion.insert(id: id, title: id));
    }
    final shelfId = await shelves.createShelf('Favourites');

    // Fill in a deliberate order; membership is idempotent.
    await shelves.addToShelf('b3', shelfId);
    await shelves.addToShelf('b1', shelfId);
    await shelves.addToShelf('b3', shelfId); // duplicate ignored
    final onShelf = await shelves.watchBooksOnShelf(shelfId).first;
    expect([for (final b in onShelf) b.id], ['b3', 'b1'],
        reason: 'insertion order preserved, no duplicate');

    // Membership stream reflects which shelves a book is on.
    expect(await shelves.watchShelfIdsFor('b3').first, {shelfId});
    expect(await shelves.watchShelfIdsFor('b2').first, isEmpty);

    await shelves.removeFromShelf('b3', shelfId);
    expect(
        [for (final b in await shelves.watchBooksOnShelf(shelfId).first) b.id],
        ['b1']);

    // Deleting a shelf drops membership but never the books.
    await shelves.deleteShelf(shelfId);
    expect(await shelves.watchShelves().first, isEmpty);
    expect(await queries.watchAllBooks().first, hasLength(3),
        reason: 'books survive shelf deletion');
  });

  test('removing from the middle then re-adding does not collide positions',
      () async {
    // Regression: removeFromShelf used to leave a gap in `position` (no
    // renumbering), so addToShelf's next position (existing.length) could
    // collide with a row already occupying that value -- two books tied on
    // `position`, with the tie broken by SQLite's arbitrary row order. Caught
    // by e2e_sync_test.dart's shelf-reorder case flaking 3/5 runs.
    final db = VellumDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final shelves = ShelfService(db);
    for (final id in ['c', 'a', 'b']) {
      await db.into(db.books).insert(BooksCompanion.insert(id: id, title: id));
    }
    final shelfId = await shelves.createShelf('Reading order');
    await shelves.addToShelf('c', shelfId);
    await shelves.addToShelf('a', shelfId);
    await shelves.addToShelf('b', shelfId);

    await shelves.removeFromShelf('c', shelfId);
    await shelves.addToShelf('c', shelfId);

    final positions = await (db.select(db.shelfBooks)
          ..where((sb) => sb.shelfId.equals(shelfId)))
        .get();
    expect(positions.map((sb) => sb.position).toSet(), hasLength(3),
        reason: 'no two rows may share a position');
    expect(
        [for (final b in await shelves.watchBooksOnShelf(shelfId).first) b.id],
        ['a', 'b', 'c']);
  });

  test('rename, reorder, and delete all mark the shelf dirty for push',
      () async {
    // Plan 5 #4: shelves now sync, so every write path that changes what a
    // push would send must bump needsPush/updatedAt -- addToShelf/
    // removeFromShelf touch only shelf_books, which is easy to miss.
    final db = VellumDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final shelves = ShelfService(db);
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'b1'));
    final shelfId = await shelves.createShelf('Mine');

    Future<Shelf> current() =>
        (db.select(db.shelves)..where((s) => s.id.equals(shelfId))).getSingle();
    await (db.update(db.shelves)..where((s) => s.id.equals(shelfId)))
        .write(const ShelvesCompanion(needsPush: Value(false)));
    expect((await current()).needsPush, false);

    await shelves.addToShelf('b1', shelfId);
    expect((await current()).needsPush, true,
        reason: 'membership change dirties the parent shelf');

    await (db.update(db.shelves)..where((s) => s.id.equals(shelfId)))
        .write(const ShelvesCompanion(needsPush: Value(false)));
    await shelves.removeFromShelf('b1', shelfId);
    expect((await current()).needsPush, true);

    await (db.update(db.shelves)..where((s) => s.id.equals(shelfId)))
        .write(const ShelvesCompanion(needsPush: Value(false)));
    await shelves.renameShelf(shelfId, 'Renamed');
    expect((await current()).needsPush, true);
  });

  test('deleting a shelf records a kind=shelf tombstone for the next push',
      () async {
    final db = VellumDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final shelves = ShelfService(db);
    final shelfId = await shelves.createShelf('Temp');

    await shelves.deleteShelf(shelfId);

    final tombstone = await (db.select(db.localDeletions)
          ..where((d) => d.bookId.equals(shelfId)))
        .getSingle();
    expect(tombstone.kind, 'shelf');
  });

  test('a pull-driven delete (recordTombstone: false) leaves no tombstone',
      () async {
    final db = VellumDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final shelves = ShelfService(db);
    final shelfId = await shelves.createShelf('FromServer');

    await shelves.deleteShelf(shelfId, recordTombstone: false);

    expect(await db.select(db.localDeletions).get(), isEmpty);
  });
}
