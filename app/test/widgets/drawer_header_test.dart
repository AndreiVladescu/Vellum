// The drawer header's two lines.
//
// The email under the avatar is *your* profile's, and it has to keep up with an
// edit made on the Account page. It used to be replaced by the signed-in
// account's the moment you connected, which left the profile email editable on
// one screen and shown on none.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/account/user_profile.dart';
import 'package:vellum/app_drawer.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/server/connection_store.dart';
import 'package:vellum/server/sync_service.dart';
import 'package:vellum/settings/app_settings.dart';

// flutter_secure_storage's channel would otherwise hang ServerConnection.load();
// a null-returning mock sends it down the documented plaintext-prefs fallback.
const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vellum_drawer_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async => null);
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  /// Tears the tree down inside the test.
  ///
  /// The drawer's wishlist count is a drift `.watch()`, and cancelling that
  /// subscription posts a zero-duration timer (drift's `markAsClosed`). Left to
  /// teardown it is still pending when the tree is disposed, which trips the
  /// leak check — so unmount first and pump the timer out.
  Future<void> disposeTree(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox());
    await tester.pump(Duration.zero);
  }

  /// Builds the drawer over [prefs], and hands back the profile so a test can
  /// edit it the way the Account page does.
  /// The repository the last [buildDrawer] built, for tests that need to seed
  /// rows the drawer then counts.
  late LibraryRepository builtRepository;

  Future<(Widget, UserProfileStore)> buildDrawer(
    WidgetTester tester,
    Map<String, Object> prefs,
  ) async {
    SharedPreferences.setMockInitialValues(prefs);
    final repository = await LibraryRepository.forTesting(
      VellumDatabase(NativeDatabase.memory()),
      dir,
    );
    builtRepository = repository;
    final profile = await UserProfileStore.load(dataDir: dir);
    final settings = await AppSettingsStore.load();
    final connection = await ServerConnection.load();
    return (
      MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: AppDrawer(
            profile: profile,
            settings: settings,
            connection: connection,
            repository: repository,
            sync: SyncService(repository, profile: profile),
          ),
        ),
      ),
      profile,
    );
  }

  testWidgets('shows the profile email, and follows an edit to it',
      (tester) async {
    late UserProfileStore profile;
    await tester.runAsync(() async {
      final (widget, store) = await buildDrawer(tester, {
        'profile.name': 'Testus Amogus',
        'profile.email': 'first@example.com',
      });
      profile = store;
      await tester.pumpWidget(widget);
    });
    await tester.pump();

    expect(find.text('first@example.com'), findsOneWidget);

    // What the Account page's Save does.
    await tester.runAsync(
      () => profile.save(name: 'Testus Amogus', email: 'second@example.com'),
    );
    await tester.pump();

    expect(find.text('second@example.com'), findsOneWidget,
        reason: 'the header follows the store, it does not cache the first '
            'email it was built with');
    expect(find.text('first@example.com'), findsNothing);

    await disposeTree(tester);
  });

  testWidgets('connected: the header keeps your email, the server tile has '
      'the account', (tester) async {
    await tester.runAsync(() async {
      final (widget, _) = await buildDrawer(tester, {
        'profile.name': 'Testus Amogus',
        'profile.email': 'me@example.com',
        'server.url': 'http://a.test',
        'server.token': 'tok',
        'server.email': 'account@example.com',
      });
      await tester.pumpWidget(widget);
    });
    await tester.pump();

    expect(find.text('me@example.com'), findsOneWidget,
        reason: 'connecting does not overwrite the line the Account page edits');
    expect(find.text('Connected · account@example.com'), findsOneWidget,
        reason: 'the identity you sync as stays visible in the same drawer');

    await disposeTree(tester);
  });

  testWidgets('with no profile email, connected shows the account', (tester) async {
    await tester.runAsync(() async {
      final (widget, _) = await buildDrawer(tester, {
        'profile.name': 'Testus Amogus',
        'server.url': 'http://a.test',
        'server.token': 'tok',
        'server.email': 'account@example.com',
      });
      await tester.pumpWidget(widget);
    });
    await tester.pump();

    expect(find.text('account@example.com'), findsOneWidget,
        reason: 'better than a blank line under the name');

    await disposeTree(tester);
  });

  testWidgets('with neither, the line says where the library lives',
      (tester) async {
    await tester.runAsync(() async {
      final (widget, _) = await buildDrawer(tester, {'profile.name': 'Testus'});
      await tester.pumpWidget(widget);
    });
    await tester.pump();

    expect(find.text('Local library'), findsOneWidget);

    await disposeTree(tester);
  });
  testWidgets('an overdue loan is counted in the drawer', (tester) async {
    // The one thing on this screen that should come and find you: everything
    // else you go looking for, but a book someone has kept too long is only
    // discoverable today by opening the Loans page and noticing.
    late Widget drawer;
    await tester.runAsync(() async {
      final built = await buildDrawer(tester, {});
      drawer = built.$1;
      final repo = builtRepository;
      final db = repo.db;
      await db.into(db.books).insert(
          BooksCompanion.insert(id: 'b1', title: 'Dune'));
      await db.into(db.physicalCopies).insert(
          PhysicalCopiesCompanion.insert(id: 'c1', bookId: 'b1'));
      // Due a week ago, never returned.
      await db.into(db.loans).insert(LoansCompanion.insert(
            id: 'l1',
            copyId: 'c1',
            borrower: 'Ana',
            dueAt: Value(DateTime.now().subtract(const Duration(days: 7))),
          ));
    });

    await tester.pumpWidget(drawer);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await tester.pump(const Duration(milliseconds: 20));
    }

    expect(find.text('Loans'), findsOneWidget);
    expect(find.text('1'), findsOneWidget);
    await disposeTree(tester);
  });

  testWidgets('nothing overdue shows no number at all', (tester) async {
    late Widget drawer;
    await tester.runAsync(() async {
      final built = await buildDrawer(tester, {});
      drawer = built.$1;
      final db = builtRepository.db;
      await db.into(db.books).insert(
          BooksCompanion.insert(id: 'b1', title: 'Dune'));
      await db.into(db.physicalCopies).insert(
          PhysicalCopiesCompanion.insert(id: 'c1', bookId: 'b1'));
      // Due in a fortnight: lent out, but nothing is wrong.
      await db.into(db.loans).insert(LoansCompanion.insert(
            id: 'l1',
            copyId: 'c1',
            borrower: 'Ana',
            dueAt: Value(DateTime.now().add(const Duration(days: 14))),
          ));
    });

    await tester.pumpWidget(drawer);
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await tester.pump(const Duration(milliseconds: 20));
    }

    // A badge that is always there stops meaning anything.
    expect(find.text('1'), findsNothing);
    await disposeTree(tester);
  });
}
