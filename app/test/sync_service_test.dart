import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
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

/// `{ server_now, shelves: [] }` — for the tests below that write their own
/// inline handler (predating shelf sync) and don't otherwise care about it.
http.Response _noShelves() => http.Response(
      jsonEncode({'server_now': '2024-01-01 00:00:00', 'shelves': []}),
      200,
    );

/// `{ server_now, copies: [] }` — same reasoning as [_noShelves], for tests
/// predating copy sync.
http.Response _noCopies() => http.Response(
      jsonEncode({'server_now': '2024-01-01 00:00:00', 'copies': []}),
      200,
    );

/// `{ server_now, loans: [] }` — same reasoning as [_noShelves], for tests
/// predating loan sync.
http.Response _noLoans() => http.Response(
      jsonEncode({'server_now': '2024-01-01 00:00:00', 'loans': []}),
      200,
    );

/// A JSON handler that serves a fixed book list + deletions, and empty file
/// lists, so pull's cover/file passes are no-ops. Shelves, copies, and loans
/// default to an empty list so tests that don't care about them (most of
/// this file) aren't affected by _pull/_push's unconditional passes.
Future<http.Response> Function(http.Request) _server({
  required List<Map<String, dynamic>> books,
  List<String> deletions = const [],
  List<String>? deletedCollector,
  List<Map<String, dynamic>> shelves = const [],
  List<String> shelfDeletions = const [],
  List<Map<String, dynamic>>? pushedShelvesCollector,
  List<String>? deletedShelvesCollector,
  List<Map<String, dynamic>> copies = const [],
  List<String> copyDeletions = const [],
  List<Map<String, dynamic>>? pushedCopiesCollector,
  List<String>? deletedCopiesCollector,
  List<Map<String, dynamic>> loans = const [],
  List<String> loanDeletions = const [],
  List<Map<String, dynamic>>? pushedLoansCollector,
  List<String>? deletedLoansCollector,
}) {
  return (req) async {
    final path = req.url.path;
    if (req.method == 'GET' && path == '/api/books') {
      return http.Response(
        jsonEncode({'server_now': '2024-06-01 00:00:00', 'books': books}),
        200,
      );
    }
    if (req.method == 'GET' && path == '/api/deletions') {
      final kind = req.url.queryParameters['kind'];
      final ids = switch (kind) {
        'shelf' => shelfDeletions,
        'copy' => copyDeletions,
        'loan' => loanDeletions,
        'book' => deletions,
        _ => [...deletions, ...shelfDeletions, ...copyDeletions, ...loanDeletions],
      };
      return http.Response(
        jsonEncode([for (final id in ids) {'book_id': id, 'deleted_at': '2020-01-01 00:00:00'}]),
        200,
      );
    }
    if (req.method == 'GET' && path == '/api/shelves') {
      return http.Response(
        jsonEncode({'server_now': '2024-06-01 00:00:00', 'shelves': shelves}),
        200,
      );
    }
    if (req.method == 'GET' && path == '/api/copies') {
      return http.Response(
        jsonEncode({'server_now': '2024-06-01 00:00:00', 'copies': copies}),
        200,
      );
    }
    if (req.method == 'GET' && path == '/api/loans') {
      return http.Response(
        jsonEncode({'server_now': '2024-06-01 00:00:00', 'loans': loans}),
        200,
      );
    }
    if (req.method == 'GET' && path.endsWith('/files')) {
      return http.Response('[]', 200);
    }
    if (req.method == 'PUT' && path.startsWith('/api/shelves/')) {
      pushedShelvesCollector?.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{}', 200);
    }
    if (req.method == 'DELETE' && path.startsWith('/api/shelves/')) {
      deletedShelvesCollector?.add(path.split('/').last);
      return http.Response('{}', 200);
    }
    if (req.method == 'PUT' && path.startsWith('/api/copies/')) {
      pushedCopiesCollector?.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{}', 200);
    }
    if (req.method == 'DELETE' && path.startsWith('/api/copies/')) {
      deletedCopiesCollector?.add(path.split('/').last);
      return http.Response('{}', 200);
    }
    if (req.method == 'PUT' && path.startsWith('/api/loans/')) {
      pushedLoansCollector?.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{}', 200);
    }
    if (req.method == 'DELETE' && path.startsWith('/api/loans/')) {
      deletedLoansCollector?.add(path.split('/').last);
      return http.Response('{}', 200);
    }
    if (req.method == 'DELETE' && path.startsWith('/api/books/')) {
      deletedCollector?.add(path.split('/').last);
      return http.Response('{}', 200);
    }
    return http.Response('{"error":"unexpected ${req.method} $path"}', 404);
  };
}

Map<String, dynamic> _serverShelf(
  String id,
  String name,
  List<String> bookIds, {
  String? updatedAt,
  int sortOrder = 0,
}) => {
  'id': id,
  'name': name,
  'sort_order': sortOrder,
  'book_ids': bookIds,
  'updated_at': ?updatedAt,
};

Map<String, dynamic> _serverCopy(
  String id,
  String bookId, {
  String? location,
  String? updatedAt,
}) => {
  'id': id,
  'book_id': bookId,
  'location': location,
  'updated_at': ?updatedAt,
};

Map<String, dynamic> _serverLoan(
  String id,
  String copyId, {
  required String borrower,
  required String loanedAt,
  String? returnedAt,
  String? updatedAt,
}) => {
  'id': id,
  'copy_id': copyId,
  'borrower': borrower,
  'loaned_at': loanedAt,
  'returned_at': ?returnedAt,
  'updated_at': ?updatedAt,
};

/// A push-side handler for the batch metadata push (plan 5 #7). Advertises
/// [features] on `/api/capabilities`, records each batch body in
/// [batchCollector] and each per-book PUT id in [putCollector] — so a test can
/// tell the batch path and its per-book fallback apart by which one filled up.
/// Anything else falls through to [_server] with an empty library.
///
/// [batchHttpStatus] simulates a batch endpoint that fails outright,
/// [statusOverrides] a per-item non-default outcome (`{'status': 'error',
/// 'message': …}`), and [omitFromResults] a server that answers without
/// mentioning an id at all.
Future<http.Response> Function(http.Request) _batchPushServer({
  List<String> features = const ['batch_push'],
  List<List<Map<String, dynamic>>>? batchCollector,
  List<String>? putCollector,
  List<String>? probeCollector,
  int batchHttpStatus = 200,
  Map<String, Map<String, dynamic>> statusOverrides = const {},
  Set<String> omitFromResults = const {},
}) {
  final fallback = _server(books: const []);
  return (req) async {
    final path = req.url.path;
    if (req.method == 'GET' && path == '/api/capabilities') {
      probeCollector?.add(path);
      return http.Response(
        jsonEncode({
          'server_version': '0.0.0-test',
          'sync_protocol': 1,
          'features': features,
        }),
        200,
      );
    }
    if (req.method == 'POST' && path == '/api/books:batch') {
      if (batchHttpStatus != 200) {
        return http.Response('{"error":"batch unavailable"}', batchHttpStatus);
      }
      final items = [
        for (final b in (jsonDecode(req.body) as Map<String, dynamic>)['books'] as List)
          b as Map<String, dynamic>,
      ];
      batchCollector?.add(items);
      final results = <Map<String, dynamic>>[];
      for (final item in items) {
        final id = item['id'] as String;
        if (omitFromResults.contains(id)) continue;
        results.add({'id': id, ...?statusOverrides[id]});
        if (statusOverrides[id] == null) results.last['status'] = 'updated';
      }
      return http.Response(jsonEncode({'results': results}), 200);
    }
    if (req.method == 'PUT' &&
        path.startsWith('/api/books/') &&
        !path.endsWith('/cover')) {
      putCollector?.add(path.split('/').last);
      return http.Response('{}', 200);
    }
    return fallback(req);
  };
}

/// Inserts [count] dirty books named `b0…b{count-1}`.
Future<void> _insertDirtyBooks(VellumDatabase db, int count) =>
    db.batch((b) => b.insertAll(db.books, [
          for (var i = 0; i < count; i++)
            BooksCompanion.insert(id: 'b$i', title: 'Book $i'),
        ]));

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

    final report = await SyncService(repo).pull(client);
    expect(report.pulled, 1);
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
    // Genres are canonicalized (Title Case) on write, so the shelf's genre set
    // stays tidy regardless of how the server cased them.
    expect(details.genres, ['Sci-fi']);
  });

  test('pull sends the cursor and persists the new server clock', () async {
    final repo = await _repo(dir);
    String? sentCursor;
    String? sentSince;
    String? stored;
    final client = _client((req) async {
      final path = req.url.path;
      if (req.method == 'GET' && path == '/api/books') {
        sentCursor = req.url.queryParameters['cursor'];
        return http.Response(
          jsonEncode({
            'server_now': '2025-06-01 12:00:00',
            'books': [_serverBook('b1', 'Dune', '2025-01-01 00:00:00')],
          }),
          200,
        );
      }
      if (req.method == 'GET' && path == '/api/deletions') {
        sentSince = req.url.queryParameters['since'];
        return http.Response('[]', 200);
      }
      if (req.method == 'GET' && req.url.path == '/api/shelves') return _noShelves();
      if (req.method == 'GET' && req.url.path == '/api/copies') return _noCopies();
      if (req.method == 'GET' && req.url.path == '/api/loans') return _noLoans();
      return http.Response('[]', 200);
    });

    await SyncService(
      repo,
    ).pull(client, cursor: 'CUR', onCursor: (n) => stored = n);
    expect(sentCursor, 'CUR', reason: 'books request carries the cursor');
    expect(sentSince, 'CUR', reason: 'deletions request carries the cursor');
    expect(stored, '2025-06-01 12:00:00', reason: 'new server clock persisted');
  });

  test('pull downloads files from the inline list, not a per-book call', () async {
    final repo = await _repo(dir);
    var perBookFilesCalled = false;
    final client = _client((req) async {
      final path = req.url.path;
      if (req.method == 'GET' && path == '/api/books') {
        return http.Response(
          jsonEncode({
            'server_now': '2024-06-01 00:00:00',
            'books': [
              {
                'id': 'b1',
                'title': 'Dune',
                'updated_at': '2024-01-01 00:00:00',
                'files': [
                  {
                    'id': 'f1',
                    'book_id': 'b1',
                    'format': 'pdf',
                    'size_bytes': 5,
                    'sha256': 'abc',
                  },
                ],
              },
            ],
          }),
          200,
        );
      }
      if (req.method == 'GET' && path.endsWith('/files')) {
        perBookFilesCalled = true;
        return http.Response('[]', 200);
      }
      if (req.method == 'GET' && path == '/api/files/f1') {
        return http.Response('hello', 200);
      }
      if (req.method == 'GET' && req.url.path == '/api/shelves') return _noShelves();
      if (req.method == 'GET' && req.url.path == '/api/copies') return _noCopies();
      if (req.method == 'GET' && req.url.path == '/api/loans') return _noLoans();
      return http.Response('[]', 200);
    });

    await SyncService(repo).pull(client);

    expect(perBookFilesCalled, false, reason: 'no per-book files round-trip');
    final files = await repo.db.select(repo.db.bookFiles).get();
    expect(files.length, 1);
    expect(files.first.sha256, 'abc');
  });

  test('a server-supplied unsafe file id is skipped, not written to disk', () async {
    final repo = await _repo(dir);
    var fileDownloaded = false;
    final client = _client((req) async {
      final path = req.url.path;
      if (req.method == 'GET' && path == '/api/books') {
        return http.Response(
          jsonEncode({
            'server_now': '2024-06-01 00:00:00',
            'books': [
              {
                'id': 'b1',
                'title': 'Dune',
                'updated_at': '2024-01-01 00:00:00',
                'files': [
                  {
                    // A malicious/compromised server tries to steer the write
                    // outside files/ via path traversal.
                    'id': '../../evil',
                    'book_id': 'b1',
                    'format': 'pdf',
                    'size_bytes': 5,
                    'sha256': 'abc',
                  },
                ],
              },
            ],
          }),
          200,
        );
      }
      if (req.method == 'GET' && path.startsWith('/api/files/')) {
        fileDownloaded = true;
        return http.Response('hello', 200);
      }
      if (req.method == 'GET' && req.url.path == '/api/shelves') return _noShelves();
      if (req.method == 'GET' && req.url.path == '/api/copies') return _noCopies();
      if (req.method == 'GET' && req.url.path == '/api/loans') return _noLoans();
      return http.Response('[]', 200);
    });

    final report = await SyncService(repo).pull(client);
    expect(fileDownloaded, false, reason: 'the unsafe file is never fetched');
    expect(await repo.db.select(repo.db.bookFiles).get(), isEmpty,
        reason: 'no file row is recorded for a traversal id');
    expect(report.issues.any((i) => i.stage == 'file'), true,
        reason: 'the skip is surfaced as an issue');
  });

  test('a failed cover download is recorded as an issue, not swallowed', () async {
    final repo = await _repo(dir);
    final client = _client((req) async {
      final path = req.url.path;
      if (req.method == 'GET' && path == '/api/books') {
        return http.Response(
          jsonEncode({
            'server_now': '2024-06-01 00:00:00',
            'books': [
              {
                'id': 'b1',
                'title': 'Dune',
                'updated_at': '2024-01-01 00:00:00',
                'cover_path': 'covers/b1.jpg',
              },
            ],
          }),
          200,
        );
      }
      if (req.method == 'GET' && path.endsWith('/cover')) {
        return http.Response('boom', 500); // cover download fails
      }
      if (req.method == 'GET' && req.url.path == '/api/shelves') return _noShelves();
      if (req.method == 'GET' && req.url.path == '/api/copies') return _noCopies();
      if (req.method == 'GET' && req.url.path == '/api/loans') return _noLoans();
      return http.Response('[]', 200);
    });

    final report = await SyncService(repo).pull(client);
    expect(report.pulled, 1, reason: 'metadata still applied');
    expect(report.issues, isNotEmpty);
    expect(report.issues.first.stage, 'cover');
  });

  test('a second concurrent sync throws instead of overlapping', () async {
    final repo = await _repo(dir);
    final gate = Completer<void>();
    final client = _client((req) async {
      if (req.url.path == '/api/books') {
        await gate.future; // hold the first pull open
        return http.Response(
          jsonEncode({'server_now': 'x', 'books': []}),
          200,
        );
      }
      if (req.method == 'GET' && req.url.path == '/api/shelves') return _noShelves();
      if (req.method == 'GET' && req.url.path == '/api/copies') return _noCopies();
      if (req.method == 'GET' && req.url.path == '/api/loans') return _noLoans();
      return http.Response('[]', 200);
    });

    final sync = SyncService(repo);
    final first = sync.pull(client);
    await expectLater(() => sync.pull(client), throwsStateError);
    gate.complete();
    await first;
  });

  test('sync pulls then pushes in one run and merges the reports', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    // A dirty local book to push (needsPush defaults true)...
    await db.into(db.books).insert(BooksCompanion.insert(id: 'mine', title: 'Local'));

    // ...and a server book to pull.
    final pushed = <String>[];
    final client = _client((req) async {
      final path = req.url.path;
      if (req.method == 'GET' && path == '/api/books') {
        return http.Response(
          jsonEncode({
            'server_now': '2024-06-01 00:00:00',
            'books': [_serverBook('theirs', 'Remote', '2024-01-01 00:00:00')],
          }),
          200,
        );
      }
      if (req.method == 'PUT' &&
          path.startsWith('/api/books/') &&
          !path.endsWith('/cover')) {
        pushed.add(path.split('/').last);
        return http.Response('{}', 200);
      }
      if (req.method == 'GET' && req.url.path == '/api/shelves') return _noShelves();
      if (req.method == 'GET' && req.url.path == '/api/copies') return _noCopies();
      if (req.method == 'GET' && req.url.path == '/api/loans') return _noLoans();
      return http.Response('[]', 200);
    });

    final report = await SyncService(repo).sync(client);
    expect(report.pulled, 1);
    expect(report.pushed, 1);
    expect(pushed, ['mine']);
    expect((await repo.watchBook('theirs').first)?.title, 'Remote');
  });

  test('a sync blocks a concurrent pull under the same guard', () async {
    final repo = await _repo(dir);
    final gate = Completer<void>();
    final client = _client((req) async {
      if (req.url.path == '/api/books') {
        await gate.future;
        return http.Response(jsonEncode({'server_now': 'x', 'books': []}), 200);
      }
      if (req.method == 'GET' && req.url.path == '/api/shelves') return _noShelves();
      if (req.method == 'GET' && req.url.path == '/api/copies') return _noCopies();
      if (req.method == 'GET' && req.url.path == '/api/loans') return _noLoans();
      return http.Response('[]', 200);
    });

    final sync = SyncService(repo);
    final first = sync.sync(client);
    await expectLater(() => sync.pull(client), throwsStateError);
    gate.complete();
    await first;
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
      if (req.method == 'GET' && req.url.path == '/api/shelves') return _noShelves();
      if (req.method == 'GET' && req.url.path == '/api/copies') return _noCopies();
      if (req.method == 'GET' && req.url.path == '/api/loans') return _noLoans();
      return http.Response('[]', 200);
    });

    final report = await SyncService(repo).push(client);
    expect(pushed, ['dirty'], reason: 'clean book is skipped');
    expect(report.pushed, 1);
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

  test('cover pull stores the ETag, then revalidates with 304', () async {
    final repo = await _repo(dir);
    var coverRequests = 0;
    var sentBytes = 0;
    // A cover server that returns the art with an ETag, and 304 when the
    // client presents that same ETag on a later request.
    http.Response handler(http.Request req) {
      final path = req.url.path;
      if (req.method == 'GET' && path == '/api/books') {
        return http.Response(
          jsonEncode({
            'server_now': '2024-06-01 00:00:00',
            'books': [
              {
                ..._serverBook('b1', 'Dune', '2024-01-01 00:00:00'),
                'cover_path': 'covers/b1.jpg',
              },
            ],
          }),
          200,
        );
      }
      if (req.method == 'GET' && path == '/api/deletions') return http.Response('[]', 200);
      if (req.method == 'GET' && path == '/api/shelves') {
        return http.Response(
          jsonEncode({'server_now': '2024-06-01 00:00:00', 'shelves': []}),
          200,
        );
      }
      if (req.method == 'GET' && path == '/api/copies') {
        return http.Response(
          jsonEncode({'server_now': '2024-06-01 00:00:00', 'copies': []}),
          200,
        );
      }
      if (req.method == 'GET' && path == '/api/loans') {
        return http.Response(
          jsonEncode({'server_now': '2024-06-01 00:00:00', 'loans': []}),
          200,
        );
      }
      if (req.method == 'GET' && path == '/api/books/b1/cover') {
        coverRequests++;
        if (req.headers['if-none-match'] == '"v1"') {
          return http.Response('', 304, headers: {'etag': '"v1"'});
        }
        sentBytes++;
        return http.Response.bytes(
          [1, 2, 3, 4],
          200,
          headers: {'etag': '"v1"', 'content-type': 'image/jpeg'},
        );
      }
      return http.Response('{"error":"unexpected $path"}', 404);
    }

    final client = _client((req) async => handler(req));
    await SyncService(repo).pull(client);
    var book = await repo.watchBook('b1').first;
    expect(book?.coverEtag, '"v1"', reason: 'ETag stored after first download');
    expect(sentBytes, 1);

    // Second pull: the stored ETag is sent, the server 304s, no re-download.
    await SyncService(repo).pull(client);
    book = await repo.watchBook('b1').first;
    expect(sentBytes, 1, reason: 'unchanged cover is not re-downloaded');
    expect(coverRequests, 2, reason: 'but it is revalidated each pull');
  });

  // ---- shelves (plan 5 #4) --------------------------------------------

  test('pull adopts a shelf, preserving explicit book order', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    for (final id in ['b1', 'b2', 'b3']) {
      await db.into(db.books).insert(BooksCompanion.insert(id: id, title: id));
    }
    final client = _client(_server(
      books: const [],
      shelves: [_serverShelf('sh-1', 'To read', ['b3', 'b1', 'b2'], updatedAt: '2024-01-01 00:00:00')],
    ));

    final report = await SyncService(repo).pull(client);
    expect(report.pulled, 1);

    final members = await (db.select(db.shelfBooks)
          ..where((sb) => sb.shelfId.equals('sh-1'))
          ..orderBy([(sb) => OrderingTerm.asc(sb.position)]))
        .get();
    expect(members.map((m) => m.bookId), ['b3', 'b1', 'b2']);
    final shelf = await (db.select(db.shelves)..where((s) => s.id.equals('sh-1'))).getSingle();
    expect(shelf.needsPush, false, reason: 'adopting the server copy leaves nothing to push');
  });

  test('pull drops shelf membership for books this device does not have', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'b1'));
    // 'b2' is intentionally never inserted locally.
    final client = _client(_server(
      books: const [],
      shelves: [_serverShelf('sh-1', 'Mixed', ['b1', 'b2'], updatedAt: '2024-01-01 00:00:00')],
    ));

    await SyncService(repo).pull(client);

    final members = await (db.select(db.shelfBooks)..where((sb) => sb.shelfId.equals('sh-1'))).get();
    expect(members.map((m) => m.bookId), ['b1']);
  });

  test('pull does not clobber a locally newer shelf edit', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.shelves).insert(ShelvesCompanion.insert(
          id: 'sh-1',
          name: 'Local name',
          updatedAt: Value(DateTime.utc(2025, 1, 1)),
        ));
    final client = _client(_server(
      books: const [],
      shelves: [_serverShelf('sh-1', 'Server name', const [], updatedAt: '2024-01-01 00:00:00')],
    ));

    await SyncService(repo).pull(client);

    final shelf = await (db.select(db.shelves)..where((s) => s.id.equals('sh-1'))).getSingle();
    expect(shelf.name, 'Local name', reason: 'local edit is newer, must win');
  });

  test('pull applies a shelf tombstone locally', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.shelves).insert(ShelvesCompanion.insert(id: 'sh-1', name: 'Gone'));
    final client = _client(_server(books: const [], shelfDeletions: ['sh-1']));

    final report = await SyncService(repo).pull(client);
    expect(report.deletedLocally, 1);
    expect(await (db.select(db.shelves)..where((s) => s.id.equals('sh-1'))).get(), isEmpty);
    expect(await db.select(db.localDeletions).get(), isEmpty,
        reason: 'a server-driven delete must not be recorded to push back');
  });

  test('push sends a dirty shelf with its full ordered membership', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    for (final id in ['b1', 'b2']) {
      await db.into(db.books).insert(BooksCompanion.insert(id: id, title: id));
    }
    final shelfId = await repo.createShelf('Mine');
    await repo.addToShelf('b2', shelfId);
    await repo.addToShelf('b1', shelfId);

    final pushed = <Map<String, dynamic>>[];
    final client = _client(_server(books: const [], pushedShelvesCollector: pushed));

    final report = await SyncService(repo).push(client);
    expect(report.pushed, 1);
    expect(pushed, hasLength(1));
    expect(pushed.single['book_ids'], ['b2', 'b1']);

    final shelf = await (db.select(db.shelves)..where((s) => s.id.equals(shelfId))).getSingle();
    expect(shelf.needsPush, false);
  });

  test('push propagates a local shelf deletion then clears the tombstone', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    final shelfId = await repo.createShelf('Temp');
    await repo.deleteShelf(shelfId);

    final deletedShelves = <String>[];
    final client = _client(_server(books: const [], deletedShelvesCollector: deletedShelves));
    await SyncService(repo).push(client);

    expect(deletedShelves, [shelfId]);
    expect(await db.select(db.localDeletions).get(), isEmpty);
  });

  // ---- physical copies (plan 5 #4) -------------------------------------

  test('pull adopts a copy for a book this device has', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'b1'));
    final client = _client(_server(
      books: const [],
      copies: [
        _serverCopy('c1', 'b1', location: 'Shelf 3', updatedAt: '2024-01-01 00:00:00'),
      ],
    ));

    final report = await SyncService(repo).pull(client);
    expect(report.pulled, 1);

    final copy =
        await (db.select(db.physicalCopies)..where((c) => c.id.equals('c1'))).getSingle();
    expect(copy.location, 'Shelf 3');
    expect(copy.needsPush, false, reason: 'adopting the server copy leaves nothing to push');
  });

  test('pull records an issue (not a silent skip) for a copy naming a book '
      'this device does not have', () async {
    // A silent skip would be permanent: the cursor still advances past this
    // pull window, so an unflagged copy would never be retried again.
    final repo = await _repo(dir);
    final db = repo.db;
    // 'b1' is intentionally never inserted locally.
    final client = _client(_server(
      books: const [],
      copies: [_serverCopy('c1', 'b1', updatedAt: '2024-01-01 00:00:00')],
    ));

    final report = await SyncService(repo).pull(client);

    expect(await db.select(db.physicalCopies).get(), isEmpty);
    expect(report.issues, hasLength(1));
    expect(report.issues.single.stage, 'copy');
    expect(report.issues.single.bookId, 'c1');
  });

  test('pull does not clobber a locally newer copy edit', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'b1'));
    await db.into(db.physicalCopies).insert(PhysicalCopiesCompanion.insert(
          id: 'c1',
          bookId: 'b1',
          location: const Value('Local desk'),
          updatedAt: Value(DateTime.utc(2025, 1, 1)),
        ));
    final client = _client(_server(
      books: const [],
      copies: [
        _serverCopy('c1', 'b1', location: 'Server shelf', updatedAt: '2024-01-01 00:00:00'),
      ],
    ));

    await SyncService(repo).pull(client);

    final copy =
        await (db.select(db.physicalCopies)..where((c) => c.id.equals('c1'))).getSingle();
    expect(copy.location, 'Local desk', reason: 'local edit is newer, must win');
  });

  test('pull applies a copy tombstone locally', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'b1'));
    await db
        .into(db.physicalCopies)
        .insert(PhysicalCopiesCompanion.insert(id: 'c1', bookId: 'b1'));
    final client = _client(_server(books: const [], copyDeletions: ['c1']));

    final report = await SyncService(repo).pull(client);
    expect(report.deletedLocally, 1);
    expect(await (db.select(db.physicalCopies)..where((c) => c.id.equals('c1'))).get(), isEmpty);
    expect(await db.select(db.localDeletions).get(), isEmpty,
        reason: 'a server-driven delete must not be recorded to push back');
  });

  test('push sends a dirty copy', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'b1'));
    final copyId = await repo.addPhysicalCopy('b1', location: 'Desk');

    final pushed = <Map<String, dynamic>>[];
    final client = _client(_server(books: const [], pushedCopiesCollector: pushed));

    final report = await SyncService(repo).push(client);
    expect(report.pushed, 1);
    expect(pushed, hasLength(1));
    expect(pushed.single['book_id'], 'b1');
    expect(pushed.single['location'], 'Desk');

    final copy =
        await (db.select(db.physicalCopies)..where((c) => c.id.equals(copyId))).getSingle();
    expect(copy.needsPush, false);
  });

  test('push propagates a local copy deletion then clears the tombstone', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'b1'));
    final copyId = await repo.addPhysicalCopy('b1');
    await repo.deletePhysicalCopy(copyId);

    final deletedCopies = <String>[];
    final client = _client(_server(books: const [], deletedCopiesCollector: deletedCopies));
    await SyncService(repo).push(client);

    expect(deletedCopies, [copyId]);
    expect(await db.select(db.localDeletions).get(), isEmpty);
  });

  // ---- loans (plan 5 #4) -------------------------------------------------

  test('pull adopts a loan for a copy this device has', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'b1'));
    await db
        .into(db.physicalCopies)
        .insert(PhysicalCopiesCompanion.insert(id: 'c1', bookId: 'b1'));
    final client = _client(_server(
      books: const [],
      loans: [
        _serverLoan('l1', 'c1',
            borrower: 'Alice',
            loanedAt: '2024-01-01 00:00:00',
            updatedAt: '2024-01-01 00:00:00'),
      ],
    ));

    final report = await SyncService(repo).pull(client);
    expect(report.pulled, 1);

    final loan = await (db.select(db.loans)..where((l) => l.id.equals('l1'))).getSingle();
    expect(loan.borrower, 'Alice');
    expect(loan.needsPush, false, reason: 'adopting the server copy leaves nothing to push');
  });

  test('pull records an issue (not a silent skip) for a loan naming a copy '
      'this device does not have', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    // 'c1' is intentionally never inserted locally.
    final client = _client(_server(
      books: const [],
      loans: [
        _serverLoan('l1', 'c1',
            borrower: 'Alice',
            loanedAt: '2024-01-01 00:00:00',
            updatedAt: '2024-01-01 00:00:00'),
      ],
    ));

    final report = await SyncService(repo).pull(client);

    expect(await db.select(db.loans).get(), isEmpty);
    expect(report.issues, hasLength(1));
    expect(report.issues.single.stage, 'loan');
    expect(report.issues.single.bookId, 'l1');
  });

  test('pull does not clobber a locally newer return', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'b1'));
    await db
        .into(db.physicalCopies)
        .insert(PhysicalCopiesCompanion.insert(id: 'c1', bookId: 'b1'));
    await db.into(db.loans).insert(LoansCompanion.insert(
          id: 'l1',
          copyId: 'c1',
          borrower: 'Alice',
          returnedAt: Value(DateTime.utc(2025, 6, 1)),
          updatedAt: Value(DateTime.utc(2025, 1, 1)),
        ));
    final client = _client(_server(
      books: const [],
      loans: [
        _serverLoan('l1', 'c1',
            borrower: 'Alice',
            loanedAt: '2024-01-01 00:00:00',
            updatedAt: '2024-01-01 00:00:00'),
      ],
    ));

    await SyncService(repo).pull(client);

    final loan = await (db.select(db.loans)..where((l) => l.id.equals('l1'))).getSingle();
    expect(loan.returnedAt, isNotNull, reason: 'local return is newer, must win');
  });

  test('push sends a dirty loan', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    // needsPush: false -- this test is about the loan push, not the book's;
    // _server() has no /api/books PUT stub, so a dirty book here would add
    // an unrelated issue to the report.
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'b1',
          title: 'b1',
          needsPush: const Value(false),
        ));
    final copyId = await repo.addPhysicalCopy('b1');
    await (db.update(db.physicalCopies)..where((c) => c.id.equals(copyId)))
        .write(const PhysicalCopiesCompanion(needsPush: Value(false)));
    await repo.lendCopy(copyId, 'Alice');

    final pushed = <Map<String, dynamic>>[];
    final client = _client(_server(books: const [], pushedLoansCollector: pushed));

    final report = await SyncService(repo).push(client);
    expect(pushed, hasLength(1));
    expect(pushed.single['copy_id'], copyId);
    expect(pushed.single['borrower'], 'Alice');
    expect(pushed.single['returned_at'], isNull);
    expect(report.issues, isEmpty);

    final loan =
        await (db.select(db.loans)..where((l) => l.copyId.equals(copyId))).getSingle();
    expect(loan.needsPush, false);
  });

  test('returnLoan dirties the loan so a return actually pushes', () async {
    // Regression risk: returnLoan is a db.update, and column defaults (which
    // cover lendCopy's insert) don't re-run on one -- an unbumped return
    // would silently never reach the server.
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'b1'));
    final copyId = await repo.addPhysicalCopy('b1');
    await repo.lendCopy(copyId, 'Alice');
    final loanId =
        (await (db.select(db.loans)..where((l) => l.copyId.equals(copyId))).getSingle()).id;
    await (db.update(db.loans)..where((l) => l.id.equals(loanId)))
        .write(const LoansCompanion(needsPush: Value(false)));

    await repo.returnLoan(loanId);

    final loan = await (db.select(db.loans)..where((l) => l.id.equals(loanId))).getSingle();
    expect(loan.needsPush, true);
    expect(loan.returnedAt, isNotNull);
  });

  // ---- Batch metadata push (plan 5 #7) --------------------------------------

  test('push sends metadata in one batch when the server advertises it', () async {
    final repo = await _repo(dir);
    await _insertDirtyBooks(repo.db, 3);

    final batches = <List<Map<String, dynamic>>>[];
    final puts = <String>[];
    final client = _client(
      _batchPushServer(batchCollector: batches, putCollector: puts),
    );

    final report = await SyncService(repo).push(client);

    expect(batches, hasLength(1), reason: 'three books, one round trip');
    expect(
      [for (final item in batches.single) item['id']],
      ['b0', 'b1', 'b2'],
    );
    expect(puts, isEmpty, reason: 'the per-book PUT path must not also run');
    expect(report.pushed, 3);
    expect(report.issues, isEmpty);
    for (final b in await repo.db.select(repo.db.books).get()) {
      expect(b.needsPush, false);
    }
  });

  test('the batch carries the same fields a per-book PUT would', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'b1',
          title: 'Dune',
          subtitle: const Value('A novel'),
          isbn: const Value('9780441013593'),
          publishedYear: const Value(1965),
          updatedAt: Value(DateTime.utc(2024, 5, 4, 3, 2, 1)),
        ));
    // A second dirty book only so the push is worth batching at all.
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b2', title: 'Other'));
    await repo.setAuthors('b1', ['Frank Herbert']);
    await repo.setGenres('b1', ['Science fiction']);

    final batches = <List<Map<String, dynamic>>>[];
    final client = _client(_batchPushServer(batchCollector: batches));
    await SyncService(repo).push(client);

    final sent = batches.single.firstWhere((i) => i['id'] == 'b1');
    expect(sent['title'], 'Dune');
    expect(sent['subtitle'], 'A novel');
    expect(sent['isbn'], '9780441013593');
    expect(sent['published_year'], 1965);
    expect(sent['updated_at'], '2024-05-04 03:02:01');
    expect(sent['authors'], ['Frank Herbert']);
    // Title-cased by the repository on the way in, not by the push.
    expect(sent['genres'], ['Science Fiction']);
  });

  test('push chunks a batch to the server cap of 200', () async {
    final repo = await _repo(dir);
    await _insertDirtyBooks(repo.db, 205);

    final batches = <List<Map<String, dynamic>>>[];
    final puts = <String>[];
    final client = _client(
      _batchPushServer(batchCollector: batches, putCollector: puts),
    );

    final report = await SyncService(repo).push(client);

    expect([for (final b in batches) b.length], [200, 5]);
    expect(puts, isEmpty);
    expect(report.pushed, 205);
  });

  test('a per-item batch error becomes a SyncIssue and stays dirty', () async {
    final repo = await _repo(dir);
    await _insertDirtyBooks(repo.db, 2);

    final client = _client(_batchPushServer(statusOverrides: {
      'b1': {'status': 'error', 'message': 'you have read-only access'},
    }));

    final report = await SyncService(repo).push(client);

    expect(report.pushed, 1);
    expect(report.issues, hasLength(1));
    expect(report.issues.single.bookId, 'b1');
    expect(report.issues.single.stage, 'push');
    expect(report.issues.single.message, 'you have read-only access');
    expect((await repo.watchBook('b0').first)?.needsPush, false);
    expect(
      (await repo.watchBook('b1').first)?.needsPush,
      true,
      reason: 'a rejected book must stay dirty so the next push retries it',
    );
  });

  test('skipped_older counts as pushed — the server is already ahead', () async {
    final repo = await _repo(dir);
    await _insertDirtyBooks(repo.db, 2);

    final client = _client(_batchPushServer(statusOverrides: {
      'b1': {'status': 'skipped_older'},
    }));

    final report = await SyncService(repo).push(client);

    expect(report.pushed, 2);
    expect(report.issues, isEmpty);
    expect((await repo.watchBook('b1').first)?.needsPush, false);
  });

  test('a book missing from the batch response is treated as a failure', () async {
    final repo = await _repo(dir);
    await _insertDirtyBooks(repo.db, 2);

    final client = _client(_batchPushServer(omitFromResults: {'b1'}));

    final report = await SyncService(repo).push(client);

    expect(report.pushed, 1);
    expect(report.issues.single.bookId, 'b1');
    expect((await repo.watchBook('b1').first)?.needsPush, true);
  });

  test('a server without batch_push falls back to per-book PUTs', () async {
    final repo = await _repo(dir);
    await _insertDirtyBooks(repo.db, 2);

    final batches = <List<Map<String, dynamic>>>[];
    final puts = <String>[];
    final client = _client(_batchPushServer(
      features: const ['delta_pull'],
      batchCollector: batches,
      putCollector: puts,
    ));

    final report = await SyncService(repo).push(client);

    expect(batches, isEmpty);
    expect(puts, ['b0', 'b1']);
    expect(report.pushed, 2);
    expect(report.issues, isEmpty);
  });

  test('a batch endpoint that fails outright falls back to per-book PUTs', () async {
    // The capability says yes but the call fails (a proxy, a rollback, a bug):
    // the push must still succeed rather than fail every book at once.
    final repo = await _repo(dir);
    await _insertDirtyBooks(repo.db, 2);

    final puts = <String>[];
    final client = _client(_batchPushServer(
      putCollector: puts,
      batchHttpStatus: 500,
    ));

    final report = await SyncService(repo).push(client);

    expect(puts, ['b0', 'b1']);
    expect(report.pushed, 2);
    expect(report.issues, isEmpty);
  });

  test('a single dirty book skips the handshake and the batch entirely', () async {
    // One book is already one request; probing capabilities to save nothing
    // would make the common auto-push case slower, not faster.
    final repo = await _repo(dir);
    await _insertDirtyBooks(repo.db, 1);

    final probes = <String>[];
    final batches = <List<Map<String, dynamic>>>[];
    final puts = <String>[];
    final client = _client(_batchPushServer(
      probeCollector: probes,
      batchCollector: batches,
      putCollector: puts,
    ));

    await SyncService(repo).push(client);

    expect(probes, isEmpty);
    expect(batches, isEmpty);
    expect(puts, ['b0']);
  });

  test('the capability handshake is memoized across pushes', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await _insertDirtyBooks(db, 2);

    final probes = <String>[];
    final client = _client(_batchPushServer(probeCollector: probes));
    final sync = SyncService(repo);

    await sync.push(client);
    // Dirty them again, as an edit would, and push the same service again.
    await db.update(db.books).write(const BooksCompanion(needsPush: Value(true)));
    await sync.push(client);

    expect(probes, hasLength(1), reason: 'one handshake, not one per push');
  });
}
