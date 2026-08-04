// Bulk folder import end to end over a real temp folder (plan 5 #15): what the
// scan finds, what the import writes, and that cancelling stops cleanly instead
// of half-writing a book.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/import/csv_import.dart';
import 'package:vellum/import/folder_import_service.dart';
import 'package:vellum/import/import_plan.dart';

Future<LibraryRepository> _repo(Directory dir) async =>
    LibraryRepository.forTesting(VellumDatabase(NativeDatabase.memory()), dir);

void main() {
  late Directory dataDir;
  late Directory folder;

  setUp(() {
    dataDir = Directory.systemTemp.createTempSync('vellum_import_data');
    folder = Directory.systemTemp.createTempSync('vellum_import_folder');
  });
  tearDown(() {
    dataDir.deleteSync(recursive: true);
    folder.deleteSync(recursive: true);
  });

  File write(String relative, String contents) {
    final file = File(p.join(folder.path, relative));
    file.parent.createSync(recursive: true);
    return file..writeAsStringSync(contents);
  }

  test('the scan finds books recursively and ignores everything else', () async {
    write('Frank Herbert - Dune-Ace (1965).pdf', 'dune bytes');
    write('nested/deep/Ursula K Le Guin - The Dispossessed.epub', 'epub bytes');
    write('notes.txt', 'not a book');
    write('cover.jpg', 'not a book either');
    write('UPPERCASE.PDF', 'case-insensitive extension');

    final service = FolderImportService(await _repo(dataDir));
    final found = await service.findImportableFiles(folder);

    expect(
      [for (final f in found) p.basename(f.path)],
      containsAll([
        'Frank Herbert - Dune-Ace (1965).pdf',
        'Ursula K Le Guin - The Dispossessed.epub',
        'UPPERCASE.PDF',
      ]),
    );
    expect(found, hasLength(3), reason: 'txt and jpg are not books');
  });

  test('the scan classifies against the existing library without writing',
      () async {
    final repo = await _repo(dataDir);
    final db = repo.db;
    // A book already here, with the exact bytes of one of the files below.
    final existing = write('already-have-this.pdf', 'identical bytes');
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'b1',
          title: 'Already Have This',
          coverPath: const Value('covers/b1.jpg'),
        ));
    await repo.attachFile('b1', existing.path);

    write('Frank Herbert - Dune-Ace (1965).pdf', 'dune bytes');
    write('copy of the same.pdf', 'identical bytes');

    final service = FolderImportService(repo);
    final booksBefore = (await db.select(db.books).get()).length;
    final plan = await service.scan(folder);

    expect((await db.select(db.books).get()).length, booksBefore,
        reason: 'a scan is a dry run — it writes nothing');
    final byName = {for (final c in plan) p.basename(c.path): c};
    expect(byName['Frank Herbert - Dune-Ace (1965).pdf']!.status,
        ImportStatus.newBook);
    expect(byName['Frank Herbert - Dune-Ace (1965).pdf']!.meta.title, 'Dune');
    expect(byName['Frank Herbert - Dune-Ace (1965).pdf']!.meta.year, 1965);
    expect(byName['copy of the same.pdf']!.status, ImportStatus.duplicateFile);
    expect(byName['copy of the same.pdf']!.matchedBookId, 'b1');
    // The already-imported file itself is also recognised, not re-imported.
    expect(byName['already-have-this.pdf']!.status, ImportStatus.duplicateFile);
  });

  test('importing creates a book per file with its file-name metadata', () async {
    write('Frank Herbert - Dune-Ace (1965).pdf', 'dune bytes');
    write('Ursula K Le Guin - The Dispossessed-Harper (1974).epub', 'epub');

    final repo = await _repo(dataDir);
    final service = FolderImportService(repo);
    final plan = await service.scan(folder);
    final report = await service.import(plan);

    expect(report.imported, 2);
    expect(report.failures, isEmpty);
    expect(report.cancelled, false);

    final books = await repo.db.select(repo.db.books).get();
    expect(books, hasLength(2));
    final dune = books.firstWhere((b) => b.title == 'Dune');
    expect(dune.publishedYear, 1965);
    expect(dune.publisher, 'Ace');
    expect((await repo.detailsFor(dune.id)).authors, ['Frank Herbert']);

    // Each book's file was copied into the store and recorded.
    final files = await repo.db.select(repo.db.bookFiles).get();
    expect(files, hasLength(2));
    for (final f in files) {
      expect(File(p.join(dataDir.path, f.path)).existsSync(), true);
    }
    expect({for (final f in files) f.format}, {'pdf', 'epub'});
  });

  test('a file with no parseable name still imports under its own name',
      () async {
    write('9780441013593.pdf', 'bytes');
    final repo = await _repo(dataDir);
    final service = FolderImportService(repo);
    await service.import(await service.scan(folder));

    final books = await repo.db.select(repo.db.books).get();
    expect(books.single.title, '9780441013593');
  });

  test('cancelling stops the run and reports what got through', () async {
    for (var i = 0; i < 6; i++) {
      write('Author $i - Book $i.pdf', 'bytes $i');
    }
    final repo = await _repo(dataDir);
    final service = FolderImportService(repo);
    final plan = await service.scan(folder);
    expect(plan, hasLength(6));

    var done = 0;
    final report = await service.import(
      plan,
      onProgress: (d, _, _) => done = d,
      // Cancel once two books are in.
      isCancelled: () async => done >= 2,
    );

    expect(report.cancelled, true);
    expect(report.imported, lessThan(6));
    expect(report.imported, greaterThan(0));
    // Whatever it managed is complete: no book without its file, no file
    // without its book.
    final books = await repo.db.select(repo.db.books).get();
    final files = await repo.db.select(repo.db.bookFiles).get();
    expect(books, hasLength(report.imported));
    expect(files, hasLength(report.imported));
    final stored = Directory(p.join(dataDir.path, 'files')).listSync();
    expect(stored, hasLength(report.imported),
        reason: 'no half-written file left behind');
  });

  test('cancelling a scan stops early and writes nothing', () async {
    for (var i = 0; i < 5; i++) {
      write('Author $i - Book $i.pdf', 'bytes $i');
    }
    final repo = await _repo(dataDir);
    final service = FolderImportService(repo);

    var seen = 0;
    final plan = await service.scan(
      folder,
      onProgress: (d, _, _) => seen = d,
      isCancelled: () async => seen >= 2,
    );

    expect(plan.length, lessThan(5));
    expect(await repo.db.select(repo.db.books).get(), isEmpty);
  });

  test('one bad row does not abort the rest of the import', () async {
    write('Author A - Good One.pdf', 'bytes');
    write('Author B - Doomed.pdf', 'bytes b');
    write('Author C - Good Two.pdf', 'bytes c');

    final repo = await _repo(dataDir);
    final service = FolderImportService(repo);
    final plan = await service.scan(folder);
    // Delete one file after the scan — the classic "the folder changed under
    // us" case, and the cheapest way to make exactly one row fail.
    File(plan.firstWhere((c) => c.path.contains('Doomed')).path).deleteSync();

    final report = await service.import(plan);

    expect(report.imported, 2);
    expect(report.failures, hasLength(1));
    expect(report.failures.single.path, contains('Doomed'));
    expect(
      (await repo.db.select(repo.db.books).get()).map((b) => b.title),
      containsAll(['Good One', 'Good Two']),
    );
  });

  test('an imported book is dirty, so the next sync pushes it', () async {
    write('Author - Fresh Import.pdf', 'bytes');
    final repo = await _repo(dataDir);
    final service = FolderImportService(repo);
    await service.import(await service.scan(folder));

    final book = (await repo.db.select(repo.db.books).get()).single;
    expect(book.needsPush, true);
  });
  test('a reading tracker export brings your ratings and shelves with it',
      () async {
    // The whole point of #17: importing a Goodreads library used to keep the
    // titles and throw away the years of judgement attached to them.
    final repo = await _repo(dataDir);
    final service = FolderImportService(repo);
    const csv = 'Title,Author,Exclusive Shelf,My Rating,Date Read,'
        'My Review,Read Count\n'
        'Dune,Frank Herbert,read,5,2019/03/14,"The best of them.",2\n'
        'The Dispossessed,Ursula K. Le Guin,to-read,0,,,0';

    final plan = await service.scanEntries(CsvImport.read(csv));
    await service.import(plan);

    final books = await repo.db.select(repo.db.books).get();
    final dune = books.firstWhere((b) => b.title == 'Dune');
    expect(dune.status, 'finished');
    expect(dune.rating, 5);
    expect(dune.finishedAt, DateTime(2019, 3, 14));
    expect(dune.readCount, 2);
    // Finished with no progress recorded would contradict itself on the page.
    expect(dune.readingProgress, 1.0);
    // The review goes to the personal channel, not the shared book row.
    expect(dune.readerNotes, 'The best of them.');
    expect(dune.readerNotesNeedsPush, true,
        reason: 'a review travels per-user, never on the book everyone sees');

    final wanted = books.firstWhere((b) => b.title == 'The Dispossessed');
    expect(wanted.status, 'wishlist');
    // 0 stars in an export means unrated, and must not become a 0 rating.
    expect(wanted.rating, isNull);
  });
}
