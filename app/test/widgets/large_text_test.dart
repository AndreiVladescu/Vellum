import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/account/user_profile.dart';
import 'package:vellum/book_detail/read_button.dart';
import 'package:vellum/loans/loans_page.dart';
import 'package:vellum/server/sync_service.dart';
import 'package:vellum/settings/preferences_page.dart';
import 'package:vellum/stats/insights_page.dart';
import 'package:vellum/stats/library_stats_page.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/main.dart';
import 'package:vellum/server/connection_store.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:vellum/shelf/shelf_view.dart';

/// B6 regression guard: the library and a book's detail must render without
/// RenderFlex overflow at a large accessibility text scale (common on phones).
/// A clip would throw a FlutterError that fails the test. Reuses the documented
/// testWidgets setup (see smoke_test.dart): dart:io repo work in runAsync, a
/// null-returning secure-storage channel, and a runAsync tree teardown.

const _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vellum_large_text');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async => null);
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  for (final scale in [1.3, 2.0]) {
    testWidgets(
      'shelf + detail render at ${scale}x text scale without overflow',
      (tester) async {
        // A narrow phone-ish surface, where large text is most likely to clip.
        tester.view.physicalSize = const Size(411 * 2.625, 891 * 2.625);
        tester.view.devicePixelRatio = 2.625;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);

        late Widget app;
        await tester.runAsync(() async {
          final repo = await LibraryRepository.forTesting(
            VellumDatabase(NativeDatabase.memory()),
            dir,
          );
          final db = repo.db;
          await db
              .into(db.books)
              .insert(
                BooksCompanion.insert(
                  id: 'a',
                  title: 'The Fellowship of the Ring',
                  subtitle: const Value(
                    'Being the First Part of The Lord of the Rings',
                  ),
                  needsPush: const Value(false),
                  readingProgress: const Value(0.42),
                  lastReadPage: const Value(214),
                  rating: const Value(3),
                ),
              );
          await db
              .into(db.shelves)
              .insert(ShelvesCompanion.insert(id: 's', name: 'Favourites'));
          await db
              .into(db.bookFiles)
              .insert(
                BookFilesCompanion.insert(
                  id: 'f',
                  bookId: 'a',
                  format: 'epub',
                  path: 'x.epub',
                  sizeBytes: 1,
                  sha256: 'h',
                ),
              );
          SharedPreferences.setMockInitialValues({
            'settings.hasSeenFirstRun': true,
          });
          final settings = await AppSettingsStore.load();
          final profile = await UserProfileStore.load();
          final connection = await ServerConnection.load();
          app = MaterialApp(
            localizationsDelegates: L10n.localizationsDelegates,
            supportedLocales: L10n.supportedLocales,
            // Force a 2x accessibility text scale over the whole app.
            builder: (context, child) => MediaQuery(
              data: MediaQuery.of(
                context,
              ).copyWith(textScaler: TextScaler.linear(scale)),
              child: child!,
            ),
            home: LibraryPage(
              repository: repo,
              profile: profile,
              settings: settings,
              connection: connection,
            ),
          );
        });

        await tester.pumpWidget(app);
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(tester.takeException(), isNull);
        expect(find.byType(BookSpine), findsOneWidget);
        // The shelf chips must fit inside their row rather than being clipped.
        final row = tester.getRect(find.byType(ListView).first);
        for (final label in ['All', 'New shelf']) {
          // A horizontal list only builds the chips near the viewport.
          if (find.text(label).evaluate().isEmpty) continue;
          final chip = tester.getRect(find.text(label));
          expect(chip.top, greaterThanOrEqualTo(row.top), reason: label);
          expect(chip.bottom, lessThanOrEqualTo(row.bottom), reason: label);
        }

        // Open the detail page (the Text-heavy screen) at 2x text.
        await tester.tap(find.byType(BookSpine).first);
        for (var i = 0; i < 5; i++) {
          await tester.pump(const Duration(milliseconds: 100));
        }
        expect(find.text('The Fellowship of the Ring'), findsWidgets);
        final scrollable = find.byType(Scrollable).last;
        await tester.scrollUntilVisible(
          find.byType(ReadButton),
          200,
          scrollable: scrollable,
        );
        await tester.pump(const Duration(milliseconds: 100));
        // The status/rating row sits further down the (lazy) list.
        await tester.scrollUntilVisible(
          find.byTooltip('5 stars'),
          200,
          scrollable: scrollable,
        );
        await tester.pump(const Duration(milliseconds: 100));
        expect(tester.takeException(), isNull);
        // Reaching here means no overflow was thrown while laying out at 2x.

        await tester.pump(const Duration(seconds: 2));
        await tester.runAsync(() async {
          await tester.pumpWidget(const SizedBox());
          await Future<void>.delayed(const Duration(milliseconds: 50));
        });
        await tester.pump();
      },
    );
  }

  // The other text-heavy screens, at 2.0 on the same 411x891 phone surface.
  // Each is scrolled end to end so every lazily built row gets laid out; a
  // RenderFlex overflow surfaces as a FlutterError via takeException.
  group('2.0x text scale, whole-screen sweep', () {
    Future<LibraryRepository> seed(WidgetTester tester) async {
      late LibraryRepository repo;
      await tester.runAsync(() async {
        repo = await LibraryRepository.forTesting(
          VellumDatabase(NativeDatabase.memory()),
          dir,
        );
        final db = repo.db;
        await db.into(db.books).insert(BooksCompanion.insert(
              id: 'a',
              title: 'The Fellowship of the Ring',
              subtitle: const Value('Being the First Part of The Lord of the Rings'),
              finishedAt: Value(DateTime(2026, 7, 20)),
              status: const Value('finished'),
              pageCount: const Value(423),
              publisher: const Value('Allen & Unwin'),
              publishedYear: const Value(1954),
            ));
        await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
              id: 'f',
              bookId: 'a',
              format: 'epub',
              path: 'x.epub',
              sizeBytes: 1,
              sha256: 'h',
            ));
        for (final (i, day) in [19, 20].indexed) {
          await db.into(db.readingSessions).insert(
                ReadingSessionsCompanion.insert(
                  id: 's$i',
                  bookId: 'a',
                  startedAt: DateTime(2026, 7, day, 21),
                  endedAt: DateTime(2026, 7, day, 21, 40),
                  startPage: Value(i * 30 + 1),
                  endPage: Value(i * 30 + 30),
                ),
              );
        }
        final copy = await repo.addPhysicalCopy('a', location: 'Living room');
        await repo.lendCopy(
          copy,
          'Alexandrina Constantinescu-Popescu',
          dueAt: DateTime(2026, 8, 1),
          contact: 'alexandrina.constantinescu@example.org',
          notes: 'Said she would return it after the summer holiday.',
        );
      });
      return repo;
    }

    Future<void> sweep(
      WidgetTester tester,
      Future<Widget> Function(LibraryRepository repo) home,
    ) async {
      tester.view.physicalSize = const Size(411 * 2.625, 891 * 2.625);
      tester.view.devicePixelRatio = 2.625;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      final repo = await seed(tester);
      late Widget page;
      await tester.runAsync(() async => page = await home(repo));
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context)
              .copyWith(textScaler: const TextScaler.linear(2.0)),
          child: child!,
        ),
        home: page,
      ));
      for (var i = 0; i < 10; i++) {
        await tester.pump(const Duration(milliseconds: 100));
      }
      expect(tester.takeException(), isNull);
      expect(find.byType(CircularProgressIndicator), findsNothing,
          reason: 'the page loaded');
      // Walk down the page in screen-sized steps, then back up.
      final scrollable = find.byType(Scrollable).first;
      for (final dy in [-600.0, 600.0]) {
        for (var i = 0; i < 12; i++) {
          await tester.drag(scrollable, Offset(0, dy));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull, reason: 'step $i, dy $dy');
        }
      }
      await tester.pump(const Duration(seconds: 2));
      await tester.runAsync(() async {
        await tester.pumpWidget(const SizedBox());
        await Future<void>.delayed(const Duration(milliseconds: 50));
      });
      await tester.pump();
    }

    testWidgets('Insights', (tester) async {
      await sweep(tester, (repo) async {
        SharedPreferences.setMockInitialValues({});
        return InsightsPage(
          repository: repo,
          settings: await AppSettingsStore.load(),
        );
      });
    });

    testWidgets('Loans', (tester) async {
      await sweep(tester, (repo) async => LoansPage(repository: repo));
    });

    testWidgets('Library statistics', (tester) async {
      await sweep(tester, (repo) async => LibraryStatsPage(db: repo.db));
    });

    testWidgets('Preferences', (tester) async {
      await sweep(tester, (repo) async {
        SharedPreferences.setMockInitialValues({});
        return PreferencesPage(
          repository: repo,
          settings: await AppSettingsStore.load(),
          connection: await ServerConnection.load(),
          sync: SyncService(repo),
        );
      });
    });
  });
}
