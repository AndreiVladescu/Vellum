import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/data/backup_crypto.dart';
import 'package:vellum/data/backup_schedule.dart';
import 'package:vellum/data/backup_service.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/settings/app_settings.dart';

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

  // ---- manifest + verify (plan 5 #13) ------------------------------------

  group('verify', () {
    test('an untouched backup checks out, and reports what is in it', () async {
      final source = await _repo(dir, 'source.sqlite');
      await source.createCustomBook(title: 'Kept');
      File(p.join(dir.path, 'covers', 'x.jpg')).writeAsBytesSync([1, 2, 3, 4]);
      final zip = File(p.join(dir.path, 'backup.zip'));
      await BackupService(source).exportTo(zip);

      final check = await BackupService(source).verify(zip);
      expect(check.ok, isTrue);
      expect(check.hashesRecorded, isTrue);
      expect(check.hasDatabase, isTrue);
      expect(check.corrupt, isEmpty);
      expect(check.missing, isEmpty);
      // The database and the cover: everything the manifest listed.
      expect(check.checked, 2);
      expect(check.counts['books'], 1);
      expect(check.schemaVersion, source.db.schemaVersion);
      expect(check.created, isNotNull);
      expect(check.describe(), contains('intact'));
      await source.db.close();
    });

    test('a tampered blob is caught without restoring anything', () async {
      // The whole point of verify: learn the backup is bad *before* you need
      // it, and learn it without touching the live library.
      final source = await _repo(dir, 'source.sqlite');
      await source.createCustomBook(title: 'Kept');
      File(p.join(dir.path, 'covers', 'x.jpg')).writeAsBytesSync([1, 2, 3, 4]);
      final zip = File(p.join(dir.path, 'backup.zip'));
      await BackupService(source).exportTo(zip);

      // Rebuild the archive with one blob's bytes changed.
      final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
      final rebuilt = Archive();
      for (final entry in archive.files) {
        rebuilt.add(entry.name == 'covers/x.jpg'
            ? ArchiveFile.bytes('covers/x.jpg', [9, 9, 9, 9])
            : entry);
      }
      zip.writeAsBytesSync(ZipEncoder().encodeBytes(rebuilt));

      final check = await BackupService(source).verify(zip);
      expect(check.ok, isFalse);
      expect(check.corrupt, ['covers/x.jpg']);
      expect(check.describe(), contains('not intact'));
      await source.db.close();
    });

    test('a missing blob is caught too', () async {
      final source = await _repo(dir, 'source.sqlite');
      File(p.join(dir.path, 'covers', 'x.jpg')).writeAsBytesSync([1, 2, 3, 4]);
      final zip = File(p.join(dir.path, 'backup.zip'));
      await BackupService(source).exportTo(zip);

      final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
      final rebuilt = Archive();
      for (final entry in archive.files) {
        if (entry.name != 'covers/x.jpg') rebuilt.add(entry);
      }
      zip.writeAsBytesSync(ZipEncoder().encodeBytes(rebuilt));

      final check = await BackupService(source).verify(zip);
      expect(check.ok, isFalse);
      expect(check.missing, ['covers/x.jpg']);
      await source.db.close();
    });

    test('a file that is not a Vellum backup is rejected, not crashed on',
        () async {
      final source = await _repo(dir, 'source.sqlite');
      final junk = File(p.join(dir.path, 'junk.zip'))
        ..writeAsStringSync('this is not a zip at all');
      final check = await BackupService(source).verify(junk);
      expect(check.ok, isFalse);
      expect(check.readable, isFalse);
      expect(check.describe(), isNotEmpty);
      await source.db.close();
    });

    test('an archive with no checksums says so rather than claiming to be fine',
        () async {
      // Backups written before #13 are still restorable; reporting them as
      // verified would be a lie about the one thing verify exists to answer.
      final source = await _repo(dir, 'source.sqlite');
      final zip = File(p.join(dir.path, 'old.zip'));
      await BackupService(source).exportTo(zip);
      final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
      final rebuilt = Archive();
      for (final entry in archive.files) {
        rebuilt.add(entry.name == 'manifest.json'
            ? ArchiveFile.string('manifest.json',
                '{"app":"vellum","created":"2026-01-01T00:00:00Z"}')
            : entry);
      }
      zip.writeAsBytesSync(ZipEncoder().encodeBytes(rebuilt));

      final check = await BackupService(source).verify(zip);
      expect(check.readable, isTrue);
      expect(check.hasDatabase, isTrue);
      expect(check.hashesRecorded, isFalse);
      expect(check.ok, isTrue, reason: 'nothing is known to be wrong');
      expect(check.describe(), contains('could not be verified'));
      await source.db.close();
    });
  });

  // ---- encryption (plan 5 #13) -------------------------------------------

  group('encrypted archives', () {
    test('round-trip: export, verify and restore with a passphrase', () async {
      final source = await _repo(dir, 'source.sqlite');
      final id = await source.createCustomBook(title: 'Secret', author: 'Anon');
      final sealed = File(p.join(dir.path, 'backup.vbk'));
      await BackupService(source).exportTo(sealed, passphrase: 'open sesame');
      await source.db.close();

      expect(await BackupCrypto.isEncrypted(sealed), isTrue);

      final destDir = Directory(p.join(dir.path, 'dest'))..createSync();
      final destDbFile = File(p.join(destDir.path, 'vellum.sqlite'));
      final dest = await _repo(destDir, 'vellum.sqlite');
      final service = BackupService(dest, databaseFile: destDbFile);

      final check = await service.verify(sealed, passphrase: 'open sesame');
      expect(check.ok, isTrue);

      expect(
        await service.restoreFrom(sealed, passphrase: 'open sesame'),
        isTrue,
      );
      final reopened = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase(destDbFile)),
        destDir,
      );
      expect((await reopened.detailsFor(id)).authors, ['Anon']);
      await reopened.db.close();
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('a wrong passphrase leaves the library untouched', () async {
      // The failure mode that would be unforgivable: a half-applied restore.
      // Decryption happens before anything is replaced, so a bad passphrase
      // costs nothing.
      final source = await _repo(dir, 'source.sqlite');
      await source.createCustomBook(title: 'Secret');
      final sealed = File(p.join(dir.path, 'backup.vbk'));
      await BackupService(source).exportTo(sealed, passphrase: 'right');
      await source.db.close();

      final destDir = Directory(p.join(dir.path, 'dest'))..createSync();
      final destDbFile = File(p.join(destDir.path, 'vellum.sqlite'));
      final dest = await _repo(destDir, 'vellum.sqlite');
      await dest.createCustomBook(title: 'Still here');
      final service = BackupService(dest, databaseFile: destDbFile);

      await expectLater(
        service.restoreFrom(sealed, passphrase: 'wrong'),
        throwsA(isA<BackupDecryptException>()),
      );
      expect(
        [for (final b in await dest.watchAllBooks().first) b.title],
        ['Still here'],
      );

      // And verify reports it as a problem rather than throwing at the UI.
      final check = await service.verify(sealed, passphrase: 'wrong');
      expect(check.ok, isFalse);
      expect(check.describe(), contains('passphrase'));

      // No passphrase at all is a distinct, actionable message.
      final noPass = await service.verify(sealed);
      expect(noPass.describe(), contains('encrypted'));
      await dest.db.close();
    }, timeout: const Timeout(Duration(minutes: 2)));
  });

  // ---- the schedule end to end -------------------------------------------

  group('scheduled runs', () {
    setUp(() => SharedPreferences.setMockInitialValues({}));

    test('writes when due, skips when not, and rotates', () async {
      final repo = await _repo(dir, 'source.sqlite');
      await repo.createCustomBook(title: 'Kept');
      final settings = await AppSettingsStore.load();
      final folder = Directory(p.join(dir.path, 'backups'))..createSync();
      await settings.setBackupFrequency('daily');
      await settings.setBackupFolder(folder.path);
      await settings.setBackupKeep(2);

      var clock = DateTime(2026, 7, 26, 9);
      final scheduler = BackupScheduler(
        repository: repo,
        settings: settings,
        now: () => clock,
      );

      expect(await scheduler.runIfDue(), BackupRunResult.written);
      expect(settings.lastBackupAt, clock);

      // An hour later it is not due; a day later it is.
      clock = clock.add(const Duration(hours: 1));
      expect(await scheduler.runIfDue(), BackupRunResult.notDue);
      clock = clock.add(const Duration(days: 1));
      expect(await scheduler.runIfDue(), BackupRunResult.written);
      clock = clock.add(const Duration(days: 1));
      expect(await scheduler.runIfDue(), BackupRunResult.written);

      // Three written, two kept.
      expect(folder.listSync().length, 2);
      await repo.db.close();
    }, timeout: const Timeout(Duration(minutes: 2)));

    test('does nothing without a folder or when switched off', () async {
      final repo = await _repo(dir, 'source.sqlite');
      final settings = await AppSettingsStore.load();
      final scheduler = BackupScheduler(repository: repo, settings: settings);

      expect(await scheduler.runIfDue(), BackupRunResult.disabled);
      await settings.setBackupFrequency('weekly');
      expect(await scheduler.runIfDue(), BackupRunResult.noFolder);
      await repo.db.close();
    });

    test('a failed run leaves the backup due rather than skipping the interval',
        () async {
      final repo = await _repo(dir, 'source.sqlite');
      final settings = await AppSettingsStore.load();
      await settings.setBackupFrequency('daily');
      // A path that cannot be created: a directory under a regular file.
      final blocker = File(p.join(dir.path, 'blocker'))..writeAsStringSync('x');
      await settings.setBackupFolder(p.join(blocker.path, 'nested'));

      final scheduler = BackupScheduler(repository: repo, settings: settings);
      expect(await scheduler.runIfDue(), BackupRunResult.failed);
      expect(settings.lastBackupAt, isNull);
      await repo.db.close();
    });
  });

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

  test('condition photos ride the backup off the device', () async {
    // Photos never sync (plan 5 #51), so a backup is the only copy of them that
    // ever leaves this machine — if the archive skipped `photos/`, the one
    // record of what a book looked like when it was lent would be un-restorable.
    final source = await _repo(dir, 'source.sqlite');
    final bookId = await source.createCustomBook(title: 'Lent out');
    final copyId = await source.addPhysicalCopy(bookId);
    final picked = File(p.join(dir.path, 'shot.jpg'))
      ..writeAsBytesSync([9, 8, 7]);
    await source.copyPhotos.addPhoto(copyId, picked.path, caption: 'torn');

    final zip = File(p.join(dir.path, 'backup.zip'));
    await BackupService(source).exportTo(zip);
    await source.db.close();

    final destDir = Directory(p.join(dir.path, 'dest'))..createSync();
    final destDbFile = File(p.join(destDir.path, 'vellum.sqlite'));
    final dest = await _repo(destDir, 'vellum.sqlite');
    expect(await BackupService(dest, databaseFile: destDbFile).restoreFrom(zip),
        isTrue);

    final reopened = await LibraryRepository.forTesting(
      VellumDatabase(NativeDatabase(destDbFile)),
      destDir,
    );
    final restored = await reopened.copyPhotos.photosOf(copyId);
    expect(restored.single.caption, 'torn');
    expect(reopened.copyPhotos.fileOf(restored.single).readAsBytesSync(),
        [9, 8, 7]);
    await reopened.db.close();
  });

  test('already-compressed blobs are stored, not recompressed, and exact',
      () async {
    final repo = await _repo(dir, 'lib.sqlite');
    final filesDir = Directory(p.join(dir.path, 'files'))
      ..createSync(recursive: true);
    final pdfBytes = <int>[
      0x25, 0x50, 0x44, 0x46, // %PDF
      for (var i = 0; i < 2000; i++) (i * 37) % 256,
    ];
    File(p.join(filesDir.path, 'book.pdf')).writeAsBytesSync(pdfBytes);

    final zip = File(p.join(dir.path, 'backup.zip'));
    await BackupService(repo).exportTo(zip);
    await repo.db.close();

    final archive = ZipDecoder().decodeBytes(zip.readAsBytesSync());
    final pdf = archive.files.firstWhere((f) => f.name == 'files/book.pdf');
    expect(pdf.content, pdfBytes, reason: 'byte-identical round-trip');
    expect(pdf.compression, CompressionType.none,
        reason: 'a .pdf is stored, not deflated');
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
