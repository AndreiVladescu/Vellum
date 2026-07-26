// FileService's import path (plan 5 #14): a file lands atomically or not at all.
// The failure this pins is the pair of half-states the old copy-then-insert
// ordering allowed — a row pointing at a partial file, or a blob no row knows
// about — both of which survive a restart and are invisible until a read fails.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';

Future<LibraryRepository> _repo(Directory dir) async =>
    LibraryRepository.forTesting(VellumDatabase(NativeDatabase.memory()), dir);

void main() {
  late Directory dir;
  late Directory source;
  setUp(() {
    dir = Directory.systemTemp.createTempSync('vellum_file_service');
    source = Directory.systemTemp.createTempSync('vellum_file_source');
  });
  tearDown(() {
    dir.deleteSync(recursive: true);
    source.deleteSync(recursive: true);
  });

  File sourceFile(String name, String contents) =>
      File(p.join(source.path, name))..writeAsStringSync(contents);

  List<String> storedFiles(Directory root) => [
        for (final e in Directory(p.join(root.path, 'files')).listSync())
          p.basename(e.path),
      ]..sort();

  test('attaching a file records it and leaves no temp behind', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    // A cover already present, so attaching a PDF doesn't also try to derive
    // one — that path needs path_provider, and covers aren't what's under test.
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'b1',
          title: 'Dune',
          coverPath: const Value('covers/b1.jpg'),
          needsPush: const Value(false),
        ));
    final src = sourceFile('dune.pdf', 'not really a pdf, but bytes are bytes');

    await repo.files.attachFile('b1', src.path);

    final rows = await db.select(db.bookFiles).get();
    expect(rows, hasLength(1));
    expect(rows.single.format, 'pdf');
    expect(rows.single.sizeBytes, src.lengthSync());
    expect(
      File(p.join(dir.path, rows.single.path)).readAsStringSync(),
      src.readAsStringSync(),
      reason: 'the stored bytes are the source bytes',
    );
    expect(storedFiles(dir).where((f) => f.endsWith('.part')), isEmpty);
    expect((await repo.watchBook('b1').first)?.needsPush, true,
        reason: 'a new file is synced data');
  });

  test('a failed row write leaves no orphan blob', () async {
    // The natural injection: `book_files.book_id` is a foreign key and
    // `PRAGMA foreign_keys` is ON, so attaching to a book that doesn't exist
    // fails *after* the bytes have been copied — exactly the window #14 closes.
    final repo = await _repo(dir);
    final src = sourceFile('orphan.epub', 'bytes');

    await expectLater(
      () => repo.files.attachFile('no-such-book', src.path),
      throwsA(anything),
    );

    expect(await repo.db.select(repo.db.bookFiles).get(), isEmpty);
    expect(
      storedFiles(dir),
      isEmpty,
      reason: 'the copied blob must be unlinked when its row rolls back',
    );
  });

  test('a missing source file writes nothing at all', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'X'));

    await expectLater(
      () => repo.files.attachFile('b1', p.join(source.path, 'ghost.pdf')),
      throwsA(isA<FileSystemException>()),
    );

    expect(await db.select(db.bookFiles).get(), isEmpty);
    expect(storedFiles(dir), isEmpty, reason: 'not even a .part survives');
  });

  test('the recorded hash is the hash of what was actually stored', () async {
    // Hashing the source instead of the destination would let a short write be
    // recorded with a hash the bytes no longer have — and sync dedupes on it.
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'b1',
          title: 'X',
          coverPath: const Value('covers/b1.jpg'),
        ));
    await repo.files.attachFile('b1', sourceFile('a.pdf', 'abc').path);

    final row = (await db.select(db.bookFiles).get()).single;
    // sha256("abc"), the canonical vector.
    expect(
      row.sha256,
      'ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad',
    );
  });

  test('opening the library sweeps an interrupted cover write', () async {
    // The files/ half of this is covered in library_repository_test.dart; this
    // is the covers/ directory the sweeper gained for #14.
    final coversDir = Directory(p.join(dir.path, 'covers'))
      ..createSync(recursive: true);
    final part = File(p.join(coversDir.path, 'b1.jpg.part'))
      ..writeAsStringSync('half an image');
    final good = File(p.join(coversDir.path, 'b1.jpg'))
      ..writeAsStringSync('a whole image');

    await _repo(dir);

    expect(part.existsSync(), false);
    expect(good.existsSync(), true, reason: 'the real cover is untouched');
  });
}
