import 'dart:io';

import 'package:path/path.dart' as p;

import '../settings/app_settings.dart';
import 'backup_service.dart';
import 'library_repository.dart';

/// How often unattended backups run (plan 5 #13).
enum BackupFrequency {
  off('Off', null),
  daily('Daily', Duration(days: 1)),
  weekly('Weekly', Duration(days: 7));

  const BackupFrequency(this.label, this.interval);

  final String label;
  final Duration? interval;

  static BackupFrequency parse(String? raw) => switch (raw) {
        'daily' => BackupFrequency.daily,
        'weekly' => BackupFrequency.weekly,
        _ => BackupFrequency.off,
      };

  String get key => name;
}

/// The outcome of a scheduled run, for logging and for the Preferences line.
enum BackupRunResult { notDue, noFolder, disabled, written, failed }

/// Unattended, rotated backups.
///
/// **On app start, not on a timer.** A desktop app that is open is a desktop
/// app being used, and "back up if the last one is older than the interval"
/// needs no background service, no new platform permission, and no daemon that
/// keeps running after the user quits. The cost is that a machine left off for
/// a month backs up when it next starts — which is exactly when it should.
///
/// **Rotation deletes, so it only ever deletes its own.** Files are matched by
/// the `vellum-backup-*.zip`/`.vbk` name this class writes; a stray document in
/// the same folder is never a candidate, because "keep 5" must not become
/// "delete your other files".
class BackupScheduler {
  BackupScheduler({
    required this.repository,
    required this.settings,
    this.now = DateTime.now,
  });

  final LibraryRepository repository;
  final AppSettingsStore settings;

  /// Test seam.
  final DateTime Function() now;

  static const _prefix = 'vellum-backup-';

  /// Runs a backup if one is due. Never throws: a failed automatic backup must
  /// not stop the app from starting.
  Future<BackupRunResult> runIfDue({String? passphrase}) async {
    final frequency = BackupFrequency.parse(settings.backupFrequency);
    if (frequency.interval == null) return BackupRunResult.disabled;
    final folderPath = settings.backupFolder;
    if (folderPath == null || folderPath.isEmpty) return BackupRunResult.noFolder;

    final last = settings.lastBackupAt;
    if (last != null && now().difference(last) < frequency.interval!) {
      return BackupRunResult.notDue;
    }

    final folder = Directory(folderPath);
    try {
      if (!await folder.exists()) await folder.create(recursive: true);
      final dest = File(p.join(folder.path, nameFor(now(), encrypted: passphrase != null)));
      await BackupService(repository).exportTo(dest, passphrase: passphrase);
      // Only after a successful write: a failure must leave the schedule due,
      // or one bad day silently skips a whole interval.
      await settings.setLastBackupAt(now());
      await rotate(folder, keep: settings.backupKeep);
      return BackupRunResult.written;
    } catch (_) {
      return BackupRunResult.failed;
    }
  }

  /// `vellum-backup-20260726-143000.zip`, seconds included so two runs on one
  /// day can't overwrite each other.
  static String nameFor(DateTime when, {bool encrypted = false}) {
    String two(int v) => v.toString().padLeft(2, '0');
    final stamp = '${when.year}${two(when.month)}${two(when.day)}'
        '-${two(when.hour)}${two(when.minute)}${two(when.second)}';
    return '$_prefix$stamp.${encrypted ? 'vbk' : 'zip'}';
  }

  /// Whether [name] is a file this class wrote — the guard that keeps rotation
  /// from touching anything else in the folder.
  static bool isOurs(String name) =>
      name.startsWith(_prefix) &&
      (name.endsWith('.zip') || name.endsWith('.vbk'));

  /// Deletes our oldest archives beyond [keep], newest first by filename.
  ///
  /// Sorted by *name*, not by mtime: the name carries the timestamp we wrote,
  /// while an mtime is changed by copying the folder to another drive — which
  /// is a thing people do with backups.
  static Future<List<String>> rotate(Directory folder, {required int keep}) async {
    if (keep <= 0 || !await folder.exists()) return const [];
    final ours = <File>[
      await for (final entry in folder.list())
        if (entry is File && isOurs(p.basename(entry.path))) entry,
    ]..sort((a, b) => p.basename(b.path).compareTo(p.basename(a.path)));

    final deleted = <String>[];
    for (final file in ours.skip(keep)) {
      try {
        await file.delete();
        deleted.add(p.basename(file.path));
      } catch (_) {
        // A locked or already-deleted file is not worth failing a backup over.
      }
    }
    return deleted;
  }
}
