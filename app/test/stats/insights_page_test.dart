// The reading insights screen (plan 5 #19, plan 6 refresh). The arithmetic
// behind every number here is pinned in stats_queries_test.dart; this only
// covers the screen's own promises — that a fresh library says so instead of
// showing empty charts, and that a library with real history renders the new
// sections rather than crashing on them.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/stats/insights_page.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_insights_ui'));
  tearDown(() => dir.deleteSync(recursive: true));

  // The page is one long ListView, and a ListView only *mounts* the children
  // near its viewport — the default 600-logical-pixel test surface leaves
  // everything past "Pages a day" simply never built, not merely offscreen.
  // Growing the surface to fit the whole page is simpler than scrolling to
  // each section in every assertion below.
  void growView(WidgetTester tester) {
    tester.view.physicalSize = const Size(800, 3600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
  }

  Future<LibraryRepository> pumpInsights(
    WidgetTester tester, {
    required bool seed,
  }) async {
    growView(tester);
    late LibraryRepository repo;
    await tester.runAsync(() async {
      repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dir,
      );
      if (seed) {
        await repo.db.into(repo.db.books).insert(BooksCompanion.insert(
              id: 'b1',
              title: 'Piranesi',
              finishedAt: Value(DateTime(2026, 7, 20)),
              status: const Value('finished'),
            ));
        await repo.db.into(repo.db.bookFiles).insert(BookFilesCompanion.insert(
              id: 'f1',
              bookId: 'b1',
              format: 'epub',
              path: 'piranesi.epub',
              sizeBytes: 1024,
              sha256: 'x',
            ));
        // Two sittings on two different days, so streaks, totals and the
        // hour-of-day bars all have something real to draw.
        await repo.db
            .into(repo.db.readingSessions)
            .insert(ReadingSessionsCompanion.insert(
              id: 's1',
              bookId: 'b1',
              startedAt: DateTime(2026, 7, 19, 21),
              endedAt: DateTime(2026, 7, 19, 21, 40),
              startPage: const Value(1),
              endPage: const Value(30),
              deviceLabel: const Value('Pixel'),
            ));
        await repo.db
            .into(repo.db.readingSessions)
            .insert(ReadingSessionsCompanion.insert(
              id: 's2',
              bookId: 'b1',
              startedAt: DateTime(2026, 7, 20, 9),
              endedAt: DateTime(2026, 7, 20, 9, 30),
              startPage: const Value(30),
              endPage: const Value(60),
              deviceLabel: const Value('Desk'),
            ));
      }
    });
    await tester.pumpWidget(MaterialApp(home: InsightsPage(repository: repo)));
    await tester.pumpAndSettle();
    return repo;
  }

  testWidgets('a library with no reading history says so', (tester) async {
    await pumpInsights(tester, seed: false);
    expect(find.text('Nothing to show yet'), findsOneWidget);
    expect(find.text('Totals'), findsNothing);
  });

  testWidgets('real history renders every new section', (tester) async {
    await pumpInsights(tester, seed: true);

    expect(find.text('Habits'), findsOneWidget);
    expect(find.text('Totals'), findsOneWidget);
    // Lifetime totals: page 1->30 then 30->60 is 29 + 30 = 59 pages, over
    // 40 + 30 = 70 minutes. Bare small integers like a book count of "1" are
    // left unchecked here — too many tiles could coincidentally show one.
    expect(find.text('Pages read'), findsOneWidget);
    expect(find.text('59'), findsOneWidget);
    expect(find.text('Time reading'), findsOneWidget);
    expect(find.text('1h 10m'), findsOneWidget);
    // Appears twice by design: the stat tile and the finished-months section
    // title below share the same label.
    expect(find.text('Books finished'), findsNWidgets(2));

    // The best-day callout: the later, bigger sitting's day.
    expect(find.textContaining('Your best day: 30 pages'), findsOneWidget);

    // The two new charts.
    expect(find.text('When you read'), findsOneWidget);
    expect(find.text('Reading days (last 12 weeks)'), findsOneWidget);

    // Two distinct devices, so the device breakdown earns its section.
    expect(find.text('Where you read'), findsOneWidget);
    expect(find.text('Pixel'), findsOneWidget);
    expect(find.text('Desk'), findsOneWidget);

    // One finished book, kept as an EPUB.
    expect(find.text('On paper or on screen'), findsOneWidget);
    expect(find.text('EPUB'), findsOneWidget);
  });

  testWidgets('a single device earns no breakdown of one', (tester) async {
    growView(tester);
    late LibraryRepository repo;
    await tester.runAsync(() async {
      repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dir,
      );
      await repo.db.into(repo.db.books).insert(
          BooksCompanion.insert(id: 'b1', title: 'Piranesi'));
      await repo.db
          .into(repo.db.readingSessions)
          .insert(ReadingSessionsCompanion.insert(
            id: 's1',
            bookId: 'b1',
            startedAt: DateTime(2026, 7, 19, 21),
            endedAt: DateTime(2026, 7, 19, 21, 40),
            startPage: const Value(1),
            endPage: const Value(30),
          ));
    });
    await tester.pumpWidget(MaterialApp(home: InsightsPage(repository: repo)));
    await tester.pumpAndSettle();
    expect(find.text('Where you read'), findsNothing);
  });
}
