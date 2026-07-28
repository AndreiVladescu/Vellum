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
  List<Map<String, dynamic>>? pushedAnnotations,
  List<String>? deletedAnnotations,
  List<Map<String, dynamic>>? pushedSessions,
  List<Map<String, dynamic>>? pushedNotes,
  bool personalSupported = true,
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
            path.startsWith('/api/profile'))) {
      // Exactly what a server that predates migration 0023 answers.
      return http.Response('{"error":"not found"}', 404);
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

  test('an older server is not reported as broken on every sync', () async {
    // A server without migration 0023 answers 404 for all of this. The library
    // still syncs; complaining once a minute forever would be noise.
    final repo = await _repo();
    final report =
        await SyncService(repo).pull(_client(_server(personalSupported: false)));
    expect(report.issues, isEmpty);
  });
}
