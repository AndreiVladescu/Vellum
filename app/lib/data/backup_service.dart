import 'dart:convert';
import 'dart:io';

import 'package:archive/archive_io.dart';
import 'package:crypto/crypto.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import 'backup_crypto.dart';
import 'library_repository.dart';

/// What [BackupService.verify] found in an archive (plan 5 #13).
///
/// A backup you have never opened is a backup you don't know you have. This is
/// the answer to "is it good?" *without* restoring — because the alternative,
/// finding out during a restore, is finding out at the worst possible moment.
class BackupCheck {
  const BackupCheck({
    required this.readable,
    required this.hasDatabase,
    this.hashesRecorded = false,
    this.checked = 0,
    this.missing = const [],
    this.corrupt = const [],
    this.unlisted = const [],
    this.created,
    this.schemaVersion,
    this.counts = const {},
    this.problem,
  });

  /// The archive could be opened at all (right format, right passphrase).
  final bool readable;

  /// It contains a real SQLite database — without one there is nothing to
  /// restore, whatever else is in the file.
  final bool hasDatabase;

  /// Whether the manifest carried per-blob hashes. False for archives written
  /// before #13, which can still be restored — they simply can't be *checked*,
  /// and saying "0 problems" about them would be a lie.
  final bool hashesRecorded;

  /// How many entries were hashed and matched.
  final int checked;

  /// Listed in the manifest but absent from the archive.
  final List<String> missing;

  /// Present, but the bytes no longer hash to what was recorded.
  final List<String> corrupt;

  /// In the archive but not in the manifest — not a failure (a future version
  /// may add entries), reported so nothing is silently ignored.
  final List<String> unlisted;

  final DateTime? created;
  final int? schemaVersion;
  final Map<String, int> counts;

  /// Why the archive couldn't be read, when [readable] is false.
  final String? problem;

  bool get ok =>
      readable && hasDatabase && missing.isEmpty && corrupt.isEmpty;

  /// A sentence for the UI.
  String describe() {
    if (!readable) return problem ?? "That file isn't a Vellum backup.";
    if (!hasDatabase) return 'No library database in this archive.';
    if (corrupt.isNotEmpty || missing.isNotEmpty) {
      final parts = [
        if (corrupt.isNotEmpty) '${corrupt.length} damaged',
        if (missing.isNotEmpty) '${missing.length} missing',
      ];
      return 'Backup is not intact: ${parts.join(', ')}.';
    }
    if (!hashesRecorded) {
      return 'Readable, but written before Vellum recorded checksums — the '
          'contents could not be verified.';
    }
    final books = counts['books'];
    return 'Backup is intact: $checked files checked'
        '${books == null ? '' : ', $books books'}.';
  }
}

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

  /// The manifest format this version writes. Bumped when the *shape* changes,
  /// which is not the same thing as the database's `schemaVersion`.
  static const manifestVersion = 2;

  /// Writes a complete backup to [dest]. Safe while the app is running: the
  /// database is snapshotted with `VACUUM INTO`, which produces a clean,
  /// compact copy even with the live connection open.
  ///
  /// With a [passphrase], the archive is built to a temporary file and then
  /// sealed into [dest] (see [BackupCrypto]); without one it stays a plain
  /// `.zip` that any tool can open, which is the default on purpose.
  Future<void> exportTo(File dest, {String? passphrase}) async {
    if (passphrase != null && passphrase.isNotEmpty) {
      final plain = File('${dest.path}.plain');
      try {
        await _exportZip(plain);
        await BackupCrypto.encryptFile(
          source: plain,
          dest: dest,
          passphrase: passphrase,
        );
      } finally {
        if (await plain.exists()) await plain.delete();
      }
      return;
    }
    await _exportZip(dest);
  }

  Future<void> _exportZip(File dest) async {
    final dataDir = repository.dataDir;
    final snapshot = File(p.join(dataDir.path, '.backup-snapshot.sqlite'));
    if (await snapshot.exists()) await snapshot.delete();
    await repository.db.customStatement('VACUUM INTO ?', [snapshot.path]);
    final encoder = ZipFileEncoder();
    // Filled as blobs are added, then written as the manifest at the end —
    // which is why the manifest is added last rather than first.
    final hashes = <String, String>{'vellum.sqlite': await _sha256(snapshot)};
    try {
      encoder.create(dest.path);
      await encoder.addFile(snapshot, 'vellum.sqlite');
      // 'photos' since plan 5 #51 — condition photos are app-local, so a
      // backup is the only copy of them that leaves the device.
      // 'backdrops' since plan 5 #29 — a room photo is app-local (it never
      // rides the published layout document), so a backup is the only copy of
      // it that leaves the device.
      for (final sub in ['covers', 'files', 'photos', 'backdrops']) {
        final dir = Directory(p.join(dataDir.path, sub));
        if (!await dir.exists()) continue;
        await for (final entry in dir.list()) {
          // Skip transfer leftovers; everything else in these dirs is a blob.
          if (entry is File && !entry.path.endsWith('.part')) {
            final ext = p.extension(entry.path).replaceFirst('.', '').toLowerCase();
            final name = '$sub/${p.basename(entry.path)}';
            hashes[name] = await _sha256(entry);
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
      encoder.addArchiveFile(ArchiveFile.string(
        'manifest.json',
        jsonEncode({
          'app': 'vellum',
          'manifestVersion': manifestVersion,
          'created': DateTime.now().toUtc().toIso8601String(),
          // The drift schema version, not an app version: this is the number
          // that decides whether a restored database can be opened at all, and
          // it needs no extra platform plugin to read.
          'schemaVersion': repository.db.schemaVersion,
          'counts': await _counts(),
          'blobs': hashes,
        }),
      ));
      await encoder.close();
    } finally {
      if (await snapshot.exists()) await snapshot.delete();
    }
  }

  /// Counts worth showing before a restore — "12 books" is the difference
  /// between the backup you meant and the one from before an import.
  Future<Map<String, int>> _counts() async {
    final db = repository.db;
    Future<int> count(dynamic table) async =>
        (await db.customSelect('SELECT COUNT(*) AS c FROM $table').getSingle())
            .read<int>('c');
    return {
      'books': await count('books'),
      'files': await count('book_files'),
      'copies': await count('physical_copies'),
      'photos': await count('copy_photos'),
    };
  }

  /// Streamed rather than `readAsBytes`: a book file can be hundreds of
  /// megabytes and this runs over every blob in the library.
  static Future<String> _sha256(File file) async =>
      (await sha256.bind(file.openRead()).first).toString();

  /// Checks an archive without restoring it (plan 5 #13).
  ///
  /// Re-hashes every entry the manifest lists and compares. This is the only
  /// way to learn a backup is bad *before* you need it — and it is read-only:
  /// nothing about the live library is touched, so it is safe to run on the
  /// backup you are about to trust.
  Future<BackupCheck> verify(File archive, {String? passphrase}) async {
    File readable = archive;
    File? decrypted;
    try {
      if (await BackupCrypto.isEncrypted(archive)) {
        if (passphrase == null || passphrase.isEmpty) {
          return const BackupCheck(
            readable: false,
            hasDatabase: false,
            problem: 'This backup is encrypted — enter its passphrase.',
          );
        }
        // In the data dir, not the system temp dir: it is always writable,
        // it is the same disk the restore staging uses, and reaching for
        // `getTemporaryDirectory()` would drag a platform plugin into a check
        // that is otherwise pure file IO.
        decrypted = File(p.join(
          repository.dataDir.path,
          '.verify-${DateTime.now().microsecondsSinceEpoch}.zip',
        ));
        try {
          await BackupCrypto.decryptFile(
            source: archive,
            dest: decrypted,
            passphrase: passphrase,
          );
        } on BackupDecryptException catch (e) {
          return BackupCheck(
            readable: false,
            hasDatabase: false,
            problem: e.message,
          );
        }
        readable = decrypted;
      }

      final InputFileStream input;
      final Archive zip;
      try {
        input = InputFileStream(readable.path);
        zip = ZipDecoder().decodeStream(input);
      } catch (_) {
        return const BackupCheck(
          readable: false,
          hasDatabase: false,
          problem: "That file isn't a readable archive.",
        );
      }

      try {
        Map<String, dynamic>? manifest;
        final present = <String, ArchiveFile>{};
        for (final entry in zip.files) {
          if (!entry.isFile) continue;
          if (entry.name == 'manifest.json') {
            try {
              manifest = jsonDecode(utf8.decode(entry.readBytes() ?? const []))
                  as Map<String, dynamic>;
            } catch (_) {
              manifest = null;
            }
            continue;
          }
          present[entry.name] = entry;
        }

        final hasDatabase = present.containsKey('vellum.sqlite');
        if (manifest == null || manifest['app'] != 'vellum') {
          return BackupCheck(
            readable: false,
            hasDatabase: hasDatabase,
            problem: "That file isn't a Vellum backup.",
          );
        }

        final blobs = (manifest['blobs'] as Map?)?.cast<String, dynamic>();
        final missing = <String>[];
        final corrupt = <String>[];
        var checked = 0;
        for (final name in (blobs ?? const {}).keys) {
          final entry = present[name];
          if (entry == null) {
            missing.add(name);
            continue;
          }
          final bytes = entry.readBytes() ?? const <int>[];
          if (sha256.convert(bytes).toString() != blobs![name]) {
            corrupt.add(name);
          } else {
            checked++;
          }
        }

        return BackupCheck(
          readable: true,
          hasDatabase: hasDatabase,
          hashesRecorded: blobs != null && blobs.isNotEmpty,
          checked: checked,
          missing: missing,
          corrupt: corrupt,
          unlisted: [
            for (final name in present.keys)
              if (blobs == null || !blobs.containsKey(name)) name,
          ],
          created: DateTime.tryParse(manifest['created'] as String? ?? ''),
          schemaVersion: (manifest['schemaVersion'] as num?)?.toInt(),
          counts: {
            for (final e
                in (manifest['counts'] as Map?)?.cast<String, dynamic>().entries ??
                    const <MapEntry<String, dynamic>>[])
              e.key: (e.value as num).toInt(),
          },
        );
      } finally {
        await input.close();
      }
    } finally {
      if (decrypted != null && await decrypted.exists()) {
        await decrypted.delete();
      }
    }
  }

  /// Replaces the current library with the contents of [archive]. Returns
  /// false (changing nothing) when the file isn't a Vellum backup.
  ///
  /// On success the database connection is **closed** and the file swapped on
  /// disk — the app must restart before touching the library again; the
  /// caller owns telling the user and exiting.
  ///
  /// An encrypted archive is decrypted to a temporary file first; a wrong
  /// passphrase throws [BackupDecryptException] **before** anything is
  /// replaced, so a failed attempt leaves the library exactly as it was.
  Future<bool> restoreFrom(File archive, {String? passphrase}) async {
    final dataDir = repository.dataDir;
    final staging = Directory(p.join(dataDir.path, '.restore-staging'));
    if (await staging.exists()) await staging.delete(recursive: true);
    File? decrypted;
    try {
      var source = archive;
      if (await BackupCrypto.isEncrypted(archive)) {
        if (passphrase == null || passphrase.isEmpty) {
          throw const BackupDecryptException(
            'this backup is encrypted — its passphrase is needed',
          );
        }
        decrypted = File(p.join(dataDir.path, '.restore-decrypted.zip'));
        await BackupCrypto.decryptFile(
          source: archive,
          dest: decrypted,
          passphrase: passphrase,
        );
        source = decrypted;
      }
      await extractFileToDisk(source.path, staging.path);

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
      for (final sub in ['covers', 'files', 'photos', 'backdrops']) {
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
      if (decrypted != null && await decrypted.exists()) {
        await decrypted.delete();
      }
    }
  }
}
