// Model-based tests for the sync state machine (plan 5 #44).
//
// LWW + tombstones + `needsPush` + a server cursor is a state machine with a lot
// of interleavings, and its worst failure mode is *silent data loss* — the one
// class of bug this project can least afford. Example-based tests (see
// `sync_service_test.dart`) cover the paths someone thought of. This file
// generates sequences instead: local edits, remote edits, deletes on either
// side, pulls, pushes, offline gaps, clock skew and an interrupted push, in
// random order, replayed against
//
//   * `_FakeServer`  — a stateful test double that follows the real server's
//     rules (each one cited to the Rust that implements it), and
//   * `_Model`       — an independent reference implementation of the intended
//     semantics, written from `DESIGN.md` rather than from `SyncService`.
//
// After every operation the real app state is compared against the model. A
// mismatch prints the failing trace and then a greedily *shrunk* one, so the
// report is a minimal reproduction rather than a 40-step haystack.
//
// What is deliberately out of scope: covers and files (blob transfer has its own
// tests) and shelves/copies/loans (same code shape as books, driven by the same
// cursor). The model is over book metadata, where the conflict rules live.
//
// Checked against deliberate mutations of `SyncService` when written, so it is
// known to fail for the right reasons rather than passing vacuously:
//   * pull adopting on a timestamp *tie* instead of strictly-newer → caught,
//     reported as a lost local edit and shrunk from 40 ops to 10.
//   * pull dropping its local-tombstone check (reviving a book deleted here but
//     not yet pushed) → caught by several seeds.

import 'dart:convert';
import 'dart:io';
import 'dart:math';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/server/server_client.dart';
import 'package:vellum/server/sync_service.dart';

// ---- the fake server --------------------------------------------------------

/// A book as the server holds it: the title stands in for all synced metadata
/// (the conflict rules don't care which field changed), plus the `updated_at`
/// the server itself assigned.
class _ServerRow {
  _ServerRow(this.title, this.updatedAt);
  String title;
  DateTime updatedAt;
}

/// Second-resolution clock shared by the fake server and the model, so both
/// agree on ordering. Ticks a second per event: real SQLite timestamps are
/// second-resolution, and distinct values keep the `>=` cursor overlap (a
/// deliberate feature of the real delta pull) from turning into ties the test
/// would have to guess about.
class _Clock {
  DateTime _now = DateTime.utc(2026, 1, 1);
  DateTime tick() => _now = _now.add(const Duration(seconds: 1));
  DateTime get now => _now;
}

/// A stateful stand-in for the Vellum server. Every rule here mirrors one in the
/// real server, cited so the double can be checked against it:
///
/// - `PUT` keeps the *server's* clock on the row, never the client's
///   (`books.rs::upsert`'s `updated_at = datetime('now')`); the client's
///   `updated_at` is only the LWW guard.
/// - a push whose `updated_at` is not strictly newer is `skipped_older`
///   (`upsert`'s `incoming <= stored_updated_at`).
/// - an unchanged push is a no-op that does *not* bump the clock (`upsert`'s
///   meta_same/authors_same/genres_same guard) — without this, one post-upgrade
///   sweep would re-timestamp the whole library.
/// - `DELETE` records a tombstone; `PUT` of the same id clears it again.
/// - `GET /api/books?cursor=` filters `updated_at >= cursor`
///   (`books::visible_books`), and `/api/deletions?since=` the same way.
class _FakeServer {
  _FakeServer(this.clock, {this.advertiseBatch = false});

  final _Clock clock;

  /// Whether this server offers `POST /api/books:batch` (plan 5 #7). Flipped
  /// per seed so both push paths get generated coverage.
  final bool advertiseBatch;

  final Map<String, _ServerRow> books = {};
  final Map<String, DateTime> tombstones = {};

  /// Ids whose next `PUT`/batch item fails with a 503 — an interrupted push.
  final Set<String> failOnce = {};

  int puts = 0;
  int batches = 0;

  DateTime? _parse(String? s) => (s == null || s.isEmpty)
      ? null
      : DateTime.tryParse('${s.replaceFirst(' ', 'T')}Z');

  /// The upsert every write path shares, returning the wire status.
  String _upsert(String id, Map<String, dynamic> body) {
    final incoming = _parse(body['updated_at'] as String?);
    final title = (body['title'] as String).trim();
    final existing = books[id];
    if (existing != null) {
      if (incoming != null && !incoming.isAfter(existing.updatedAt)) {
        return 'skipped_older';
      }
      // Unchanged data with no tombstone to clear: no write, no new timestamp.
      if (existing.title == title && !tombstones.containsKey(id)) {
        return 'updated';
      }
      existing.title = title;
      existing.updatedAt = clock.tick();
    } else {
      books[id] = _ServerRow(title, clock.tick());
    }
    tombstones.remove(id);
    return 'updated';
  }

  /// Server-side edit (a console edit, or another device that already synced).
  void edit(String id, String title) {
    final row = books[id];
    if (row == null) {
      books[id] = _ServerRow(title, clock.tick());
    } else {
      row.title = title;
      row.updatedAt = clock.tick();
    }
    tombstones.remove(id);
  }

  void delete(String id) {
    if (books.remove(id) != null) tombstones[id] = clock.tick();
  }

  /// JSON with an explicit UTF-8 body: `http.Response(String, …)` encodes
  /// latin-1, which a title with an em dash in it would fail on.
  static http.Response _json(Object body, [int status = 200]) =>
      http.Response.bytes(
        utf8.encode(jsonEncode(body)),
        status,
        headers: {'content-type': 'application/json; charset=utf-8'},
      );

  Future<http.Response> call(http.Request req) async {
    final path = req.url.path;
    final method = req.method;
    String? fmt(DateTime? d) => formatServerTime(d);

    if (method == 'GET' && path == '/api/capabilities') {
      return _json({
        'server_version': '0.0.0-fake',
        'sync_protocol': 1,
        'features': [
          'delta_pull',
          'deletions',
          if (advertiseBatch) 'batch_push',
        ],
      });
    }
    if (method == 'GET' && path == '/api/books') {
      final cursor = _parse(req.url.queryParameters['cursor']);
      final visible = [
        for (final e in books.entries)
          if (cursor == null || !e.value.updatedAt.isBefore(cursor))
            {
              'id': e.key,
              'title': e.value.title,
              'updated_at': fmt(e.value.updatedAt),
              'authors': <String>[],
              'genres': <String>[],
              'files': <Map<String, dynamic>>[],
            },
      ];
      return _json({'server_now': fmt(clock.now), 'books': visible});
    }
    if (method == 'GET' && path == '/api/deletions') {
      final since = _parse(req.url.queryParameters['since']);
      final kind = req.url.queryParameters['kind'];
      final Iterable<MapEntry<String, DateTime>> ids =
          (kind == null || kind == 'book') ? tombstones.entries : const [];
      return _json([
        for (final e in ids)
          if (since == null || !e.value.isBefore(since))
            {'book_id': e.key, 'deleted_at': fmt(e.value), 'kind': 'book'},
      ]);
    }
    // Shelves/copies/loans aren't modelled here; empty envelopes keep their
    // passes no-ops without special-casing them in SyncService.
    for (final (route, key) in [
      ('/api/shelves', 'shelves'),
      ('/api/copies', 'copies'),
      ('/api/loans', 'loans'),
    ]) {
      if (method == 'GET' && path == route) {
        return _json({'server_now': fmt(clock.now), key: []});
      }
    }
    if (method == 'PUT' && path.startsWith('/api/books/') && !path.endsWith('/cover')) {
      final id = path.split('/').last;
      puts++;
      if (failOnce.remove(id)) {
        return http.Response('{"error":"interrupted"}', 503);
      }
      _upsert(id, jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{}', 200);
    }
    if (method == 'POST' && path == '/api/books:batch') {
      batches++;
      final items = (jsonDecode(req.body) as Map<String, dynamic>)['books'] as List;
      final results = <Map<String, dynamic>>[];
      for (final raw in items) {
        final item = raw as Map<String, dynamic>;
        final id = item['id'] as String;
        if (failOnce.remove(id)) {
          results.add({'id': id, 'status': 'error', 'message': 'interrupted'});
          continue;
        }
        results.add({'id': id, 'status': _upsert(id, item)});
      }
      return _json({'results': results});
    }
    if (method == 'DELETE' && path.startsWith('/api/books/')) {
      final id = path.split('/').last;
      if (!books.containsKey(id)) {
        return http.Response('{"error":"not found"}', 404);
      }
      delete(id);
      return http.Response('{}', 200);
    }
    if (method == 'GET' && path.endsWith('/files')) {
      return http.Response('[]', 200);
    }
    return http.Response('{"error":"unexpected $method $path"}', 404);
  }
}

// ---- the reference model ----------------------------------------------------

class _ModelBook {
  _ModelBook(this.title, this.updatedAt, this.needsPush);
  String title;
  DateTime updatedAt;
  bool needsPush;
}

/// What the app's local state *should* be, derived from `DESIGN.md`'s rules
/// rather than from `SyncService`:
///
/// - a pull adopts a server row only when the server's timestamp is **strictly**
///   newer (local edits win until pushed), copies that timestamp, and clears
///   `needsPush` — the row now matches the server.
/// - a pull never revives a book this device deleted but hasn't pushed.
/// - a server deletion applies locally even to a dirty book: delete wins.
/// - a push clears `needsPush` on every book it got an answer for, *including*
///   `skipped_older` — under LWW the server's newer copy is the answer, and the
///   next pull brings it down. An interrupted book stays dirty.
/// - a push drops its local tombstones whatever the server said (already gone,
///   or not ours to delete — either way there is nothing left to tell it).
///
/// The model deliberately predicts **local** state only. Server timestamps are
/// assigned by the server itself (`updated_at = datetime('now')`), so the model
/// *reads* them from the shared [_FakeServer] when deciding what a pull adopts
/// instead of trying to predict values it has no business knowing. The cursor
/// likewise comes from the server, echoed back through the app's `onCursor`
/// (that it advances at all is pinned by `sync_service_test.dart`).
class _Model {
  final Map<String, _ModelBook> local = {};
  final Set<String> localTombstones = {};

  DateTime? cursor;

  void localCreate(String id, String title, DateTime at) {
    local[id] = _ModelBook(title, at, true);
  }

  void localEdit(String id, String title, DateTime at) {
    final book = local[id];
    if (book == null) return;
    book
      ..title = title
      ..updatedAt = at
      ..needsPush = true;
  }

  void localDelete(String id) {
    if (local.remove(id) != null) localTombstones.add(id);
  }

  void pull(_FakeServer server, DateTime? serverNow) {
    // Server deletions first, exactly as _pull does: a delete beats a local
    // edit, dirty or not.
    for (final e in server.tombstones.entries) {
      if (cursor != null && e.value.isBefore(cursor!)) continue;
      local.remove(e.key);
    }
    for (final e in server.books.entries) {
      if (cursor != null && e.value.updatedAt.isBefore(cursor!)) continue;
      if (localTombstones.contains(e.key)) continue;
      final mine = local[e.key];
      if (mine != null && !mine.updatedAt.isBefore(e.value.updatedAt)) continue;
      local[e.key] = _ModelBook(e.value.title, e.value.updatedAt, false);
    }
    if (serverNow != null) cursor = serverNow;
  }

  /// [failId] is the book whose push was interrupted, if any. Note what this
  /// does *not* consult: the server. Whether a push was applied or skipped as
  /// older changes nothing locally — only the next pull sees the difference.
  void push({String? failId}) {
    localTombstones.clear();
    for (final e in local.entries) {
      if (e.key == failId) continue;
      e.value.needsPush = false;
    }
  }
}

// ---- generated operations --------------------------------------------------

enum _OpKind {
  localCreate,
  localEdit,
  remoteEdit,
  localDelete,
  remoteDelete,
  pull,
  push,
  interruptedPush,
}

class _Op {
  _Op(this.kind, {this.id, this.title, this.skewSeconds = 0});
  final _OpKind kind;
  final String? id;
  final String? title;

  /// Local clock offset for this edit — negative means this device's clock is
  /// *behind* the server's, the case that makes a local edit lose LWW.
  final int skewSeconds;

  @override
  String toString() => switch (kind) {
        _OpKind.pull => 'pull',
        _OpKind.push => 'push',
        _OpKind.interruptedPush => 'push(interrupt $id)',
        _ => '${kind.name}($id${title == null ? '' : ', "$title"'}'
            '${skewSeconds == 0 ? '' : ', skew ${skewSeconds}s'})',
      };
}

List<_Op> _generate(Random rng, int length) {
  const ids = ['b1', 'b2', 'b3'];
  var version = 0;
  return [
    for (var i = 0; i < length; i++)
      switch (rng.nextInt(10)) {
        0 || 1 => _Op(_OpKind.localCreate,
            id: ids[rng.nextInt(ids.length)],
            title: 'local-${version++}',
            skewSeconds: rng.nextBool() ? 0 : -rng.nextInt(30)),
        2 || 3 => _Op(_OpKind.localEdit,
            id: ids[rng.nextInt(ids.length)],
            title: 'local-${version++}',
            skewSeconds: rng.nextBool() ? 0 : -rng.nextInt(30)),
        4 || 5 => _Op(_OpKind.remoteEdit,
            id: ids[rng.nextInt(ids.length)], title: 'remote-${version++}'),
        6 => _Op(rng.nextBool() ? _OpKind.localDelete : _OpKind.remoteDelete,
            id: ids[rng.nextInt(ids.length)]),
        7 || 8 => _Op(_OpKind.pull),
        _ => rng.nextInt(5) == 0
            ? _Op(_OpKind.interruptedPush, id: ids[rng.nextInt(ids.length)])
            : _Op(_OpKind.push),
      },
  ];
}

// ---- the harness ------------------------------------------------------------

/// One run of a trace: fresh database, fresh fake server, fresh model.
/// Returns null when the app matched the model at every step, or a description
/// of the first divergence.
Future<String?> _run(
  List<_Op> ops, {
  required bool advertiseBatch,
  void Function(_FakeServer server)? inspect,
}) async {
  final dir = Directory.systemTemp.createTempSync('vellum_sync_model');
  final db = VellumDatabase(NativeDatabase.memory());
  final repo = await LibraryRepository.forTesting(db, dir);
  final clock = _Clock();
  final server = _FakeServer(clock, advertiseBatch: advertiseBatch);
  final model = _Model();
  final client = VellumServerClient(
    baseUrl: 'http://model',
    token: 't',
    httpClient: MockClient(server.call),
  );
  final sync = SyncService(repo);

  try {
    for (var i = 0; i < ops.length; i++) {
      final op = ops[i];
      switch (op.kind) {
        case _OpKind.localCreate:
          final at = clock.tick().add(Duration(seconds: op.skewSeconds));
          await db.into(db.books).insertOnConflictUpdate(
                BooksCompanion.insert(
                  id: op.id!,
                  title: op.title!,
                  updatedAt: Value(at),
                  needsPush: const Value(true),
                ),
              );
          model.localCreate(op.id!, op.title!, at);
        case _OpKind.localEdit:
          final at = clock.tick().add(Duration(seconds: op.skewSeconds));
          await (db.update(db.books)..where((b) => b.id.equals(op.id!))).write(
            BooksCompanion(
              title: Value(op.title!),
              updatedAt: Value(at),
              needsPush: const Value(true),
            ),
          );
          model.localEdit(op.id!, op.title!, at);
        case _OpKind.remoteEdit:
          server.edit(op.id!, op.title!);
        case _OpKind.localDelete:
          final row = await (db.select(db.books)
                ..where((b) => b.id.equals(op.id!)))
              .getSingleOrNull();
          if (row != null) await repo.deleteBook(row);
          model.localDelete(op.id!);
        case _OpKind.remoteDelete:
          server.delete(op.id!);
        case _OpKind.pull:
          DateTime? serverNow;
          await sync.pull(
            client,
            cursor: formatServerTime(model.cursor),
            onCursor: (s) => serverNow = DateTime.parse('${s.replaceFirst(' ', 'T')}Z'),
          );
          model.pull(server, serverNow);
        case _OpKind.push:
          await sync.push(client);
          model.push();
        case _OpKind.interruptedPush:
          // Arm the failure, push, then tell the model which book it hit — the
          // fake server consumes the flag while serving the app's request.
          server.failOnce.add(op.id!);
          await sync.push(client);
          model.push(failId: op.id);
          server.failOnce.remove(op.id!);
      }

      final divergence = await _compare(db, model);
      if (divergence != null) {
        return 'after step ${i + 1} (${op.kind.name}): $divergence';
      }
    }
    inspect?.call(server);
    return null;
  } finally {
    await db.close();
    dir.deleteSync(recursive: true);
  }
}

/// Compares the app's local books against the model's. Titles, existence and
/// `needsPush` are asserted exactly; timestamps are not, because the server
/// assigns its own and the model only needs their *ordering* to predict LWW.
Future<String?> _compare(VellumDatabase db, _Model model) async {
  final rows = await db.select(db.books).get();
  final actual = {for (final r in rows) r.id: r};
  if (actual.length != model.local.length ||
      !actual.keys.toSet().containsAll(model.local.keys)) {
    return 'books present: app ${actual.keys.toList()..sort()}, '
        'model ${model.local.keys.toList()..sort()}';
  }
  for (final e in model.local.entries) {
    final row = actual[e.key]!;
    if (row.title != e.value.title) {
      return '${e.key} title: app "${row.title}", model "${e.value.title}"';
    }
    if (row.needsPush != e.value.needsPush) {
      return '${e.key} needsPush: app ${row.needsPush}, '
          'model ${e.value.needsPush}';
    }
  }
  final tombstones = {
    for (final t in await db.select(db.localDeletions).get())
      if (t.kind == 'book') t.bookId,
  };
  if (!setEquals(tombstones, model.localTombstones)) {
    return 'local tombstones: app $tombstones, model ${model.localTombstones}';
  }
  return null;
}

bool setEquals(Set<String> a, Set<String> b) =>
    a.length == b.length && a.containsAll(b);

/// Greedily drops operations that aren't needed to reproduce a failure, so the
/// report is a minimal trace. Bounded: a trace is short and each attempt is a
/// full replay.
Future<List<_Op>> _shrink(List<_Op> ops, {required bool advertiseBatch}) async {
  var best = ops;
  var changed = true;
  while (changed && best.length > 1) {
    changed = false;
    for (var i = 0; i < best.length; i++) {
      final candidate = [...best]..removeAt(i);
      if (candidate.isEmpty) continue;
      if (await _run(candidate, advertiseBatch: advertiseBatch) != null) {
        best = candidate;
        changed = true;
        break;
      }
    }
  }
  return best;
}

void main() {
  // Fixed seeds, not a fresh Random(): a failure has to be reproducible from
  // the test name alone. Half run against a batch-push server (plan 5 #7), so
  // both push paths are covered by the same model.
  for (var seed = 0; seed < 12; seed++) {
    final advertiseBatch = seed.isEven;
    test(
      'sync converges with the model — seed $seed'
      '${advertiseBatch ? ' (batch push)' : ''}',
      () async {
        final ops = _generate(Random(seed), 40);
        final failure = await _run(ops, advertiseBatch: advertiseBatch);
        if (failure == null) return;
        final minimal = await _shrink(ops, advertiseBatch: advertiseBatch);
        fail('$failure\n\n'
            'minimal trace (${minimal.length} ops):\n'
            '${minimal.map((o) => '  $o').join('\n')}\n\n'
            'full trace:\n${ops.map((o) => '  $o').join('\n')}');
      },
    );
  }

  test('the generated runs exercise both push paths', () async {
    // Guards the coverage claim above: if the capability gate or the
    // single-book shortcut regressed, these traces would quietly stop testing
    // the batch path and every seed above would still pass.
    final trace = [
      _Op(_OpKind.localCreate, id: 'b1', title: 'a'),
      _Op(_OpKind.localCreate, id: 'b2', title: 'b'),
      _Op(_OpKind.localCreate, id: 'b3', title: 'c'),
      _Op(_OpKind.push),
    ];

    late int batchedBatches, batchedPuts;
    expect(
      await _run(trace, advertiseBatch: true, inspect: (s) {
        batchedBatches = s.batches;
        batchedPuts = s.puts;
      }),
      isNull,
    );
    expect(batchedBatches, 1, reason: 'three dirty books, one batch');
    expect(batchedPuts, 0, reason: 'no per-book PUT when batching');

    late int plainBatches, plainPuts;
    expect(
      await _run(trace, advertiseBatch: false, inspect: (s) {
        plainBatches = s.batches;
        plainPuts = s.puts;
      }),
      isNull,
    );
    expect(plainBatches, 0);
    expect(plainPuts, 3, reason: 'a server without the capability gets PUTs');
  });

  test('pull-push-pull reaches a fixed point where nothing is dirty', () async {
    // The property that matters most: whatever mess a trace leaves, syncing to
    // quiescence must agree with the server and leave nothing queued. A dirty
    // flag that survives a successful push is a book that silently never syncs.
    for (var seed = 0; seed < 6; seed++) {
      final ops = [
        ..._generate(Random(1000 + seed), 30),
        _Op(_OpKind.pull),
        _Op(_OpKind.push),
        _Op(_OpKind.pull),
      ];
      final failure = await _run(ops, advertiseBatch: seed.isOdd);
      expect(failure, isNull, reason: 'seed ${1000 + seed}');
    }
  });

  test('a locally created book survives every sync that has no competitor',
      () async {
    // The narrowest anti-data-loss claim, stated on its own so a regression
    // here can't hide behind a broader property: nothing but a *newer remote
    // edit or a delete* may change or drop a local book.
    final ops = [
      _Op(_OpKind.localCreate, id: 'b1', title: 'mine'),
      _Op(_OpKind.pull),
      _Op(_OpKind.push),
      _Op(_OpKind.pull),
      _Op(_OpKind.push),
    ];
    expect(await _run(ops, advertiseBatch: false), isNull);
    expect(await _run(ops, advertiseBatch: true), isNull);
  });

  // ---- DTO round-trip fuzz --------------------------------------------------

  test('every synced field survives a push/pull round trip', () async {
    final dirA = Directory.systemTemp.createTempSync('vellum_dto_a');
    final dirB = Directory.systemTemp.createTempSync('vellum_dto_b');
    final dbA = VellumDatabase(NativeDatabase.memory());
    final dbB = VellumDatabase(NativeDatabase.memory());
    final repoA = await LibraryRepository.forTesting(dbA, dirA);
    final repoB = await LibraryRepository.forTesting(dbB, dirB);
    final clock = _Clock();
    final server = _FakeServer(clock);
    // The round trip needs full metadata, which _FakeServer's title-only model
    // doesn't carry — so this case drives a metadata-preserving handler instead.
    final stored = <String, Map<String, dynamic>>{};
    final client = VellumServerClient(
      baseUrl: 'http://dto',
      token: 't',
      httpClient: MockClient((req) async {
        final path = req.url.path;
        if (req.method == 'PUT' && path.startsWith('/api/books/')) {
          final id = path.split('/').last;
          stored[id] = {
            'id': id,
            ...jsonDecode(req.body) as Map<String, dynamic>,
            'files': <Map<String, dynamic>>[],
          };
          return http.Response('{}', 200);
        }
        if (req.method == 'GET' && path == '/api/books') {
          // UTF-8 bytes, not the String constructor: the fuzzed titles below
          // are full of characters latin-1 can't encode.
          return http.Response.bytes(
            utf8.encode(jsonEncode({
              'server_now': formatServerTime(clock.now),
              'books': stored.values.toList(),
            })),
            200,
            headers: {'content-type': 'application/json; charset=utf-8'},
          );
        }
        return server.call(req);
      }),
    );

    final rng = Random(7);
    const alphabet = 'aA0 é"\\\'<>&{}[]—\n\tzZ';
    String noise(int n) => [
          for (var i = 0; i < n; i++) alphabet[rng.nextInt(alphabet.length)],
        ].join();

    for (var i = 0; i < 15; i++) {
      final id = 'book-$i';
      final title = 'T${noise(rng.nextInt(12) + 1)}';
      await dbA.into(dbA.books).insert(BooksCompanion.insert(
            id: id,
            title: title,
            subtitle: Value(rng.nextBool() ? noise(6) : null),
            description: Value(rng.nextBool() ? noise(40) : null),
            isbn: Value(rng.nextBool() ? '978${rng.nextInt(999999999)}' : null),
            publisher: Value(rng.nextBool() ? noise(8) : null),
            publishedYear: Value(rng.nextBool() ? 1500 + rng.nextInt(526) : null),
            pageCount: Value(rng.nextBool() ? rng.nextInt(3000) : null),
            updatedAt: Value(clock.tick()),
            // App-local-only columns, set here precisely so the assertions
            // below can prove they never crossed the wire.
            readingProgress: Value(rng.nextDouble()),
            lastReadPage: Value(rng.nextInt(500)),
            readerNotes: Value(noise(20)),
            sourceMetadata: const Value('{"source":"local"}'),
          ));
      await repoA.setAuthors(id, [for (var a = 0; a <= i % 3; a++) 'Author ${noise(4)}']);
      await repoA.setGenres(id, ['Genre ${noise(3)}']);
    }

    await SyncService(repoA).push(client);
    await SyncService(repoB).pull(client);

    for (final row in await dbA.select(dbA.books).get()) {
      final mirrored = await (dbB.select(dbB.books)
            ..where((b) => b.id.equals(row.id)))
          .getSingleOrNull();
      expect(mirrored, isNotNull, reason: '${row.id} never arrived');
      expect(mirrored!.title, row.title);
      expect(mirrored.subtitle, row.subtitle);
      expect(mirrored.description, row.description);
      expect(mirrored.isbn, row.isbn);
      expect(mirrored.publisher, row.publisher);
      expect(mirrored.publishedYear, row.publishedYear);
      expect(mirrored.pageCount, row.pageCount);
      expect(
        await repoB.detailsFor(row.id).then((d) => d.authors),
        await repoA.detailsFor(row.id).then((d) => d.authors),
        reason: 'author order and content must survive',
      );
      expect(
        await repoB.detailsFor(row.id).then((d) => d.genres),
        await repoA.detailsFor(row.id).then((d) => d.genres),
      );

      // The point of the exercise: app-local-only columns are not synced, so
      // the receiving device must not have them, whatever the sender held.
      expect(mirrored.readingProgress, isNull);
      expect(mirrored.lastReadPage, isNull);
      expect(mirrored.readerNotes, isNull);
      expect(mirrored.sourceMetadata, isNull);
    }

    // And they never appeared in the payload at all — a stricter statement than
    // "the receiver ignored them".
    for (final body in stored.values) {
      for (final forbidden in [
        'reading_progress',
        'last_read_page',
        'last_read_at',
        'reader_notes',
        'source_metadata',
        'needs_push',
        'needs_progress_push',
        'cover_etag',
      ]) {
        expect(body.containsKey(forbidden), false,
            reason: '$forbidden must never be pushed');
      }
    }

    await dbA.close();
    await dbB.close();
    dirA.deleteSync(recursive: true);
    dirB.deleteSync(recursive: true);
  });
}
