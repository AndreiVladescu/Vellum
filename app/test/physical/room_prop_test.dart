// Things that stand on a shelf next to the books (next features #10, stage 2).
//
// The prop *art* is not worth testing — it is a handful of Paths, and a test
// asserting on curve control points would only ever break when someone improves
// the drawing. What is worth testing is everything around it: that a prop is
// stored and removed, that a room can still be deleted once it has one, and
// that books make room for it.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/physical/room_prop.dart';
import 'package:vellum/physical/settle.dart';

void main() {
  late Directory dir;
  late LibraryRepository repo;
  late String envId;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vellum_props');
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

  group('the kinds', () {
    test('all have a sensible shelf-sized footprint', () {
      for (final kind in PropKind.values) {
        expect(kind.width, greaterThan(0));
        expect(kind.height, greaterThan(0));
        // Nothing here should be taller than a shelf gap or wider than a shelf.
        expect(kind.height, lessThan(0.35), reason: '${kind.name} is enormous');
        expect(kind.width, lessThan(0.35), reason: '${kind.name} is enormous');
      }
    });

    test('an unknown kind still occupies its space', () {
      // A prop written by a newer build must not vanish, or books would
      // silently overlap something that is still on the shelf.
      expect(PropKind.parse('a-kind-from-the-future'), isNotNull);
      expect(PropKind.parse(null), isNotNull);
      expect(PropKind.parse('statuette'), PropKind.statuette);
    });
  });

  group('storage', () {
    test('a prop is stored where it was put, at its own size', () async {
      final id = await repo.layout.addProp(
        envId,
        kind: PropKind.statuette,
        x: 0.4,
        y: 1.0,
      );
      final props = await repo.layout.watchProps(envId).first;
      expect(props, hasLength(1));
      expect(props.single.id, id);
      expect(props.single.kind, 'statuette');
      expect(props.single.x, closeTo(0.4, 1e-9));
      expect(props.single.widthM, closeTo(PropKind.statuette.width, 1e-9));
    });

    test('moving one keeps its size', () async {
      final id = await repo.layout
          .addProp(envId, kind: PropKind.vase, x: 0, y: 1.0);
      await repo.layout.moveProp(id, x: 0.7, y: 1.4);
      final prop = (await repo.layout.watchProps(envId).first).single;
      expect(prop.x, closeTo(0.7, 1e-9));
      expect(prop.y, closeTo(1.4, 1e-9));
      expect(prop.heightM, closeTo(PropKind.vase.height, 1e-9));
    });

    test('removing one leaves the rest alone', () async {
      final a =
          await repo.layout.addProp(envId, kind: PropKind.plant, x: 0, y: 1);
      await repo.layout.addProp(envId, kind: PropKind.clock, x: 0.5, y: 1);
      await repo.layout.deleteProp(a);
      final left = await repo.layout.watchProps(envId).first;
      expect(left, hasLength(1));
      expect(left.single.kind, 'clock');
    });

    test('a room with props in it can still be deleted', () async {
      // Props reference the room with no ON DELETE cascade and foreign keys are
      // enforced — the same trap that made a photographed book undeletable.
      await repo.layout.addProp(envId, kind: PropKind.boxes, x: 0, y: 1);
      await repo.layout.deleteEnvironment(envId);
      expect(await repo.layout.watchEnvironments().first, isEmpty);
      expect(await repo.layout.watchProps(envId).first, isEmpty);
    });

    test('putting a prop in a room marks it for publishing', () async {
      await repo.layout.markPublished(envId, 3);
      expect((await repo.layout.environment(envId))!.needsPublish, isFalse);
      await repo.layout.addProp(envId, kind: PropKind.vase, x: 0, y: 1);
      expect((await repo.layout.environment(envId))!.needsPublish, isTrue);
    });
  });

  group('books make room for one', () {
    test('a book dropped onto a prop is nudged clear of it', () {
      // A prop is a *barrier*, not a surface: books go round it, and none
      // balances on top of it.
      const statuette = SettleBox(x: 0.30, y: 1.0, w: 0.08, h: 0.18);
      final r = settle(
        x: 0.30,
        y: 1.3,
        w: 0.04,
        h: 0.2,
        shelves: [
          const SettleSegment(x1: 0, y1: 1.0, x2: 0.9, y2: 1.0),
        ],
        others: const [],
        barriers: const [statuette],
      );
      expect(r.onSurface, isTrue);
      expect(r.y, closeTo(1.0, 1e-9),
          reason: 'it should rest on the shelf, not on the statuette');
      final overlaps = r.x < 0.38 - 1e-9 && r.x + 0.04 > 0.30 + 1e-9;
      expect(overlaps, isFalse, reason: 'the book landed on the statuette');
    });
  });

  testWidgets('every kind draws without throwing', (tester) async {
    // Cheap, and it catches the one thing that would take the whole room down:
    // a Path built from a bad value.
    for (final kind in PropKind.values) {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: kind.width * 300,
              height: kind.height * 300,
              child: PropArt(kind: kind, color: Colors.brown),
            ),
          ),
        ),
      );
      await tester.pump();
      expect(tester.takeException(), isNull, reason: '${kind.name} threw');
    }
  });
  group('the solid part is not the drawn part', () {
    // Until this split existed a prop's **artwork was its collider**: the box
    // it was painted in was the box books were pushed out of, so nothing could
    // overhang its own footprint. A book tucked under a plant's leaves is what
    // a real shelf looks like, and refusing it left a gap that read as a bug.

    test('a plant is narrower to books than it is drawn', () {
      const drawn = 0.16;
      final span = PropKind.plant.solidSpan(1.0, drawn);
      expect(span.w, lessThan(drawn));
      // Centred on the artwork, because these are drawn about their own axis.
      expect(span.x + span.w / 2, closeTo(1.0 + drawn / 2, 1e-9));
    });

    test('a solid prop keeps its whole footprint', () {
      const drawn = 0.22;
      final span = PropKind.boxes.solidSpan(2.0, drawn);
      // A stack of boxes has no overhang to allow for; changing this would
      // start letting books sit inside it.
      expect(span.w, closeTo(drawn, 1e-9));
      expect(span.x, closeTo(2.0, 1e-9));
    });

    test('the fraction survives a resize', () {
      // Stored as a fraction rather than a second size precisely so that
      // resizing a prop does not need the collider migrating too.
      final small = PropKind.plant.solidSpan(0, 0.10);
      final large = PropKind.plant.solidSpan(0, 0.20);
      expect(large.w / small.w, closeTo(2.0, 1e-9));
    });

    test('every kind keeps its collider inside its artwork', () {
      // A collider wider than the art would push books away from empty space.
      for (final kind in PropKind.values) {
        expect(kind.solidWidthFraction, greaterThan(0));
        expect(kind.solidWidthFraction, lessThanOrEqualTo(1.0),
            reason: '${kind.name} would block more than it draws');
      }
    });
  });
}
