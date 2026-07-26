// The `layout_doc` v1 document (plan 5 #47).
//
// Two properties are worth more than the round trip itself: the document must
// carry **no book metadata** (that is what makes the console's room view safe
// by construction), and applying one must be **idempotent and subtractive** —
// a book someone else took off the shelf has to actually disappear here.
import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/physical/layout_doc.dart';

void main() {
  late Directory dir;
  late LibraryRepository repo;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vellum_layout_doc');
    repo = await LibraryRepository.forTesting(
      VellumDatabase(NativeDatabase.memory()),
      dir,
    );
  });

  tearDown(() async {
    await repo.db.close();
    dir.deleteSync(recursive: true);
  });

  /// A room with one shelf and [books] placed on it. Returns the environment id.
  Future<String> seedRoom({int books = 2, String name = 'Living room'}) async {
    final envId = await repo.layout.createEnvironment(name);
    await repo.layout
        .addShelf(envId, x1: 0, y1: 1.0, x2: 2.0, y2: 1.0, label: 'Shelf 1');
    for (var i = 0; i < books; i++) {
      final bookId = await repo.createCustomBook(
        title: 'Book $i',
        author: 'Author $i',
      );
      await repo.layout.placeBook(envId, bookId, x: 0.1 * i, y: 1.0);
    }
    return envId;
  }

  Future<Map<String, dynamic>> docFor(String envId) async {
    final env = await repo.layout.environment(envId);
    return buildLayoutDoc(
      environment: env!,
      shelves: await repo.layout.watchShelves(envId).first,
      placed: await repo.layout.watchPlacedBooks(envId).first,
    );
  }

  test('the document carries geometry and nothing else', () async {
    // The security property: a viewer who may not see a book learns nothing
    // about it from the room, because there is nothing in the document to
    // learn. Redaction is structural, not a filter someone has to remember.
    final envId = await seedRoom();
    final doc = await docFor(envId);
    final json = jsonEncode(doc);

    expect(json, isNot(contains('Book 0')));
    expect(json, isNot(contains('Author 0')));
    expect(json, isNot(contains('cover')));
    expect(json, isNot(contains('isbn')));
    // The room's own name is not a secret — it's what you chose to publish.
    expect(doc['environment']['name'], 'Living room');

    final placement = (doc['placements'] as List).first as Map;
    expect(placement.keys.toSet(), {
      'id',
      'copy_id',
      'book_id',
      'x',
      'y',
      'rotation',
      'width_m',
      'height_m',
    });
  });

  test('sizes are resolved at publish time, not left to the viewer', () async {
    // A viewer who can't read a book's page count still has to draw its spine
    // at the right thickness.
    final envId = await repo.layout.createEnvironment('Study');
    final bookId = await repo.createCustomBook(title: 'Thick');
    await repo.updateBookDetails(bookId, title: 'Thick', pageCount: 900);
    await repo.layout.placeBook(envId, bookId, x: 0, y: 0);

    final doc = await docFor(envId);
    final placement = (doc['placements'] as List).single as Map;
    expect(placement['width_m'], greaterThan(0.04),
        reason: '900 pages is a fat book');
    expect(placement['height_m'], greaterThan(0.1));
  });

  test('a document round-trips onto a blank device with identical geometry',
      () async {
    final envId = await seedRoom(books: 3);
    final doc = await docFor(envId);
    final originalShelves = await repo.layout.watchShelves(envId).first;
    final originalPlaced = await repo.layout.watchPlacedBooks(envId).first;

    // A second, empty library that already has the books (they sync
    // separately) but not the room.
    final otherDir = Directory.systemTemp.createTempSync('vellum_layout_other');
    final other = await LibraryRepository.forTesting(
      VellumDatabase(NativeDatabase.memory()),
      otherDir,
    );
    for (final pb in originalPlaced) {
      await other.db.into(other.db.books).insert(
            BooksCompanion.insert(id: pb.book.id, title: pb.book.title),
          );
    }

    final skipped = await applyLayoutDoc(
      other.db,
      parseLayoutDoc(doc),
      revision: 4,
    );
    expect(skipped, 0);

    final appliedShelves = await other.layout.watchShelves(envId).first;
    expect(appliedShelves.length, originalShelves.length);
    expect(appliedShelves.single.label, 'Shelf 1');
    expect(appliedShelves.single.y1, 1.0);

    final appliedPlaced = await other.layout.watchPlacedBooks(envId).first;
    expect(appliedPlaced.length, 3);
    expect(
      appliedPlaced.map((p) => p.placement.x).toList()..sort(),
      originalPlaced.map((p) => p.placement.x).toList()..sort(),
    );
    // And the room is recorded as level with the server, not dirty.
    final env = await other.layout.environment(envId);
    expect(env!.serverRevision, 4);
    expect(env.needsPublish, isFalse);

    await other.db.close();
    otherDir.deleteSync(recursive: true);
  });

  test('applying twice changes nothing the second time', () async {
    final envId = await seedRoom(books: 2);
    final doc = await docFor(envId);
    final parsed = parseLayoutDoc(doc);

    await applyLayoutDoc(repo.db, parsed, revision: 1);
    final after1 = await repo.layout.watchPlacedBooks(envId).first;
    await applyLayoutDoc(repo.db, parsed, revision: 1);
    final after2 = await repo.layout.watchPlacedBooks(envId).first;

    expect(after2.length, after1.length);
    expect(
      after2.map((p) => p.placement.id).toSet(),
      after1.map((p) => p.placement.id).toSet(),
    );
  });

  test('a book removed from the published room disappears locally', () async {
    // The subtractive half: without it, a fetch could only ever add, and a
    // shelf someone tidied would keep its ghosts forever.
    final envId = await seedRoom(books: 3);
    final full = parseLayoutDoc(await docFor(envId));

    final trimmed = ParsedLayout(
      environmentId: full.environmentId,
      name: full.name,
      shelves: full.shelves,
      placements: full.placements.take(1).toList(),
    );
    await applyLayoutDoc(repo.db, trimmed, revision: 2);

    expect((await repo.layout.watchPlacedBooks(envId).first).length, 1);
  });

  test('a shelf removed from the published room goes too', () async {
    final envId = await seedRoom(books: 0);
    final full = parseLayoutDoc(await docFor(envId));
    await applyLayoutDoc(
      repo.db,
      ParsedLayout(
        environmentId: full.environmentId,
        name: full.name,
        shelves: const [],
        placements: const [],
      ),
      revision: 2,
    );
    expect(await repo.layout.watchShelves(envId).first, isEmpty);
  });

  test('a placement for a book this device does not have is reported, not lost',
      () async {
    // "3 books aren't here yet" is the difference between a bug report and a
    // sync — silently dropping them would look like data loss.
    final envId = await seedRoom(books: 1);
    final doc = await docFor(envId);
    final parsed = parseLayoutDoc(doc);
    final withGhost = ParsedLayout(
      environmentId: parsed.environmentId,
      name: parsed.name,
      shelves: parsed.shelves,
      placements: [
        ...parsed.placements,
        const ParsedPlacement(
          id: 'ghost',
          copyId: 'ghost-copy',
          bookId: 'a-book-that-never-synced',
          x: 1,
          y: 1,
          rotation: 0,
          widthM: 0.02,
          heightM: 0.2,
        ),
      ],
    );

    final skipped = await applyLayoutDoc(repo.db, withGhost, revision: 3);
    expect(skipped, 1);
    expect((await repo.layout.watchPlacedBooks(envId).first).length, 1);
  });

  test('a copy minted by a fetch is not marked for push', () async {
    // It came *from* the server; pushing it straight back is the trap #17's
    // series pull hit.
    final bookId = await repo.createCustomBook(title: 'Elsewhere');
    await applyLayoutDoc(
      repo.db,
      ParsedLayout(
        environmentId: 'env-1',
        name: 'Fetched',
        shelves: const [],
        placements: [
          ParsedPlacement(
            id: 'p1',
            copyId: 'copy-from-server',
            bookId: bookId,
            x: 0,
            y: 0,
            rotation: 0,
            widthM: 0.02,
            heightM: 0.2,
          ),
        ],
      ),
      revision: 1,
    );
    final copy = await (repo.db.select(repo.db.physicalCopies)
          ..where((c) => c.id.equals('copy-from-server')))
        .getSingle();
    expect(copy.needsPush, isFalse);
  });

  group('parsing', () {
    test('refuses a document from a newer app', () {
      expect(
        () => parseLayoutDoc({
          'doc': 'vellum.layout',
          'version': 99,
          'environment': {'id': 'x', 'name': 'y'},
        }),
        throwsA(isA<LayoutDocException>()),
      );
    });

    test('refuses something that is not a room document', () {
      expect(
        () => parseLayoutDoc({'doc': 'something.else', 'version': 1}),
        throwsA(isA<LayoutDocException>()),
      );
      expect(
        () => parseLayoutDoc({'doc': 'vellum.layout', 'version': 1}),
        throwsA(isA<LayoutDocException>()),
      );
    });

    test('tolerates a document with no shelves or placements', () {
      final parsed = parseLayoutDoc({
        'doc': 'vellum.layout',
        'version': 1,
        'environment': {'id': 'x', 'name': 'Empty room'},
      });
      expect(parsed.shelves, isEmpty);
      expect(parsed.placements, isEmpty);
      expect(parsed.name, 'Empty room');
    });
  });

  group('dirty tracking', () {
    test('editing a room marks it as needing a publish', () async {
      final envId = await seedRoom(books: 1);
      await repo.layout.markPublished(envId, 1);
      expect((await repo.layout.environment(envId))!.needsPublish, isFalse);

      final placed = await repo.layout.watchPlacedBooks(envId).first;
      await repo.layout.updatePlacement(placed.single.placement.id, x: 0.5);
      expect((await repo.layout.environment(envId))!.needsPublish, isTrue);
    });

    test('a shelf edit marks the room too', () async {
      final envId = await seedRoom(books: 0);
      await repo.layout.markPublished(envId, 1);
      final shelf = (await repo.layout.watchShelves(envId).first).single;
      await repo.layout.updateShelf(shelf.id, y1: 1.4, y2: 1.4);
      expect((await repo.layout.environment(envId))!.needsPublish, isTrue);
    });

    test('a never-published room does not start life dirty', () async {
      // Publishing is a deliberate act; a badge on a room nobody ever meant to
      // publish is noise.
      final envId = await repo.layout.createEnvironment('Fresh');
      final env = await repo.layout.environment(envId);
      expect(env!.needsPublish, isFalse);
      expect(env.serverRevision, isNull);
    });
  });
}
