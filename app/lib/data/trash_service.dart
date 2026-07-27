import 'package:drift/drift.dart';

import 'book_write_service.dart';
import 'database.dart';

/// The trash: a grace period between "remove this book" and the delete
/// actually happening (plan 5 #52).
///
/// Deleting a book is otherwise immediate *and* tombstoned — right for sync,
/// brutal for a mis-click, and #21b's merge and the console's bulk delete both
/// raise the stakes. So [trash] only marks the row: files stay on disk, no
/// tombstone is written, and nothing is said to the server. The real delete —
/// [BookWriteService.deleteBook], with its tombstone and blob removal — runs
/// either when [sweep] finds a book that has been in the trash longer than
/// [graceperiod], or when the user picks "delete now".
///
/// The grace period is the whole design: until it expires, a trashed book is
/// recoverable with one tap and the server has not been told anything, so no
/// other device has acted on the deletion either.
class TrashService {
  TrashService(this.db, this._writes);

  final VellumDatabase db;
  final BookWriteService _writes;

  /// How long a book sits in the trash before [sweep] deletes it for good.
  static const graceperiod = Duration(days: 30);

  /// Books currently in the trash, most recently trashed first — the order the
  /// trash screen wants, since a mis-click is usually the thing you came to
  /// undo.
  Stream<List<Book>> watchTrashed() => (db.select(db.books)
        ..where((b) => b.deletedAt.isNotNull())
        ..orderBy([(b) => OrderingTerm.desc(b.deletedAt)]))
      .watch();

  /// A live count of what's in the trash, for the Preferences entry's badge.
  Stream<int> watchTrashCount() {
    final q = db.selectOnly(db.books)
      ..addColumns([db.books.id.count()])
      ..where(db.books.deletedAt.isNotNull());
    return q.watch().map((rows) => rows.first.read(db.books.id.count()) ?? 0);
  }

  /// Moves a book to the trash. Nothing is deleted and nothing is pushed: the
  /// row simply stops appearing in the library.
  ///
  /// Deliberately does **not** touch `updatedAt` or `needsPush`. `updatedAt` is
  /// the sync conflict clock and trashing is a local, reversible act — bumping
  /// it would let a book that is on its way out win the next push against a
  /// genuine remote edit. `needsPush` is left exactly as it was so a restore
  /// picks up whatever was owed before, rather than silently dropping an edit
  /// made just before the mis-click.
  Future<void> trash(String bookId) async {
    await (db.update(db.books)..where((b) => b.id.equals(bookId)))
        .write(BooksCompanion(deletedAt: Value(DateTime.now())));
  }

  /// Takes a book back out of the trash, exactly as it was.
  Future<void> restore(String bookId) async {
    await (db.update(db.books)..where((b) => b.id.equals(bookId)))
        .write(const BooksCompanion(deletedAt: Value(null)));
  }

  /// Deletes a trashed book for good, now, without waiting out the grace
  /// period — the real delete, tombstone and blobs included.
  Future<void> deleteNow(Book book) =>
      _writes.deleteBook(book, recordTombstone: true);

  /// Hard-deletes everything that has been in the trash longer than
  /// [graceperiod], and returns how many books went. Called on launch.
  ///
  /// [now] is injectable so a test can age the trash without waiting a month.
  /// Best-effort per book: one book whose file the OS won't let go of must not
  /// leave the rest of the trash un-swept, so a failure is skipped and retried
  /// on the next launch.
  Future<int> sweep({DateTime? now}) async {
    final cutoff = (now ?? DateTime.now()).subtract(graceperiod);
    final expired = await (db.select(db.books)
          ..where((b) => b.deletedAt.isNotNull() & b.deletedAt.isSmallerThanValue(cutoff)))
        .get();
    var deleted = 0;
    for (final book in expired) {
      try {
        await _writes.deleteBook(book, recordTombstone: true);
        deleted++;
      } catch (_) {
        // Leave it in the trash; the next launch tries again.
      }
    }
    return deleted;
  }

  /// When [book] will be deleted for good, or null if it isn't trashed.
  static DateTime? purgeDateOf(Book book) =>
      book.deletedAt?.add(graceperiod);
}
