import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';

Future<LibraryRepository> _repo(Directory dir) async =>
    LibraryRepository.forTesting(VellumDatabase(NativeDatabase.memory()), dir);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_repo_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('deleting a placed book removes its copies and placements', () async {
    final repo = await _repo(dir);
    final db = repo.db;

    await db
        .into(db.books)
        .insert(BooksCompanion.insert(id: 'b1', title: 'Placed'));
    final envId = await repo.layout.createEnvironment('Study');
    // placeBook mints a physical_copy and a placement referencing it.
    await repo.layout.placeBook(envId, 'b1', x: 0, y: 0);

    expect(await db.select(db.physicalCopies).get(), isNotEmpty);
    expect(await db.select(db.bookPlacements).get(), isNotEmpty);

    // Deleting the placed book must not trip the placement->copy foreign key.
    final book = await repo.watchBook('b1').first as Book;
    await repo.deleteBook(book);

    expect(await repo.watchBook('b1').first, isNull);
    expect(await db.select(db.physicalCopies).get(), isEmpty);
    expect(await db.select(db.bookPlacements).get(), isEmpty);
  });

  test('custom shelves: create, fill in order, browse, and delete', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    for (final id in ['b1', 'b2', 'b3']) {
      await db.into(db.books).insert(BooksCompanion.insert(id: id, title: id));
    }
    final shelfId = await repo.createShelf('Favourites');

    // Fill in a deliberate order; membership is idempotent.
    await repo.addToShelf('b3', shelfId);
    await repo.addToShelf('b1', shelfId);
    await repo.addToShelf('b3', shelfId); // duplicate ignored
    final onShelf = await repo.watchBooksOnShelf(shelfId).first;
    expect([for (final b in onShelf) b.id], ['b3', 'b1'],
        reason: 'insertion order preserved, no duplicate');

    // Membership stream reflects which shelves a book is on.
    expect(await repo.watchShelfIdsFor('b3').first, {shelfId});
    expect(await repo.watchShelfIdsFor('b2').first, isEmpty);

    await repo.removeFromShelf('b3', shelfId);
    expect([for (final b in await repo.watchBooksOnShelf(shelfId).first) b.id],
        ['b1']);

    // Deleting a shelf drops membership but never the books.
    await repo.deleteShelf(shelfId);
    expect(await repo.watchShelves().first, isEmpty);
    expect(await repo.watchAllBooks().first, hasLength(3),
        reason: 'books survive shelf deletion');
  });

  test('saveEpubPosition stores and round-trips the global reading fraction',
      () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'e1', title: 'E'));

    // Chapter 2 of 4 (index 1), halfway scrolled → (1 + 0.5) / 4 = 0.375.
    await repo.saveEpubPosition('e1',
        chapterIndex: 1, chapterCount: 4, scrollFraction: 0.5);
    final book = await repo.watchBook('e1').first;
    expect(book!.lastReadPage, 2, reason: '1-based chapter, like PDF pages');
    expect(book.readingProgress, closeTo(0.375, 1e-9));

    // The reader recovers the in-chapter fraction as progress*count - chapter.
    final within = (book.readingProgress! * 4) - 1;
    expect(within, closeTo(0.5, 1e-9));
  });

  test('watchAllLoans joins the book and reflects active then returned', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'Lent'));
    await db
        .into(db.physicalCopies)
        .insert(PhysicalCopiesCompanion.insert(id: 'c1', bookId: 'b1'));

    await repo.lendCopy('c1', 'Alice');
    var loans = await repo.watchAllLoans().first;
    expect(loans, hasLength(1));
    expect(loans.first.book.title, 'Lent');
    expect(loans.first.loan.borrower, 'Alice');
    expect(loans.first.loan.returnedAt, isNull, reason: 'active loan');

    await repo.returnLoan(loans.first.loan.id);
    loans = await repo.watchAllLoans().first;
    expect(loans.first.loan.returnedAt, isNotNull, reason: 'now in history');
  });

  test('addPhysicalCopy returns the new id so it can be lent immediately', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'Book'));

    // The lend sheet's "no copy yet" path adds a copy and lends it in one go,
    // which needs the new copy's id back from addPhysicalCopy.
    final copyId = await repo.addPhysicalCopy('b1', location: 'Desk');
    expect(copyId, isNotEmpty);

    await repo.lendCopy(copyId, 'Bob');
    final active = (await repo.watchLoansOf(copyId).first)
        .where((l) => l.returnedAt == null)
        .toList();
    expect(active, hasLength(1));
    expect(active.single.borrower, 'Bob');
  });

  test('re-tagging and deleting sweep orphaned author rows', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'A'));
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b2', title: 'B'));

    await repo.setAuthors('b1', ['Shared', 'Only One']);
    await repo.setAuthors('b2', ['Shared']);
    expect((await db.select(db.authors).get()).length, 2);

    // Re-tag b1 to drop "Only One" — it's now referenced by nothing.
    await repo.setAuthors('b1', ['Shared']);
    final names = [for (final a in await db.select(db.authors).get()) a.name];
    expect(names, ['Shared'], reason: 'orphaned author swept');

    // Deleting the last book referencing "Shared" removes it too.
    await repo.deleteBook(await repo.watchBook('b1').first as Book);
    await repo.deleteBook(await repo.watchBook('b2').first as Book);
    expect(await db.select(db.authors).get(), isEmpty);
  });

  test('opening the library sweeps leftover .part downloads', () async {
    final filesDir = Directory(p.join(dir.path, 'files'))
      ..createSync(recursive: true);
    final part = File(p.join(filesDir.path, 'abc.pdf.part'))
      ..writeAsStringSync('partial');
    final complete = File(p.join(filesDir.path, 'abc.pdf'))
      ..writeAsStringSync('done');

    await _repo(dir); // opening the repository runs the sweep

    expect(part.existsSync(), false, reason: 'interrupted .part removed');
    expect(complete.existsSync(), true, reason: 'complete file kept');
  });

  test('canonicalGenreName trims, collapses spaces, and Title Cases', () {
    expect(canonicalGenreName('computer security'), 'Computer Security');
    expect(canonicalGenreName('Computer Security'), 'Computer Security');
    expect(canonicalGenreName('  COMPUTER   SECURITY  '), 'Computer Security');
    expect(canonicalGenreName(''), '');
    expect(canonicalGenreName('   '), '');
  });

  test('addGenre/removeGenre tag a book, canonicalize, and dedup', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'X'));

    Future<List<String>> genres() => repo.watchGenresOf('b1').first;

    await repo.addGenre('b1', 'engineering');
    await repo.addGenre('b1', 'Engineering'); // same canonical -> no-op
    await repo.addGenre('b1', '  '); // blank -> ignored
    expect(await genres(), ['Engineering'], reason: 'canonicalized, deduped');

    await repo.addGenre('b1', 'fiction');
    expect(await genres(), ['Engineering', 'Fiction'],
        reason: 'ordered by name');
    expect(await repo.watchAllGenreNames().first, ['Engineering', 'Fiction']);

    await repo.removeGenre('b1', 'ENGINEERING'); // case-insensitive removal
    expect(await genres(), ['Fiction']);
    // Removing the last book with "Engineering" swept the orphaned genre.
    expect(await repo.watchAllGenreNames().first, ['Fiction']);
  });

  test('setGenres canonicalizes and dedups case/spacing variants', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'X'));

    // Variants that all canonicalize to the same genre must yield one row.
    await repo.setGenres('b1', ['computer security', 'Computer Security', '  ']);

    final genres = [for (final g in await db.select(db.genres).get()) g.name];
    expect(genres, ['Computer Security'],
        reason: 'one canonical genre, empties dropped');
    expect((await db.select(db.bookGenres).get()).length, 1,
        reason: 'book tagged with it exactly once');
  });
}
