// On-demand audio (docs/AUDIOBOOKS.md §6): a pull brings audio rows but not
// their bytes; Listen downloads the parts, the needed one first, resuming an
// interrupted transfer with Range and checking every part's hash; the
// Wi-Fi-only rule; and Remove download, which only removes what the server
// still holds.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/audio/audio_downloads.dart';
import 'package:vellum/audio/audiobook_player.dart';
import 'package:vellum/audio/playback_options.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/server/server_client.dart';
import 'package:vellum/server/sync_service.dart';

import 'fake_engine.dart';

/// Distinct bytes per part, big enough to split.
List<int> _bytesOf(int part) => List<int>.generate(3000, (i) => (i * 7 + part) % 256);

String _sha(List<int> bytes) => sha256.convert(bytes).toString();

/// Waits (up to five seconds) for [condition]; a fixed delay is flaky when
/// the suite runs in parallel.
Future<void> until(bool Function() condition) async {
  for (var i = 0; i < 500 && !condition(); i++) {
    await Future<void>.delayed(const Duration(milliseconds: 10));
  }
}

void main() {
  test('the network rule asks only on Android, on metered, with it on', () {
    AudioNetworkVerdict v({
      bool android = true,
      bool wifiOnly = true,
      bool metered = true,
      bool allowed = false,
    }) =>
        audioNetworkVerdict(
          isAndroid: android,
          wifiOnly: wifiOnly,
          metered: metered,
          allowedForBook: allowed,
        );
    expect(v(), AudioNetworkVerdict.askFirst);
    expect(v(android: false), AudioNetworkVerdict.go, reason: 'desktop ignores it');
    expect(v(wifiOnly: false), AudioNetworkVerdict.go);
    expect(v(metered: false), AudioNetworkVerdict.go, reason: 'on Wi-Fi');
    expect(v(allowed: true), AudioNetworkVerdict.go, reason: '"Download anyway"');
  });

  late Directory dir;
  late LibraryRepository repo;
  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vellum_audio_dl');
    repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()), dir);
  });
  tearDown(() async {
    await repo.db.close();
    dir.deleteSync(recursive: true);
  });

  test('a pull brings audio rows but not their bytes; text still downloads',
      () async {
    final requested = <String>[];
    final client = VellumServerClient(
      baseUrl: 'http://test',
      token: 't',
      httpClient: MockClient((req) async {
        final path = req.url.path;
        if (path == '/api/books') {
          return http.Response(
            jsonEncode({
              'server_now': '2026-11-01 00:00:00',
              'books': [
                {
                  'id': 'b1',
                  'title': 'Dune',
                  'updated_at': '2026-01-01 00:00:00',
                  'files': [
                    {
                      'id': 'a1',
                      'book_id': 'b1',
                      'format': 'm4b',
                      'size_bytes': 430000000,
                      'sha256': 'audiohash',
                      'duration_ms': 54000000,
                      'track': 1,
                      'label': 'Dune',
                    },
                    {
                      'id': 't1',
                      'book_id': 'b1',
                      'format': 'epub',
                      'size_bytes': 5,
                      'sha256': 'texthash',
                    },
                  ],
                },
              ],
            }),
            200,
          );
        }
        if (path.startsWith('/api/files/')) {
          requested.add(path);
          return http.Response('hello', 200);
        }
        if (path == '/api/shelves') {
          return http.Response('{"server_now":"x","shelves":[]}', 200);
        }
        if (path == '/api/copies') {
          return http.Response('{"server_now":"x","copies":[]}', 200);
        }
        if (path == '/api/loans') {
          return http.Response('{"server_now":"x","loans":[]}', 200);
        }
        return http.Response('[]', 200);
      }),
    );

    await SyncService(repo).pull(client);

    expect(requested, ['/api/files/t1'], reason: 'the audio is not fetched');
    final audio = (await repo.fileById('a1'))!;
    expect(audio.present, isFalse);
    expect(audio.durationMs, 54000000, reason: 'the book still shows its length');
    expect(audio.label, 'Dune');
    expect(File(p.join(dir.path, audio.path)).existsSync(), isFalse);
    expect((await repo.fileById('t1'))!.present, isTrue);

    // A second pull does not fetch it either (nor the text, already here).
    await SyncService(repo).pull(client);
    expect(requested, ['/api/files/t1']);
    expect((await repo.fileById('a1'))!.present, isFalse);
  });

  group('on demand', () {
    late List<List<int>> bytes;

    /// Three mp3 parts of a minute each, none of them here.
    Future<void> seed({List<bool> present = const [false, false, false]}) async {
      bytes = [for (var i = 1; i <= 3; i++) _bytesOf(i)];
      final db = repo.db;
      await db.into(db.books).insert(BooksCompanion.insert(id: 'b', title: 'Dune'));
      for (var i = 1; i <= 3; i++) {
        await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
              id: 'p$i',
              bookId: 'b',
              format: 'mp3',
              path: 'files/p$i.mp3',
              sizeBytes: bytes[i - 1].length,
              sha256: _sha(bytes[i - 1]),
              durationMs: const Value(60000),
              track: Value(i),
              label: Value('Part $i'),
              present: Value(present[i - 1]),
            ));
        if (present[i - 1]) {
          File(p.join(dir.path, 'files', 'p$i.mp3')).writeAsBytesSync(bytes[i - 1]);
        }
      }
    }

    /// A file server over [bytes] that honours Range, recording each request.
    final requests = <http.BaseRequest>[];
    Future<http.StreamedResponse> Function(http.BaseRequest, http.ByteStream)
        server({
      Stream<List<int>> Function(int part, int attempt, List<int> body)? body,
      List<int> Function(int part)? serve,
    }) {
      final attempts = <int, int>{};
      return (req, _) async {
        requests.add(req);
        final path = req.url.path;
        if (path.startsWith('/api/books/') && path.endsWith('/files')) {
          return http.StreamedResponse(
            Stream.value(utf8.encode(jsonEncode([
              for (var i = 1; i <= 3; i++)
                {
                  'id': 'p$i',
                  'book_id': 'b',
                  'format': 'mp3',
                  'size_bytes': bytes[i - 1].length,
                  'sha256': _sha(bytes[i - 1]),
                },
            ]))),
            200,
          );
        }
        final part = int.parse(path.split('/').last.substring(1));
        final attempt = attempts[part] = (attempts[part] ?? 0) + 1;
        final all = serve?.call(part) ?? bytes[part - 1];
        final range = req.headers['range'];
        var status = 200;
        var from = 0;
        if (range != null) {
          from = int.parse(range.substring('bytes='.length, range.length - 1));
          status = 206;
        }
        final rest = all.sublist(from);
        return http.StreamedResponse(
          body?.call(part, attempt, rest) ?? Stream.value(rest),
          status,
          contentLength: rest.length,
        );
      };
    }

    AudioDownloads downloads(
      Future<http.StreamedResponse> Function(http.BaseRequest, http.ByteStream) handler, {
      bool android = false,
      bool metered = false,
    }) =>
        AudioDownloads(
          client: () async => VellumServerClient(
            baseUrl: 'http://test',
            token: 't',
            httpClient: MockClient.streaming(handler),
          ),
          isAndroid: android,
          isMetered: () async => metered,
          wifiOnly: () async => true,
          retryDelays: const [Duration.zero],
          progressInterval: Duration.zero,
        );

    setUp(requests.clear);

    test('fetches the part with the position first, then the rest in order',
        () async {
      await seed();
      final dl = downloads(server());
      expect(await dl.download(repo, 'b', firstFileId: 'p2'),
          AudioDownloadStart.started);
      await dl.whenSettled('b');

      expect([for (final r in requests) r.url.path],
          ['/api/files/p2', '/api/files/p3', '/api/files/p1']);
      for (var i = 1; i <= 3; i++) {
        final row = (await repo.fileById('p$i'))!;
        expect(row.present, isTrue);
        expect(File(p.join(dir.path, 'files', 'p$i.mp3')).readAsBytesSync(),
            bytes[i - 1]);
      }
      // Chapters are re-derived from what arrived (here, the label).
      final chapters = await repo.db.select(repo.db.audioChapters).get();
      expect(chapters.length, 3);
      expect(dl.statusOf('b'), isNull, reason: 'done: nothing to report');
      expect(await dl.download(repo, 'b'), AudioDownloadStart.alreadyHere);
    });

    test('an interrupted part resumes with Range where it stopped', () async {
      await seed();
      final dl = downloads(server(body: (part, attempt, rest) async* {
        if (part == 1 && attempt == 1) {
          yield rest.sublist(0, 1200);
          throw http.ClientException('connection reset');
        }
        yield rest;
      }));
      await dl.download(repo, 'b');
      await dl.whenSettled('b');

      final p1 = [for (final r in requests) if (r.url.path == '/api/files/p1') r];
      expect(p1.length, 2);
      expect(p1.first.headers['range'], isNull);
      expect(p1.last.headers['range'], 'bytes=1200-',
          reason: 'only the rest is asked for');
      expect(p1.last.headers['if-range'], '"${_sha(bytes[0])}"');
      expect((await repo.fileById('p1'))!.present, isTrue);
      expect(File(p.join(dir.path, 'files', 'p1.mp3')).readAsBytesSync(), bytes[0]);
    });

    test('a resume survives a restart: the partial file is kept for next time',
        () async {
      await seed();
      final first = downloads(server(body: (part, attempt, rest) async* {
        yield rest.sublist(0, 1000);
        throw http.ClientException('gone');
      }));
      await first.download(repo, 'b');
      await first.whenSettled('b');
      expect(first.statusOf('b')!.failure, AudioDownloadFailure.network);
      expect((await repo.fileById('p1'))!.present, isFalse);

      // The app restarts: a fresh repository sweeps `.part` files, but the
      // audio partials live outside files/.
      await LibraryRepository.forTesting(repo.db, dir);
      requests.clear();
      final second = downloads(server());
      await second.download(repo, 'b');
      await second.whenSettled('b');
      expect(requests.first.headers['range'], startsWith('bytes='));
      expect(File(p.join(dir.path, 'files', 'p1.mp3')).readAsBytesSync(), bytes[0]);
    });

    test('a part that fails its hash is thrown away and not marked present',
        () async {
      await seed();
      final dl = downloads(server(
          serve: (part) => part == 1 ? List<int>.filled(3000, 0) : bytes[part - 1]));
      await dl.download(repo, 'b');
      await dl.whenSettled('b');

      final status = dl.statusOf('b')!;
      expect(status.phase, AudioDownloadPhase.failed);
      expect(status.failure, AudioDownloadFailure.hashMismatch);
      expect((await repo.fileById('p1'))!.present, isFalse);
      expect(File(p.join(dir.path, 'files', 'p1.mp3')).existsSync(), isFalse);
      expect(AudioDownloads.partialOf(repo, (await repo.fileById('p1'))!).existsSync(),
          isFalse, reason: 'the bad bytes are not resumed from either');
    });

    test('a bad resume starts that part again from scratch, once', () async {
      await seed();
      // A partial left by a crash, with garbage in it.
      final partial = AudioDownloads.partialOf(repo, (await repo.fileById('p1'))!);
      partial.parent.createSync(recursive: true);
      partial.writeAsBytesSync(List<int>.filled(500, 9));
      final dl = downloads(server());
      await dl.download(repo, 'b');
      await dl.whenSettled('b');

      final p1 = [for (final r in requests) if (r.url.path == '/api/files/p1') r];
      expect([for (final r in p1) r.headers['range']], ['bytes=500-', null]);
      expect((await repo.fileById('p1'))!.present, isTrue);
      expect(File(p.join(dir.path, 'files', 'p1.mp3')).readAsBytesSync(), bytes[0]);
    });

    test('cancel stops between chunks and keeps what arrived', () async {
      await seed();
      final release = Completer<void>();
      final dl = downloads(server(body: (part, attempt, rest) async* {
        if (attempt == 1 && part == 1) {
          yield rest.sublist(0, 800);
          await release.future;
          yield rest.sublist(800, 1600);
        }
        yield rest;
      }));
      await dl.download(repo, 'b');
      // Until the first chunk is on disk (a fixed delay is flaky under load).
      await until(() => (dl.statusOf('b')?.receivedBytes ?? 0) >= 800);
      expect(dl.statusOf('b')!.phase, AudioDownloadPhase.downloading);
      expect(dl.statusOf('b')!.receivedBytes, 800);
      dl.cancel('b');
      expect(dl.statusOf('b'), isNull);
      release.complete();
      await dl.whenSettled('b');
      expect((await repo.fileById('p1'))!.present, isFalse);
      expect(AudioDownloads.partialOf(repo, (await repo.fileById('p1'))!).lengthSync(),
          800);
      expect(requests.where((r) => r.url.path == '/api/files/p2'), isEmpty);
    });

    test('on mobile data with Wi-Fi only, it asks; "Download anyway" goes',
        () async {
      await seed();
      final dl = downloads(server(), android: true, metered: true);
      expect(await dl.download(repo, 'b'), AudioDownloadStart.needsConsent);
      expect(dl.statusOf('b')!.phase, AudioDownloadPhase.needsConsent);
      expect(requests, isEmpty);

      expect(await dl.download(repo, 'b', allowMetered: true),
          AudioDownloadStart.started);
      await dl.whenSettled('b');
      expect((await repo.fileById('p3'))!.present, isTrue);
    });

    test('the player waits for the next part and plays on when it arrives',
        () async {
      await seed(present: const [true, false, false]);
      final gate = Completer<void>();
      final dl = downloads(server(body: (part, attempt, rest) async* {
        await gate.future;
        yield rest;
      }));
      final engine = FakeEngine();
      final player = AudiobookPlayer(
        repository: repo,
        bookId: 'b',
        engine: () => engine,
        speedStore: MemorySpeedStore(),
        fetchPart: (part) => dl.ensurePart(repo, part),
      );
      await player.load();
      await player.play();
      expect(engine.isPlaying, isTrue);

      engine.finishPart(); // part 1 ends; part 2 is not here
      await until(() => player.waitingForPart);
      expect(player.waitingForPart, isTrue);
      expect(player.playPending, isTrue);
      expect(player.currentPart, 1);
      expect(engine.isPlaying, isFalse);

      gate.complete();
      await dl.whenSettled('b');
      await until(() => engine.isPlaying);
      expect(player.waitingForPart, isFalse);
      expect(engine.opened.last.$1, p.join(dir.path, 'files', 'p2.mp3'));
      expect(engine.isPlaying, isTrue, reason: 'it plays on by itself');
      await player.pause();
      player.dispose();
      await player.sittingsSettled;
    });

    test('a player opened on a missing part waits for it on play', () async {
      await seed();
      final dl = downloads(server());
      final engine = FakeEngine();
      final player = AudiobookPlayer(
        repository: repo,
        bookId: 'b',
        engine: () => engine,
        speedStore: MemorySpeedStore(),
        fetchPart: (part) => dl.ensurePart(repo, part),
      );
      await player.load();
      expect(player.partMissing, isTrue);
      expect(engine.opened, isEmpty, reason: 'nothing to open yet');
      expect(player.total, const Duration(minutes: 3),
          reason: 'the length is known without the bytes');

      await player.play();
      expect(engine.opened.single.$1, p.join(dir.path, 'files', 'p1.mp3'));
      expect(engine.isPlaying, isTrue);
      await player.pause();
      player.dispose();
      await player.sittingsSettled;
      await dl.whenSettled('b'); // the rest followed
      expect((await repo.fileById('p3'))!.present, isTrue);
    });

    test('Remove download frees the space only when the server has it all',
        () async {
      await seed(present: const [true, true, false]);
      final dl = downloads(server());
      expect(await dl.remove(repo, 'b'), AudioRemoveResult.removed);
      for (var i = 1; i <= 3; i++) {
        expect((await repo.fileById('p$i'))!.present, isFalse);
        expect(File(p.join(dir.path, 'files', 'p$i.mp3')).existsSync(), isFalse);
      }
      expect(await repo.db.select(repo.db.books).get(), hasLength(1),
          reason: 'the book stays');

      // A part the server does not hold (imported here, never uploaded).
      File(p.join(dir.path, 'files', 'p1.mp3')).writeAsBytesSync([1, 2, 3]);
      await (repo.db.update(repo.db.bookFiles)..where((f) => f.id.equals('p1')))
          .write(const BookFilesCompanion(
              present: Value(true), sha256: Value('only-here')));
      expect(await dl.remove(repo, 'b'), AudioRemoveResult.notOnServer);
      expect(File(p.join(dir.path, 'files', 'p1.mp3')).existsSync(), isTrue);

      final offline = AudioDownloads(client: () async => null);
      expect(await offline.remove(repo, 'b'), AudioRemoveResult.notOnServer);
    });

    test('the storage line counts only audio that is here', () async {
      await seed(present: const [true, false, true]);
      final used = await watchAudioStorage(repo.db).first;
      expect(used.bytes, bytes[0].length + bytes[2].length);
      expect(used.books, 1);
    });
  });
}
