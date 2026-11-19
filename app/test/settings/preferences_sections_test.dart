// Preferences split into sections with a search box (roadmap v1.4.1).
//
// The risk in a reshuffle like this is a setting that quietly drops out, so the
// first test names every entry. The others pin the two layouts and the
// search -> section -> scrolled-to-setting path.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/data/local_text_index.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/server/connection_store.dart';
import 'package:vellum/server/sync_service.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:vellum/settings/preferences_layout.dart';
import 'package:vellum/settings/preferences_page.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_prefs'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await tester.pump(const Duration(milliseconds: 100));
    }
  }

  late LibraryRepository repo;
  late AppSettingsStore settings;
  late ServerConnection connection;

  Future<void> load(WidgetTester tester) async {
    await tester.runAsync(() async {
      repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dir,
      );
      SharedPreferences.setMockInitialValues({});
      settings = await AppSettingsStore.load();
      connection = await ServerConnection.load();
    });
  }

  Future<void> pump(WidgetTester tester, {String? section, String? entry}) async {
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: PreferencesPage(
        repository: repo,
        settings: settings,
        connection: connection,
        sync: SyncService(repo),
        initialSection: section,
        initialEntry: entry,
      ),
    ));
    await settle(tester);
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  }

  testWidgets('every setting from the old single page is still catalogued',
      (tester) async {
    await load(tester);
    late List<PrefsSection> sections;
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Builder(builder: (context) {
        sections = preferencesCatalogue(
          context,
          settings: settings,
          repository: repo,
          connection: connection,
          sync: SyncService(repo),
        );
        return const SizedBox();
      }),
    ));
    final ids = {
      for (final s in sections)
        for (final e in s.entries) e.id,
    };
    expect(ids, {
      'appearance', 'language', 'wallpaper', 'books', 'genres',
      if (textIndexSupportedHere) 'index',
      'samples', 'autoPush', 'readingPosition', 'backgroundSync',
      'audioWifiOnly',
      // 'sharedShelves' only when connected to a server.
      'tray', 'loanReminders', 'backup', 'audioStorage', 'trash', 'health',
      'diagnostics', 'clearLibrary',
    });
    expect(sections.map((s) => s.id),
        ['appearance', 'shelf', 'sync', 'notifications', 'data']);
    // No id appears twice, in any section.
    expect(ids.length,
        sections.fold<int>(0, (n, s) => n + s.entries.length));
    await unmount(tester);
  });

  testWidgets('a phone shows a list of sections; one opens its own page',
      (tester) async {
    await load(tester);
    await pump(tester);
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Data and backups'), findsOneWidget);
    // Nothing from inside a section on the first screen.
    expect(find.text('Scheduled backups'), findsNothing);

    await tester.tap(find.byKey(const ValueKey('prefs-section-data')));
    await settle(tester);
    expect(find.widgetWithText(AppBar, 'Data and backups'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('search finds by keyword, names the section, and opens it',
      (tester) async {
    await load(tester);
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'wipe');
    await settle(tester);
    // "wipe" is only a keyword of the clear-library entry.
    expect(find.byKey(const ValueKey('prefs-result-clearLibrary')),
        findsOneWidget);
    expect(find.text('Data and backups'), findsOneWidget,
        reason: 'the result carries its section name');

    await tester.tap(find.byKey(const ValueKey('prefs-result-clearLibrary')));
    await settle(tester, rounds: 30);
    expect(find.text('Remove every book from this device'), findsOneWidget,
        reason: 'the page scrolled to the setting it was asked for');
    await unmount(tester);
  });

  testWidgets('search finds the audiobook download settings', (tester) async {
    await load(tester);
    await pump(tester);
    // A keyword, not the title: someone thinks "mobile data", not "Wi-Fi".
    await tester.enterText(find.byType(TextField), 'mobile data');
    await settle(tester);
    expect(find.byKey(const ValueKey('prefs-result-audioWifiOnly')),
        findsOneWidget);
    await tester.enterText(find.byType(TextField), 'storage');
    await settle(tester);
    expect(find.byKey(const ValueKey('prefs-result-audioStorage')),
        findsOneWidget);
    // The backup line is found by the switch's own title.
    await tester.enterText(find.byType(TextField), 'audiobook audio');
    await settle(tester);
    expect(find.byKey(const ValueKey('prefs-result-backup')), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('search with no match says so', (tester) async {
    await load(tester);
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'zzzqq');
    await settle(tester);
    expect(find.text('No preference matches "zzzqq"'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('wide: sections on the left, the chosen one on the right',
      (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await load(tester);
    await pump(tester);
    // First section is showing already, beside the list.
    expect(find.text('Notifications'), findsOneWidget);
    expect(find.text('Wallpaper'), findsWidgets);

    await tester.tap(find.byKey(const ValueKey('prefs-section-notifications')));
    await settle(tester);
    expect(find.text('Borrowing notifications'), findsOneWidget);
    expect(find.byType(SwitchListTile), findsWidgets);
    await unmount(tester);
  });

  testWidgets('deep link opens the section and the setting', (tester) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(tester.view.reset);
    await load(tester);
    await pump(tester, section: 'data', entry: 'clearLibrary');
    await settle(tester, rounds: 30);
    expect(find.text('Remove every book from this device'), findsOneWidget);
    await unmount(tester);
  });
}
