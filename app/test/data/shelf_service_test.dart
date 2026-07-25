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
}
