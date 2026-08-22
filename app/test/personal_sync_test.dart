// Personal data crossing between two devices of one account.
//
// The library already synced; what did not was everything that makes a book
// *yours* — highlights, notes, sittings. Three devices kept three disjoint sets
// silently. These tests drive the sync against a fake server and assert the
// halves that are easy to get wrong: a delete that stays deleted, an offline
// edit that doesn't clobber a newer one, and an older server that isn't
// reported as broken every time you sync.
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/server/server_client.dart';
import 'package:vellum/server/sync_service.dart';

VellumServerClient _client(Future<http.Response> Function(http.Request) handler) =>
    VellumServerClient(
      baseUrl: 'http://test',
      token: 't',
      httpClient: MockClient(handler),
    );

/// A server that knows nothing but the personal endpoints — the library ones
/// answer empty, so these tests are about one thing at a time.
Future<http.Response> Function(http.Request) _server({
  List<Map<String, dynamic>> annotations = const [],
  List<Map<String, dynamic>> annotationDeletions = const [],
  List<Map<String, dynamic>> sessions = const [],
  List<Map<String, dynamic>> notes = const [],
  List<Map<String, dynamic>> statuses = const [],
  List<Map<String, dynamic>>? pushedAnnotations,
  List<String>? deletedAnnotations,
  List<Map<String, dynamic>>? pushedSessions,
  List<Map<String, dynamic>>? pushedNotes,
  List<Map<String, dynamic>>? pushedStatuses,
  List<Map<String, dynamic>> copyPhotos = const [],
  List<Map<String, dynamic>>? pushedCopyPhotos,
  List<String>? uploadedPhotoImages,
  bool personalSupported = true,
  bool bookStatusSupported = true,
}) {
  return (req) async {
    final path = req.url.path;
    const now = '2026-07-28 00:00:00';
    http.Response envelope(List<Map<String, dynamic>> entries) => http.Response(
          jsonEncode({'server_now': now, 'entries': entries}),
          200,
        );

    if (!personalSupported &&
        (path.startsWith('/api/annotations') ||
            path.startsWith('/api/sessions') ||
            path.startsWith('/api/notes') ||
            path.startsWith('/api/statuses') ||
            path.startsWith('/api/profile'))) {
      // Exactly what a server that predates migration 0023 answers.
      return http.Response('{"error":"not found"}', 404);
    }

    if (req.method == 'GET' && path == '/api/capabilities') {
      // Reading status is asked for by name rather than discovered from a 404
      // — see `_supportsBookStatus`.
      return http.Response(
        jsonEncode({
          'version': 'test',
          'features': [if (bookStatusSupported) 'book_status'],
        }),
        200,
      );
    }
    if (req.method == 'GET') {
      switch (path) {
        case '/api/annotations':
          return envelope(annotations);
        case '/api/annotations/deletions':
          return envelope(annotationDeletions);
        case '/api/sessions':
          return envelope(sessions);
        case '/api/notes':
          return envelope(notes);
        case '/api/statuses':
          return envelope(statuses);
        case '/api/books':
          return http.Response(
              jsonEncode({'server_now': now, 'books': []}), 200);
        case '/api/shelves':
          return http.Response(
              jsonEncode({'server_now': now, 'shelves': []}), 200);
        case '/api/copies':
          return http.Response(
              jsonEncode({'server_now': now, 'copies': []}), 200);
        case '/api/loans':
          return http.Response(
              jsonEncode({'server_now': now, 'loans': []}), 200);
        case '/api/copy-photos':
          return http.Response(
              jsonEncode({'server_now': now, 'photos': copyPhotos}), 200);
        case '/api/deletions':
          return http.Response('[]', 200);
      }
    }
    if (req.method == 'PUT' && path.startsWith('/api/annotations/')) {
      pushedAnnotations?.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{}', 200);
    }
    if (req.method == 'DELETE' && path.startsWith('/api/annotations/')) {
      deletedAnnotations?.add(path.split('/').last);
      return http.Response('{}', 200);
    }
    if (req.method == 'PUT' && path.startsWith('/api/sessions/')) {
      pushedSessions?.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{}', 200);
    }
    if (req.method == 'PUT' && path.endsWith('/image') &&
        path.startsWith('/api/copy-photos/')) {
      uploadedPhotoImages?.add(path.split('/')[3]);
      return http.Response('{}', 200);
    }
    if (req.method == 'GET' && path.startsWith('/api/copy-photos/') &&
        path.endsWith('/image')) {
      // A one-pixel PNG is enough: the sync only stores the bytes.
      return http.Response.bytes(
          [0x89, 0x50, 0x4E, 0x47, 0x0D, 0x0A, 0x1A, 0x0A, 0, 0, 0, 0], 200);
    }
    if (req.method == 'PUT' && path.startsWith('/api/copy-photos/')) {
      pushedCopyPhotos?.add({
        'id': path.split('/').last,
        ...jsonDecode(req.body) as Map<String, dynamic>,
      });
      return http.Response('{}', 200);
    }
    if (req.method == 'PUT' && path.startsWith('/api/statuses/')) {
      pushedStatuses?.add({
        'book_id': path.split('/').last,
        ...jsonDecode(req.body) as Map<String, dynamic>,
      });
      return http.Response('{}', 200);
    }
    if (req.method == 'PUT' && path.startsWith('/api/notes/')) {
      pushedNotes?.add({
        'book_id': path.split('/').last,
        ...jsonDecode(req.body) as Map<String, dynamic>,
      });
      return http.Response('{}', 200);
    }
    return http.Response('{"error":"unexpected ${req.method} $path"}', 404);
  };
}

Future<LibraryRepository> _repo() async {
  final dir = await Directory.systemTemp.createTemp('vellum_personal_sync');
  final repo = await LibraryRepository.forTesting(
    VellumDatabase(NativeDatabase.memory()),
    dir,
  );
  await repo.db.into(repo.db.books).insert(
        BooksCompanion.insert(id: 'b1', title: 'Dune', needsPush: const Value(false)),
      );
  return repo;
}

void main() {
  test('a highlight made here is pushed, once', () async {
    final repo = await _repo();
    final pushed = <Map<String, dynamic>>[];
    final id = await repo.annotations.add(
      bookId: 'b1',
      kind: AnnotationKind.highlight,
      quotedText: 'the spice must flow',
      color: 0xFF8FD48A,
    );

    final sync = SyncService(repo);
    await sync.push(_client(_server(pushedAnnotations: pushed)));
    expect(pushed, hasLength(1));
    expect(pushed.single['quoted_text'], 'the spice must flow');
    expect(pushed.single['color'], 0xFF8FD48A);

    // Clean now, so a second sync doesn't re-send it.
    pushed.clear();
    await sync.push(_client(_server(pushedAnnotations: pushed)));
    expect(pushed, isEmpty, reason: 'needsPush was cleared');

    final stored = await (repo.db.select(repo.db.annotations)
          ..where((a) => a.id.equals(id)))
        .getSingle();
    expect(stored.needsPush, isFalse);
  });

  test("another device's highlight arrives and is not pushed back", () async {
    final repo = await _repo();
    final pushed = <Map<String, dynamic>>[];
    final sync = SyncService(repo);
    await sync.pull(_client(_server(annotations: [
      {
        'id': 'remote-1',
        'book_id': 'b1',
        'kind': 'highlight',
        'quoted_text': 'from the laptop',
        'created_at': '2026-07-20 10:00:00',
        'updated_at': '2026-07-20 10:00:00',
      }
    ])));

    final all = await repo.db.select(repo.db.annotations).get();
    expect(all, hasLength(1));
    expect(all.single.quotedText, 'from the laptop');
    expect(all.single.needsPush, isFalse, reason: 'it came *from* the server');

    await sync.push(_client(_server(pushedAnnotations: pushed)));
    expect(pushed, isEmpty);
  });

  test('an edit made offline does not clobber a newer one from elsewhere',
      () async {
    final repo = await _repo();
    await repo.db.into(repo.db.annotations).insert(AnnotationsCompanion.insert(
          id: 'a1',
          bookId: 'b1',
          kind: 'note',
          note: const Value('newer, made here'),
          updatedAt: Value(DateTime(2026, 7, 25)),
          needsPush: const Value(false),
        ));

    await SyncService(repo).pull(_client(_server(annotations: [
      {
        'id': 'a1',
        'book_id': 'b1',
        'kind': 'note',
        'note': 'older, from the phone',
        'created_at': '2026-07-01 10:00:00',
        'updated_at': '2026-07-01 10:00:00',
      }
    ])));

    final stored = await (repo.db.select(repo.db.annotations)
          ..where((a) => a.id.equals('a1')))
        .getSingle();
    expect(stored.note, 'newer, made here');
  });

  test('a deletion is sent, and the tombstone is then dropped', () async {
    final repo = await _repo();
    final deleted = <String>[];
    final id = await repo.annotations
        .add(bookId: 'b1', kind: AnnotationKind.bookmark, page: 7);
    await repo.annotations.delete(id);

    // The tombstone is what stops the other device pushing it back.
    final before = await (repo.db.select(repo.db.localDeletions)
          ..where((d) => d.kind.equals('annotation')))
        .get();
    expect(before, hasLength(1));

    await SyncService(repo).push(_client(_server(deletedAnnotations: deleted)));
    expect(deleted, [id]);
    final after = await (repo.db.select(repo.db.localDeletions)
          ..where((d) => d.kind.equals('annotation')))
        .get();
    expect(after, isEmpty, reason: 'sent once, not on every sync forever');
  });

  test("a deletion from elsewhere removes the highlight here", () async {
    final repo = await _repo();
    await repo.db.into(repo.db.annotations).insert(AnnotationsCompanion.insert(
          id: 'gone',
          bookId: 'b1',
          kind: 'highlight',
          needsPush: const Value(false),
        ));

    await SyncService(repo).pull(_client(_server(
      annotationDeletions: [
        {'id': 'gone', 'deleted_at': '2026-07-27 00:00:00'}
      ],
    )));
    expect(await repo.db.select(repo.db.annotations).get(), isEmpty);
  });

  test('sittings from three devices all land, and merge as a union', () async {
    final repo = await _repo();
    await SyncService(repo).pull(_client(_server(sessions: [
      for (final d in ['phone', 'laptop', 'pc'])
        {
          'id': 'session-$d',
          'book_id': 'b1',
          'device_id': d,
          'device_label': d,
          'started_at': '2026-07-20 20:00:00',
          'ended_at': '2026-07-20 20:45:00',
        }
    ])));

    final sessions = await repo.db.select(repo.db.readingSessions).get();
    expect(sessions, hasLength(3));
    expect(
      sessions.map((s) => s.deviceLabel).toSet(),
      {'phone', 'laptop', 'pc'},
      reason: 'statistics can still say where you read',
    );
  });

  test('a private note travels to the account, not to the book row', () async {
    final repo = await _repo();
    final pushed = <Map<String, dynamic>>[];
    await repo.writes.setReaderNotes('b1', 'my own thoughts');

    await SyncService(repo).push(_client(_server(pushedNotes: pushed)));
    expect(pushed, hasLength(1));
    expect(pushed.single['book_id'], 'b1');
    expect(pushed.single['note'], 'my own thoughts');

    final book = await (repo.db.select(repo.db.books)
          ..where((b) => b.id.equals('b1')))
        .getSingle();
    expect(book.readerNotesNeedsPush, isFalse);
    expect(book.needsPush, isFalse,
        reason: "a note is not a catalogue edit, so it must not dirty the book");
  });

  group('reading status', () {
    // v1.1.5: a book wanted on the phone arrived on the tablet as one you own,
    // and a book read to the end stayed unread everywhere else. Status is
    // personal — per reader, not per book — so it travels the same channel the
    // private note does, never the book row (server migration 0006 and 0034).

    test('marking a book finished sends it, with its dates', () async {
      final repo = await _repo();
      final pushed = <Map<String, dynamic>>[];
      await repo.readingStatus.setStatus('b1', ReadingStatus.finished);

      await SyncService(repo).push(_client(_server(pushedStatuses: pushed)));

      expect(pushed, hasLength(1));
      expect(pushed.single['book_id'], 'b1');
      expect(pushed.single['status'], 'finished');
      expect(pushed.single['finished_at'], isNotNull,
          reason: 'the date is half the fact');
      expect(pushed.single['read_count'], 1);

      final book = await (repo.db.select(repo.db.books)
            ..where((b) => b.id.equals('b1')))
          .getSingle();
      expect(book.statusNeedsPush, isFalse, reason: 'sent once, not every sync');
      expect(book.needsPush, isFalse,
          reason: 'finishing a book is not a catalogue edit');
    });

    test('a wishlist book stays wanted here rather than becoming owned',
        () async {
      final repo = await _repo();
      await SyncService(repo).pull(_client(_server(statuses: [
        {
          'book_id': 'b1',
          'status': 'wishlist',
          'read_count': 0,
          'updated_at': '2026-07-27 10:00:00',
        }
      ])));

      final book = await (repo.db.select(repo.db.books)
            ..where((b) => b.id.equals('b1')))
          .getSingle();
      expect(book.status, 'wishlist');
      expect(book.statusNeedsPush, isFalse,
          reason: 'it came from the server; it is not waiting to go back');
    });

    test("another device's finish arrives, with the dates behind it", () async {
      final repo = await _repo();
      await SyncService(repo).pull(_client(_server(statuses: [
        {
          'book_id': 'b1',
          'status': 'finished',
          'started_at': '2026-07-01 09:00:00',
          'finished_at': '2026-07-20 22:00:00',
          'read_count': 2,
          'updated_at': '2026-07-20 22:00:00',
        }
      ])));

      final book = await (repo.db.select(repo.db.books)
            ..where((b) => b.id.equals('b1')))
          .getSingle();
      expect(book.status, 'finished');
      expect(book.readCount, 2);
      expect(book.finishedAt, isNotNull);
    });

    test('a newer local change is not overwritten by an older one', () async {
      final repo = await _repo();
      await repo.readingStatus.setStatus('b1', ReadingStatus.finished);

      // The server still holds what this book was yesterday.
      await SyncService(repo).pull(_client(_server(statuses: [
        {
          'book_id': 'b1',
          'status': 'reading',
          'read_count': 0,
          'updated_at': '2020-01-01 00:00:00',
        }
      ])));

      final book = await (repo.db.select(repo.db.books)
            ..where((b) => b.id.equals('b1')))
          .getSingle();
      expect(book.status, 'finished');
      expect(book.statusNeedsPush, isTrue,
          reason: 'and it is still waiting to be published');
    });

    test('a book with nothing to say about its status says nothing', () async {
      final repo = await _repo();
      final pushed = <Map<String, dynamic>>[];

      await SyncService(repo).push(_client(_server(pushedStatuses: pushed)));

      expect(pushed, isEmpty,
          reason: 'an untouched `unread` book has no opinion to publish');
    });

    test('a server without the feature is left alone, not asked anyway',
        () async {
      final repo = await _repo();
      final pushed = <Map<String, dynamic>>[];
      await repo.readingStatus.setStatus('b1', ReadingStatus.finished);

      final report = await SyncService(repo).push(_client(
          _server(pushedStatuses: pushed, bookStatusSupported: false)));

      expect(pushed, isEmpty);
      expect(report.issues, isEmpty,
          reason: 'a server without migration 0034 is a server without the '
              'feature, not a failed sync');

      final book = await (repo.db.select(repo.db.books)
            ..where((b) => b.id.equals('b1')))
          .getSingle();
      expect(book.statusNeedsPush, isTrue,
          reason: 'and it is still waiting for a server that can take it');
    });

    test('a book kept on this device only keeps its status here too', () async {
      final repo = await _repo();
      final pushed = <Map<String, dynamic>>[];
      await repo.readingStatus.setStatus('b1', ReadingStatus.finished);
      await (repo.db.update(repo.db.books)
            ..where((b) => b.id.equals('b1')))
          .write(const BooksCompanion(syncExcluded: Value(true)));

      await SyncService(repo).push(_client(_server(pushedStatuses: pushed)));

      expect(pushed, isEmpty,
          reason: 'the server has never heard of this book, and is not owed '
              'the fact that it was finished');
    });

    test('a trashed book does not announce itself on the way out', () async {
      final repo = await _repo();
      final pushed = <Map<String, dynamic>>[];
      await repo.readingStatus.setStatus('b1', ReadingStatus.finished);
      await (repo.db.update(repo.db.books)..where((b) => b.id.equals('b1')))
          .write(BooksCompanion(deletedAt: Value(DateTime.now())));

      await SyncService(repo).push(_client(_server(pushedStatuses: pushed)));

      expect(pushed, isEmpty);
    });
  });

  test('an incoming note replaces the local one', () async {
    final repo = await _repo();
    await SyncService(repo).pull(_client(_server(notes: [
      {
        'book_id': 'b1',
        'note': 'written on the laptop',
        'updated_at': '2026-07-27 00:00:00',
      }
    ])));
    final book = await (repo.db.select(repo.db.books)
          ..where((b) => b.id.equals('b1')))
        .getSingle();
    expect(book.readerNotes, 'written on the laptop');
    expect(book.readerNotesNeedsPush, isFalse);
  });

  test('a book this device does not have is skipped, not thrown on', () async {
    // A shared library, or a book whose own pull failed. The foreign key would
    // otherwise abort the whole sync.
    final repo = await _repo();
    await SyncService(repo).pull(_client(_server(annotations: [
      {
        'id': 'orphan',
        'book_id': 'not-here',
        'kind': 'highlight',
        'created_at': '2026-07-20 10:00:00',
        'updated_at': '2026-07-20 10:00:00',
      }
    ])));
    expect(await repo.db.select(repo.db.annotations).get(), isEmpty);
  });

  test('an overwritten local edit is reported rather than vanishing', () async {
    // Last-write-wins stays — field-level merge was rejected in plan 3 — but
    // silence was a separate choice, and the wrong one: an edit made here and
    // never pushed used to be replaced with nothing said anywhere.
    final repo = await _repo();
    await (repo.db.update(repo.db.books)..where((b) => b.id.equals('b1'))).write(
      BooksCompanion(
        title: const Value('Dune, my edit'),
        needsPush: const Value(true),
        updatedAt: Value(DateTime(2026, 7, 1)),
      ),
    );

    final report = await SyncService(repo).pull(_client((req) async {
      if (req.url.path == '/api/books') {
        return http.Response(
          jsonEncode({
            'server_now': '2026-07-28 00:00:00',
            'books': [
              {
                'id': 'b1',
                'title': 'Dune, from the laptop',
                'updated_at': '2026-07-27 00:00:00',
              }
            ],
          }),
          200,
        );
      }
      return _server()(req);
    }));

    final overwritten =
        report.issues.where((i) => i.stage == 'overwritten').toList();
    expect(overwritten, hasLength(1));
    expect(overwritten.single.message, contains('Dune, my edit'));
    expect(overwritten.single.message, contains('another device'));

    // And the server's version did win — the report is a notice, not a veto.
    final book = await (repo.db.select(repo.db.books)
          ..where((b) => b.id.equals('b1')))
        .getSingle();
    expect(book.title, 'Dune, from the laptop');
  });

  test('a book with no unsent edits is replaced quietly', () async {
    // The common case. Reporting every incoming update as an overwrite would
    // make the report useless.
    final repo = await _repo();
    final report = await SyncService(repo).pull(_client((req) async {
      if (req.url.path == '/api/books') {
        return http.Response(
          jsonEncode({
            'server_now': '2026-07-28 00:00:00',
            'books': [
              {
                'id': 'b1',
                'title': 'Dune, from the laptop',
                'updated_at': '2026-07-27 00:00:00',
              }
            ],
          }),
          200,
        );
      }
      return _server()(req);
    }));
    expect(report.issues.where((i) => i.stage == 'overwritten'), isEmpty);
  });

  group('copy photos', () {
    // Library data, not personal: a photo hangs off a copy, and a copy is
    // visible to whoever the book is shared with.
    Future<LibraryRepository> withCopy() async {
      final repo = await _repo();
      await repo.db.into(repo.db.physicalCopies).insert(
            PhysicalCopiesCompanion.insert(
              id: 'c1',
              bookId: 'b1',
              needsPush: const Value(false),
            ),
          );
      return repo;
    }

    test('one taken here is pushed with its bytes', () async {
      final repo = await withCopy();
      final pushed = <Map<String, dynamic>>[];
      final uploaded = <String>[];

      final source = File('${repo.dataDir.path}/source.jpg');
      await source.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]);
      final id = await repo.copyPhotos
          .addPhoto('c1', source.path, caption: 'top shelf');

      await SyncService(repo).push(_client(_server(
        pushedCopyPhotos: pushed,
        uploadedPhotoImages: uploaded,
      )));

      expect(pushed, hasLength(1));
      expect(pushed.single['caption'], 'top shelf');
      expect(uploaded, [id], reason: 'the row is nothing without the image');

      final stored = await (repo.db.select(repo.db.copyPhotos)
            ..where((ph) => ph.id.equals(id)))
          .getSingle();
      expect(stored.needsPush, isFalse);
    });

    test('one from another device arrives with its bytes on disk', () async {
      final repo = await withCopy();
      await SyncService(repo).pull(_client(_server(copyPhotos: [
        {
          'id': 'remote-photo',
          'copy_id': 'c1',
          'path': 'copy-photos/remote-photo',
          'caption': 'their shelf',
          'taken_at': '2026-07-20 10:00:00',
          'updated_at': '2026-07-20 10:00:00',
        }
      ])));

      final all = await repo.db.select(repo.db.copyPhotos).get();
      expect(all, hasLength(1));
      expect(all.single.caption, 'their shelf');
      expect(all.single.needsPush, isFalse);
      expect(File('${repo.dataDir.path}/${all.single.path}').existsSync(), isTrue,
          reason: 'a row without its image renders as a gap');
    });

    test('a photo for a copy this device lacks is skipped', () async {
      final repo = await _repo(); // no copy at all
      await SyncService(repo).pull(_client(_server(copyPhotos: [
        {
          'id': 'orphan',
          'copy_id': 'not-here',
          'path': 'copy-photos/orphan',
          'taken_at': '2026-07-20 10:00:00',
          'updated_at': '2026-07-20 10:00:00',
        }
      ])));
      expect(await repo.db.select(repo.db.copyPhotos).get(), isEmpty);
    });

    test('deleting one leaves a tombstone to send', () async {
      final repo = await withCopy();
      final source = File('${repo.dataDir.path}/source.jpg');
      await source.writeAsBytes([0xFF, 0xD8, 0xFF, 0xE0, 0, 0, 0, 0]);
      final id = await repo.copyPhotos.addPhoto('c1', source.path);

      await repo.copyPhotos.deletePhoto(id);
      final tombstones = await (repo.db.select(repo.db.localDeletions)
            ..where((d) => d.kind.equals('copy_photo')))
          .get();
      expect(tombstones.map((t) => t.bookId), [id]);
    });
  });

  test('an older server is not reported as broken on every sync', () async {
    // A server without migration 0023 answers 404 for all of this. The library
    // still syncs; complaining once a minute forever would be noise.
    final repo = await _repo();
    final report =
        await SyncService(repo).pull(_client(_server(personalSupported: false)));
    expect(report.issues, isEmpty);
  });
}
