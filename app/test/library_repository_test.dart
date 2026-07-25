// Integration-level tests that genuinely cross service boundaries (a book
// delete tripping the layout's placement/copy FKs; the facade's own
// construction-time sweep). Single-service behaviour lives in
// test/data/*_service_test.dart, next to plan 5 §A10's split.
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
}
