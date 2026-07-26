// Condition photos for physical copies (plan 5 #51). The interesting parts are
// not the CRUD but the two places blobs and rows can disagree: a copy being
// deleted, and a backup that has to carry the photos off the device (they never
// sync, so a backup is the only copy that leaves).
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/data/copy_photo_service.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/physical_service.dart';

void main() {
  late VellumDatabase db;
  late Directory dataDir;
  late CopyPhotoService photos;
  late PhysicalService physical;

  setUp(() async {
    db = VellumDatabase(NativeDatabase.memory());
    dataDir = Directory.systemTemp.createTempSync('vellum_copy_photos');
    photos = CopyPhotoService(db, dataDir);
    physical = PhysicalService(db, photos);
  });

  tearDown(() async {
    await db.close();
    if (dataDir.existsSync()) dataDir.deleteSync(recursive: true);
  });

  /// A book, a copy, and a file on disk to photograph.
  Future<String> seedCopy() async {
    await db.into(db.books).insert(
          BooksCompanion.insert(id: 'b1', title: 'Dune'),
        );
    return physical.addPhysicalCopy('b1');
  }

  File sourceImage(String name, {String bytes = 'not really a jpeg'}) {
    final file = File(p.join(dataDir.path, name));
    file.writeAsStringSync(bytes);
    return file;
  }

  test('a photo is copied into the store, not referenced where it was picked',
      () async {
    // The point: a shot picked from the camera roll can be deleted from the
    // roll tomorrow, and a condition record that evaporates is worse than none.
    final copyId = await seedCopy();
    final source = sourceImage('picked.jpg', bytes: 'original bytes');
    final id = await photos.addPhoto(copyId, source.path, caption: '  torn  ');

    final stored = (await photos.photosOf(copyId)).single;
    expect(stored.id, id);
    expect(stored.path, p.join('photos', '$id.jpg'));
    expect(stored.caption, 'torn', reason: 'captions are trimmed');
    expect(photos.fileOf(stored).readAsStringSync(), 'original bytes');

    source.deleteSync();
    expect(photos.fileOf(stored).existsSync(), isTrue,
        reason: 'the library copy survives the source going away');
  });

  test('an extensionless source still lands as an image file', () async {
    final copyId = await seedCopy();
    final id = await photos.addPhoto(copyId, sourceImage('shot').path);
    expect((await photos.photosOf(copyId)).single.path,
        p.join('photos', '$id.jpg'));
  });

  test('no .part file is left behind by a successful add', () async {
    final copyId = await seedCopy();
    await photos.addPhoto(copyId, sourceImage('a.jpg').path);
    final leftovers = Directory(p.join(dataDir.path, 'photos'))
        .listSync()
        .where((e) => e.path.endsWith('.part'));
    expect(leftovers, isEmpty);
  });

  test('a failed add records nothing', () async {
    final copyId = await seedCopy();
    await expectLater(
      photos.addPhoto(copyId, p.join(dataDir.path, 'nope.jpg')),
      throwsA(isA<FileSystemException>()),
    );
    expect(await photos.photosOf(copyId), isEmpty);
  });

  test('newest first, so the latest condition is the one you see', () async {
    final copyId = await seedCopy();
    await photos.addPhoto(copyId, sourceImage('old.jpg').path,
        caption: 'lent', takenAt: DateTime(2026, 1, 1));
    await photos.addPhoto(copyId, sourceImage('new.jpg').path,
        caption: 'returned', takenAt: DateTime(2026, 3, 1));
    expect(
      (await photos.photosOf(copyId)).map((ph) => ph.caption),
      ['returned', 'lent'],
    );
  });

  test('deleting a photo takes its blob with it', () async {
    final copyId = await seedCopy();
    final id = await photos.addPhoto(copyId, sourceImage('a.jpg').path);
    final file = photos.fileOf((await photos.photosOf(copyId)).single);
    await photos.deletePhoto(id);
    expect(await photos.photosOf(copyId), isEmpty);
    expect(file.existsSync(), isFalse);
  });

  test('deleting a photo whose blob already vanished still clears the row',
      () async {
    final copyId = await seedCopy();
    final id = await photos.addPhoto(copyId, sourceImage('a.jpg').path);
    photos.fileOf((await photos.photosOf(copyId)).single).deleteSync();
    await photos.deletePhoto(id); // must not throw
    expect(await photos.photosOf(copyId), isEmpty);
  });

  test('deleting a copy deletes its photos, rows and blobs', () async {
    // `copyId` has no ON DELETE CASCADE — same as loans and placements — so
    // leaving a photo row behind would make the copy delete fail on a foreign
    // key, and a pull-driven delete must never fail.
    final copyId = await seedCopy();
    await photos.addPhoto(copyId, sourceImage('a.jpg').path);
    await photos.addPhoto(copyId, sourceImage('b.jpg').path);
    final files =
        (await photos.photosOf(copyId)).map(photos.fileOf).toList();

    await physical.deletePhysicalCopy(copyId);

    expect(await db.select(db.copyPhotos).get(), isEmpty);
    for (final f in files) {
      expect(f.existsSync(), isFalse);
    }
  });

  test('a copy delete without a photo service still clears the rows', () async {
    // Tooling and tests build a database-only PhysicalService; the foreign key
    // has to be satisfied there too, even though no blob can be reached.
    final copyId = await seedCopy();
    await photos.addPhoto(copyId, sourceImage('a.jpg').path);
    await PhysicalService(db).deletePhysicalCopy(copyId);
    expect(await db.select(db.copyPhotos).get(), isEmpty);
  });

  test('setCaption clears rather than stores a blank', () async {
    final copyId = await seedCopy();
    final id = await photos.addPhoto(copyId, sourceImage('a.jpg').path,
        caption: 'tear');
    await photos.setCaption(id, '   ');
    expect((await photos.photosOf(copyId)).single.caption, isNull);
  });

  test('watchPhotosOf emits as photos are added', () async {
    final copyId = await seedCopy();
    final stream = photos.watchPhotosOf(copyId);
    expect(
      stream.map((rows) => rows.length),
      emitsInOrder([0, 1]),
    );
    await photos.addPhoto(copyId, sourceImage('a.jpg').path);
  });
}
