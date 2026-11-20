// The player's bookkeeping (docs/AUDIOBOOKS.md §4) over a fake backend: one
// timeline across parts, chapters placed on it, the position saved where the
// reading-progress channel picks it up, and the offer from another device.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/audio/audiobook_player.dart';
import 'package:vellum/audio/background_playback.dart';
import 'package:vellum/audio/playback_host.dart';
import 'package:vellum/audio/playback_options.dart';
import 'package:vellum/audio/player_page.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';

import 'fake_engine.dart';

void main() {
  group('timeline', () {
    test('maps book time to a part and back', () {
      final t = PartTimeline([60000, 90000, 30000]);
      expect(t.totalMs, 180000);
      expect(t.locate(0), (0, 0));
      expect(t.locate(59999), (0, 59999));
      expect(t.locate(60000), (1, 0));
      expect(t.locate(170000), (2, 20000));
      expect(t.locate(999999), (2, 30000), reason: 'past the end: the end');
      expect(t.locate(-5), (0, 0));
      expect(t.startOf(2), 150000);
      final unknown = PartTimeline([0, 5000]);
      expect(unknown.locate(0), (0, 0), reason: 'an unmeasured part still opens');
    });
  });

  group('player', () {
    late Directory dir;
    late LibraryRepository repo;
    late FakeEngine engine;

    setUp(() async {
      dir = Directory.systemTemp.createTempSync('vellum_player');
      repo = await LibraryRepository.forTesting(
          VellumDatabase(NativeDatabase.memory()), dir);
      engine = FakeEngine();
      final db = repo.db;
      await db.into(db.books).insert(BooksCompanion.insert(id: 'b', title: 'Dune'));
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
      // Part 2 has two chapters of its own; the others none.
      await db.into(db.audioChapters).insert(AudioChaptersCompanion.insert(
          fileId: 'p2', idx: 0, title: const Value('Two A'), startMs: 0));
      await db.into(db.audioChapters).insert(AudioChaptersCompanion.insert(
          fileId: 'p2', idx: 1, title: const Value('Two B'), startMs: 45000));
    });
    tearDown(() async {
      await repo.db.close();
      dir.deleteSync(recursive: true);
    });

    Future<Book> book() async => (await repo.watchBook('b').first)!;

    AudiobookPlayer make() => AudiobookPlayer(
        repository: repo,
        bookId: 'b',
        engine: () => engine,
        speedStore: MemorySpeedStore());

    test('chapters sit on the whole book', () async {
      final player = make();
      await player.load();
      expect([for (final c in player.chapters) c.title],
          ['Part 1', 'Two A', 'Two B', 'Part 3']);
      expect([for (final c in player.chapters) c.startMs], [0, 60000, 105000, 150000]);
      expect(player.total, const Duration(minutes: 3));
      player.dispose();
    });

    test('resumes in the right part, and crosses parts when seeking', () async {
      await repo.readingPositions.saveListenPosition('b', 100); // 1:40
      final player = make();
      await player.load();
      expect(engine.opened.single.$1, endsWith('p2.mp3'));
      expect(engine.opened.single.$2, const Duration(seconds: 40));
      expect(player.position, const Duration(seconds: 100));

      await player.jumpToChapter(3);
      expect(engine.opened.last.$1, endsWith('p3.mp3'));
      expect((await book()).listenPosition, 150, reason: 'a chapter skip saves');

      await player.skip(const Duration(seconds: -30));
      expect(engine.opened.last.$1, endsWith('p2.mp3'));
      expect(engine.opened.last.$2, const Duration(seconds: 60));
      player.dispose();
    });

    test('playing marks an unread book reading; pausing saves and queues it',
        () async {
      final player = make();
      await player.load();
      await player.play();
      expect((await book()).status, 'reading');
      engine.tick(const Duration(seconds: 12));
      await player.pause();
      final b = await book();
      expect(b.listenPosition, 12);
      expect(b.lastListenedAt, isNotNull);
      expect(b.needsProgressPush, isTrue);
      expect(b.readingProgress, isNull, reason: 'the text position is untouched');
      player.dispose();
    });

    test('the end of a part plays the next; the end of the book stops', () async {
      final player = make();
      await player.load();
      await player.play();
      engine.finishPart();
      await pumpEventQueue();
      expect(engine.opened.last.$1, endsWith('p2.mp3'));
      expect(engine.isPlaying, isTrue);
      await player.seek(const Duration(seconds: 170));
      engine.finishPart();
      await pumpEventQueue();
      expect(player.ended, isTrue);
      expect(player.playing, isFalse);
      expect((await book()).listenPosition, 180);
      player.dispose();
    });

    test('a part without a duration is measured once and the length kept',
        () async {
      await (repo.db.update(repo.db.bookFiles)..where((f) => f.id.equals('p1')))
          .write(const BookFilesCompanion(durationMs: Value(null)));
      engine.reportDuration = const Duration(seconds: 61);
      final player = make();
      await player.load();
      final p1 = await (repo.db.select(repo.db.bookFiles)
            ..where((f) => f.id.equals('p1')))
          .getSingle();
      expect(p1.durationMs, 61000);
      expect(player.total, const Duration(seconds: 181));
      expect((await book()).needsPush, isTrue, reason: 'durations are synced');
      player.dispose();
    });
  });

  group('the offer from another device', () {
    late Directory dir;
    late LibraryRepository repo;
    setUp(() async {
      dir = Directory.systemTemp.createTempSync('vellum_listen_offer');
      repo = await LibraryRepository.forTesting(
          VellumDatabase(NativeDatabase.memory()), dir);
    });
    tearDown(() async {
      await repo.db.close();
      dir.deleteSync(recursive: true);
    });

    RemoteReadingPosition remote(double? at, double? total, {String label = 'Pixel 8'}) =>
        RemoteReadingPosition(
          bookId: 'b',
          deviceId: label,
          deviceLabel: label,
          audioPosition: at,
          audioDuration: total,
          updatedAt: DateTime.utc(2026, 11),
        );

    test('same edition and well ahead: offered; otherwise not', () async {
      await repo.db.into(repo.db.books).insert(BooksCompanion.insert(
          id: 'b', title: 'Dune', listenPosition: const Value(100)));
      final b = (await repo.watchBook('b').first)!;
      final positions = repo.readingPositions;
      final offer = positions.listenOfferFor(
        book: b,
        totalSeconds: 54000,
        remotes: [remote(18753, 54001), remote(20000, 60000, label: 'Other narration')],
      );
      expect(offer!.seconds, 18753);
      expect(offer.deviceLabel, 'Pixel 8');

      expect(
          positions.listenOfferFor(
              book: b, totalSeconds: 54000, remotes: [remote(120, 54000)]),
          isNull,
          reason: 'twenty seconds ahead is noise');
      expect(
          positions.listenOfferFor(
              book: b, totalSeconds: 54000, remotes: [remote(30000, 54010)]),
          isNull,
          reason: 'ten seconds longer is a different edition');
      expect(
          positions.listenOfferFor(
              book: b, totalSeconds: 54000, remotes: [remote(null, null)]),
          isNull,
          reason: 'a device that only read');
    });
  });

  // The repository is real I/O, so it is made (and filled) in
  // `runAsync`; the page runs on the fake clock. [settle] alternates the two
  // so work started on either side can finish.
  testWidgets('the player page plays, skips and lists chapters', (tester) async {
    final dir = Directory.systemTemp.createTempSync('vellum_player_page');
    addTearDown(() => dir.deleteSync(recursive: true));
    final repo = (await tester.runAsync(() async {
      final repo = await LibraryRepository.forTesting(
          VellumDatabase(NativeDatabase.memory()), dir);
      final db = repo.db;
      await db.into(db.books).insert(BooksCompanion.insert(id: 'b', title: 'Dune'));
      await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
            id: 'p1',
            bookId: 'b',
            format: 'm4b',
            path: 'files/p1.m4b',
            sizeBytes: 1,
            sha256: 'h',
            durationMs: const Value(3600000),
            track: const Value(1),
          ));
      for (final (i, title, ms) in [(0, 'Prologue', 0), (1, 'The Desert', 600000)]) {
        await db.into(db.audioChapters).insert(AudioChaptersCompanion.insert(
            fileId: 'p1', idx: i, title: Value(title), startMs: ms));
      }
      return repo;
    }))!;
    Future<void> settle() async {
      for (var i = 0; i < 6; i++) {
        await tester.runAsync(() => Future<void>.delayed(const Duration(milliseconds: 10)));
        await tester.pump();
      }
    }

    final engine = FakeEngine();
    final host = PlaybackHost(
      engine: () => engine,
      speedStore: MemorySpeedStore(),
      background: BackgroundPlayback(handlerFactory: (_) async => null),
    );
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: PlayerPage(
        bookId: 'b',
        repository: repo,
        host: host,
      ),
    ));
    await settle();
    expect(find.text('The Desert'), findsOneWidget);
    expect(find.text('1:00:00'), findsOneWidget, reason: 'the total');

    await tester.tap(find.byTooltip('Play'));
    await settle();
    expect(engine.isPlaying, isTrue);

    await tester.tap(find.byTooltip('Forward 30 seconds'));
    await settle();
    expect(engine.position, const Duration(seconds: 30));

    await tester.tap(find.text('The Desert'));
    await settle();
    expect(engine.position, const Duration(minutes: 10));

    // Leaving the page leaves the book playing, and the position was saved by
    // the chapter jump.
    await tester.pumpWidget(const SizedBox());
    await settle();
    // Drift schedules a zero-length timer when a watched stream (the
    // download panel's) loses its last listener; let it fire.
    await tester.pump(const Duration(milliseconds: 1));
    expect(engine.isPlaying, isTrue);
    final saved = await tester.runAsync(() => (repo.db.select(repo.db.books)
          ..where((b) => b.id.equals('b')))
        .getSingle());
    expect(saved!.listenPosition, 600);
    await tester.runAsync(host.close); // stops the save timer
    // Not closed: closing a database opened outside the fake clock from
    // inside a widget test never completes, and an in-memory one holds
    // nothing worth releasing.
  });
}
