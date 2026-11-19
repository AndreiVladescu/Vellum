// Listening sittings (docs/AUDIOBOOKS.md section 5): the player records one
// `reading_sessions` row per listen, from the engine's events, on a clock the
// test holds.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/audio/audiobook_player.dart';
import 'package:vellum/audio/playback_options.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';

import 'fake_engine.dart';

void main() {
  late Directory dir;
  late LibraryRepository repo;
  late FakeEngine engine;
  late DateTime now;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vellum_listen');
    repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()), dir);
    engine = FakeEngine();
    now = DateTime(2026, 11, 20, 20);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b', title: 'Dune'));
    for (final (i, ms) in [(1, 3600000), (2, 3600000)]) {
      await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
            id: 'p$i',
            bookId: 'b',
            format: 'mp3',
            path: 'files/p$i.mp3',
            sizeBytes: 1,
            sha256: 'h$i',
            durationMs: Value(ms),
            track: Value(i),
          ));
    }
  });
  tearDown(() async {
    await repo.db.close();
    dir.deleteSync(recursive: true);
  });

  AudiobookPlayer make() => AudiobookPlayer(
        repository: repo,
        bookId: 'b',
        engine: () => engine,
        speedStore: MemorySpeedStore(),
        clock: () => now,
      );

  Future<List<ReadingSession>> sittings() async {
    return (repo.db.select(repo.db.readingSessions)
          ..orderBy([(s) => OrderingTerm.asc(s.startedAt)]))
        .get();
  }

  Future<void> at(AudiobookPlayer player, int seconds) async {
    engine.tick(Duration(seconds: seconds));
    await Future<void>.delayed(Duration.zero);
  }

  test('play to pause is one listening sitting, in wall-clock minutes', () async {
    final player = make();
    await player.load();
    await player.play();
    await at(player, 100);
    now = now.add(const Duration(minutes: 20));
    await at(player, 1900); // 1800 s of audio in 20 min: 1.5x
    await player.pause();
    await player.sittingsSettled;

    final rows = await sittings();
    expect(rows, hasLength(1));
    final s = rows.single;
    expect(s.kind, 'listen');
    expect(s.endedAt.difference(s.startedAt), const Duration(minutes: 20));
    expect(s.startSecond, 0);
    expect(s.endSecond, 1900);
    expect(s.startPage, isNull);
    expect(s.endPage, isNull);
    expect(s.needsPush, isTrue, reason: 'over, so it may go');
    player.dispose();
  });

  test('a sitting under five seconds is not kept', () async {
    final player = make();
    await player.load();
    await player.play();
    now = now.add(const Duration(seconds: 3));
    await player.pause();
    await player.sittingsSettled;
    expect(await sittings(), isEmpty);
    player.dispose();
  });

  test('a short pause is the same sitting, a long one is not', () async {
    final player = make();
    await player.load();
    await player.play();
    now = now.add(const Duration(minutes: 10));
    await player.pause();
    now = now.add(const Duration(seconds: 90));
    await player.play();
    now = now.add(const Duration(minutes: 5));
    await player.pause();
    await player.sittingsSettled;
    expect(await sittings(), hasLength(1), reason: 'under two minutes apart');
    expect((await sittings()).single.endedAt.difference(now),
        Duration.zero);

    now = now.add(const Duration(minutes: 3));
    await player.play();
    now = now.add(const Duration(minutes: 5));
    await player.pause();
    await player.sittingsSettled;
    expect(await sittings(), hasLength(2));
    player.dispose();
  });

  test('the system pausing playback ends the sitting', () async {
    final player = make();
    await player.load();
    await player.play();
    now = now.add(const Duration(minutes: 7));
    engine.interrupt(playing: false); // a phone call
    await Future<void>.delayed(Duration.zero);
    await player.sittingsSettled;
    final s = (await sittings()).single;
    expect(s.endedAt.difference(s.startedAt), const Duration(minutes: 7));
    player.dispose();
  });

  test('the end of the book ends the sitting', () async {
    final player = make();
    await player.load();
    await player.seek(const Duration(minutes: 59));
    await player.play();
    now = now.add(const Duration(minutes: 1));
    engine.finishPart(); // part 1
    await Future<void>.delayed(Duration.zero);
    await player.sittingsSettled;
    // Part 1 handed on to part 2 and playback carries on: still one sitting.
    expect(player.playing, isTrue);
    now = now.add(const Duration(minutes: 1));
    engine.finishPart(); // part 2, the last
    await Future<void>.delayed(Duration.zero);
    await player.sittingsSettled;
    expect(player.ended, isTrue);
    final s = (await sittings()).single;
    expect(s.endedAt.difference(s.startedAt), const Duration(minutes: 2));
    player.dispose();
  });

  test('the sleep timer ends the sitting', () async {
    final player = make();
    await player.load();
    await player.play();
    now = now.add(const Duration(minutes: 30));
    player.sleepFor(const Duration(milliseconds: 300));
    await Future<void>.delayed(const Duration(milliseconds: 900));
    expect(player.playing, isFalse);
    await player.sittingsSettled;
    final s = (await sittings()).single;
    expect(s.endedAt.difference(s.startedAt), const Duration(minutes: 30));
    player.dispose();
  });

  test('closing the player while it plays closes the sitting', () async {
    final player = make();
    await player.load();
    await player.play();
    now = now.add(const Duration(minutes: 12));
    player.dispose();
    // dispose finishes its writes in the background.
    for (var i = 0; i < 20 && (await sittings()).isEmpty; i++) {
      await Future<void>.delayed(const Duration(milliseconds: 20));
    }
    final s = (await sittings()).single;
    expect(s.endedAt.difference(s.startedAt), const Duration(minutes: 12));
    expect(s.needsPush, isTrue);
  });

  test('reading straight after listening starts a new sitting', () async {
    final player = make();
    await player.load();
    await player.play();
    now = now.add(const Duration(minutes: 10));
    await player.pause();
    await player.sittingsSettled;

    final reader = SessionRecorder(repo.db);
    await reader.begin('b', page: 4, now: now.add(const Duration(seconds: 30)));
    await reader.end(
        page: 9, now: now.add(const Duration(minutes: 5, seconds: 30)));
    final rows = await sittings();
    expect(rows.map((s) => s.kind), ['listen', 'read']);
    expect(rows.last.endPage, 9);
    player.dispose();
  });
}
