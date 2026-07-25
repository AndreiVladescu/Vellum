import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';

/// A loan joined with the book it's for, for the cross-library Loans overview.
typedef LoanEntry = ({Loan loan, Book book});

/// Physical copies and loan history. Split out of `LibraryRepository`
/// (plan 5 §A10). Both sync since plan 5 #4 (copies, then loans) — LWW on
/// `updatedAt`, no owner of their own (access derives from the parent book
/// server-side, and for a loan, from its copy's book).
class PhysicalService {
  PhysicalService(this.db);

  final VellumDatabase db;

  static const _uuid = Uuid();

  Stream<List<PhysicalCopy>> watchCopiesOf(String bookId) => (db.select(
    db.physicalCopies,
  )..where((c) => c.bookId.equals(bookId))).watch();

  /// Adds a physical copy and returns its new id (so a caller can, e.g., lend it
  /// straight away). `needsPush` defaults true, so the next push sends it.
  Future<String> addPhysicalCopy(
    String bookId, {
    String? location,
    String? notes,
  }) async {
    final id = _uuid.v4();
    await db
        .into(db.physicalCopies)
        .insert(
          PhysicalCopiesCompanion.insert(
            id: id,
            bookId: bookId,
            location: Value(location),
            notes: Value(notes),
          ),
        );
    return id;
  }

  /// Deletes a physical copy along with its loan history and any layout
  /// placement referencing it. Both `Loans.copyId` and `BookPlacements.copyId`
  /// reference this row with no cascade, so either left behind would make the
  /// final delete throw a foreign-key error — notably on a pull-driven delete,
  /// which must not fail. [recordTombstone] is false for that pull-driven case
  /// (the server already knows), same convention as deleteShelf/deleteBook.
  Future<void> deletePhysicalCopy(String id, {bool recordTombstone = true}) async {
    await db.transaction(() async {
      if (recordTombstone) {
        await db.into(db.localDeletions).insertOnConflictUpdate(
              LocalDeletionsCompanion.insert(
                bookId: id,
                kind: const Value('copy'),
              ),
            );
      }
      await (db.delete(db.bookPlacements)..where((p) => p.copyId.equals(id))).go();
      await (db.delete(db.loans)..where((l) => l.copyId.equals(id))).go();
      await (db.delete(db.physicalCopies)..where((c) => c.id.equals(id))).go();
    });
  }

  /// Loan history for a physical copy, most recent first. The active loan (if
  /// any) is the row whose returnedAt is null.
  Stream<List<Loan>> watchLoansOf(String copyId) =>
      (db.select(db.loans)
            ..where((l) => l.copyId.equals(copyId))
            ..orderBy([(l) => OrderingTerm.desc(l.loanedAt)]))
          .watch();

  /// Every loan across the library joined with the book it's for, most recent
  /// first — for the cross-library Loans overview. The UI splits active
  /// (`returnedAt == null`) from returned history.
  Stream<List<LoanEntry>> watchAllLoans() {
    final query = db.select(db.loans).join([
      innerJoin(
        db.physicalCopies,
        db.physicalCopies.id.equalsExp(db.loans.copyId),
      ),
      innerJoin(db.books, db.books.id.equalsExp(db.physicalCopies.bookId)),
    ])
      ..orderBy([OrderingTerm.desc(db.loans.loanedAt)]);
    return query.watch().map(
          (rows) => [
            for (final r in rows)
              (loan: r.readTable(db.loans), book: r.readTable(db.books)),
          ],
        );
  }

  /// Lends a copy to [borrower]. Callers only offer this when the copy has no
  /// active loan, so no additional check is needed here. `needsPush` defaults
  /// true (an insert), so the next push sends it.
  Future<void> lendCopy(String copyId, String borrower) async {
    await db
        .into(db.loans)
        .insert(
          LoansCompanion.insert(
            id: _uuid.v4(),
            copyId: copyId,
            borrower: borrower,
          ),
        );
  }

  /// Marks a loan returned as of now, keeping it in the history. `needsPush`
  /// and `updatedAt` are bumped explicitly, same reasoning as
  /// `ShelfService._touch`: this is an update, and column defaults don't
  /// re-run on one -- an unbumped return would never reach the server.
  Future<void> returnLoan(String loanId) async {
    await (db.update(db.loans)..where((l) => l.id.equals(loanId))).write(
      LoansCompanion(
        returnedAt: Value(DateTime.now()),
        updatedAt: Value(DateTime.now()),
        needsPush: const Value(true),
      ),
    );
  }
}
