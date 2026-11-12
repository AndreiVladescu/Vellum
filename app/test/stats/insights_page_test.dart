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
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/stats/heatmap_grid.dart';
import 'package:vellum/stats/insights_page.dart';
import 'package:vellum/stats/insights_range.dart';
import 'heatmap_test_utils.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';

void main() {
  late Directory dir;
  late AppSettingsStore settings;
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
    InsightsRange? range,
  }) async {
    growView(tester);
    late LibraryRepository repo;
    await tester.runAsync(() async {
      // A fresh settings store per test, so one test's goals never leak.
      SharedPreferences.setMockInitialValues({});
      settings = await AppSettingsStore.load();
      if (range != null) await settings.setInsightsRange(range);
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
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: InsightsPage(repository: repo, settings: settings)));
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
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: InsightsPage(repository: repo, settings: settings)));
    await tester.pumpAndSettle();
    expect(find.text('Where you read'), findsNothing);
  });

  testWidgets('with no goal set the card offers one and shows no progress',
      (tester) async {
    await pumpInsights(tester, seed: true);
    expect(find.text('Goals'), findsOneWidget);
    expect(find.text('Set a goal'), findsOneWidget);
    expect(find.text('Reading today'), findsNothing);
    expect(find.text('Books in ${DateTime.now().year}'), findsNothing);
  });

  testWidgets('goals are set from the card and shown as progress',
      (tester) async {
    await pumpInsights(tester, seed: true);
    await tester.tap(find.text('Set a goal'));
    await tester.pumpAndSettle();
    expect(find.text('Reading goals'), findsOneWidget);
    final dialog = find.byType(AlertDialog);
    await tester.tap(find.descendant(of: dialog, matching: find.text('24')));
    await tester.tap(find.descendant(of: dialog, matching: find.text('30m')));
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(settings.readingGoalBooks, 24);
    expect(settings.readingGoalMinutes, 30);
    expect(find.text('Books in ${DateTime.now().year}'), findsOneWidget);
    expect(find.text('Reading today'), findsOneWidget);

    // And "no goal" takes them off again in one tap each.
    await tester.tap(find.byTooltip('Edit goals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('No goal').first);
    await tester.tap(find.text('No goal').last);
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(settings.readingGoalBooks, isNull);
    expect(settings.readingGoalMinutes, isNull);
    expect(find.text('Reading today'), findsNothing);
    expect(find.text('Set a goal'), findsOneWidget);
  });

  testWidgets('a free number can be typed', (tester) async {
    await pumpInsights(tester, seed: true);
    await tester.tap(find.byTooltip('Edit goals'));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Other').first);
    await tester.pumpAndSettle();
    await tester.enterText(find.byType(TextField), '40');
    await tester.tap(find.text('Save'));
    await tester.pumpAndSettle();
    expect(settings.readingGoalBooks, 40);
  });

  testWidgets('the default range is the page as it always was',
      (tester) async {
    await pumpInsights(tester, seed: true);
    expect(settings.insightsRange, InsightsRange.standard);
    final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Default'));
    expect(chip.selected, isTrue);
    expect(
        find.text('Totals and lists cover all time; the daily chart shows '
            'the last 30 days.'),
        findsOneWidget);
    expect(find.text('Pages a day (last 30)'), findsOneWidget);
    // Lifetime totals, as before the control existed.
    expect(find.text('1h 10m'), findsOneWidget);
  });

  testWidgets('choosing a range filters the totals and is remembered',
      (tester) async {
    await pumpInsights(tester, seed: true);
    await tester.tap(find.widgetWithText(ChoiceChip, 'Last 30 days'));
    await tester.pumpAndSettle();
    expect(settings.insightsRange, InsightsRange.last30Days);
    // The seeded sittings are from July 2026, outside the last 30 days.
    expect(find.text('1h 10m'), findsNothing);
    expect(find.text('0m'), findsWidgets);

    await tester.tap(find.widgetWithText(ChoiceChip, 'All time'));
    await tester.pumpAndSettle();
    expect(settings.insightsRange, InsightsRange.allTime);
    expect(find.text('1h 10m'), findsOneWidget);
    expect(find.text('Pages a day (all time)'), findsOneWidget);
  });

  testWidgets('a stored range is what the page opens on', (tester) async {
    await pumpInsights(tester,
        seed: true, range: InsightsRange.last30Days);
    final chip = tester.widget<ChoiceChip>(
        find.widgetWithText(ChoiceChip, 'Last 30 days'));
    expect(chip.selected, isTrue);
    expect(find.text('1h 10m'), findsNothing);
  });

  testWidgets('the streaks and the 12-week map ignore the range',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpInsights(tester, seed: true);
    int days() => semanticsLabelsUnder(tester, find.byType(HeatmapGrid))
        .where((l) => l.contains(': '))
        .length;
    final before = days();
    await tester.tap(find.widgetWithText(ChoiceChip, 'This year'));
    await tester.pumpAndSettle();
    expect(days(), before);
    // One labelled node per day of the 12 weeks.
    expect(before, 84);
    handle.dispose();
  });

  testWidgets('the range control and heat map hold up at phone width and 2x text',
      (tester) async {
    tester.platformDispatcher.textScaleFactorTestValue = 2;
    addTearDown(tester.platformDispatcher.clearTextScaleFactorTestValue);
    await pumpInsights(tester, seed: true);
    tester.view.physicalSize = const Size(360, 12000);
    await tester.pumpAndSettle();
    expect(tester.takeException(), isNull);
    expect(find.widgetWithText(ChoiceChip, 'Last 30 days'), findsOneWidget);
    expect(find.byType(HeatmapGrid), findsOneWidget);
  });

  testWidgets('the Month by month entry opens the review', (tester) async {
    await pumpInsights(tester, seed: true);
    await tester.tap(find.text('Month by month'));
    await tester.pumpAndSettle();
    expect(find.byTooltip('Previous month'), findsOneWidget);
    // Drift's stream cleanup posts a zero-duration timer; unmount in-test.
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  });
}
