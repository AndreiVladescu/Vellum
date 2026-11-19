// Audiobooks on the wire (docs/AUDIOBOOKS.md §3–§4): an audio part's fields
// travel with its upload, the listening position travels on the
// reading-progress channel, and the books list asks for audio explicitly.
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

VellumServerClient _client(Future<http.Response> Function(http.Request) handler) =>
    VellumServerClient(baseUrl: 'http://test', token: 't', httpClient: MockClient(handler));

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_audio_sync'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('an audio upload names its part fields in the query', () async {
    Uri? seen;
    String? type;
    final client = _client((req) async {
      seen = req.url;
      type = req.headers['content-type'];
      return http.Response('{}', 200);
    });
    final file = File('${dir.path}/x.mp3')..writeAsBytesSync([1, 2, 3]);
    await client.uploadFileFrom('b1', file,
        format: 'mp3', durationMs: 61000, track: 2, label: 'Chapter 2 & 3', narrator: 'Ned');
    expect(seen!.path, '/api/books/b1/files');
    expect(seen!.queryParameters, {
      'filename': 'book.mp3',
      'duration_ms': '61000',
      'track': '2',
      'label': 'Chapter 2 & 3',
      'narrator': 'Ned',
    });
    expect(type, 'audio/mpeg');

    await client.uploadFileFrom('b1', file, format: 'pdf');
    expect(seen!.queryParameters, {'filename': 'book.pdf'},
        reason: 'a text file sends nothing new');
  });

  test('the books list asks for audio', () async {
    Uri? seen;
    final client = _client((req) async {
      seen = req.url;
      return http.Response('{"server_now":"2026-11-01 00:00:00","books":[]}', 200);
    });
    await client.listBooks(cursor: '');
    expect(seen!.queryParameters['audio'], '1');
  });

  test('the listening position is pushed with the audio total and cached back',
      () async {
    final repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()), dir);
    addTearDown(repo.db.close);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'b1',
          title: 'Dune',
          listenPosition: const Value(1234.5),
          lastListenedAt: Value(DateTime.utc(2026, 11, 2)),
          needsProgressPush: const Value(true),
        ));
    for (final (id, ms) in [('p1', 60000), ('p2', 90000)]) {
      await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
            id: id,
            bookId: 'b1',
            format: 'mp3',
            path: 'files/$id.mp3',
            sizeBytes: 1,
            sha256: id,
            durationMs: Value(ms),
          ));
    }

    final pushed = <Map<String, dynamic>>[];
    final client = _client((req) async {
      if (req.method == 'GET') {
        return http.Response(
          jsonEncode({
            'server_now': '2026-11-03 00:00:00',
            'entries': [
              {
                'book_id': 'b1',
                'device_id': 'phone',
                'device_label': 'Pixel 8',
                'audio_position': 18753.0,
                'audio_duration': 150.0,
                'updated_at': '2026-11-01 00:00:00',
              },
            ],
          }),
          200,
        );
      }
      pushed.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{}', 200);
    });

    await SyncService(repo).syncReadingProgress(client, deviceId: 'desk');
    expect(pushed.single['audio_position'], 1234.5);
    expect(pushed.single['audio_duration'], 150.0, reason: 'the parts summed');
    expect(pushed.single['unit'], 'chapter', reason: 'unit still says page|chapter');

    final cached = await db.select(db.remoteReadingPositions).getSingle();
    expect(cached.audioPosition, 18753.0);
    expect(cached.audioDuration, 150.0);
  });

  test('a book never listened to sends no audio fields at all', () async {
    final repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()), dir);
    addTearDown(repo.db.close);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'b1',
          title: 'Dune',
          readingProgress: const Value(0.5),
          lastReadPage: const Value(4),
          lastReadAt: Value(DateTime.utc(2026, 11, 2)),
          needsProgressPush: const Value(true),
        ));
    final pushed = <Map<String, dynamic>>[];
    final client = _client((req) async {
      if (req.method == 'GET') {
        return http.Response('{"server_now":"x","entries":[]}', 200);
      }
      pushed.add(jsonDecode(req.body) as Map<String, dynamic>);
      return http.Response('{}', 200);
    });
    await SyncService(repo).syncReadingProgress(client, deviceId: 'desk');
    expect(pushed.single.containsKey('audio_position'), isFalse,
        reason: 'absent, so the server keeps what this device said before');
  });
}
