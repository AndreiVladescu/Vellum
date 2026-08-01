// Bookcases as a group of segments (next features #11).
//
// The design being pinned: a bookcase is a *tag* on ordinary segments, not a
// parent row. So grouping is one UPDATE, ungrouping moves nothing, and every
// query that reasons about a flat list of shelves keeps working.
import 'dart:io';
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/physical/bookcase_template.dart';

void main() {
  late Directory dir;
  late LibraryRepository repo;
  late String envId;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vellum_group');
    repo = await LibraryRepository.forTesting(
      VellumDatabase(NativeDatabase.memory()),
      dir,
    );
    envId = await repo.layout.createEnvironment('Study');
  });

  tearDown(() async {
    await repo.db.close();
    dir.deleteSync(recursive: true);
  });

  Future<String> addCase({double x = 0, double y = 0.09}) => repo.layout
      .addBookcase(envId, bookcaseSegments(style: BookcaseStyle.low, x: x, y: y));

  test('every part of a bookcase carries the same group', () async {
    final group = await addCase();
    final parts = await repo.layout.shelvesInGroup(group);
    expect(parts, hasLength(BookcaseStyle.low.shelves + 2));
    expect(parts.every((s) => s.groupId == group), isTrue);
  });

  test('two bookcases do not share a group', () async {
    final a = await addCase();
    final b = await addCase(x: 2.0);
    expect(a, isNot(b));
    expect(await repo.layout.shelvesInGroup(a),
        hasLength(BookcaseStyle.low.shelves + 2));
    expect(await repo.layout.shelvesInGroup(b),
        hasLength(BookcaseStyle.low.shelves + 2));
  });

  test('moving a bookcase moves every part by the same amount', () async {
    final group = await addCase();
    final before = await repo.layout.shelvesInGroup(group);
    await repo.layout.moveGroup(group, const Offset(1.5, 0.2));
    final after = {
      for (final s in await repo.layout.shelvesInGroup(group)) s.id: s,
    };
    for (final part in before) {
      expect(after[part.id]!.x1, closeTo(part.x1 + 1.5, 1e-9));
      expect(after[part.id]!.y1, closeTo(part.y1 + 0.2, 1e-9));
      expect(after[part.id]!.x2, closeTo(part.x2 + 1.5, 1e-9));
      expect(after[part.id]!.y2, closeTo(part.y2 + 0.2, 1e-9));
    }
  });

  test('ungrouping forgets the tag and moves nothing', () async {
    final group = await addCase();
    final before = await repo.layout.shelvesInGroup(group);
    await repo.layout.ungroup(group);

    expect(await repo.layout.shelvesInGroup(group), isEmpty);
    final all = await repo.layout.watchShelves(envId).first;
    expect(all, hasLength(before.length), reason: 'nothing was deleted');
    expect(all.every((s) => s.groupId == null), isTrue);
    // Same geometry, to the last millimetre.
    final byId = {for (final s in all) s.id: s};
    for (final part in before) {
      expect(byId[part.id]!.x1, part.x1);
      expect(byId[part.id]!.y1, part.y1);
    }
  });

  test('loose segments can be grouped by hand', () async {
    await repo.layout.addShelf(envId, x1: 0, y1: 1, x2: 0.9, y2: 1);
    await repo.layout.addShelf(envId, x1: 0, y1: 1.4, x2: 0.9, y2: 1.4);
    final loose = await repo.layout.watchShelves(envId).first;
    expect(loose.every((s) => s.groupId == null), isTrue);

    final group = await repo.layout
        .groupShelves(envId, loose.map((s) => s.id).toList());
    expect(await repo.layout.shelvesInGroup(group), hasLength(2));
  });

  test('deleting a bookcase takes only its own parts', () async {
    final keep = await addCase();
    final go = await addCase(x: 2.0);
    await repo.layout.deleteGroup(go);

    expect(await repo.layout.shelvesInGroup(go), isEmpty);
    expect(await repo.layout.shelvesInGroup(keep),
        hasLength(BookcaseStyle.low.shelves + 2));
  });

  test('a bookcase stands on the skirting, not in it', () async {
    // At y = 0 the bottom shelf lands inside the 9 cm skirting band and reads
    // as a stripe across the base of the case.
    final group = await addCase(y: 0.09);
    final lowest = (await repo.layout.shelvesInGroup(group))
        .map((s) => s.y1)
        .reduce((a, b) => a < b ? a : b);
    expect(lowest, closeTo(0.09, 1e-9));
  });

  group('anchoring', () {
    test('a new bookcase is anchored, and a new shelf is too', () async {
      // Anchored by default: a room is arranged once and looked at hundreds of
      // times, so a left-click that shifts furniture is a mistake you have to
      // notice before you can undo it.
      final group = await addCase();
      expect(
        (await repo.layout.shelvesInGroup(group)).every((s) => s.anchored),
        isTrue,
      );
      await repo.layout.addShelf(envId, x1: 0, y1: 1, x2: 0.9, y2: 1);
      final loose = (await repo.layout.watchShelves(envId).first)
          .firstWhere((s) => s.groupId == null);
      expect(loose.anchored, isTrue);
    });

    test('unlocking a bookcase unlocks all of it, and locking puts it back',
        () async {
      final group = await addCase();
      final ids = (await repo.layout.shelvesInGroup(group)).map((s) => s.id);
      await repo.layout.setAnchored(envId, ids, anchored: false);
      expect(
        (await repo.layout.shelvesInGroup(group)).every((s) => s.anchored),
        isFalse,
        reason: 'a bookcase moves as one, so it unlocks as one',
      );

      await repo.layout.setAnchored(envId, ids, anchored: true);
      expect(
        (await repo.layout.shelvesInGroup(group)).every((s) => s.anchored),
        isTrue,
      );
    });
  });

  test('moving a bookcase keeps its uprights upright', () async {
    // The regression: a drag used to write the resting height into *both* y
    // values, which is a no-op for a flat shelf and collapses a side panel or
    // divider to a single point.
    final group = await addCase();
    final before = (await repo.layout.shelvesInGroup(group))
        .where((s) => (s.y2 - s.y1).abs() > 1e-9)
        .toList();
    expect(before, isNotEmpty, reason: 'the case should have side panels');

    await repo.layout.moveGroup(group, const Offset(0.5, 0));
    final after = {
      for (final s in await repo.layout.shelvesInGroup(group)) s.id: s,
    };
    for (final upright in before) {
      final moved = after[upright.id]!;
      expect(
        (moved.y2 - moved.y1).abs(),
        closeTo((upright.y2 - upright.y1).abs(), 1e-9),
        reason: 'the upright lost its height',
      );
    }
  });
}
