// The library health check (plan 5 #11). Each defect is seeded on purpose, then
// three things are asserted: the scan finds it, the scan changed *nothing*, and
// the repair fixes that defect and touches nothing else.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_doctor.dart';
import 'package:vellum/data/library_repository.dart';

Future<LibraryRepository> _repo(Directory dir) async =>
    LibraryRepository.forTesting(VellumDatabase(NativeDatabase.memory()), dir);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_doctor'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> addBook(
    VellumDatabase db,
    String id,
    String title, {
    String? coverPath,
  }) =>
      db.into(db.books).insert(BooksCompanion.insert(
            id: id,
            title: title,
            coverPath: Value(coverPath),
            needsPush: const Value(false),
          ));

  Future<void> addFileRow(
    VellumDatabase db, {
    required String id,
    required String bookId,
    required String relPath,
    String sha256 = 'hash',
  }) =>
      db.into(db.bookFiles).insert(BookFilesCompanion.insert(
            id: id,
            bookId: bookId,
            format: 'pdf',
            path: relPath,
            sizeBytes: 10,
            sha256: sha256,
          ));

  File write(String relPath, String contents) {
    final file = File(p.join(dir.path, relPath));
    file.parent.createSync(recursive: true);
    return file..writeAsStringSync(contents);
  }

  test('a healthy library reports nothing', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    write('files/f1.pdf', 'bytes');
    write('covers/b1.jpg', 'image');
    await addBook(db, 'b1', 'Dune', coverPath: 'covers/b1.jpg');
    await addFileRow(db, id: 'f1', bookId: 'b1', relPath: 'files/f1.pdf');

    final report = await LibraryDoctor(repo).scan();
    expect(report.isHealthy, true);
    expect(report.checkedBlobs, greaterThan(0), reason: 'it did look');
  });

  test('a file row whose bytes are gone is found and can be detached', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await addBook(db, 'b1', 'Dune');
    await addFileRow(db, id: 'f1', bookId: 'b1', relPath: 'files/gone.pdf');

    final doctor = LibraryDoctor(repo);
    final report = await doctor.scan();
    final found = report.of(DefectKind.missingFile);
    expect(found, hasLength(1));
    expect(found.single.description, contains('Dune'));
    // The scan is read-only.
    expect(await db.select(db.bookFiles).get(), hasLength(1));

    expect(await doctor.repair(found.single), true);
    expect(await db.select(db.bookFiles).get(), isEmpty);
    expect((await repo.watchBook('b1').first)!.needsPush, true,
        reason: 'the file list is synced data, so the book needs pushing');
  });

  test('a cover pointing at nothing is found and cleared', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await addBook(db, 'b1', 'Dune', coverPath: 'covers/missing.jpg');

    final doctor = LibraryDoctor(repo);
    final found = (await doctor.scan()).of(DefectKind.missingCover);
    expect(found, hasLength(1));

    await doctor.repair(found.single);
    final book = (await repo.watchBook('b1').first)!;
    expect(book.coverPath, isNull,
        reason: 'cleared, so the shelf draws a generated spine and a new cover '
            'can be set');
    expect(book.coverEtag, isNull);
  });

  test('blobs nobody references are found with their size', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    write('files/kept.pdf', 'bytes');
    final orphan = write('files/orphan.pdf', '0123456789');
    write('covers/orphan.jpg', 'img');
    await addBook(db, 'b1', 'Dune');
    await addFileRow(db, id: 'f1', bookId: 'b1', relPath: 'files/kept.pdf');

    final doctor = LibraryDoctor(repo);
    final report = await doctor.scan();
    final orphans = report.of(DefectKind.orphanBlob);
    expect(orphans.map((d) => d.path).toSet(),
        {'files/orphan.pdf', 'covers/orphan.jpg'});
    expect(report.reclaimableBytes, greaterThan(0));
    // Read-only until repaired.
    expect(orphan.existsSync(), true);

    expect(await doctor.repairAll(orphans), 2);
    expect(orphan.existsSync(), false);
    expect(File(p.join(dir.path, 'files/kept.pdf')).existsSync(), true,
        reason: 'the referenced file must be untouched');
  });

  test('a .part leftover is not treated as an orphan', () async {
    // Those are swept at startup and are none of the doctor's business; flagging
    // them would train the user to ignore the report.
    final repo = await _repo(dir);
    write('files/in-flight.pdf.part', 'half');
    final report = await LibraryDoctor(repo).scan();
    expect(report.of(DefectKind.orphanBlob), isEmpty);
  });

  test('the same content attached twice collapses to one row', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    write('files/f1.pdf', 'bytes');
    write('files/f2.pdf', 'bytes');
    await addBook(db, 'b1', 'Dune');
    await addFileRow(db,
        id: 'f1', bookId: 'b1', relPath: 'files/f1.pdf', sha256: 'same');
    await addFileRow(db,
        id: 'f2', bookId: 'b1', relPath: 'files/f2.pdf', sha256: 'same');

    final doctor = LibraryDoctor(repo);
    final found = (await doctor.scan()).of(DefectKind.duplicateFileRow);
    expect(found, hasLength(1), reason: 'one *extra* row, not two defects');

    await doctor.repair(found.single);
    final rows = await db.select(db.bookFiles).get();
    expect(rows, hasLength(1));
    expect(rows.single.id, 'f1', reason: 'the first row survives');
  });

  test('the same content on two different books is not a duplicate', () async {
    // Two books legitimately sharing a PDF (an omnibus, a duplicate import the
    // user wants) must not be "repaired".
    final repo = await _repo(dir);
    final db = repo.db;
    write('files/f1.pdf', 'bytes');
    write('files/f2.pdf', 'bytes');
    await addBook(db, 'b1', 'One');
    await addBook(db, 'b2', 'Two');
    await addFileRow(db,
        id: 'f1', bookId: 'b1', relPath: 'files/f1.pdf', sha256: 'same');
    await addFileRow(db,
        id: 'f2', bookId: 'b2', relPath: 'files/f2.pdf', sha256: 'same');

    final report = await LibraryDoctor(repo).scan();
    expect(report.of(DefectKind.duplicateFileRow), isEmpty);
  });

  test('a placement whose copy is gone is found and removed', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await addBook(db, 'b1', 'Dune');
    final env = await repo.layout.createEnvironment('Study');
    await repo.layout.placeBook(env, 'b1', x: 1, y: 1);
    // Delete the copy behind it the only way this state can actually arise: with
    // foreign keys off, i.e. a partial restore or a hand-edited database. The FK
    // is what stops it happening in normal operation — which is worth knowing,
    // since it means this defect is always a symptom of something external.
    await db.customStatement('PRAGMA foreign_keys = OFF');
    await db.customStatement('DELETE FROM physical_copies');
    await db.customStatement('PRAGMA foreign_keys = ON');

    final doctor = LibraryDoctor(repo);
    final found = (await doctor.scan()).of(DefectKind.danglingPlacement);
    expect(found, hasLength(1));

    await doctor.repair(found.single);
    expect(await db.select(db.bookPlacements).get(), isEmpty);
  });

  test('old tombstones are prunable only when there is no server', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.localDeletions).insert(LocalDeletionsCompanion.insert(
          bookId: 'long-gone',
          deletedAt: Value(DateTime(2020)),
        ));
    await db.into(db.localDeletions).insert(LocalDeletionsCompanion.insert(
          bookId: 'recent',
          deletedAt: Value(DateTime.now()),
        ));

    final doctor = LibraryDoctor(repo);
    final withoutServer = await doctor.scan();
    expect(
      withoutServer.of(DefectKind.staleTombstone).map((d) => d.rowId),
      ['long-gone'],
      reason: 'a recent tombstone may still need pushing',
    );

    // With a server configured, an old tombstone is one that hasn't synced —
    // pruning it would resurrect a deleted book on the next pull.
    final withServer = await doctor.scan(hasServer: true);
    expect(withServer.of(DefectKind.staleTombstone), isEmpty);

    await doctor.repair(withoutServer.of(DefectKind.staleTombstone).single);
    final left = await db.select(db.localDeletions).get();
    expect(left.map((t) => t.bookId), ['recent']);
  });

  test('a scan can be cancelled and returns what it found so far', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    for (var i = 0; i < 20; i++) {
      await addBook(db, 'b$i', 'Book $i');
      await addFileRow(db,
          id: 'f$i', bookId: 'b$i', relPath: 'files/missing$i.pdf');
    }

    var seen = 0;
    final report = await LibraryDoctor(repo).scan(isCancelled: () async {
      seen++;
      return seen > 5;
    });
    expect(report.defects.length, lessThan(20));
    // Nothing was repaired by a cancelled scan.
    expect(await db.select(db.bookFiles).get(), hasLength(20));
  });

  test('counts and labels are reportable per category', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await addBook(db, 'b1', 'Dune', coverPath: 'covers/missing.jpg');
    await addFileRow(db, id: 'f1', bookId: 'b1', relPath: 'files/gone.pdf');

    final report = await LibraryDoctor(repo).scan();
    expect(report.counts[DefectKind.missingCover], 1);
    expect(report.counts[DefectKind.missingFile], 1);
    expect(DefectKind.orphanBlob.isDestructive, true);
    expect(DefectKind.missingCover.isDestructive, false);
    expect(DefectKind.missingFile.repairLabel, isNotEmpty);
  });
  // ---- advisory findings -------------------------------------------------
  //
  // These three are judgements rather than damage, so the contract is
  // different: they are reported, they never offer a repair, and they must not
  // make a structurally sound library look broken.

  Future<void> addAuthor(
    VellumDatabase db,
    String bookId,
    String authorId,
    String name,
  ) async {
    await db.into(db.authors).insert(
        AuthorsCompanion.insert(id: authorId, name: name),
        mode: InsertMode.insertOrIgnore);
    await db.into(db.bookAuthors).insert(
        BookAuthorsCompanion.insert(bookId: bookId, authorId: authorId));
  }

  test('advice does not make a sound library unhealthy', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    // No author, no year, no cover: three pieces of advice, zero damage.
    await addBook(db, 'b1', 'Dune');

    final report = await LibraryDoctor(repo).scan();
    expect(report.isHealthy, true,
        reason: 'integrity is what "healthy" means; a missing year is not damage');
    expect(report.adviceCounts[DefectKind.noCover], 1);
    expect(report.adviceCounts[DefectKind.incompleteMetadata], 1);
    expect(report.repairableCounts, isEmpty);
  });

  test('two books with the same ISBN are flagged as one book twice', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(
        id: 'b1', title: 'Dune', isbn: const Value('978-0-441-01359-3')));
    await db.into(db.books).insert(BooksCompanion.insert(
        id: 'b2', title: 'Dune (paperback)', isbn: const Value('9780441013593')));

    final report = await LibraryDoctor(repo).scan();
    // Hyphenation must not hide it — the importer normalises ISBNs and so does
    // this, from the same helper.
    expect(report.adviceCounts[DefectKind.duplicateBook], 1);
  });

  test('same title and author, no ISBN, is still a probable duplicate', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await addBook(db, 'b1', 'The Dispossessed');
    await addBook(db, 'b2', 'Dispossessed');
    await addAuthor(db, 'b1', 'a1', 'Ursula K. Le Guin');
    await addAuthor(db, 'b2', 'a1', 'Ursula K. Le Guin');

    final report = await LibraryDoctor(repo).scan();
    // "The" is a stop word in `normalizeForMatch`, so the two titles agree.
    expect(report.adviceCounts[DefectKind.duplicateBook], 1);
  });

  test('same title by different authors is not a duplicate', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await addBook(db, 'b1', 'Selected Poems');
    await addBook(db, 'b2', 'Selected Poems');
    await addAuthor(db, 'b1', 'a1', 'Elizabeth Bishop');
    await addAuthor(db, 'b2', 'a2', 'Robert Frost');

    final report = await LibraryDoctor(repo).scan();
    expect(report.adviceCounts[DefectKind.duplicateBook], isNull,
        reason: 'a shared title is not a shared book');
  });

  test('untitled-ish books with no author are not all one duplicate', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    // Two authorless books with different titles must not collapse together
    // just because neither has anything to match on.
    await addBook(db, 'b1', 'scan001');
    await addBook(db, 'b2', 'scan002');

    final report = await LibraryDoctor(repo).scan();
    expect(report.adviceCounts[DefectKind.duplicateBook], isNull);
  });

  test('trashed and wishlist books are left out of the advice', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(
        id: 'b1', title: 'On the way out',
        deletedAt: Value(DateTime.now())));
    await db.into(db.books).insert(BooksCompanion.insert(
        id: 'b2', title: 'Want to read', status: const Value('wishlist')));

    final report = await LibraryDoctor(repo).scan();
    // A wishlist entry is a book you do not own; a trashed one is leaving.
    // Neither is missing a cover in any sense worth reporting.
    expect(report.adviceCounts, isEmpty);
  });

  test('advisory kinds offer no repair, and repairing one is a no-op', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await addBook(db, 'b1', 'Dune');

    final report = await LibraryDoctor(repo).scan();
    final advice = report.of(DefectKind.noCover).single;
    expect(DefectKind.noCover.isRepairable, false);
    expect(await LibraryDoctor(repo).repair(advice), false);
    // And it changed nothing.
    expect(await db.select(db.books).get(), hasLength(1));
  });
}
