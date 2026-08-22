import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'sync_clock.dart';

/// Custom shelves — manual panes, distinct from genres and from the
/// physical-layout "shelves". They order books explicitly and never delete
/// the books they hold. Synced since plan 5 #4 (LWW on `updatedAt`, full
/// ordered-membership replace on push — see `SyncService`); split out of
/// `LibraryRepository` (plan 5 §A10).
/// Whether [shelf] was made by somebody else on the server.
///
/// [myUserId] empty means this device doesn't know who it is signed in as — an
/// offline library, or a session saved before the id was recorded. Then every
/// shelf counts as your own, because the alternative is hiding shelves on a
/// guess.
bool shelfMadeByAnother(Shelf shelf, String myUserId) =>
    shelf.ownerId != null &&
    myUserId.isNotEmpty &&
    shelf.ownerId != myUserId;

/// Whether this device shows [shelf].
///
/// Your own shelves always show — including the personal ones, which are
/// personal to *other people*, not to you. Someone else's shelf shows if you
/// said so; if you never said, [acceptByDefault] (the `acceptSharedShelves`
/// preference) answers for it.
bool shelfIsShown(
  Shelf shelf, {
  required String myUserId,
  required bool acceptByDefault,
}) {
  if (!shelfMadeByAnother(shelf, myUserId)) return true;
  return shelf.accepted ?? acceptByDefault;
}

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
  /// so a rename, reorder, or membership change all reach the server. The clock
  /// is bumped past the row's own value rather than set to "now": the server
  /// drops a push it thinks is older than what it holds, and says 200 while
  /// doing it (see [stampSyncClock]).
  Future<void> _touch(String id) => stampSyncClock(db, SyncedRow.shelf, id);

  /// Creates a shelf. [personal] keeps it to its owner: it still syncs (it is
  /// yours on every device you use) but the server withholds it from shares,
  /// so it never appears in anyone else's chip row.
  Future<String> createShelf(String name, {bool personal = false}) async {
    final id = _uuid.v4();
    final existing = await db.select(db.shelves).get();
    await db.into(db.shelves).insert(ShelvesCompanion.insert(
          id: id,
          name: name.trim(),
          sortOrder: Value(existing.length),
          isPersonal: Value(personal),
        ));
    return id;
  }

  /// Moves a shelf between personal and shared. Dirties it, so the server
  /// hears about it on the next push — until then the shelf is still visible
  /// to whoever it was already visible to.
  Future<void> setShelfPersonal(String id, bool personal) async {
    await (db.update(db.shelves)..where((s) => s.id.equals(id)))
        .write(ShelvesCompanion(isPersonal: Value(personal)));
    await _touch(id);
  }

  /// This device's answer about a shelf somebody else made. Local only — see
  /// `Shelves.accepted` — so it deliberately does *not* dirty the shelf.
  /// Passing null puts it back to undecided, which follows the preference.
  Future<void> setShelfAccepted(String id, bool? accepted) =>
      (db.update(db.shelves)..where((s) => s.id.equals(id)))
          .write(ShelvesCompanion(accepted: Value(accepted)));

  /// Bulk form of [setShelfAccepted] for the "accept/decline all" buttons.
  Future<void> setAllAccepted(Iterable<String> ids, bool? accepted) async {
    if (ids.isEmpty) return;
    await (db.update(db.shelves)..where((s) => s.id.isIn(ids.toList())))
        .write(ShelvesCompanion(accepted: Value(accepted)));
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
    await db.transaction(() async {
      await (db.delete(db.shelfBooks)
            ..where((sb) => sb.shelfId.equals(shelfId) & sb.bookId.equals(bookId)))
          .go();
      // Close the gap left behind: addToShelf's next position is
      // `existing.length`, so a stale gap (positions 1, 2 with none at 0)
      // makes the next append collide with an already-occupied position,
      // and ties break on SQLite's arbitrary internal row order.
      await _renumber(shelfId);
    });
    await _touch(shelfId);
  }

  /// Reassigns [shelfId]'s membership to consecutive positions 0..n-1,
  /// preserving current order. Keeps `addToShelf`'s `existing.length`
  /// next-position always distinct from every row already present.
  Future<void> _renumber(String shelfId) async {
    final rows = await (db.select(db.shelfBooks)
          ..where((sb) => sb.shelfId.equals(shelfId))
          ..orderBy([(sb) => OrderingTerm.asc(sb.position)]))
        .get();
    for (var i = 0; i < rows.length; i++) {
      if (rows[i].position != i) {
        await (db.update(db.shelfBooks)
              ..where((sb) =>
                  sb.shelfId.equals(shelfId) & sb.bookId.equals(rows[i].bookId)))
            .write(ShelfBooksCompanion(position: Value(i)));
      }
    }
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
