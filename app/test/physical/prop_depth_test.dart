import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/physical/room_prop.dart';

/// Whether a prop stands in front of the books or behind them (issue #10
/// item 4).
///
/// Props have always been drawn behind — an ornament pushed to the back of a
/// shelf, with the spines readable in front of it — and that stays the
/// default. The choice exists because a room usually wants both: a plant whose
/// leaves fall across the books really is in front of them.
///
/// It is app-local, like the rest of the room: `room_props` is not a synced
/// table, so this is a drift migration with no server counterpart.
void main() {
  late Directory dir;
  late LibraryRepository repo;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vellum_prop_depth');
    repo = await LibraryRepository.forTesting(
      VellumDatabase(NativeDatabase.memory()),
      dir,
    );
  });
  tearDown(() async {
    await repo.db.close();
    dir.deleteSync(recursive: true);
  });

  Future<String> aRoomWithAProp() async {
    final env = await repo.layout.createEnvironment('Study');
    return repo.layout.addProp(
      env,
      kind: PropKind.plant,
      x: 0.5,
      y: 1.0,
    );
  }

  Future<RoomProp> read(String id) async =>
      (await (repo.db.select(repo.db.roomProps)..where((p) => p.id.equals(id)))
          .getSingle());

  test('a new prop stands behind the books', () async {
    final prop = await aRoomWithAProp();
    expect((await read(prop)).inFront, isFalse,
        reason: 'the ordinary case, and what every existing room already does');
  });

  test('and can be brought in front, and sent back', () async {
    final prop = await aRoomWithAProp();

    await repo.layout.setPropInFront(prop, true);
    expect((await read(prop)).inFront, isTrue);

    await repo.layout.setPropInFront(prop, false);
    expect((await read(prop)).inFront, isFalse);
  });

  test('changing it marks the room for republishing', () async {
    // A shared room is a document someone else fetches; a change nobody
    // publishes is a change only this device can see.
    final prop = await aRoomWithAProp();
    final env = (await read(prop)).environmentId;
    await (repo.db.update(repo.db.physicalEnvironments)
          ..where((e) => e.id.equals(env)))
        .write(const PhysicalEnvironmentsCompanion(needsPublish: Value(false)));

    await repo.layout.setPropInFront(prop, true);

    final room = await (repo.db.select(repo.db.physicalEnvironments)
          ..where((e) => e.id.equals(env)))
        .getSingle();
    expect(room.needsPublish, isTrue);
  });
}
