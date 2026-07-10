import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/server/server_client.dart';
import 'package:vellum/server/sync_service.dart';

/// Builds a repository over an in-memory database and a throwaway data dir.
Future<LibraryRepository> _repo(Directory dir) async =>
    LibraryRepository.forTesting(VellumDatabase(NativeDatabase.memory()), dir);

VellumServerClient _client(Future<http.Response> Function(http.Request) handler) =>
    VellumServerClient(baseUrl: 'http://test', token: 't', httpClient: MockClient(handler));

/// A JSON handler that serves a fixed book list + deletions, and empty file
/// lists, so pull's cover/file passes are no-ops.
Future<http.Response> Function(http.Request) _server({
  required List<Map<String, dynamic>> books,
  List<String> deletions = const [],
  List<String>? deletedCollector,
}) {
  return (req) async {
    final path = req.url.path;
    if (req.method == 'GET' && path == '/api/books') {
      return http.Response(jsonEncode(books), 200);
    }
    if (req.method == 'GET' && path == '/api/deletions') {
      return http.Response(
        jsonEncode([for (final id in deletions) {'book_id': id, 'deleted_at': '2020-01-01 00:00:00'}]),
        200,
      );
    }
    if (req.method == 'GET' && path.endsWith('/files')) {
      return http.Response('[]', 200);
    }
    if (req.method == 'DELETE' && path.startsWith('/api/books/')) {
      deletedCollector?.add(path.split('/').last);
      return http.Response('{}', 200);
    }
    return http.Response('{"error":"unexpected ${req.method} $path"}', 404);
  };
}

Map<String, dynamic> _serverBook(String id, String title, String updatedAt) => {
  'id': id,
  'title': title,
  'updated_at': updatedAt,
};

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_sync_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('pull inserts a book the device does not have', () async {
    final repo = await _repo(dir);
    final client = _client(_server(books: [_serverBook('b1', 'Dune', '2024-01-01 00:00:00')]));

    final n = await SyncService(repo).pull(client);
    expect(n, 1);
    final book = await repo.watchBook('b1').first;
    expect(book?.title, 'Dune');
  });

  test('pull does not clobber a locally newer edit', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    // Local row edited "now" (newer than the server's copy).
    await db.into(db.books).insert(
      BooksCompanion.insert(
        id: 'b1',
        title: 'Local edit',
        updatedAt: Value(DateTime.utc(2025, 1, 1)),
      ),
    );

    final client = _client(_server(books: [_serverBook('b1', 'Server title', '2024-01-01 00:00:00')]));
    await SyncService(repo).pull(client);

    final book = await repo.watchBook('b1').first;
    expect(book?.title, 'Local edit', reason: 'local edit is newer, must win');
  });

  test('pull overwrites when the server copy is newer', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(
      BooksCompanion.insert(
        id: 'b1',
        title: 'Old local',
        updatedAt: Value(DateTime.utc(2024, 1, 1)),
      ),
    );

    final client = _client(_server(books: [_serverBook('b1', 'Newer server', '2025-06-01 00:00:00')]));
    await SyncService(repo).pull(client);

    final book = await repo.watchBook('b1').first;
    expect(book?.title, 'Newer server');
  });

  test('a page-turn does not bump the sync clock, so a newer server edit wins', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(
      BooksCompanion.insert(
        id: 'b1',
        title: 'Old local',
        pageCount: const Value(100),
        updatedAt: Value(DateTime.utc(2024, 1, 1)),
      ),
    );

    // Reading is app-local state and must not touch updatedAt.
    await repo.saveReadingPosition('b1', 50, 100);
    final afterRead = await repo.watchBook('b1').first;
    expect(
      afterRead?.updatedAt.millisecondsSinceEpoch,
      DateTime.utc(2024, 1, 1).millisecondsSinceEpoch,
      reason: 'reading state must not bump the sync conflict clock',
    );

    // So a genuine console edit (newer) still wins on the next pull.
    final client = _client(
      _server(books: [_serverBook('b1', 'Console edit', '2025-06-01 00:00:00')]),
    );
    await SyncService(repo).pull(client);
    final book = await repo.watchBook('b1').first;
    expect(book?.title, 'Console edit');
  });

  test('pull maps server authors and genres into the local db', () async {
    final repo = await _repo(dir);
    final client = _client(
      _server(
        books: [
          {
            'id': 'b1',
            'title': 'Dune',
            'updated_at': '2024-01-01 00:00:00',
            'authors': ['Frank Herbert'],
            'genres': ['Sci-Fi'],
          },
        ],
      ),
    );

    await SyncService(repo).pull(client);

    final details = await repo.detailsFor('b1');
    expect(details.authors, ['Frank Herbert']);
    expect(details.genres, ['Sci-Fi']);
  });

  test('a server deletion removes the local book', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'gone', title: 'Doomed'));

    final client = _client(_server(books: const [], deletions: ['gone']));
    await SyncService(repo).pull(client);

    expect(await repo.watchBook('gone').first, isNull);
    // And it did NOT leave a local tombstone (the server already knows).
    expect(await db.select(db.localDeletions).get(), isEmpty);
  });

  test('push sends only books that need pushing, and clears the flag', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(
      BooksCompanion.insert(
        id: 'clean',
        title: 'Clean',
        needsPush: const Value(false),
      ),
    );
    // Default needsPush is true, so this one is dirty.
    await db.into(db.books).insert(BooksCompanion.insert(id: 'dirty', title: 'Dirty'));

    final pushed = <String>[];
    final client = _client((req) async {
      final path = req.url.path;
      if (req.method == 'PUT' &&
          path.startsWith('/api/books/') &&
          !path.endsWith('/cover')) {
        pushed.add(path.split('/').last);
        return http.Response('{}', 200);
      }
      if (req.method == 'GET' && path == '/api/deletions') {
        return http.Response('[]', 200);
      }
      return http.Response('[]', 200);
    });

    final n = await SyncService(repo).push(client);
    expect(pushed, ['dirty'], reason: 'clean book is skipped');
    expect(n, 1);
    expect((await repo.watchBook('dirty').first)?.needsPush, false);
  });

  test('pull clears the dirty flag on adopted books', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(
      BooksCompanion.insert(
        id: 'b1',
        title: 'Old local',
        updatedAt: Value(DateTime.utc(2024, 1, 1)),
      ),
    );

    final client = _client(
      _server(books: [_serverBook('b1', 'Newer server', '2025-01-01 00:00:00')]),
    );
    await SyncService(repo).pull(client);

    final b = await repo.watchBook('b1').first;
    expect(b?.title, 'Newer server');
    expect(b?.needsPush, false, reason: 'adopted rows have nothing local to push');
  });

  test('push propagates a local deletion then clears the tombstone', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'x', title: 'Delete me'));
    await repo.deleteBook(await repo.watchBook('x').first as Book);
    expect(await db.select(db.localDeletions).get(), isNotEmpty);

    final deleted = <String>[];
    final client = _client(_server(books: const [], deletedCollector: deleted));
    await SyncService(repo).push(client);

    expect(deleted, ['x'], reason: 'server delete should be called');
    expect(await db.select(db.localDeletions).get(), isEmpty, reason: 'tombstone cleared');
  });
}
