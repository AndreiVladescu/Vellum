// v1.5.1: speed, the sleep timer (on a fake clock) and the handover of a
// playing book to the media session, all over the fake backend.
import 'dart:io';

import 'package:audio_service/audio_service.dart';
import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/audio/audio_handler.dart';
import 'package:vellum/audio/audiobook_player.dart';
import 'package:vellum/audio/background_playback.dart';
import 'package:vellum/audio/now_playing_bar.dart';
import 'package:vellum/audio/playback_host.dart';
import 'package:vellum/audio/playback_options.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';

import 'fake_engine.dart';

/// Book 'b': three parts (60 s, 90 s, 30 s), part 2 holding two chapters, so
/// the chapters start at 0, 60, 105 and 150 s. Book 'c': one short part.
Future<LibraryRepository> seed(Directory dir) async {
  final repo = await LibraryRepository.forTesting(
      VellumDatabase(NativeDatabase.memory()), dir);
  final db = repo.db;
  await db.into(db.books).insert(BooksCompanion.insert(id: 'b', title: 'Dune'));
  await db.into(db.books).insert(BooksCompanion.insert(id: 'c', title: 'Emma'));
  for (final (i, ms) in [(1, 60000), (2, 90000), (3, 30000)]) {
    await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
          id: 'p$i',
          bookId: 'b',
          format: 'mp3',
          path: 'files/p$i.mp3',
          sizeBytes: 1,
          sha256: 'h$i',
          durationMs: Value(ms),
          track: Value(i),
          label: Value('Part $i'),
        ));
  }
  await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
        id: 'c1',
        bookId: 'c',
        format: 'mp3',
        path: 'files/c1.mp3',
        sizeBytes: 1,
        sha256: 'hc',
        durationMs: const Value(20000),
        track: const Value(1),
        label: const Value('Only part'),
      ));
  await db.into(db.audioChapters).insert(AudioChaptersCompanion.insert(
      fileId: 'p2', idx: 0, title: const Value('Two A'), startMs: 0));
  await db.into(db.audioChapters).insert(AudioChaptersCompanion.insert(
      fileId: 'p2', idx: 1, title: const Value('Two B'), startMs: 45000));
  return repo;
}

void main() {
  group('speed and sleep arithmetic', () {
    test('speeds are clamped, snapped to a step and printed plainly', () {
      expect(normaliseSpeed(1.2500001), 1.25);
      expect(normaliseSpeed(0.1), minSpeed);
      expect(normaliseSpeed(7), maxSpeed);
      expect(normaliseSpeed(double.nan), 1.0);
      expect(formatSpeed(1.0), '1×');
      expect(formatSpeed(1.25), '1.25×');
      expect(formatSpeed(1.5), '1.5×');
      expect(formatSpeed(3), '3×');
    });

    test('the fade is full, then a line to silence over the last ten seconds', () {
      expect(sleepVolume(const Duration(minutes: 1)), 1.0);
      expect(sleepVolume(const Duration(seconds: 10)), 1.0);
      expect(sleepVolume(const Duration(seconds: 5)), closeTo(0.5, 1e-9));
      expect(sleepVolume(const Duration(seconds: 1)), closeTo(0.1, 1e-9));
      expect(sleepVolume(Duration.zero), 0.0);
      expect(sleepVolume(const Duration(seconds: -3)), 0.0);
    });
  });

  group('speed on the controller', () {
    late Directory dir;
    late LibraryRepository repo;
    late FakeEngine engine;
    late MemorySpeedStore store;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('vellum_speed');
      repo = await seed(dir);
      engine = FakeEngine();
      store = MemorySpeedStore();
    });
    tearDown(() async {
      await repo.db.close();
      dir.deleteSync(recursive: true);
    });

    AudiobookPlayer make(String id) => AudiobookPlayer(
        repository: repo, bookId: id, engine: () => engine, speedStore: store);

    test('is applied, remembered per book, and survives a part change', () async {
      final player = make('b');
      await player.load();
      expect(player.speed, 1.0);
      await player.setSpeed(1.5);
      expect(engine.speed, 1.5);
      expect(store.values, {'b': 1.5}, reason: 'per book, nothing on the row');

      engine.resetsSpeedOnOpen = true;
      await player.jumpToChapter(3); // another part: a new file is opened
      expect(engine.speed, 1.5, reason: 'said again after open');
      player.dispose();

      // Same book later: back to 1.5 before anything plays. Another book: 1.
      final again = make('b');
      await again.load();
      expect(again.speed, 1.5);
      expect(engine.speed, 1.5);
      again.dispose();
      final other = make('c');
      await other.load();
      expect(other.speed, 1.0);
      other.dispose();
    });

    test('an out of range speed is brought into range', () async {
      final player = make('b');
      await player.load();
      await player.setSpeed(9);
      expect(player.speed, maxSpeed);
      await player.setSpeed(0.2);
      expect(engine.speed, minSpeed);
      player.dispose();
    });

    test('the system pausing and resuming playback is followed', () async {
      final player = make('b');
      await player.load();
      await player.play();
      engine.tick(const Duration(seconds: 20));
      await pumpEventQueue();

      engine.interrupt(playing: false); // a call; the headphones came out
      await pumpEventQueue();
      expect(player.playing, isFalse);
      final saved = await (repo.db.select(repo.db.books)
            ..where((b) => b.id.equals('b')))
          .getSingle();
      expect(saved.listenPosition, 20, reason: 'an outside pause saves');

      engine.interrupt(playing: true); // the call ended
      await pumpEventQueue();
      expect(player.playing, isTrue);
      player.dispose();
    });
  });

  // The timer runs on the widget tester's fake clock. The repository is real
  // I/O, so it is built, loaded and driven in `runAsync`, and [settle]
  // alternates the two so the saves the timer starts can finish.
  group('sleep timer', () {
    late Directory dir;
    late LibraryRepository repo;
    late FakeEngine engine;
    late AudiobookPlayer player;

    Future<void> start(WidgetTester tester, {double? savedAt}) async {
      dir = Directory.systemTemp.createTempSync('vellum_sleep');
      addTearDown(() => dir.deleteSync(recursive: true));
      engine = FakeEngine();
      await tester.runAsync(() async {
        repo = await seed(dir);
        if (savedAt != null) {
          await repo.readingPositions.saveListenPosition('b', savedAt);
        }
        player = AudiobookPlayer(
            repository: repo,
            bookId: 'b',
            engine: () => engine,
            speedStore: MemorySpeedStore());
        await player.load();
      });
    }

    Future<void> settle(WidgetTester tester) async {
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
    }

    Future<double?> savedPosition(WidgetTester tester) async {
      final row = await tester.runAsync(() => (repo.db.select(repo.db.books)
            ..where((b) => b.id.equals('b')))
          .getSingle());
      return row!.listenPosition;
    }

    testWidgets('stops after the minutes, fading out, and saves the position',
        (tester) async {
      await start(tester);
      await tester.runAsync(player.play);
      engine.tick(const Duration(seconds: 42));
      await tester.pump();

      player.sleepFor(const Duration(minutes: 5));
      expect(player.sleepActive, isTrue);
      expect(player.sleepRemaining, const Duration(minutes: 5));

      await tester.pump(const Duration(minutes: 4, seconds: 40));
      expect(engine.isPlaying, isTrue);
      expect(engine.volume, 1.0, reason: 'full until the last ten seconds');

      await tester.pump(const Duration(seconds: 15)); // 5 s left
      expect(engine.volume, closeTo(0.5, 0.06));
      expect(engine.isPlaying, isTrue);

      await tester.pump(const Duration(seconds: 6));
      await settle(tester);
      expect(engine.isPlaying, isFalse);
      expect(player.playing, isFalse);
      expect(player.sleepActive, isFalse);
      expect(engine.volume, 1.0, reason: 'loud again for the next play');
      expect(await savedPosition(tester), 42);
      player.dispose();
    });

    testWidgets('does not count while paused, and can be cancelled', (tester) async {
      await start(tester);
      await tester.runAsync(player.play);
      player.sleepFor(const Duration(minutes: 10));
      await tester.pump(const Duration(minutes: 2));
      await tester.runAsync(player.pause);
      await tester.pump(const Duration(minutes: 30));
      expect(player.sleepActive, isTrue);
      expect(player.sleepRemaining!.inSeconds, closeTo(8 * 60, 1));

      player.cancelSleep();
      expect(player.sleepActive, isFalse);
      await tester.runAsync(player.play);
      await tester.pump(const Duration(minutes: 30));
      expect(engine.isPlaying, isTrue);
      player.dispose();
      await settle(tester);
    });

    testWidgets('at the end of the chapter: fades over its last ten seconds, stops there',
        (tester) async {
      // 80 s in: part 2 at 20 s, in "Two A", which ends at 105 s.
      await start(tester, savedAt: 80);
      await tester.runAsync(player.play);
      player.sleepAtEndOfChapter();
      expect(player.sleepAtChapterEnd, isTrue);

      await tester.pump(const Duration(seconds: 1));
      expect(engine.volume, 1.0, reason: '25 s to go');

      engine.tick(const Duration(seconds: 40)); // 100 s: 5 s to go
      await tester.pump(const Duration(milliseconds: 500));
      expect(engine.volume, closeTo(0.5, 0.06));
      expect(engine.isPlaying, isTrue);

      engine.tick(const Duration(seconds: 45)); // 105 s
      await tester.pump(const Duration(milliseconds: 500));
      await settle(tester);
      expect(engine.isPlaying, isFalse);
      expect(player.sleepActive, isFalse);
      expect(engine.volume, 1.0);
      expect(await savedPosition(tester), 105);
      player.dispose();
    });

    testWidgets('the fade is ten seconds of listening, not of book, at 2x',
        (tester) async {
      await start(tester, savedAt: 80);
      await tester.runAsync(() => player.setSpeed(2));
      await tester.runAsync(player.play);
      player.sleepAtEndOfChapter();
      engine.tick(const Duration(seconds: 40)); // 5 book seconds = 2.5 real
      await tester.pump(const Duration(milliseconds: 500));
      expect(engine.volume, closeTo(0.25, 0.06));

      engine.tick(const Duration(seconds: 35)); // 10 book seconds = 5 real
      await tester.pump(const Duration(milliseconds: 500));
      expect(engine.volume, closeTo(0.5, 0.06));
      player.cancelSleep();
      player.dispose();
      await settle(tester);
    });

    testWidgets('a chapter that ends with its part stops before the next part plays',
        (tester) async {
      // 140 s in: "Two B" ends at 150 s, which is the end of part 2.
      await start(tester, savedAt: 140);
      await tester.runAsync(player.play);
      player.sleepAtEndOfChapter();

      engine.finishPart();
      await settle(tester);
      expect(engine.opened.last.$1, endsWith('p3.mp3'), reason: 'lined up');
      expect(engine.isPlaying, isFalse, reason: '…but not playing');
      expect(player.sleepActive, isFalse);
      expect(await savedPosition(tester), 150);
      player.dispose();
    });
  });

  group('handover to the media session', () {
    late Directory dir;
    late LibraryRepository repo;
    late FakeEngine engine;
    late VellumAudioHandler handler;
    late PlaybackHost host;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('vellum_handover');
      repo = await seed(dir);
      engine = FakeEngine();
      handler = VellumAudioHandler();
      host = PlaybackHost(
        engine: () => engine,
        speedStore: MemorySpeedStore(),
        background: BackgroundPlayback(handlerFactory: (_) async => handler),
      );
    });
    tearDown(() async {
      await host.close();
      await repo.db.close();
      dir.deleteSync(recursive: true);
    });

    Future<AudiobookPlayer> open([String id = 'b']) async => (await host.open(
          repo,
          id,
          channelName: 'Playback',
          untitledChapter: (n) => 'Chapter $n',
        ))
            .player;

    test('describes the whole book to the session, with five controls', () async {
      final player = await open();
      expect(handler.player, same(player));
      final item = handler.mediaItem.value!;
      expect(item.title, 'Part 1');
      expect(item.album, 'Dune');
      expect(item.duration, const Duration(minutes: 3),
          reason: 'the book, not the part');
      final state = handler.playbackState.value;
      expect(state.playing, isFalse);
      expect(state.controls, hasLength(5));
      expect(state.processingState, AudioProcessingState.ready);
      expect(state.systemActions, contains(MediaAction.seek));
    });

    test('the session\'s buttons drive the player', () async {
      final player = await open();
      await handler.play();
      expect(engine.isPlaying, isTrue);
      expect(handler.playbackState.value.playing, isTrue);

      await handler.fastForward();
      expect(player.position, const Duration(seconds: 30));
      await handler.skipToNext(); // chapter 2 starts at 60 s
      expect(player.position, const Duration(seconds: 60));
      expect(handler.mediaItem.value!.title, 'Two A');
      await handler.rewind();
      expect(player.position, const Duration(seconds: 30));
      await handler.seek(const Duration(seconds: 110));
      expect(player.position, const Duration(seconds: 110));
      expect(handler.mediaItem.value!.title, 'Two B');

      // Back: restarts "Two B" once past three seconds into it, else goes on.
      await handler.skipToPrevious();
      expect(player.position, const Duration(seconds: 105));
      await handler.skipToPrevious();
      expect(player.position, const Duration(seconds: 60));

      await handler.setSpeed(1.5);
      expect(engine.speed, 1.5);
      expect(handler.playbackState.value.speed, 1.5);

      await handler.pause();
      expect(engine.isPlaying, isFalse);
      expect(handler.playbackState.value.playing, isFalse);
    });

    test('leaving the page leaves the book playing; reopening finds it', () async {
      final first = await open();
      await first.play();

      // The page goes away: nothing the page owns is disposed. Opening the
      // same book again hands back the running player, untouched.
      final again = await host.open(repo, 'b',
          channelName: 'Playback', untitledChapter: (n) => 'Chapter $n');
      expect(again.reused, isTrue);
      expect(again.player, same(first));
      expect(first.playing, isTrue);
      expect(engine.isPlaying, isTrue);
    });

    test('another book replaces the first, saving it', () async {
      final first = await open();
      await first.play();
      engine.tick(const Duration(seconds: 33));
      await pumpEventQueue();

      final second = await open('c');
      expect(second, isNot(same(first)));
      expect(handler.player, same(second));
      expect(handler.mediaItem.value!.album, 'Emma');
      final saved = await (repo.db.select(repo.db.books)
            ..where((b) => b.id.equals('b')))
          .getSingle();
      expect(saved.listenPosition, 33);
    });

    test('closing and stopping: the session lets go, a stop keeps the book',
        () async {
      final player = await open();
      await player.play();
      await handler.stop();
      expect(engine.isPlaying, isFalse);
      expect(host.player, same(player), reason: 'the mini bar still resumes');
      expect(handler.playbackState.value.processingState, AudioProcessingState.idle);

      await player.play();
      expect(handler.playbackState.value.playing, isTrue,
          reason: 'playing again reaches the session');

      await host.close();
      expect(host.player, isNull);
      expect(handler.player, isNull);
    });

    test('a book that cannot load leaves what was playing alone', () async {
      final first = await open();
      await expectLater(open('nope'), throwsA(isA<StateError>()));
      expect(host.player, same(first));
    });
  });

  testWidgets('the now-playing bar shows a loaded book, plays it and closes',
      (tester) async {
    final dir = Directory.systemTemp.createTempSync('vellum_bar');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repo = (await tester.runAsync(() => seed(dir)))!;
    final engine = FakeEngine();
    final host = PlaybackHost(
      engine: () => engine,
      speedStore: MemorySpeedStore(),
      background: BackgroundPlayback(handlerFactory: (_) async => null),
    );
    Future<void> settle() async {
      for (var i = 0; i < 4; i++) {
        await tester.runAsync(
            () => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
    }

    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(bottomNavigationBar: NowPlayingBar(host: host)),
    ));
    expect(find.text('Dune'), findsNothing, reason: 'nothing loaded, no bar');

    await tester.runAsync(() => host.open(repo, 'b',
        channelName: 'Playback', untitledChapter: (n) => 'Chapter $n'));
    await settle();
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Part 1'), findsOneWidget);

    await tester.tap(find.byTooltip('Play'));
    await settle();
    expect(engine.isPlaying, isTrue);
    expect(find.byTooltip('Pause'), findsOneWidget);

    await tester.tap(find.byTooltip('Stop and close'));
    await settle();
    expect(find.text('Dune'), findsNothing);
    expect(engine.isPlaying, isFalse);
  });
}
