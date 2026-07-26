// The optional cross-device reading position (plan 5 #5). Two things are worth
// pinning here: the *offer* logic (when does another device's position deserve
// a prompt, and when would jumping be a lie?) and the sync pass's contract with
// the opt-in — nothing published unless asked, this device's own row never
// mistaken for a remote one, and switching off leaving nothing behind.

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

Future<LibraryRepository> _repo(Directory dir) async =>
    LibraryRepository.forTesting(VellumDatabase(NativeDatabase.memory()), dir);

VellumServerClient _client(Future<http.Response> Function(http.Request) handler) =>
    VellumServerClient(
      baseUrl: 'http://test',
      token: 't',
      httpClient: MockClient(handler),
    );

/// A server that serves [entries] from the reading-position endpoint and
/// records what gets pushed to (and deleted from) it.
Future<http.Response> Function(http.Request) _progressServer({
  List<Map<String, dynamic>> entries = const [],
  List<Map<String, dynamic>>? pushCollector,
  List<String>? forgetCollector,
  String serverNow = '2026-07-01 00:00:00',
}) {
  return (req) async {
    final path = req.url.path;
    if (req.method == 'GET' && path == '/api/reading-progress') {
      return http.Response(
        jsonEncode({'server_now': serverNow, 'entries': entries}),
        200,
      );
    }
    if (req.method == 'PUT' && path.startsWith('/api/reading-progress/')) {
      pushCollector?.add({
        'book_id': path.split('/').last,
        ...jsonDecode(req.body) as Map<String, dynamic>,
      });
      return http.Response('{}', 200);
    }
    if (req.method == 'DELETE' && path == '/api/reading-progress') {
      forgetCollector?.add(req.url.queryParameters['device_id'] ?? '');
      return http.Response('{"deleted":0}', 200);
    }
    return http.Response('{"error":"unexpected ${req.method} $path"}', 404);
  };
}

Map<String, dynamic> _entry(
  String bookId,
  String deviceId, {
  String? label,
  double? progress,
  int? page,
  String? unit,
  String updatedAt = '2026-06-01 00:00:00',
}) => {
  'book_id': bookId,
  'device_id': deviceId,
  'device_label': label,
  'progress': progress,
  'page': page,
  'unit': unit,
  'updated_at': updatedAt,
};

/// A cached remote row, as the sync pass would have written it.
Future<void> _cacheRemote(
  VellumDatabase db, {
  required String bookId,
  required String deviceId,
  String? label,
  double? progress,
  int? page,
  String? unit,
}) => db.into(db.remoteReadingPositions).insert(
      RemoteReadingPositionsCompanion.insert(
        bookId: bookId,
        deviceId: deviceId,
        deviceLabel: Value(label),
        progress: Value(progress),
        page: Value(page),
        unit: Value(unit),
        updatedAt: DateTime.utc(2026, 6),
      ),
    );

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_reading_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Book> seedBook(
    LibraryRepository repo, {
    double? progress,
    int? page,
  }) async {
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'b1',
          title: 'Dune',
          readingProgress: Value(progress),
          lastReadPage: Value(page),
          lastReadAt: Value(progress == null ? null : DateTime.utc(2026, 5)),
        ));
    return (await repo.watchBook('b1').first)!;
  }

  // ---- the jump offer -------------------------------------------------------

  test('offers the furthest-ahead remote position', () async {
    final repo = await _repo(dir);
    final book = await seedBook(repo, progress: 0.2, page: 40);
    final positions = repo.readingPositions;

    final offer = positions.offerFor(
      book: book,
      localUnit: 'page',
      remotes: [
        RemoteReadingPosition(
          bookId: 'b1',
          deviceId: 'phone',
          deviceLabel: 'phone',
          progress: 0.4,
          page: 90,
          unit: 'page',
          updatedAt: DateTime.utc(2026, 6),
        ),
        RemoteReadingPosition(
          bookId: 'b1',
          deviceId: 'desktop',
          deviceLabel: 'desktop',
          progress: 0.72,
          page: 214,
          unit: 'page',
          updatedAt: DateTime.utc(2026, 5),
        ),
      ],
    );

    expect(offer, isNotNull);
    expect(offer!.page, 214);
    expect(offer.deviceLabel, 'desktop');
    expect(offer.description, 'page 214 on desktop (72%)');
  });

  test('no offer when this device is level with or ahead of every other', () async {
    final repo = await _repo(dir);
    final book = await seedBook(repo, progress: 0.8, page: 240);
    final positions = repo.readingPositions;

    RemoteReadingPosition remote(double progress, int page) =>
        RemoteReadingPosition(
          bookId: 'b1',
          deviceId: 'phone',
          progress: progress,
          page: page,
          unit: 'page',
          updatedAt: DateTime.utc(2026, 6),
        );

    expect(
      positions.offerFor(
          book: book, localUnit: 'page', remotes: [remote(0.5, 150)]),
      isNull,
      reason: 'behind',
    );
    expect(
      positions.offerFor(
          book: book, localUnit: 'page', remotes: [remote(0.8, 240)]),
      isNull,
      reason: 'level',
    );
    expect(
      positions.offerFor(
          book: book, localUnit: 'page', remotes: [remote(0.805, 241)]),
      isNull,
      reason: 'ahead by less than the minimum lead — not worth a prompt',
    );
    expect(
      positions.offerFor(book: book, localUnit: 'page', remotes: const []),
      isNull,
    );
  });

  test('never offers a position measured in a different unit', () async {
    // The device that read the EPUB counts chapters; converting "chapter 12"
    // into a PDF page would land somewhere plausible and wrong.
    final repo = await _repo(dir);
    final book = await seedBook(repo, progress: 0.1, page: 20);

    final offer = repo.readingPositions.offerFor(
      book: book,
      localUnit: 'page',
      remotes: [
        RemoteReadingPosition(
          bookId: 'b1',
          deviceId: 'phone',
          deviceLabel: 'phone',
          progress: 0.9,
          page: 12,
          unit: 'chapter',
          updatedAt: DateTime.utc(2026, 6),
        ),
      ],
    );
    expect(offer, isNull);
  });

  test('offers to an unopened book, and accepting it writes the position',
      () async {
    final repo = await _repo(dir);
    final book = await seedBook(repo);
    final positions = repo.readingPositions;

    final offer = positions.offerFor(
      book: book,
      localUnit: 'page',
      remotes: [
        RemoteReadingPosition(
          bookId: 'b1',
          deviceId: 'desktop',
          progress: 0.5,
          page: 120,
          unit: 'page',
          updatedAt: DateTime.utc(2026, 6),
        ),
      ],
    );
    expect(offer, isNotNull);
    expect(offer!.deviceLabel, 'another device', reason: 'unlabelled fallback');

    final before = (await repo.watchBook('b1').first)!.updatedAt;
    await positions.applyOffer('b1', offer);

    final after = (await repo.watchBook('b1').first)!;
    expect(after.lastReadPage, 120);
    expect(after.readingProgress, 0.5);
    expect(after.needsProgressPush, true, reason: 'republish where we now are');
    expect(
      after.updatedAt,
      before,
      reason: 'accepting a jump is reading state, not a metadata edit — it must '
          'not touch the sync clock',
    );
  });

  // ---- the sync pass --------------------------------------------------------

  test('publishes a dirty position with the unit of the file it opens in',
      () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await seedBook(repo, progress: 0.35, page: 70);
    await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
          id: 'f1',
          bookId: 'b1',
          format: 'epub',
          path: 'files/f1.epub',
          sizeBytes: 10,
          sha256: 'abc',
        ));
    // What opting in does: queue the position this device already has.
    await repo.readingPositions.markReadBooksForProgressPush();

    final pushed = <Map<String, dynamic>>[];
    final client = _client(_progressServer(pushCollector: pushed));

    final result = await SyncService(repo).syncReadingProgress(
      client,
      deviceId: 'this-device',
      deviceLabel: 'laptop',
    );

    expect(result.published, 1);
    expect(pushed.single['book_id'], 'b1');
    expect(pushed.single['device_id'], 'this-device');
    expect(pushed.single['device_label'], 'laptop');
    expect(pushed.single['page'], 70);
    expect(pushed.single['unit'], 'chapter', reason: 'the book is an EPUB');
    expect((await repo.watchBook('b1').first)?.needsProgressPush, false);
  });

  test('an unread book is never published, however dirty its flag', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'b1',
          title: 'Never opened',
          needsProgressPush: const Value(true),
        ));

    final pushed = <Map<String, dynamic>>[];
    final client = _client(_progressServer(pushCollector: pushed));
    final result = await SyncService(repo)
        .syncReadingProgress(client, deviceId: 'this-device');

    expect(result.published, 0);
    expect(pushed, isEmpty);
  });

  test('caches other devices rows but never its own', () async {
    final repo = await _repo(dir);
    await seedBook(repo, progress: 0.1, page: 20);

    final client = _client(_progressServer(entries: [
      _entry('b1', 'this-device', progress: 0.1, page: 20, unit: 'page'),
      _entry('b1', 'desktop',
          label: 'desktop', progress: 0.7, page: 200, unit: 'page'),
    ]));

    await SyncService(repo).syncReadingProgress(client, deviceId: 'this-device');

    final cached = await repo.readingPositions.watchRemotePositions('b1').first;
    expect(cached.map((r) => r.deviceId), ['desktop'],
        reason: "this device's own row must not come back as a remote one");
    expect(cached.single.page, 200);
    expect(cached.single.unit, 'page');
  });

  test('a full pull replaces the cache, dropping a device that stopped publishing',
      () async {
    final repo = await _repo(dir);
    await seedBook(repo, progress: 0.1, page: 20);
    await _cacheRemote(repo.db,
        bookId: 'b1', deviceId: 'gone', progress: 0.9, page: 300, unit: 'page');

    // The server no longer lists 'gone' — a device that opted out leaves no
    // tombstone, so only a full pull can notice.
    final client = _client(_progressServer(entries: [
      _entry('b1', 'desktop', progress: 0.5, page: 150, unit: 'page'),
    ]));
    await SyncService(repo).syncReadingProgress(client, deviceId: 'this-device');

    final cached = await repo.readingPositions.watchRemotePositions('b1').first;
    expect(cached.map((r) => r.deviceId), ['desktop']);
  });

  test('a delta pull keeps rows outside its window', () async {
    final repo = await _repo(dir);
    await seedBook(repo, progress: 0.1, page: 20);
    await _cacheRemote(repo.db,
        bookId: 'b1', deviceId: 'quiet', progress: 0.3, page: 60, unit: 'page');

    var sentCursor = '';
    var newCursor = '';
    final client = _client((req) async {
      if (req.method == 'GET' && req.url.path == '/api/reading-progress') {
        sentCursor = req.url.queryParameters['cursor'] ?? '';
        return http.Response(
          jsonEncode({
            'server_now': '2026-07-02 00:00:00',
            'entries': [
              _entry('b1', 'desktop', progress: 0.6, page: 180, unit: 'page'),
            ],
          }),
          200,
        );
      }
      return http.Response('{}', 200);
    });

    await SyncService(repo).syncReadingProgress(
      client,
      deviceId: 'this-device',
      cursor: '2026-07-01 00:00:00',
      onCursor: (c) => newCursor = c,
    );

    expect(sentCursor, '2026-07-01 00:00:00');
    expect(newCursor, '2026-07-02 00:00:00',
        reason: 'the channel advances its own cursor');
    final cached = await repo.readingPositions.watchRemotePositions('b1').first;
    expect(
      cached.map((r) => r.deviceId).toSet(),
      {'quiet', 'desktop'},
      reason: 'a delta pull adds to the cache instead of replacing it',
    );
  });

  test('opting in queues every already-read book, and only those', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await seedBook(repo, progress: 0.4, page: 100);
    await db.into(db.books).insert(
        BooksCompanion.insert(id: 'b2', title: 'Unopened'));

    await repo.readingPositions.markReadBooksForProgressPush();

    expect((await repo.watchBook('b1').first)?.needsProgressPush, true);
    expect((await repo.watchBook('b2').first)?.needsProgressPush, false);
  });

  test('opting out clears the cache and every queued position', () async {
    final repo = await _repo(dir);
    await seedBook(repo, progress: 0.4, page: 100);
    await _cacheRemote(repo.db,
        bookId: 'b1', deviceId: 'desktop', progress: 0.9, page: 300);

    await repo.readingPositions.forgetLocally();

    expect(await repo.readingPositions.watchRemotePositions('b1').first, isEmpty);
    expect((await repo.watchBook('b1').first)?.needsProgressPush, false);
  });

  test('the client asks the server to forget exactly this device', () async {
    final repo = await _repo(dir);
    final forgotten = <String>[];
    final client = _client(_progressServer(forgetCollector: forgotten));

    await client.forgetReadingPositions('this-device');

    expect(forgotten, ['this-device']);
    // Keeps the analyzer honest about the unused repo in this narrow test.
    expect(repo.readingPositions, isNotNull);
  });

  test('the reading-position pass shares the sync re-entrancy guard', () async {
    final repo = await _repo(dir);
    await seedBook(repo, progress: 0.2, page: 50);
    final client = _client(_progressServer());
    final sync = SyncService(repo);

    final first = sync.syncReadingProgress(client, deviceId: 'd1');
    await expectLater(
      () => sync.syncReadingProgress(client, deviceId: 'd1'),
      throwsStateError,
    );
    await first;
    // Guard released afterwards.
    await sync.syncReadingProgress(client, deviceId: 'd1');
  });
}
