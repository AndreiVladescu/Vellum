// The month-by-month page (roadmap v1.3.2): what it shows for a month with
// reading, the calm empty state, stepping between months, and the limits of
// the stepping. The arithmetic itself is pinned in month_review_test.dart.
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
import 'package:vellum/stats/heatmap_grid.dart';
import 'heatmap_test_utils.dart';
import 'package:vellum/stats/month_review_page.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_month_ui'));
  tearDown(() => dir.deleteSync(recursive: true));

  // A fixed "now" in the middle of November 2026.
  final now = DateTime(2026, 11, 12, 15);

  Future<void> pumpPage(
    WidgetTester tester, {
    bool seed = true,
    Size size = const Size(800, 2400),
    double textScale = 1,
  }) async {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);
    late LibraryRepository repo;
    late AppSettingsStore settings;
    await tester.runAsync(() async {
      SharedPreferences.setMockInitialValues({});
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

        // October: 100 pages over 100 minutes. November so far: 50 pages
        // over 50 minutes on a day inside the first twelve.
        await sitting('o1', DateTime(2026, 10, 3, 20), 60, 1, 61);
        await sitting('o2', DateTime(2026, 10, 20, 20), 40, 61, 101);
        await sitting('n1', DateTime(2026, 11, 4, 20), 50, 101, 151);
      }
    });
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context).copyWith(
          textScaler: TextScaler.linear(textScale),
        ),
        child: child!,
      ),
      home: MonthReviewPage(repository: repo, settings: settings, now: now),
    ));
    await tester.pumpAndSettle();
  }

  // Drift's stream cleanup posts a zero-duration timer; unmount inside the
  // test so it is not pending at teardown.
  Future<void> dispose(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  testWidgets('opens on the current month with its figures', (tester) async {
    await pumpPage(tester);
    expect(find.text('November 2026'), findsOneWidget);
    expect(find.text('50'), findsOneWidget); // pages
    expect(find.text('50m'), findsWidgets); // time, average, longest
    expect(find.text('1 of 12'), findsOneWidget); // days, out of days so far
    expect(find.text('Calendar'), findsOneWidget);
    // The month is part-finished, so October is weighed over the same days
    // (none of October's reading falls in 1-12 October except the 3rd).
    expect(find.text('Compared with October'), findsOneWidget);
    expect(find.textContaining('by this point in October'), findsWidgets);
    // Next is disabled on the current month.
    final next = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_right));
    expect(next.onPressed, isNull);
    await dispose(tester);
  });

  testWidgets('steps back to a finished month and lists its books',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('100'), findsOneWidget);
    expect(find.text('1h 40m'), findsOneWidget);
    expect(find.text('2 of 31'), findsOneWidget);
    expect(find.text('Piranesi'), findsOneWidget);
    // Nothing was read in September: said plainly, not as a percentage.
    expect(find.text('Compared with September'), findsOneWidget);
    expect(find.textContaining('Nothing was read in September'),
        findsOneWidget);
    await dispose(tester);
  });

  testWidgets('does not step before the first sitting', (tester) async {
    await pumpPage(tester);
    await tester.tap(find.byTooltip('Previous month'));
    await tester.pumpAndSettle();
    final back = tester.widget<IconButton>(
        find.widgetWithIcon(IconButton, Icons.chevron_left));
    expect(back.onPressed, isNull);
    await dispose(tester);
  });

  testWidgets('the month list jumps and offers only months with reading',
      (tester) async {
    await pumpPage(tester);
    await tester.tap(find.text('November 2026'));
    await tester.pumpAndSettle();
    expect(find.text('Jump to a month'), findsOneWidget);
    expect(find.text('September 2026'), findsNothing);
    await tester.tap(find.text('October 2026'));
    await tester.pumpAndSettle();
    expect(find.text('October 2026'), findsOneWidget);
    expect(find.text('Jump to a month'), findsNothing);
    await dispose(tester);
  });

  testWidgets('a month with no reading is a calm empty state',
      (tester) async {
    await pumpPage(tester, seed: false);
    expect(find.text('No reading in November 2026'), findsOneWidget);
    expect(find.text('Calendar'), findsNothing);
    expect(find.text('0'), findsNothing);
    await dispose(tester);
  });

  testWidgets('holds up at a phone width and large text', (tester) async {
    await pumpPage(
      tester,
      size: const Size(360, 2400),
      textScale: 2,
    );
    expect(tester.takeException(), isNull);
    expect(find.text('November 2026'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('each calendar day is a labelled node for a screen reader',
      (tester) async {
    final handle = tester.ensureSemantics();
    await pumpPage(tester);
    final labels = semanticsLabelsUnder(tester, find.byType(HeatmapGrid));
    expect(labels, contains('Wednesday, November 4: 50m read, 50 pages'));
    expect(labels, contains('Thursday, November 5: no reading'));
    // One node per day of the month, plus the grid's own label.
    expect(labels.where((l) => l.contains('November')).length, 30 + 1);
    handle.dispose();
    await dispose(tester);
  });
}
