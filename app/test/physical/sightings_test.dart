// "Which shelf is my copy on?" (plan 5 #28) — the query behind *Find my copy*.
// The case that matters is the one where guessing goes wrong: the same title
// placed twice, in two rooms.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';

void main() {
  late Directory dir;
  late LibraryRepository repo;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vellum_sightings');
    repo = await LibraryRepository.forTesting(
      VellumDatabase(NativeDatabase.memory()),
      dir,
    );
  });

  tearDown(() async {
    await repo.db.close();
    dir.deleteSync(recursive: true);
  });

  /// A room with one shelf at [shelfY], returning the environment id.
  Future<String> room(String name, {double shelfY = 1.0, String? label}) async {
    final id = await repo.layout.createEnvironment(name);
    await repo.layout.addShelf(id, x1: 0, y1: shelfY, x2: 2, y2: shelfY,
        label: label);
    return id;
  }

  test('an unplaced book has no sightings', () async {
    final bookId = await repo.createCustomBook(title: 'Dune');
    expect(await repo.layout.sightingsOf(bookId), isEmpty);
  });

  test('resolves book → copy → placement → environment, naming the shelf',
      () async {
    final bookId = await repo.createCustomBook(title: 'Dune');
    final envId = await room('Living room', shelfY: 1.0, label: 'Shelf 2');
    await repo.layout.placeBook(envId, bookId, x: 0.5, y: 1.0);

    final sighting = (await repo.layout.sightingsOf(bookId)).single;
    expect(sighting.environmentId, envId);
    expect(sighting.environmentName, 'Living room');
    expect(sighting.shelfLabel, 'Shelf 2');
    expect(sighting.display, 'Living room · Shelf 2');
    expect(sighting.x, 0.5);
  });

  test('two copies in two rooms are both reported', () async {
    // The whole reason *Find my copy* asks rather than jumps: picking the first
    // row would silently send you to the wrong room half the time.
    final bookId = await repo.createCustomBook(title: 'Dune');
    final study = await room('Study', label: 'Top');
    final bedroom = await room('Bedroom', label: 'Bottom');
    await repo.layout.placeBook(study, bookId, x: 0.5, y: 1.0);
    await repo.layout.placeBook(bedroom, bookId, x: 0.5, y: 1.0);

    final sightings = await repo.layout.sightingsOf(bookId);
    expect(sightings.length, 2);
    expect(
      sightings.map((s) => s.environmentName),
      ['Bedroom', 'Study'],
      reason: 'ordered by room name so the list is stable',
    );
    // Each placement owns its own copy, which is why the same title can be in
    // two places at once.
    expect(sightings.map((s) => s.copyId).toSet().length, 2);
  });

  test('two copies on one shelf are ordered left to right', () async {
    final bookId = await repo.createCustomBook(title: 'Dune');
    final envId = await room('Study');
    await repo.layout.placeBook(envId, bookId, x: 1.5, y: 1.0);
    await repo.layout.placeBook(envId, bookId, x: 0.2, y: 1.0);

    expect(
      (await repo.layout.sightingsOf(bookId)).map((s) => s.x),
      [0.2, 1.5],
    );
  });

  test('a sighting on an unlabelled shelf still names the room', () async {
    final bookId = await repo.createCustomBook(title: 'Dune');
    final envId = await room('Hallway'); // no shelf label
    await repo.layout.placeBook(envId, bookId, x: 0.5, y: 1.0);

    final sighting = (await repo.layout.sightingsOf(bookId)).single;
    expect(sighting.shelfLabel, isNull);
    expect(sighting.display, 'Hallway');
  });

  test('another book in the same room is not reported', () async {
    final dune = await repo.createCustomBook(title: 'Dune');
    final other = await repo.createCustomBook(title: 'Neuromancer');
    final envId = await room('Study');
    await repo.layout.placeBook(envId, other, x: 0.5, y: 1.0);
    expect(await repo.layout.sightingsOf(dune), isEmpty);
  });

  group('environmentOfShelf', () {
    test('finds the room a scanned label belongs to', () async {
      final envId = await room('Study');
      final shelf = (await repo.layout.watchShelves(envId).first).single;
      expect((await repo.layout.environmentOfShelf(shelf.id))?.name, 'Study');
    });

    test('a label that outlived its shelf resolves to nothing', () async {
      // Printed labels are physical objects; the shelf can be deleted while the
      // sticker is still on the wood.
      final envId = await room('Study');
      final shelf = (await repo.layout.watchShelves(envId).first).single;
      await repo.layout.deleteShelf(shelf.id);
      expect(await repo.layout.environmentOfShelf(shelf.id), isNull);
    });
  });
}
