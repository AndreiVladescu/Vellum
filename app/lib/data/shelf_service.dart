import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

/// Custom shelves — manual panes, distinct from genres and from the
/// physical-layout "shelves". They order books explicitly and never delete
/// the books they hold. Synced since plan 5 #4 (LWW on `updatedAt`, full
/// ordered-membership replace on push — see `SyncService`); split out of
/// `LibraryRepository` (plan 5 §A10).
class ShelfService {
  ShelfService(this.db);

  final VellumDatabase db;

  static const _uuid = Uuid();

  Stream<List<Shelf>> watchShelves() => (db.select(db.shelves)
        ..orderBy([
          (s) => OrderingTerm.asc(s.sortOrder),
          (s) => OrderingTerm.asc(s.name),
        ]))
      .watch();

  /// Marks [id] dirty for the next push — every write path below calls this
  /// so a rename, reorder, or membership change all reach the server. Bumps
  /// `updatedAt` explicitly (not just relying on the column default) since
  /// this is called from an `update`, which doesn't re-run column defaults.
  Future<void> _touch(String id) async {
    await (db.update(db.shelves)..where((s) => s.id.equals(id))).write(
      ShelvesCompanion(updatedAt: Value(DateTime.now()), needsPush: const Value(true)),
    );
  }

  Future<String> createShelf(String name) async {
    final id = _uuid.v4();
    final existing = await db.select(db.shelves).get();
    await db.into(db.shelves).insert(ShelvesCompanion.insert(
          id: id,
          name: name.trim(),
          sortOrder: Value(existing.length),
        ));
    return id;
  }

  Future<void> renameShelf(String id, String name) async {
    await (db.update(db.shelves)..where((s) => s.id.equals(id)))
        .write(ShelvesCompanion(name: Value(name.trim())));
    await _touch(id);
  }

  /// Deletes the shelf and its membership rows — never the books themselves.
  /// [recordTombstone] leaves a [LocalDeletions] row (kind='shelf') so the
  /// next push tells the server too; pull-driven deletes (the server already
  /// knows) pass false, same convention as `BookWriteService.deleteBook`.
  Future<void> deleteShelf(String id, {bool recordTombstone = true}) async {
    await db.transaction(() async {
      if (recordTombstone) {
        await db.into(db.localDeletions).insertOnConflictUpdate(
              LocalDeletionsCompanion.insert(
                bookId: id,
                kind: const Value('shelf'),
              ),
            );
      }
      await (db.delete(db.shelfBooks)..where((sb) => sb.shelfId.equals(id))).go();
      await (db.delete(db.shelves)..where((s) => s.id.equals(id))).go();
    });
  }

  /// Appends [bookId] to [shelfId] (no-op if already present).
  Future<void> addToShelf(String bookId, String shelfId) async {
    final existing = await (db.select(db.shelfBooks)
          ..where((sb) => sb.shelfId.equals(shelfId)))
        .get();
    if (existing.any((sb) => sb.bookId == bookId)) return;
    await db.into(db.shelfBooks).insert(ShelfBooksCompanion.insert(
          shelfId: shelfId,
          bookId: bookId,
          position: Value(existing.length),
        ));
    await _touch(shelfId);
  }

  Future<void> removeFromShelf(String bookId, String shelfId) async {
    await (db.delete(db.shelfBooks)
          ..where((sb) => sb.shelfId.equals(shelfId) & sb.bookId.equals(bookId)))
        .go();
    await _touch(shelfId);
  }

  /// The books on [shelfId], in the shelf's explicit order.
  Stream<List<Book>> watchBooksOnShelf(String shelfId) {
    final query = db.select(db.shelfBooks).join([
      innerJoin(db.books, db.books.id.equalsExp(db.shelfBooks.bookId)),
    ])
      ..where(db.shelfBooks.shelfId.equals(shelfId))
      ..orderBy([OrderingTerm.asc(db.shelfBooks.position)]);
    return query.watch().map(
          (rows) => [for (final r in rows) r.readTable(db.books)],
        );
  }

  /// The set of shelf ids [bookId] currently belongs to (for the detail-page
  /// "Add to shelf" checkmarks).
  Stream<Set<String>> watchShelfIdsFor(String bookId) =>
      (db.select(db.shelfBooks)..where((sb) => sb.bookId.equals(bookId)))
          .watch()
          .map((rows) => {for (final sb in rows) sb.shelfId});
}
