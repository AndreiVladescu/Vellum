import 'dart:convert';
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/server/auto_pusher.dart';
import 'package:vellum/server/server_client.dart';
import 'package:vellum/server/sync_service.dart';

Future<LibraryRepository> _repo(Directory dir) async =>
    LibraryRepository.forTesting(VellumDatabase(NativeDatabase.memory()), dir);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_autopush_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('coalesces a burst of edits into a single push run', () async {
    final repo = await _repo(dir);
    final sync = SyncService(repo);

    // Count push *runs*: each _push over dirty books fetches the book list once
    // (for remote file hashes), so one GET /api/books == one push run.
    var pushRuns = 0;
    final pushedIds = <String>[];
    final client = VellumServerClient(
      baseUrl: 'http://test',
      token: 't',
      httpClient: MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'GET' && path == '/api/books') {
          pushRuns++;
          return http.Response(
            jsonEncode({'server_now': '2024-06-01 00:00:00', 'books': []}),
            200,
          );
        }
        if (req.method == 'PUT' &&
            path.startsWith('/api/books/') &&
            !path.endsWith('/cover')) {
          pushedIds.add(path.split('/').last);
          return http.Response('{}', 200);
        }
        return http.Response('[]', 200);
      }),
    );

    final pusher = AutoPusher(
      repository: repo,
      sync: sync,
      client: () => client,
      enabled: () => true,
      debounce: const Duration(milliseconds: 100),
    );
    pusher.start();

    // Three edits in quick succession (each inserted book is dirty by default).
    final db = repo.db;
    for (final id in ['a', 'b', 'c']) {
      await db.into(db.books).insert(BooksCompanion.insert(id: id, title: id));
    }

    // Wait past the debounce for the coalesced push to fire and finish.
    await Future.delayed(const Duration(milliseconds: 400));

    expect(pushRuns, 1, reason: 'three edits coalesce into one push run');
    expect(pushedIds..sort(), ['a', 'b', 'c']);
    for (final id in ['a', 'b', 'c']) {
      expect((await repo.watchBook(id).first)?.needsPush, false);
    }
    pusher.dispose();
  });

  test('does not push while the preference is off', () async {
    final repo = await _repo(dir);
    final sync = SyncService(repo);
    var pushRuns = 0;
    final client = VellumServerClient(
      baseUrl: 'http://test',
      token: 't',
      httpClient: MockClient((req) async {
        if (req.method == 'GET' && req.url.path == '/api/books') pushRuns++;
        return http.Response(
          jsonEncode({'server_now': 'x', 'books': []}),
          200,
        );
      }),
    );

    final pusher = AutoPusher(
      repository: repo,
      sync: sync,
      client: () => client,
      enabled: () => false, // preference off
      debounce: const Duration(milliseconds: 50),
    );
    pusher.start();

    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'a', title: 'a'));
    await Future.delayed(const Duration(milliseconds: 200));

    expect(pushRuns, 0, reason: 'disabled: nothing is pushed');
    expect((await repo.watchBook('a').first)?.needsPush, true);
    pusher.dispose();
  });

  test('does not push when there is no connected client', () async {
    final repo = await _repo(dir);
    final sync = SyncService(repo);
    final pusher = AutoPusher(
      repository: repo,
      sync: sync,
      client: () => null, // not connected
      enabled: () => true,
      debounce: const Duration(milliseconds: 50),
    );
    pusher.start();

    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'a', title: 'a'));
    await Future.delayed(const Duration(milliseconds: 200));

    // Nothing to assert on the wire; the dirty flag simply stays set.
    expect((await repo.watchBook('a').first)?.needsPush, true);
    pusher.dispose();
  });
}
