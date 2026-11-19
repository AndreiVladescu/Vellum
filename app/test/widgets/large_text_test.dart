import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/account/user_profile.dart';
import 'package:vellum/book_detail/read_button.dart';
import 'package:vellum/loans/loans_page.dart';
import 'package:vellum/reader/auto_scroll.dart';
import 'package:vellum/reader/auto_scroll_bar.dart';
import 'package:vellum/reader/reader_actions.dart';
import 'package:vellum/reader/reader_settings.dart';
import 'package:vellum/reader/reader_settings_sheet.dart';
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
///
/// Every check runs in each shipped language, not just English: Romanian runs
/// 20–30% longer, and a label that fits in English is no promise it fits there.

const _secureStorageChannel = MethodChannel(
  'plugins.it_nomads.com/flutter_secure_storage',
);

/// The languages every layout check runs in.
const _locales = [Locale('en'), Locale('ro')];

/// A narrow phone-ish surface (411x891 dp), where long text is most likely to
/// clip.
void _phone(WidgetTester tester) {
  tester.view.physicalSize = const Size(411 * 2.625, 891 * 2.625);
  tester.view.devicePixelRatio = 2.625;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// The app shell around a test page: the real delegates, [locale], and a forced
/// accessibility text [scale] over everything.
Widget _app({
  required Locale locale,
  required double scale,
  required Widget home,
}) =>
    MaterialApp(
      locale: locale,
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(scale)),
        child: child!,
      ),
      home: home,
    );

Future<void> _unmount(WidgetTester tester) async {
  await tester.pump(const Duration(seconds: 2));
  await tester.runAsync(() async {
    await tester.pumpWidget(const SizedBox());
    await Future<void>.delayed(const Duration(milliseconds: 50));
  });
  await tester.pump();
}

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

  for (final locale in _locales) {
    final l10n = lookupL10n(locale);
    for (final scale in [1.3, 2.0]) {
      testWidgets(
        '[$locale] shelf, drawer + detail render at ${scale}x text scale '
        'without overflow',
        (tester) async {
          _phone(tester);

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
            app = _app(
              locale: locale,
              scale: scale,
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
          for (final label in [l10n.shelfAll, l10n.shelfNew]) {
            // A horizontal list only builds the chips near the viewport.
            if (find.text(label).evaluate().isEmpty) continue;
            final chip = tester.getRect(find.text(label));
            expect(chip.top, greaterThanOrEqualTo(row.top), reason: label);
            expect(chip.bottom, lessThanOrEqualTo(row.bottom), reason: label);
          }

          // The drawer: every entry laid out at this scale, in this language.
          final shell = find.byWidgetPredicate(
            (w) => w is Scaffold && w.drawer != null,
          );
          tester.state<ScaffoldState>(shell.first).openDrawer();
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }
          expect(find.text(l10n.drawerMyShelf), findsOneWidget);
          expect(tester.takeException(), isNull, reason: 'drawer');
          final drawerList = find.descendant(
            of: find.byType(Drawer),
            matching: find.byType(Scrollable),
          );
          if (drawerList.evaluate().isNotEmpty) {
            await tester.drag(drawerList.first, const Offset(0, -2000));
            await tester.pump(const Duration(milliseconds: 100));
            expect(tester.takeException(), isNull, reason: 'drawer, scrolled');
          }
          tester.state<ScaffoldState>(shell.first).closeDrawer();
          for (var i = 0; i < 5; i++) {
            await tester.pump(const Duration(milliseconds: 100));
          }

          // Open the detail page (the Text-heavy screen).
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
            find.byTooltip(l10n.detailRatingStars(5)),
            200,
            scrollable: scrollable,
          );
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
          // Reaching here means no overflow was thrown while laying out.

          await _unmount(tester);
        },
      );
    }
  }

  // The other text-heavy screens on the same 411x891 phone surface. Each is
  // scrolled end to end so every lazily built row gets laid out; a RenderFlex
  // overflow surfaces as a FlutterError via takeException.
  group('whole-screen sweep', () {
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
      Locale locale,
      double scale,
      Future<Widget> Function(LibraryRepository repo) home,
    ) async {
      _phone(tester);
      final repo = await seed(tester);
      late Widget page;
      await tester.runAsync(() async => page = await home(repo));
      await tester.pumpWidget(_app(locale: locale, scale: scale, home: page));
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
      await _unmount(tester);
    }

    for (final locale in _locales) {
      for (final scale in [1.3, 2.0]) {
        final at = '[$locale] ${scale}x';

        testWidgets('$at Insights', (tester) async {
          await sweep(tester, locale, scale, (repo) async {
            SharedPreferences.setMockInitialValues({});
            return InsightsPage(
              repository: repo,
              settings: await AppSettingsStore.load(),
            );
          });
        });

        testWidgets('$at Loans', (tester) async {
          await sweep(tester, locale, scale,
              (repo) async => LoansPage(repository: repo));
        });

        testWidgets('$at Library statistics', (tester) async {
          await sweep(tester, locale, scale,
              (repo) async => LibraryStatsPage(db: repo.db));
        });

        testWidgets('$at Preferences', (tester) async {
          await sweep(tester, locale, scale, (repo) async {
            SharedPreferences.setMockInitialValues({});
            return PreferencesPage(
              repository: repo,
              settings: await AppSettingsStore.load(),
              connection: await ServerConnection.load(),
              sync: SyncService(repo),
            );
          });
        });
      }
    }
  });

  // The reader's chrome. The reader pages themselves cannot be pumped in a test
  // (see epub_reader_page_test.dart), so the pieces are pumped on their own: the
  // reading options sheet (the longest labels), the toolbar with its overflow
  // menu open, and the auto-scroll pill.
  group('reader chrome', () {
    for (final locale in _locales) {
      final l10n = lookupL10n(locale);
      for (final scale in [1.3, 2.0]) {
        final at = '[$locale] ${scale}x';

        testWidgets('$at reading options sheet', (tester) async {
          _phone(tester);
          SharedPreferences.setMockInitialValues({});
          late ReaderSettings settings;
          await tester.runAsync(() async {
            settings = await ReaderSettings.load();
          });
          await tester.pumpWidget(_app(
            locale: locale,
            scale: scale,
            home: Scaffold(
              body: ReaderSettingsSheet(
                settings: settings,
                showTypography: true,
                showPdfOptions: true,
              ),
            ),
          ));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
          final scrollable = find.byType(Scrollable).first;
          for (var i = 0; i < 8; i++) {
            await tester.drag(scrollable, const Offset(0, -500));
            await tester.pump(const Duration(milliseconds: 100));
            expect(tester.takeException(), isNull, reason: 'step $i');
          }
        });

        testWidgets('$at toolbar and its menu', (tester) async {
          _phone(tester);
          final actions = [
            ReaderAction(
                icon: Icons.bookmark_add_outlined,
                label: l10n.readerActBookmarkPage,
                onPressed: () {}),
            ReaderAction(
                icon: Icons.format_list_bulleted,
                label: l10n.readerActChapters,
                onPressed: () {}),
            ReaderAction(
                icon: Icons.search,
                label: l10n.readerActSearch('Ctrl+'),
                onPressed: () {}),
            ReaderAction(
                icon: Icons.notes,
                label: l10n.readerActAnnotations,
                onPressed: () {}),
            ReaderAction(
                icon: Icons.swipe_down_alt,
                label: l10n.readerActAutoScroll,
                onPressed: () {}),
            ReaderAction(
                icon: Icons.record_voice_over_outlined,
                label: l10n.ttsReadAloud,
                onPressed: () {}),
            ReaderAction(
                icon: Icons.fullscreen,
                label: l10n.readerActReadingMode,
                onPressed: () {}),
            ReaderAction(
                icon: Icons.tune,
                label: l10n.readerActReadingOptions,
                onPressed: () {}),
          ];
          await tester.pumpWidget(_app(
            locale: locale,
            scale: scale,
            home: Scaffold(
              appBar: AppBar(
                leading: const BackButton(),
                title: Text(l10n.readerChapterPageOf(3, 12)),
                actions: [ReaderActionBar(actions: actions)],
              ),
            ),
          ));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
          await tester.tap(find.byTooltip(l10n.readerMore));
          await tester.pumpAndSettle();
          expect(tester.takeException(), isNull, reason: 'the open menu');
          expect(find.text(l10n.readerActReadingOptions), findsOneWidget);
        });

        testWidgets('$at auto-scroll pill', (tester) async {
          _phone(tester);
          await tester.pumpWidget(_app(
            locale: locale,
            scale: scale,
            home: Scaffold(
              body: Align(
                alignment: Alignment.bottomCenter,
                child: AutoScrollBar(
                  speed: 0.75,
                  unit: AutoScrollUnit.pages,
                  min: 0.25,
                  max: 20,
                  onSpeed: (_) {},
                  onStop: () {},
                ),
              ),
            ),
          ));
          await tester.pump(const Duration(milliseconds: 100));
          expect(tester.takeException(), isNull);
        });
      }
    }
  });
}
