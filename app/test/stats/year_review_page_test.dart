// The year-in-review page (roadmap v1.3.5): figures, stepping between years,
// the empty year, and the shareable card rendering to a PNG in both themes.
// The arithmetic is pinned in year_review_test.dart.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:vellum/stats/year_card.dart';
import 'package:vellum/stats/year_review.dart';
import 'package:vellum/stats/year_review_page.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_year_ui'));
  tearDown(() => dir.deleteSync(recursive: true));

  final now = DateTime(2026, 11, 12, 15);

  Future<void> pumpPage(WidgetTester tester, {bool seed = true}) async {
    tester.view.physicalSize = const Size(800, 2600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late LibraryRepository repo;
    late AppSettingsStore settings;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({'settings.readingGoalBooks': 4});
      settings = await AppSettingsStore.load();
      repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dir,
      );
      if (seed) {
        await repo.db.into(repo.db.books).insert(BooksCompanion.insert(
              id: 'b1',
              title: 'Piranesi',
              finishedAt: Value(DateTime(2026, 10, 20)),
              status: const Value('finished'),
            ));
        Future<void> sitting(String id, DateTime at, int minutes, int from,
            int to) {
          return repo.db
              .into(repo.db.readingSessions)
              .insert(ReadingSessionsCompanion.insert(
                id: id,
                bookId: 'b1',
                startedAt: at,
                endedAt: at.add(Duration(minutes: minutes)),
                startPage: Value(from),
                endPage: Value(to),
              ));
        }

        await sitting('a', DateTime(2025, 5, 3, 20), 60, 1, 61);
        await sitting('o1', DateTime(2026, 10, 3, 20), 60, 1, 61);
        await sitting('n1', DateTime(2026, 11, 4, 20), 90, 61, 151);
      }
    });
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: YearReviewPage(repository: repo, settings: settings, now: now),
    ));
    await tester.pumpAndSettle();
  }

  // Drift's stream cleanup posts a zero-duration timer; unmount in the test.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('opens on this year with its figures, goal and comparison',
      (tester) async {
    await pumpPage(tester);
    expect(find.text('2026'), findsWidgets);
    expect(find.text('1'), findsWidgets); // books finished
    expect(find.text('1 of 4 books'), findsOneWidget);
    expect(find.text('Compared with 2025'), findsOneWidget);
    expect(find.textContaining('more pages than in 2025'), findsOneWidget);
    expect(find.byType(FilledButton), findsOneWidget); // save or share
    // Next is disabled on the current year.
    final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right));
    expect(next.onPressed, isNull);
    await dispose(tester);
  });

  testWidgets('steps back to an earlier year and stops at the first',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byTooltip('Previous year'));
    await tester.pumpAndSettle();
    expect(find.text('2025'), findsWidgets);
    final prev = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left));
    expect(prev.onPressed, isNull);
    await dispose(tester);
  });

  testWidgets('a year with nothing in it says so and has no picture',
      (tester) async {
    await pumpPage(tester, seed: false);
    expect(find.text('Nothing read in 2026'), findsOneWidget);
    expect(find.byType(YearCard), findsNothing);
    expect(find.text('Share picture'), findsNothing);
    await dispose(tester);
  });

  for (final brightness in Brightness.values) {
    testWidgets('the card renders to a PNG in ${brightness.name} theme',
        (tester) async {
      final key = GlobalKey();
      final review = YearReviews.review(
        sessions: [
          ReadingSession(
            id: 's',
            bookId: 'b',
            startedAt: DateTime(2026, 3, 1, 20),
            endedAt: DateTime(2026, 3, 1, 21),
            startPage: 1,
            endPage: 20,
            needsPush: false,
          ),
        ],
        books: [],
        year: 2026,
      );
      await tester.pumpWidget(MaterialApp(
        theme: ThemeData(
          colorScheme: ColorScheme.fromSeed(
              seedColor: Colors.indigo, brightness: brightness),
        ),
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: Center(
            child: RepaintBoundary(key: key, child: YearCard(review: review)),
          ),
        ),
      ));
      expect(find.text('Year in review'), findsOneWidget);
      expect(find.text('2026'), findsOneWidget);
      // Image encoding is real async work, outside the fake-async test zone.
      final bytes = await tester.runAsync(() => captureYearCard(key));
      expect(bytes, isNotNull);
      // PNG signature.
      expect(bytes!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
    });
  }
}
