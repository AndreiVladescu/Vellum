// Preferences -> "Copy diagnostics": copies, confirms, and can show first.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/server/connection_store.dart';
import 'package:vellum/server/sync_service.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:vellum/settings/preferences_page.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_diag_ui'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 8; i++) {
      await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 5)),
      );
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('the button copies the report and says so', (tester) async {
    String? clip;
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      (call) async {
        if (call.method == 'Clipboard.setData') {
          clip = (call.arguments as Map)['text'] as String;
        }
        return null;
      },
    );
    late LibraryRepository repo;
    late AppSettingsStore settings;
    late ServerConnection connection;
    await tester.runAsync(() async {
      repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dir,
      );
      SharedPreferences.setMockInitialValues({});
      settings = await AppSettingsStore.load();
      connection = await ServerConnection.load();
    });
    await tester.pumpWidget(
      MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
        home: PreferencesPage(
          repository: repo,
          settings: settings,
          connection: connection,
          sync: SyncService(repo),
        ),
      ),
    );
    await settle(tester);

    await tester.scrollUntilVisible(find.text('Copy diagnostics'), 300);
    // Scrolled into reach is not yet on screen enough to tap: bring the whole
    // row in, wherever the rows above it leave it.
    await tester.ensureVisible(find.text('Copy diagnostics'));
    await settle(tester);
    await tester.tap(find.text('Copy diagnostics'));
    await settle(tester);

    expect(clip, startsWith('Vellum diagnostics'));
    expect(find.text('Diagnostics copied'), findsOneWidget);

    await tester.tap(find.text('Show'));
    await settle(tester);
    expect(find.byType(SelectableText), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);

    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    tester.binding.defaultBinaryMessenger.setMockMethodCallHandler(
      SystemChannels.platform,
      null,
    );
  });
}
