import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/import/filename_metadata.dart';
import 'package:vellum/import/folder_import_service.dart';
import 'package:vellum/import/import_plan.dart';
import 'package:vellum/settings/shelf_sort.dart';

/// A book added while a shelf is open joins that shelf (issue #10 item 3).
///
/// Reported as tedium rather than as a bug: you walk to a shelf, press Add
/// book, and the book lands in All — so you then open the book, find "Add to
/// shelf", and pick the shelf you were already standing on.
///
/// The shelf is threaded in from the caller rather than read from settings
/// inside each page, so the paths that have no business guessing — a file
/// shared from another app, the first-run import — simply pass nothing.
void main() {
  late Directory dir;
  late LibraryRepository repo;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vellum_open_shelf');
    repo = await LibraryRepository.forTesting(
      VellumDatabase(NativeDatabase.memory()),
      dir,
    );
  });
  tearDown(() async {
    await repo.db.close();
    dir.deleteSync(recursive: true);
  });

  Future<Set<String>> shelfMembers(String shelfId) async {
    final view = await repo.queries
        .watchLibrary(shelfId: shelfId, query: '', sort: ShelfSort.title)
        .first;
    return {for (final entry in view.entries) entry.book.title};
  }

  ImportCandidate candidate(String title) {
    final file = File('${dir.path}/$title.pdf')..writeAsStringSync('x');
    return ImportCandidate(
      path: file.path,
      sizeBytes: 1,
      format: 'pdf',
      meta: FilenameMeta(title: title),
      status: ImportStatus.newBook,
      sha256: title,
    );
  }

  test('an imported book joins the shelf that was open', () async {
    final shelf = await repo.createShelf('Technical');

    final report = await FolderImportService(repo).import(
      [candidate('A Book')],
      shelfId: shelf,
    );

    expect(report.outcomes.single.error, isNull);
    expect(await shelfMembers(shelf), {'A Book'});
  });

  test('and with no shelf open it just joins the library', () async {
    final shelf = await repo.createShelf('Technical');

    await FolderImportService(repo).import([candidate('Loose')]);

    expect(await shelfMembers(shelf), isEmpty);
    final all = await repo.watchAllBooks().first;
    expect(all.map((b) => b.title), contains('Loose'));
  });

  test('every book in a bulk import lands there, not just the first', () async {
    // The case that made the review step worth a warning line: an import is
    // many books at once, and half of them landing would be worse than none.
    final shelf = await repo.createShelf('Technical');
    final candidates = [
      for (final title in ['One', 'Two', 'Three']) candidate(title),
    ];

    await FolderImportService(repo).import(candidates, shelfId: shelf);

    expect(await shelfMembers(shelf), {'One', 'Two', 'Three'});
  });
}
