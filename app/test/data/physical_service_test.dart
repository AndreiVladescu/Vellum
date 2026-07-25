import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/physical_service.dart';

void main() {
  test('watchAllLoans joins the book and reflects active then returned',
      () async {
    final db = VellumDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final physical = PhysicalService(db);

    await db
        .into(db.books)
        .insert(BooksCompanion.insert(id: 'b1', title: 'Lent'));
    await db
        .into(db.physicalCopies)
        .insert(PhysicalCopiesCompanion.insert(id: 'c1', bookId: 'b1'));

    await physical.lendCopy('c1', 'Alice');
    var loans = await physical.watchAllLoans().first;
    expect(loans, hasLength(1));
    expect(loans.first.book.title, 'Lent');
    expect(loans.first.loan.borrower, 'Alice');
    expect(loans.first.loan.returnedAt, isNull, reason: 'active loan');

    await physical.returnLoan(loans.first.loan.id);
    loans = await physical.watchAllLoans().first;
    expect(loans.first.loan.returnedAt, isNotNull, reason: 'now in history');
  });

  test('addPhysicalCopy returns the new id so it can be lent immediately',
      () async {
    final db = VellumDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final physical = PhysicalService(db);

    await db
        .into(db.books)
        .insert(BooksCompanion.insert(id: 'b1', title: 'Book'));

    // The lend sheet's "no copy yet" path adds a copy and lends it in one go,
    // which needs the new copy's id back from addPhysicalCopy.
    final copyId = await physical.addPhysicalCopy('b1', location: 'Desk');
    expect(copyId, isNotEmpty);

    await physical.lendCopy(copyId, 'Bob');
    final active = (await physical.watchLoansOf(copyId).first)
        .where((l) => l.returnedAt == null)
        .toList();
    expect(active, hasLength(1));
    expect(active.single.borrower, 'Bob');
  });
}
