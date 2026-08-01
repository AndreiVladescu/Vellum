// Choosing what syncs (next features #8).
//
// The rule the whole feature rests on is **off means off in both directions**.
// A resource that stopped pushing but kept pulling would look like it was still
// syncing; one that stopped pulling but kept pushing would quietly publish what
// you asked it not to. So these drive a real SyncService against a fake server
// and assert on the requests that were actually made.
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
import 'package:vellum/server/sync_scope.dart';
import 'package:vellum/server/sync_service.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_scope'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Runs a full sync and returns every path the client asked for.
  Future<List<String>> pathsTouchedBy(SyncScope scope) async {
    final repo = await LibraryRepository.forTesting(
      VellumDatabase(NativeDatabase.memory()),
      dir,
    );
    final db = repo.db;
    // One of each kind of local thing, all dirty, so every push pass has
    // something to send if it is allowed to.
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'Dune'));
    await db.into(db.shelves).insert(
          ShelvesCompanion.insert(id: 'sh1', name: 'Favourites'),
        );
    await db.into(db.physicalCopies).insert(
          PhysicalCopiesCompanion.insert(id: 'c1', bookId: 'b1'),
        );
    await db.into(db.loans).insert(
          LoansCompanion.insert(
            id: 'l1',
            copyId: 'c1',
            borrower: 'A friend',
            loanedAt: Value(DateTime(2026)),
          ),
        );
    await db.into(db.annotations).insert(
          AnnotationsCompanion.insert(id: 'a1', bookId: 'b1', kind: 'highlight'),
        );
    await db.into(db.readingSessions).insert(
          ReadingSessionsCompanion.insert(
            id: 'rs1',
            bookId: 'b1',
            startedAt: DateTime(2026),
            endedAt: DateTime(2026, 1, 1, 1),
          ),
        );
    await db.into(db.copyPhotos).insert(
          CopyPhotosCompanion.insert(
            id: 'ph1',
            copyId: 'c1',
            path: 'photos/ph1.jpg',
          ),
        );

    final paths = <String>[];
    final client = VellumServerClient(
      baseUrl: 'http://test.local',
      token: 't',
      httpClient: MockClient((request) async {
        paths.add('${request.method} ${request.url.path}');
        // Every list endpoint answers "nothing here" in the envelope its own
        // client method expects; every write answers OK.
        if (request.method == 'GET') {
          const now = '2026-08-01 00:00:00';
          // Two shapes on this server: a bare list for the tombstone and
          // layout endpoints, an envelope with a cursor for everything else.
          if (request.url.path.contains('deletions') ||
              request.url.path.endsWith('/layouts')) {
            return http.Response('[]', 200,
                headers: {'content-type': 'application/json'});
          }
          final body = jsonEncode({
            'server_now': now,
            'books': <Object>[],
            'shelves': <Object>[],
            'copies': <Object>[],
            'loans': <Object>[],
            'photos': <Object>[],
            'entries': <Object>[],
          });
          return http.Response(body, 200,
              headers: {'content-type': 'application/json'});
        }
        return http.Response(jsonEncode({'ok': true}), 200,
            headers: {'content-type': 'application/json'});
      }),
    );

    await SyncService(repo).sync(client, scope: scope);
    await repo.db.close();
    return paths;
  }

  bool touched(List<String> paths, String fragment) =>
      paths.any((p) => p.contains(fragment));

  test('everything on touches every resource', () async {
    final paths = await pathsTouchedBy(SyncScope.everything);
    for (final resource in [
      '/api/books',
      '/api/shelves',
      '/api/copies',
      '/api/loans',
      '/api/annotations',
      '/api/sessions',
      '/api/copy-photos',
    ]) {
      expect(touched(paths, resource), isTrue, reason: 'never asked $resource');
    }
  });

  test('loans off stops both the pull and the push', () async {
    final paths = await pathsTouchedBy(const SyncScope(loans: false));
    expect(touched(paths, '/api/loans'), isFalse,
        reason: 'a loan request escaped with loans switched off');
    // And the rest is untouched by the exclusion.
    expect(touched(paths, '/api/copies'), isTrue);
  });

  test('copy photos off sends no photo and fetches none', () async {
    final paths = await pathsTouchedBy(const SyncScope(copyPhotos: false));
    expect(touched(paths, '/api/copy-photos'), isFalse);
  });

  test('personal marks can be switched off without losing sittings', () async {
    // The two are separable on purpose: "sync my highlights" and "sync my
    // reading habits" are different appetites.
    final paths = await pathsTouchedBy(const SyncScope(annotations: false));
    expect(touched(paths, '/api/annotations'), isFalse);
    expect(touched(paths, '/api/notes'), isFalse,
        reason: 'a reader note is an annotation by another name');
    expect(touched(paths, '/api/sessions'), isTrue,
        reason: 'sittings are a separate switch');
  });

  test('sittings off leaves highlights alone', () async {
    final paths = await pathsTouchedBy(const SyncScope(sessions: false));
    expect(touched(paths, '/api/sessions'), isFalse);
    expect(touched(paths, '/api/annotations'), isTrue);
  });

  test('everything off still completes, and asks for almost nothing', () async {
    final paths = await pathsTouchedBy(const SyncScope(
      books: false,
      copies: false,
      loans: false,
      annotations: false,
      sessions: false,
      copyPhotos: false,
    ));
    for (final resource in [
      '/api/shelves',
      '/api/copies',
      '/api/loans',
      '/api/annotations',
      '/api/sessions',
      '/api/copy-photos',
    ]) {
      expect(touched(paths, resource), isFalse, reason: 'asked $resource');
    }
  });

  test('the summary names what is switched off', () {
    expect(SyncScope.everything.isEverything, isTrue);
    expect(SyncScope.everything.excluded, isEmpty);
    const partial = SyncScope(loans: false, copyPhotos: false);
    expect(partial.isEverything, isFalse);
    expect(partial.excluded, ['loans', 'copy photos']);
  });
}
