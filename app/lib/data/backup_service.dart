import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'library_repository.dart';

/// Exports the whole library — a clean database snapshot plus every cover and
/// book file — into a single `.zip`, and restores such an archive over the
/// current library. The app is local-first, so this is the only backup a
/// standalone (serverless) install has.
class BackupService {
  BackupService(this.repository, {File? databaseFile})
      : _databaseFileOverride = databaseFile;

  final LibraryRepository repository;

  /// Blob types that are already compressed; deflating them again burns CPU for
  /// ~0% gain, so they're stored (not recompressed) in the archive.
  static const _storedExtensions = {
    'pdf', 'epub', 'jpg', 'jpeg', 'png', 'gif', 'webp', 'zip',
  };

  /// Test seam: the live database file to replace on restore. Defaults to
  /// where `driftDatabase(name: 'vellum')` puts it (documents dir).
  final File? _databaseFileOverride;

  Future<File> _databaseFile() async {
    if (_databaseFileOverride != null) return _databaseFileOverride;
    final docs = await getApplicationDocumentsDirectory();
    return File(p.join(docs.path, 'vellum.sqlite'));
  }

  /// Writes a complete backup to [dest]. Safe while the app is running: the
  /// database is snapshotted with `VACUUM INTO`, which produces a clean,
  /// compact copy even with the live connection open.
  Future<void> exportTo(File dest) async {
    final dataDir = repository.dataDir;
    final snapshot = File(p.join(dataDir.path, '.backup-snapshot.sqlite'));
    if (await snapshot.exists()) await snapshot.delete();
    await repository.db.customStatement('VACUUM INTO ?', [snapshot.path]);
    final encoder = ZipFileEncoder();
    try {
      encoder.create(dest.path);
      await encoder.addFile(snapshot, 'vellum.sqlite');
      encoder.addArchiveFile(ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'app': 'vellum',
          'created': DateTime.now().toUtc().toIso8601String(),
        }),
      ));
      // 'photos' since plan 5 #51 — condition photos are app-local, so a
      // backup is the only copy of them that leaves the device.
      for (final sub in ['covers', 'files', 'photos']) {
        final dir = Directory(p.join(dataDir.path, sub));
        if (!await dir.exists()) continue;
        await for (final entry in dir.list()) {
          // Skip transfer leftovers; everything else in these dirs is a blob.
          if (entry is File && !entry.path.endsWith('.part')) {
            final ext = p.extension(entry.path).replaceFirst('.', '').toLowerCase();
            final name = '$sub/${p.basename(entry.path)}';
            if (_storedExtensions.contains(ext)) {
              // Already-compressed: store it (the archive's compression method
              // is set on the entry, not via addFile's deflate-level argument).
              // Streamed from disk so a big file isn't read into memory.
              encoder.addArchiveFile(
                ArchiveFile.stream(name, InputFileStream(entry.path))
                  ..compression = CompressionType.none,
              );
            } else {
              await encoder.addFile(entry, name); // deflate the rest
            }
          }
        }
      }
      await encoder.close();
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
  }

  /// Replaces the current library with the contents of [archive]. Returns
  /// false (changing nothing) when the file isn't a Vellum backup.
  ///
  /// On success the database connection is **closed** and the file swapped on
  /// disk — the app must restart before touching the library again; the
  /// caller owns telling the user and exiting.
  Future<bool> restoreFrom(File archive) async {
    final dataDir = repository.dataDir;
    final staging = Directory(p.join(dataDir.path, '.restore-staging'));
    if (await staging.exists()) await staging.delete(recursive: true);
    try {
      await extractFileToDisk(archive.path, staging.path);

      // It must contain a real SQLite database to be a backup of ours.
      final stagedDb = File(p.join(staging.path, 'vellum.sqlite'));
      if (!await stagedDb.exists()) return false;
      final header = await stagedDb.openRead(0, 15).first;
      if (!utf8.decode(header, allowMalformed: true).startsWith('SQLite format 3')) {
        return false;
      }

      // Past this point we mutate the library: close the live connection so
      // the swap below can't race a write.
      final liveDb = await _databaseFile();
      await repository.db.close();

      // Swap the database atomically: stage a copy next to the live file,
      // then rename over it. Sidecar journals belong to the old file.
      final incoming = File('${liveDb.path}.restored');
      await stagedDb.copy(incoming.path);
      await incoming.rename(liveDb.path);
      for (final suffix in ['-wal', '-shm', '-journal']) {
        final sidecar = File('${liveDb.path}$suffix');
        if (await sidecar.exists()) await sidecar.delete();
      }

      // Replace the blob directories with the archive's (absent in the
      // archive = empty in the restored library).
      for (final sub in ['covers', 'files', 'photos']) {
        final live = Directory(p.join(dataDir.path, sub));
        if (await live.exists()) await live.delete(recursive: true);
        final staged = Directory(p.join(staging.path, sub));
        if (await staged.exists()) {
          await staged.rename(live.path);
        } else {
          await live.create(recursive: true);
        }
      }
      return true;
    } finally {
      if (await staging.exists()) await staging.delete(recursive: true);
    }
  }
}
