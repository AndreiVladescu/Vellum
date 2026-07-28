import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import 'database.dart';

/// Condition photos for physical copies (plan 5 #51).
///
/// The bytes are copied into `photos/` under the data dir and the row stores
/// only the relative path — the same split as [FileService] and covers, so a
/// backup that snapshots the database plus the blob directories is complete.
///
/// Copying rather than referencing the picked file is deliberate: a photo
/// picked from the camera roll can be deleted from the roll the next day, and a
/// condition record that evaporates is worse than none.
class CopyPhotoService {
  CopyPhotoService(this.db, this._dataDir);

  final VellumDatabase db;
  final Directory _dataDir;

  static const _uuid = Uuid();

  /// Where photo blobs live, relative to the data dir. Shared with
  /// `BackupService` so the two can't drift apart.
  static const dirName = 'photos';

  Stream<List<CopyPhoto>> watchPhotosOf(String copyId) =>
      (db.select(db.copyPhotos)
            ..where((ph) => ph.copyId.equals(copyId))
            ..orderBy([(ph) => OrderingTerm.desc(ph.takenAt)]))
          .watch();

  Future<List<CopyPhoto>> photosOf(String copyId) =>
      (db.select(db.copyPhotos)
            ..where((ph) => ph.copyId.equals(copyId))
            ..orderBy([(ph) => OrderingTerm.desc(ph.takenAt)]))
          .get();

  /// Absolute file for a stored photo.
  File fileOf(CopyPhoto photo) => File(p.join(_dataDir.path, photo.path));

  /// Copies [sourcePath] into the store and records it against [copyId].
  ///
  /// Written to a `.part` file and renamed into place, like [FileService]: the
  /// sweep at startup already deletes stray `.part` files, and it means a photo
  /// row never points at a half-copied image. Returns the new row's id.
  Future<String> addPhoto(
    String copyId,
    String sourcePath, {
    String? caption,
    DateTime? takenAt,
  }) async {
    final id = _uuid.v4();
    final ext = p.extension(sourcePath).replaceFirst('.', '').toLowerCase();
    final relPath = p.join(dirName, '$id.${ext.isEmpty ? 'jpg' : ext}');
    final dest = File(p.join(_dataDir.path, relPath));
    await dest.parent.create(recursive: true);
    final part = File('${dest.path}.part');
    try {
      await File(sourcePath).copy(part.path);
      await part.rename(dest.path);
    } catch (_) {
      if (await part.exists()) {
        try {
          await part.delete();
        } catch (_) {
          // Best-effort cleanup; the startup sweep will get it.
        }
      }
      rethrow; // Nothing recorded yet, so nothing to roll back.
    }

    final trimmed = caption?.trim();
    await db.into(db.copyPhotos).insert(
          CopyPhotosCompanion.insert(
            id: id,
            copyId: copyId,
            path: relPath,
            takenAt: Value(takenAt ?? DateTime.now()),
            caption:
                Value(trimmed == null || trimmed.isEmpty ? null : trimmed),
            updatedAt: Value(DateTime.now()),
          ),
        );
    return id;
  }

  Future<void> setCaption(String photoId, String? caption) {
    final trimmed = caption?.trim();
    return (db.update(db.copyPhotos)..where((ph) => ph.id.equals(photoId)))
        .write(CopyPhotosCompanion(
      caption: Value(trimmed == null || trimmed.isEmpty ? null : trimmed),
      updatedAt: Value(DateTime.now()),
      needsPush: const Value(true),
    ));
  }

  /// Removes the row and its blob. The row goes first: an orphaned file wastes
  /// space, an orphaned row shows a broken image.
  Future<void> deletePhoto(String photoId) async {
    final photo = await (db.select(db.copyPhotos)
          ..where((ph) => ph.id.equals(photoId)))
        .getSingleOrNull();
    if (photo == null) return;
    await db.transaction(() async {
      await (db.delete(db.copyPhotos)..where((ph) => ph.id.equals(photoId)))
          .go();
      // A tombstone, so the other devices stop showing it rather than pushing
      // it back on their next sync (plan 6 #4).
      await db.into(db.localDeletions).insertOnConflictUpdate(
            LocalDeletionsCompanion.insert(
              bookId: photoId,
              kind: const Value('copy_photo'),
            ),
          );
    });
    await deleteBlobs([photo]);
  }

  /// Drops every photo of a copy, blobs included.
  ///
  /// No tombstones: the copy's own deletion already tells the server, and the
  /// server's `ON DELETE CASCADE` takes its photos with it. One tombstone per
  /// photo would be noise saying the same thing.
  Future<void> deletePhotosOfCopy(String copyId) async {
    final photos = await photosOf(copyId);
    await (db.delete(db.copyPhotos)..where((ph) => ph.copyId.equals(copyId)))
        .go();
    await deleteBlobs(photos);
  }

  /// Unlinks the files behind [photos], ignoring ones already gone.
  ///
  /// Separate from the row delete because `PhysicalService.deletePhysicalCopy`
  /// clears the rows itself inside its transaction — `copyId` has no
  /// `ON DELETE CASCADE`, exactly like `loans` and `book_placements` — and so
  /// has to read the rows *before* that and hand them here afterwards. A blob
  /// pass that ran after the rows were gone would silently find nothing and
  /// leak every file.
  Future<void> deleteBlobs(Iterable<CopyPhoto> photos) async {
    for (final photo in photos) {
      try {
        await fileOf(photo).delete();
      } catch (_) {
        // Already gone, or unreadable — the row is what mattered.
      }
    }
  }
}
