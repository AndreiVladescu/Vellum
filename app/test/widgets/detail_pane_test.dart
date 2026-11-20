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
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/account/user_profile.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/l10n/delegates.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/main.dart';
import 'package:vellum/navigation_history.dart';
import 'package:vellum/server/connection_store.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:vellum/book_detail/book_detail_page.dart';
import 'package:vellum/shelf/detail_pane.dart';
import 'package:vellum/shelf/shelf_view.dart';

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vellum_pane');
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
      for (final (id, title) in [('a', 'Dune'), ('b', 'Emma')]) {
        await db.into(db.books).insert(BooksCompanion.insert(
              id: id,
              title: title,
              needsPush: const Value(false),
              readerNotesNeedsPush: const Value(false),
            ));
      }
      // Past the first-run sheet, which would otherwise sit over the shell
      // and take the taps.
      SharedPreferences.setMockInitialValues(
          {'settings.hasSeenFirstRun': true});
      final settings = await AppSettingsStore.load();
      final profile = await UserProfileStore.load();
      final connection = await ServerConnection.load();
      app = MaterialApp(
        localizationsDelegates: appLocalizationsDelegates,
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

  Finder pane() => find.byType(DetailPane);
  Finder inPane(Finder f) => find.descendant(of: pane(), matching: f);

  Future<void> openFirst(WidgetTester tester) async {
    await tester.tap(find.byType(BookSpine).first);
    await settle(tester);
  }

  String openId(WidgetTester tester) =>
      tester.widget<BookDetailPage>(find.byType(BookDetailPage)).book.id;

  testWidgets('at 1600 a tap opens the book in the pane, not a page',
      (tester) async {
    setWidth(tester, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await buildApp(tester, NavigationHistory()));
    await settle(tester);
    expect(find.byType(BookDetailPage), findsNothing);
    expect(find.text('Select a book to see its details here.'), findsOneWidget);

    await openFirst(tester);
    expect(inPane(find.byType(BookDetailPage)), findsOneWidget);
    expect(find.byTooltip('Close'), findsOneWidget);
    expect(tester.takeException(), isNull);
    await dispose(tester);
  });

  testWidgets('at 900 a tap pushes the page and there is no pane',
      (tester) async {
    setWidth(tester, 900);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await buildApp(tester, NavigationHistory()));
    await settle(tester);
    expect(pane(), findsNothing);

    await openFirst(tester);
    expect(find.byType(BookDetailPage), findsOneWidget);
    expect(pane(), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('the close button and Esc empty the pane', (tester) async {
    setWidth(tester, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await buildApp(tester, NavigationHistory()));
    await settle(tester);

    await openFirst(tester);
    await tester.tap(find.byTooltip('Close'));
    await settle(tester);
    expect(find.byType(BookDetailPage), findsNothing);

    await openFirst(tester);
    expect(find.byType(BookDetailPage), findsOneWidget);
    await tester.sendKeyEvent(LogicalKeyboardKey.escape);
    await settle(tester);
    expect(find.byType(BookDetailPage), findsNothing);
    await dispose(tester);
  });

  testWidgets('selecting another book swaps the pane', (tester) async {
    setWidth(tester, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await buildApp(tester, NavigationHistory()));
    await settle(tester);
    await openFirst(tester);
    final first = openId(tester);
    await tester.tap(find.byType(BookSpine).last);
    await settle(tester);
    expect(openId(tester), isNot(first));
    await dispose(tester);
  });

  testWidgets('resizing keeps the selection, pane to page and back',
      (tester) async {
    setWidth(tester, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await buildApp(tester, NavigationHistory()));
    await settle(tester);
    await openFirst(tester);
    final id = openId(tester);

    setWidth(tester, 900);
    await tester.pump();
    await settle(tester);
    expect(pane(), findsNothing);
    expect(find.byType(BackButton), findsOneWidget);
    expect(openId(tester), id);

    setWidth(tester, 1600);
    await tester.pump();
    await settle(tester);
    expect(find.byType(BackButton), findsNothing);
    expect(inPane(find.byType(BookDetailPage)), findsOneWidget);
    expect(openId(tester), id);
    expect(tester.takeException(), isNull);
    await dispose(tester);
  });

  testWidgets('trashing the book empties the pane', (tester) async {
    setWidth(tester, 1600);
    addTearDown(tester.view.reset);
    await tester.pumpWidget(await buildApp(tester, NavigationHistory()));
    await settle(tester);
    await openFirst(tester);

    final trash = inPane(find.text('Move to trash'));
    await tester.scrollUntilVisible(trash, 300,
        scrollable: inPane(find.byType(Scrollable)).first);
    await tester.tap(trash);
    await settle(tester);
    await tester.tap(find.widgetWithText(FilledButton, 'Move to trash'));
    await settle(tester);
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 100)));
    await settle(tester);
    expect(find.byType(BookDetailPage), findsNothing);
    expect(find.text('Select a book to see its details here.'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('selecting does not rebuild the shelf spines', (tester) async {
    final controller = DetailPaneController()..enabled = true;
    addTearDown(controller.dispose);
    late List<Book> books;
    await tester.runAsync(() async {
      final repo = await LibraryRepository.forTesting(
          VellumDatabase(NativeDatabase.memory()), dir);
      for (final id in ['x', 'y', 'z']) {
        await repo.db.into(repo.db.books).insert(BooksCompanion.insert(
              id: id,
              title: id,
              needsPush: const Value(false),
              readerNotesNeedsPush: const Value(false),
            ));
      }
      books = await repo.db.select(repo.db.books).get();
      await repo.db.close();
    });
    var builds = 0;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: ShelfView(
          books: books,
          pane: controller,
          detailBuilder: (b) => const SizedBox(),
          coverFileOf: (_) {
            builds++;
            return null;
          },
        ),
      ),
    ));
    await tester.pump();
    final initial = builds;
    expect(initial, greaterThanOrEqualTo(3));

    controller.select(books[1]);
    await tester.pump();
    controller.select(books[2]);
    await tester.pump();
    expect(builds, initial, reason: 'no spine was rebuilt');
    expect(find.byType(PaneHighlight), findsNWidgets(3));
  });
}
