// External catalogues through the shared import pipeline (plan 5 #21c).
//
// The readers have their own tests; this covers the part that only shows up
// once they meet the pipeline: that a stated title beats a parsed file name,
// that a metadata-only row is a valid import rather than a skipped one, and
// that re-importing the same catalogue reports duplicates instead of doubling
// the library.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/import/catalog_entry.dart';
import 'package:vellum/import/folder_import_service.dart';
import 'package:vellum/import/import_plan.dart';

void main() {
  late Directory dir;
  late LibraryRepository repo;
  late FolderImportService service;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vellum_catalog_import');
    repo = await LibraryRepository.forTesting(
      VellumDatabase(NativeDatabase.memory()),
      dir,
    );
    service = FolderImportService(repo);
  });
  tearDown(() async {
    await repo.db.close();
    dir.deleteSync(recursive: true);
  });

  File sourceFile(String name, List<int> bytes) =>
      File('${dir.path}/$name')..writeAsBytesSync(bytes);

  test('a stated title beats whatever the file is called', () async {
    // The exact reason to read Calibre rather than scan its folder.
    final file = sourceFile('0001_ocr_final_v2.epub', [1, 2, 3]);
    final plan = await service.scanEntries([
      CatalogEntry(
        title: 'Gödel, Escher, Bach',
        authors: const ['Douglas Hofstadter'],
        year: 1979,
        publisher: 'Basic Books',
        isbn: '9780465026562',
        description: 'An eternal golden braid.',
        series: 'Pulitzer Winners',
        seriesIndex: 3,
        genres: const ['Philosophy', 'Mathematics'],
        filePath: file.path,
      ),
    ]);

    expect(plan.single.status, ImportStatus.newBook);
    await service.import(plan);

    final book = (await repo.watchAllBooks().first).single;
    expect(book.title, 'Gödel, Escher, Bach');
    expect(book.publishedYear, 1979);
    expect(book.publisher, 'Basic Books');
    expect(book.isbn, '9780465026562');
    expect(book.description, 'An eternal golden braid.');

    final details = await repo.detailsFor(book.id);
    expect(details.authors, ['Douglas Hofstadter']);
    expect(details.genres, ['Mathematics', 'Philosophy']);
    expect(await repo.seriesService.nameOf(book.id), 'Pulitzer Winners');
    expect(book.seriesIndex, 3);
    expect(await repo.watchFilesOf(book.id).first, hasLength(1));
  });

  test('a metadata-only row imports as a book with no file', () async {
    // What a console CSV export is: books whose bytes live somewhere else.
    final plan = await service.scanEntries([
      const CatalogEntry(title: 'A Physical Book', authors: ['Someone']),
    ]);
    expect(plan.single.status, ImportStatus.newBook,
        reason: 'no file is not the same as unreadable');

    final report = await service.import(plan);
    expect(report.failures, isEmpty);
    final book = (await repo.watchAllBooks().first).single;
    expect(book.title, 'A Physical Book');
    expect(await repo.watchFilesOf(book.id).first, isEmpty);
  });

  test('a catalogue naming a file that is gone reports it on the row',
      () async {
    final plan = await service.scanEntries([
      CatalogEntry(title: 'Moved Away', filePath: '${dir.path}/not-here.epub'),
    ]);
    expect(plan.single.status, ImportStatus.skip);
    expect(plan.single.error, contains('not readable'));
  });

  test('re-importing the same catalogue is caught by hash, not by title',
      () async {
    final file = sourceFile('book.epub', [1, 2, 3]);
    final first = await service.scanEntries(
      [CatalogEntry(title: 'Dune', filePath: file.path)],
    );
    await service.import(first);

    final second = await service.scanEntries(
      // Deliberately a different title: the file is what settles it.
      [CatalogEntry(title: 'Something Else Entirely', filePath: file.path)],
    );
    expect(second.single.status, ImportStatus.duplicateFile);
    expect(second.single.matchedTitle, 'Dune');
    expect(second.single.selectedByDefault, isFalse,
        reason: 'duplicates are shown but not imported by default');
  });

  test('the ISBN a catalogue supplies makes the duplicate check decisive',
      () async {
    // A folder import has no ISBN, so this arm is dormant there and live here.
    final a = sourceFile('a.epub', [1, 1, 1]);
    final b = sourceFile('b.pdf', [2, 2, 2]);
    await service.import(await service.scanEntries(
      [CatalogEntry(title: 'Dune', isbn: '9780441013593', filePath: a.path)],
    ));

    final plan = await service.scanEntries([
      CatalogEntry(
        title: 'Dune (Deluxe Edition)',
        isbn: '978-0-441-01359-3',
        filePath: b.path,
      ),
    ]);
    expect(plan.single.status, ImportStatus.probableDuplicate,
        reason: 'same ISBN is the same book, whatever either file is called');
    expect(plan.single.matchedTitle, 'Dune');
  });

  test('a cover the catalogue points at is attached', () async {
    final cover = sourceFile('cover.jpg', List.filled(64, 9));
    final plan = await service.scanEntries([
      CatalogEntry(title: 'With Art', coverPath: cover.path),
    ]);
    await service.import(plan);

    final book = (await repo.watchAllBooks().first).single;
    expect(book.coverPath, isNotNull);
    expect(repo.coverFileOf(book)!.existsSync(), isTrue);
  });

  test('an unreadable cover loses the cover, never the book', () async {
    final plan = await service.scanEntries([
      CatalogEntry(title: 'No Art', coverPath: '${dir.path}/ghost.jpg'),
    ]);
    final report = await service.import(plan);

    expect(report.failures, isEmpty);
    final book = (await repo.watchAllBooks().first).single;
    expect(book.title, 'No Art');
    expect(book.coverPath, isNull);
  });

  test('folder imports are untouched by any of this', () async {
    // The pipeline gained a branch; the original path must still behave.
    final file = sourceFile('Frank Herbert - Dune (1965).epub', [7, 7, 7]);
    final plan = await service.scanFiles([file]);
    expect(plan.single.entry, isNull);
    await service.import(plan);

    final book = (await repo.watchAllBooks().first).single;
    expect(book.title, 'Dune');
    expect(book.publishedYear, 1965);
    expect((await repo.detailsFor(book.id)).authors, ['Frank Herbert']);
  });
}
