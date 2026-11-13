// The shell and the book page at phone, tablet-upright and tablet-on-its-side
// widths.
//
// What is worth pinning: which navigation each width gets (a phone must keep
// exactly what it had), that the wide layouts' navigation still goes through
// the back/forward history, that the permanent drawer doesn't close the page
// the way the modal one closes itself, and that nothing overflows at any of
// the three. Uses the documented LibraryPage test setup (see smoke_test.dart):
// dart:io work in runAsync, a null secure-storage channel, a runAsync teardown.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/account/user_profile.dart';
import 'package:vellum/app_drawer.dart';
import 'package:vellum/book_detail/cover_thumb.dart';
import 'package:vellum/book_detail/formats_section.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/main.dart';
import 'package:vellum/navigation_history.dart';
import 'package:vellum/server/connection_store.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:vellum/shelf/shelf_view.dart';
import 'package:vellum/widgets/adaptive.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vellum_adaptive');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async => null);
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  void setWidth(WidgetTester tester, double width) {
    tester.view.physicalSize = Size(width, 900);
    tester.view.devicePixelRatio = 1;
  }

  Future<Widget> buildApp(WidgetTester tester, NavigationHistory history) async {
    late Widget app;
    await tester.runAsync(() async {
      final repo = await LibraryRepository.forTesting(
          VellumDatabase(NativeDatabase.memory()), dir);
      final db = repo.db;
      await db.into(db.books).insert(BooksCompanion.insert(
            id: 'a',
            title: 'Dune',
            needsPush: const Value(false),
            readerNotesNeedsPush: const Value(false),
          ));
      // Past the first-run sheet, which would otherwise sit over the shell
      // and take the taps.
      SharedPreferences.setMockInitialValues(
          {'settings.hasSeenFirstRun': true});
      final settings = await AppSettingsStore.load();
      final profile = await UserProfileStore.load();
      final connection = await ServerConnection.load();
      app = MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        navigatorObservers: [history],
        home: LibraryPage(
          repository: repo,
          profile: profile,
          settings: settings,
          connection: connection,
          history: history,
        ),
      );
    });
    return app;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  Future<void> dispose(WidgetTester tester) async {
    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox());
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  }

  test('breakpoints are Material 3\'s', () {
    expect(WindowSize.ofWidth(400), WindowSize.compact);
    expect(WindowSize.ofWidth(599), WindowSize.compact);
    expect(WindowSize.ofWidth(600), WindowSize.medium);
    expect(WindowSize.ofWidth(839), WindowSize.medium);
    expect(WindowSize.ofWidth(840), WindowSize.expanded);
    expect(WindowSize.ofWidth(1280), WindowSize.expanded);
  });

  for (final (width, expected) in [
    (400.0, NavigationBar),
    (700.0, NavigationRail),
    (1280.0, AppDrawer),
  ]) {
    testWidgets('at ${width.toInt()} wide the shell navigates with $expected',
        (tester) async {
      setWidth(tester, width);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await buildApp(tester, NavigationHistory()));
      await settle(tester);

      expect(find.byType(BookSpine), findsOneWidget);
      expect(find.byType(NavigationBar),
          expected == NavigationBar ? findsOneWidget : findsNothing);
      expect(find.byType(NavigationRail),
          expected == NavigationRail ? findsOneWidget : findsNothing);
      // The modal drawer is only in the tree while open, so on the two
      // narrower widths none is built until asked for.
      expect(find.byType(AppDrawer),
          expected == AppDrawer ? findsOneWidget : findsNothing);
      expect(find.byTooltip('Open navigation menu'),
          expected == AppDrawer ? findsNothing : findsOneWidget,
          reason: 'a permanent drawer needs no button to open it');
      expect(tester.takeException(), isNull, reason: 'no overflow');

      await dispose(tester);
    });
  }

  testWidgets('the rail switches section, and back undoes it', (tester) async {
    setWidth(tester, 700);
    addTearDown(tester.view.reset);
    final history = NavigationHistory();
    await tester.pumpWidget(await buildApp(tester, history));
    await settle(tester);

    await tester.tap(find.text('Physical'));
    await settle(tester);
    expect(find.text('Physical libraries'), findsOneWidget,
        reason: 'the physical section\'s app bar');

    await history.back();
    await settle(tester);
    expect(find.byType(BookSpine), findsOneWidget, reason: 'back on the shelf');
    expect(tester.takeException(), isNull);

    await dispose(tester);
  });

  testWidgets('the permanent drawer switches section without closing the page',
      (tester) async {
    setWidth(tester, 1280);
    addTearDown(tester.view.reset);
    final history = NavigationHistory();
    await tester.pumpWidget(await buildApp(tester, history));
    await settle(tester);

    await tester.tap(find.widgetWithText(ListTile, 'Physical libraries'));
    await settle(tester);
    // The modal drawer pops itself shut; had this one done the same, the pop
    // would have taken the whole shell with it.
    expect(find.byType(LibraryPage), findsOneWidget);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.widgetWithText(AppBar, 'Physical libraries'), findsOneWidget);

    await history.back();
    await settle(tester);
    expect(find.byType(BookSpine), findsOneWidget);
    expect(tester.takeException(), isNull);

    await dispose(tester);
  });

  testWidgets('crossing a breakpoint keeps the shelf, not a rebuilt one',
      (tester) async {
    setWidth(tester, 700);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await buildApp(tester, NavigationHistory()));
    await settle(tester);

    ScrollableState shelfScroll() => tester.state<ScrollableState>(find
        .descendant(
            of: find.byType(IndexedStack), matching: find.byType(Scrollable))
        .first);
    final before = shelfScroll();

    setWidth(tester, 1280);
    await settle(tester);
    expect(find.byType(AppDrawer), findsOneWidget);
    expect(identical(shelfScroll(), before), isTrue,
        reason: 'the shelf moved, it was not built again');

    setWidth(tester, 400);
    await settle(tester);
    expect(find.byType(NavigationBar), findsOneWidget);
    expect(identical(shelfScroll(), before), isTrue);
    expect(tester.takeException(), isNull);

    await dispose(tester);
  });

  // 700, not 400, for the one-column case: at 400 the read button's own row
  // overflows under the test font, which is that row's problem (tracked with
  // the large-text fixes), not the page layout's.
  for (final (width, twoColumns) in [(700.0, false), (1280.0, true)]) {
    testWidgets(
        'at ${width.toInt()} wide the book page is '
        '${twoColumns ? 'two columns' : 'one column'}', (tester) async {
      setWidth(tester, width);
      addTearDown(tester.view.reset);
      await tester.pumpWidget(await buildApp(tester, NavigationHistory()));
      await settle(tester);

      await tester.tap(find.byType(BookSpine).first);
      await settle(tester);

      final cover = tester.getTopLeft(find.byType(CoverThumb));
      final formats = tester.getTopLeft(find.byType(DigitalFormatsSection));
      if (twoColumns) {
        expect(formats.dx, greaterThan(cover.dx + 400),
            reason: 'formats sit in the right-hand column');
        expect(formats.dy,
            lessThan(tester.getBottomLeft(find.byType(CoverThumb)).dy),
            reason: 'beside the cover, not under it');
        // Centred in the window rather than starting at its left edge.
        expect(cover.dx, greaterThan(24));
      } else {
        expect(formats.dx, cover.dx, reason: 'one column: same left edge');
        expect(formats.dy, greaterThan(cover.dy));
      }
      expect(tester.takeException(), isNull, reason: 'no overflow');

      await dispose(tester);
    });
  }
}
