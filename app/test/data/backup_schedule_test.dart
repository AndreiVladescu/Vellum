// Scheduled, rotated backups (plan 5 #13). Rotation deletes files, so the tests
// that matter are the ones proving it deletes only its own and only the excess.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/data/backup_schedule.dart';

void main() {
  late Directory dir;

  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_backup_rot'));
  tearDown(() => dir.deleteSync(recursive: true));

  File touch(String name) =>
      File(p.join(dir.path, name))..writeAsStringSync('x');

  List<String> remaining() =>
      [for (final e in dir.listSync()) p.basename(e.path)]..sort();

  test('the name carries a sortable timestamp and the right extension', () {
    final when = DateTime(2026, 7, 26, 14, 30, 5);
    expect(BackupScheduler.nameFor(when), 'vellum-backup-20260726-143005.zip');
    expect(
      BackupScheduler.nameFor(when, encrypted: true),
      'vellum-backup-20260726-143005.vbk',
    );
  });

  test('two runs in the same day do not collide', () {
    // Seconds in the name, precisely so a second run doesn't overwrite the
    // first — which would make "keep 5" mean "keep 5 of one day".
    expect(
      BackupScheduler.nameFor(DateTime(2026, 7, 26, 9)),
      isNot(BackupScheduler.nameFor(DateTime(2026, 7, 26, 21))),
    );
  });

  test('rotation keeps the newest N and deletes the rest', () async {
    for (final day in ['0721', '0722', '0723', '0724', '0725']) {
      touch('vellum-backup-2026$day-120000.zip');
    }
    final deleted = await BackupScheduler.rotate(dir, keep: 2);
    expect(deleted.length, 3);
    expect(remaining(), [
      'vellum-backup-20260724-120000.zip',
      'vellum-backup-20260725-120000.zip',
    ]);
  });

  test('rotation never touches files it did not write', () async {
    // The failure this prevents is not "a lost backup" — it is Vellum deleting
    // somebody's tax return because it shared a folder with the backups.
    touch('holiday-photos.zip');
    touch('notes.txt');
    touch('vellum-backup-20260721-120000.zip');
    touch('vellum-backup-20260722-120000.zip');
    touch('vellum-backup-20260723-120000.zip');

    await BackupScheduler.rotate(dir, keep: 1);
    expect(remaining(), [
      'holiday-photos.zip',
      'notes.txt',
      'vellum-backup-20260723-120000.zip',
    ]);
  });

  test('encrypted and plain archives rotate together', () async {
    touch('vellum-backup-20260721-120000.zip');
    touch('vellum-backup-20260722-120000.vbk');
    touch('vellum-backup-20260723-120000.zip');
    await BackupScheduler.rotate(dir, keep: 2);
    expect(remaining(), [
      'vellum-backup-20260722-120000.vbk',
      'vellum-backup-20260723-120000.zip',
    ]);
  });

  test('fewer archives than the limit deletes nothing', () async {
    touch('vellum-backup-20260721-120000.zip');
    expect(await BackupScheduler.rotate(dir, keep: 5), isEmpty);
    expect(remaining().length, 1);
  });

  test('keep: 0 is treated as "do not rotate", not "delete everything"', () async {
    // A misread setting must fail safe. Deleting every backup because a number
    // was zero is the worst possible interpretation.
    touch('vellum-backup-20260721-120000.zip');
    expect(await BackupScheduler.rotate(dir, keep: 0), isEmpty);
    expect(remaining().length, 1);
  });

  test('a missing folder is not an error', () async {
    final gone = Directory(p.join(dir.path, 'nope'));
    expect(await BackupScheduler.rotate(gone, keep: 3), isEmpty);
  });

  group('isOurs', () {
    test('matches only what the scheduler writes', () {
      expect(BackupScheduler.isOurs('vellum-backup-20260726-120000.zip'), isTrue);
      expect(BackupScheduler.isOurs('vellum-backup-20260726-120000.vbk'), isTrue);
      // A manual export named by the user, and unrelated files.
      expect(BackupScheduler.isOurs('vellum-backup-20260726.zip.part'), isFalse);
      expect(BackupScheduler.isOurs('my-vellum-backup-2026.zip'), isFalse);
      expect(BackupScheduler.isOurs('backup.zip'), isFalse);
    });
  });

  group('frequency', () {
    test('parses stored values and defaults to off', () {
      expect(BackupFrequency.parse('daily'), BackupFrequency.daily);
      expect(BackupFrequency.parse('weekly'), BackupFrequency.weekly);
      expect(BackupFrequency.parse(null), BackupFrequency.off);
      expect(BackupFrequency.parse('nonsense'), BackupFrequency.off);
    });

    test('off has no interval, which is what disables the schedule', () {
      expect(BackupFrequency.off.interval, isNull);
      expect(BackupFrequency.daily.interval, const Duration(days: 1));
      expect(BackupFrequency.weekly.interval, const Duration(days: 7));
    });
  });
}
