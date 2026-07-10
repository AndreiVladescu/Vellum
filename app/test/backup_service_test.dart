import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/data/backup_service.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';

/// A repository over a real on-disk database (backup needs `VACUUM INTO` and
/// a file to swap, so `NativeDatabase.memory()` won't do here).
Future<LibraryRepository> _repo(Directory dir, String dbName) async =>
    LibraryRepository.forTesting(
      VellumDatabase(NativeDatabase(File(p.join(dir.path, dbName)))),
      dir,
    );

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_backup_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('export/restore round-trips books and blobs', () async {
    // Source library: one custom book plus a fake cover blob.
    final source = await _repo(dir, 'source.sqlite');
    final id = await source.createCustomBook(title: 'Kept', author: 'Someone');
    final cover = File(p.join(dir.path, 'covers', 'x.jpg'));
    await cover.writeAsBytes([1, 2, 3, 4]);

    final zip = File(p.join(dir.path, 'backup.zip'));
    await BackupService(source).exportTo(zip);
    await source.db.close();
    expect(await zip.exists(), isTrue);

    // Destination: a fresh, separate library that gets replaced.
    final destDir = Directory(p.join(dir.path, 'dest'))..createSync();
    final destDbFile = File(p.join(destDir.path, 'vellum.sqlite'));
    final dest = await _repo(destDir, 'vellum.sqlite');
    await dest.createCustomBook(title: 'Doomed');

    final ok = await BackupService(dest, databaseFile: destDbFile)
        .restoreFrom(zip);
    expect(ok, isTrue);

    // The restored database holds the source's book, not the destination's.
    final reopened = await LibraryRepository.forTesting(
      VellumDatabase(NativeDatabase(destDbFile)),
      destDir,
    );
    final books = await reopened.watchAllBooks().first;
    expect([for (final b in books) b.title], ['Kept']);
    expect((await reopened.detailsFor(id)).authors, ['Someone']);
    expect(
      File(p.join(destDir.path, 'covers', 'x.jpg')).readAsBytesSync(),
      [1, 2, 3, 4],
    );
    await reopened.db.close();
  });

  test('restore rejects a zip that is not a Vellum backup', () async {
    final repo = await _repo(dir, 'lib.sqlite');
    await repo.createCustomBook(title: 'Safe');

    // A zip with no vellum.sqlite inside: back up an empty dir structure by
    // exporting, then tampering — simplest is a plain file renamed .zip.
    final bogus = File(p.join(dir.path, 'bogus.zip'));
    await bogus.writeAsString('not a zip at all');

    var ok = false;
    try {
      ok = await BackupService(repo, databaseFile: File(p.join(dir.path, 'lib.sqlite')))
          .restoreFrom(bogus);
    } catch (_) {
      // An unreadable archive may throw instead — either way nothing changed.
    }
    expect(ok, isFalse);
    final books = await repo.watchAllBooks().first;
    expect(books.single.title, 'Safe', reason: 'library must be untouched');
    await repo.db.close();
  });
}
