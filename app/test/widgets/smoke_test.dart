import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/account/user_profile.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/main.dart';
import 'package:vellum/server/connection_store.dart';
import 'package:vellum/server/server_page.dart';
import 'package:vellum/server/sync_service.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:vellum/settings/book_face.dart';
import 'package:vellum/settings/preferences_page.dart';
import 'package:vellum/shelf/shelf_filter.dart';
import 'package:vellum/shelf/shelf_view.dart';

/// Structural smoke tests over real app widgets — no goldens, so they don't
/// flake across platforms/fonts. They guard the heavily-rebuilt screens
/// (shelf, detail, preferences, server) against a silent render regression.
///
/// The shelf-render/search case drives [ShelfView] with a plain book list and
/// the real [filterBooks], rather than the whole [LibraryPage]: LibraryPage
/// recreates its drift `.watch()` streams on every build, and that subscription
/// churn under testWidgets' FakeAsync zone leaves stream-cancel timers pending
/// that the end-of-test leak check trips on. Driving the widgets directly keeps
/// the test deterministic while still exercising the real rendering + filter.
///
/// The tap-to-detail case does use the real LibraryPage; two testWidgets
/// gotchas shaped it (and the shared helpers below):
///  * Opening the repository touches dart:io (mkdir/list), which never
///    completes under FakeAsync — so setup runs inside [WidgetTester.runAsync].
///  * flutter_secure_storage's platform channel would otherwise hang
///    ServerConnection.load(); a null-returning mock resolves it (the token is
///    seeded via plaintext prefs, the documented fallback path).

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

Future<LibraryRepository> _repo(Directory dir) async =>
    LibraryRepository.forTesting(VellumDatabase(NativeDatabase.memory()), dir);

/// A minimal cover-less [Book] (so [ShelfView] draws a generated spine).
Book _book(String id, String title) => Book(
      id: id,
      title: title,
      createdAt: DateTime(2024),
      updatedAt: DateTime(2024),
      needsPush: false, syncExcluded: false,
      readerNotesNeedsPush: false,
      statusNeedsPush: false,
      needsProgressPush: false,
      status: 'unread',
      readCount: 0,
    );

/// Seeds a clean (already-pushed) book so the launch auto-push schedules no
/// timer — a pending timer would fail the test at teardown.
Future<void> _seed(LibraryRepository repo, String id, String title) async {
  final db = repo.db;
  await db.into(db.books).insert(
        BooksCompanion.insert(
          id: id,
          title: title,
          needsPush: const Value(false),
          readerNotesNeedsPush: const Value(false),
        ),
      );
}

/// Pumps a few bounded frames so streams emit and short animations run, without
/// waiting for a perpetually-scheduling widget (a text cursor would make
/// pumpAndSettle time out).
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 100));
  }
}

/// Unmounts a LibraryPage tree on the real event loop, so drift's async stream
/// teardown completes and leaves nothing pending for the leak check.
Future<void> _disposeTree(WidgetTester tester) async {
  await tester.runAsync(() async {
    await tester.pumpWidget(const SizedBox());
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
}

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vellum_widget_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async => null);
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  Future<Widget> buildLibrary(LibraryRepository repo) async {
    SharedPreferences.setMockInitialValues({}); // disconnected, defaults
    final settings = await AppSettingsStore.load();
    final profile = await UserProfileStore.load();
    final connection = await ServerConnection.load();
    return MaterialApp(
      // The real app registers these (plan 5 #38); a page that looks a string
      // up would otherwise throw on a null L10n, which is the point of
      // `nullable-getter: false`.
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: LibraryPage(
        repository: repo,
        profile: profile,
        settings: settings,
        connection: connection,
      ),
    );
  }

  testWidgets('shelf renders a spine per book and search narrows them',
      (tester) async {
    final books = [_book('a', 'Dune'), _book('b', 'Hyperion'), _book('c', 'Neuromancer')];
    final authors = {
      'a': ['Frank Herbert'],
      'b': <String>[],
      'c': <String>[],
    };

    Widget shelf(List<Book> shown) => MaterialApp(
          home: Scaffold(
            body: ShelfView(books: shown, detailBuilder: (_) => const SizedBox()),
          ),
        );

    await tester.pumpWidget(shelf(books));
    await tester.pump();
    expect(find.byType(BookSpine), findsNWidgets(3));

    // The real search filter narrows to the matching title...
    final byTitle = filterBooks(
        books: books, query: 'dune', authorsByBook: authors, genresByBook: const {});
    await tester.pumpWidget(shelf(byTitle));
    await tester.pump();
    expect(find.byType(BookSpine), findsOneWidget,
        reason: 'search narrows the shelf to the matching title');

    // ...and matches an author name, not just the title.
    final byAuthor = filterBooks(
        books: books, query: 'herbert', authorsByBook: authors, genresByBook: const {});
    expect(byAuthor.map((b) => b.id), ['a'],
        reason: 'a query matches author names too');
  });

  testWidgets('tapping a spine opens the book detail page', (tester) async {
    late Widget app;
    await tester.runAsync(() async {
      final repo = await _repo(dir);
      await _seed(repo, 'a', 'Dune');
      app = await buildLibrary(repo);
    });

    await tester.pumpWidget(app);
    await _settle(tester);

    await tester.tap(find.byType(BookSpine).first);
    await _settle(tester); // run the pull-out route animation to completion

    // The detail page shows the title (app bar + header); the shelf paints its
    // spine title on a canvas, so this text can only come from the detail page.
    expect(find.text('Dune'), findsWidgets);

    await _disposeTree(tester);
  });

  testWidgets('preferences shows the spine-art control only in spine mode',
      (tester) async {
    // A surface tall enough for the whole page. Preferences is a lazy ListView,
    // so a control below the fold isn't built at all and `find.text` can't see
    // it — which says nothing about the behaviour under test. Adding the
    // Appearance section (plan 5 #39) above this one is what pushed it off the
    // default 800x600 view.
    tester.view.physicalSize = const Size(1200, 3200);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);

    late LibraryRepository repo;
    late AppSettingsStore settings;
    late ServerConnection connection;
    await tester.runAsync(() async {
      repo = await _repo(dir);
      SharedPreferences.setMockInitialValues({});
      settings = await AppSettingsStore.load();
      connection = await ServerConnection.load();
    });

    await tester.pumpWidget(MaterialApp(
      home: PreferencesPage(
        settings: settings,
        repository: repo,
        connection: connection,
        sync: SyncService(repo),
      ),
    ));
    await _settle(tester);

    const label = 'Spine artwork for books with a cover';
    expect(find.text(label), findsOneWidget, reason: 'spine mode is the default');

    await settings.setBookFace(BookFace.cover);
    await _settle(tester);
    expect(find.text(label), findsNothing,
        reason: 'face-out mode hides the spine-art control');

    // Take the tree down inside the test. On a surface this tall the trash
    // tile's live drift `.watch()` is built too, and cancelling it at teardown
    // schedules a zero-duration timer that trips the pending-timer check.
    await tester.pumpWidget(const SizedBox.shrink());
    await _settle(tester);
  });

  testWidgets('server page offers Sync now when connected', (tester) async {
    late LibraryRepository repo;
    late ServerConnection connection;
    late AppSettingsStore settings;
    await tester.runAsync(() async {
      repo = await _repo(dir);
      SharedPreferences.setMockInitialValues({
        'server.url': 'http://server.test',
        'server.token': 'tok', // secure store mocked → prefs fallback
        'server.email': 'reader@example.com',
      });
      connection = await ServerConnection.load();
      settings = await AppSettingsStore.load();
    });
    expect(connection.isConnected, true);

    await tester.pumpWidget(MaterialApp(
      home: ServerPage(
        connection: connection,
        repository: repo,
        sync: SyncService(repo),
        settings: settings,
      ),
    ));
    await _settle(tester);

    expect(find.text('Sync now'), findsOneWidget);
  });
}
