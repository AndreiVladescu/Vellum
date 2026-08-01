// "Remove every book from this device" (next features #1).
//
// Two promises worth pinning, because getting either wrong is expensive: the
// confirmation cannot be dismissed by reflex, and the books go to the *trash*
// rather than being deleted — which is what makes the whole thing forgiving.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/server/connection_store.dart';
import 'package:vellum/server/sync_service.dart';
import 'package:vellum/settings/preferences_page.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:shared_preferences/shared_preferences.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_clear'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> settle(WidgetTester tester, {int rounds = 8}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  }

  Future<LibraryRepository> pumpPreferences(WidgetTester tester) async {
    late LibraryRepository repo;
    late AppSettingsStore settings;
    late ServerConnection connection;
    await tester.runAsync(() async {
      repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dir,
      );
      for (final title in ['Dune', 'Piranesi', 'Solaris']) {
        await repo.db.into(repo.db.books).insert(
              BooksCompanion.insert(id: title, title: title),
            );
      }
      SharedPreferences.setMockInitialValues({});
      settings = await AppSettingsStore.load();
      connection = await ServerConnection.load();
    });
    await tester.pumpWidget(
      MaterialApp(
        home: PreferencesPage(
          repository: repo,
          settings: settings,
          connection: connection,
          sync: SyncService(repo),
        ),
      ),
    );
    await settle(tester);
    return repo;
  }

  Future<void> openDialog(WidgetTester tester) async {
    await tester.scrollUntilVisible(
      find.text('Remove every book from this device'),
      300,
    );
    await settle(tester);
    await tester.tap(find.text('Remove every book from this device'));
    await settle(tester);
  }

  testWidgets('the confirmation stays disabled until the word is typed',
      (tester) async {
    final repo = await pumpPreferences(tester);
    await openDialog(tester);

    expect(find.text('Remove all 3 books?'), findsOneWidget);
    final button = tester.widget<FilledButton>(
      find.widgetWithText(FilledButton, 'Move all to trash'),
    );
    expect(button.onPressed, isNull,
        reason: 'a dialog you can dismiss by reflex is not a confirmation');

    // A near miss is still a miss.
    await tester.enterText(find.byType(TextField).last, 'delete me');
    await settle(tester);
    expect(
      tester
          .widget<FilledButton>(
              find.widgetWithText(FilledButton, 'Move all to trash'))
          .onPressed,
      isNull,
    );

    await tester.runAsync(() async {
      expect(await repo.watchAllBooks().first, hasLength(3));
    });
    await unmount(tester);
  });

  testWidgets('typing the word trashes every book, and none is deleted',
      (tester) async {
    final repo = await pumpPreferences(tester);
    await openDialog(tester);

    // Case-insensitive and trimmed: the point is intent, not typing accuracy.
    await tester.enterText(find.byType(TextField).last, ' delete ');
    await settle(tester);
    await tester.tap(find.text('Move all to trash'));
    await settle(tester);

    await tester.runAsync(() async {
      expect(await repo.watchAllBooks().first, isEmpty,
          reason: 'the shelf should be empty');
      expect(await repo.watchTrashedBooks().first, hasLength(3),
          reason: 'they must be recoverable, not gone');
    });
    expect(find.text('Moved 3 books to the trash'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('cancelling leaves the library alone', (tester) async {
    final repo = await pumpPreferences(tester);
    await openDialog(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    await tester.runAsync(() async {
      expect(await repo.watchAllBooks().first, hasLength(3));
      expect(await repo.watchTrashedBooks().first, isEmpty);
    });
    await unmount(tester);
  });
}
