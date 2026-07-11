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
import 'package:vellum/main.dart';
import 'package:vellum/server/connection_store.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:vellum/shelf/shelf_view.dart';

/// B6 regression guard: the library and a book's detail must render without
/// RenderFlex overflow at a large accessibility text scale (common on phones).
/// A clip would throw a FlutterError that fails the test. Reuses the documented
/// testWidgets setup (see smoke_test.dart): dart:io repo work in runAsync, a
/// null-returning secure-storage channel, and a runAsync tree teardown.

const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

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

  testWidgets('shelf + detail render at 2x text scale without overflow',
      (tester) async {
    // A narrow phone-ish surface, where large text is most likely to clip.
    tester.view.physicalSize = const Size(1080, 2160);
    tester.view.devicePixelRatio = 3.0;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    late Widget app;
    await tester.runAsync(() async {
      final repo = await LibraryRepository.forTesting(
          VellumDatabase(NativeDatabase.memory()), dir);
      final db = repo.db;
      await db.into(db.books).insert(BooksCompanion.insert(
            id: 'a',
            title: 'The Fellowship of the Ring',
            subtitle: const Value('Being the First Part of The Lord of the Rings'),
            needsPush: const Value(false),
          ));
      SharedPreferences.setMockInitialValues({});
      final settings = await AppSettingsStore.load();
      final profile = await UserProfileStore.load();
      final connection = await ServerConnection.load();
      app = MaterialApp(
        // Force a 2x accessibility text scale over the whole app.
        builder: (context, child) => MediaQuery(
          data: MediaQuery.of(context).copyWith(textScaler: const TextScaler.linear(2.0)),
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
    expect(find.byType(BookSpine), findsOneWidget);

    // Open the detail page (the Text-heavy screen) at 2x text.
    await tester.tap(find.byType(BookSpine).first);
    for (var i = 0; i < 5; i++) {
      await tester.pump(const Duration(milliseconds: 100));
    }
    expect(find.text('The Fellowship of the Ring'), findsWidgets);
    // Reaching here means no overflow was thrown while laying out at 2x.

    await tester.runAsync(() async {
      await tester.pumpWidget(const SizedBox());
      await Future<void>.delayed(const Duration(milliseconds: 50));
    });
    await tester.pump();
  });
}
