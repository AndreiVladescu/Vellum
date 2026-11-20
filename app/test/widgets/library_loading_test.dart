import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/account/user_profile.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_queries.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/main.dart';
import 'package:vellum/server/connection_store.dart';
import 'package:vellum/settings/app_settings.dart';
import 'package:vellum/shelf/shelf_view.dart';

/// The library page must not claim the library is empty before its stream has
/// said so: a full library used to flash "Your shelf is empty" for ~0.2 s at
/// every launch. Setup follows smoke_test.dart (dart:io work in runAsync, a
/// null secure-storage channel). The "delayed stream" is the real one, before
/// the database's first answer has been let through the event loop.
const _secureStorageChannel =
    MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

void main() {
  late Directory dir;

  setUp(() {
    dir = Directory.systemTemp.createTempSync('vellum_loading_test');
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, (call) async => null);
  });

  tearDown(() {
    dir.deleteSync(recursive: true);
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(_secureStorageChannel, null);
  });

  Future<(Widget, AppSettingsStore)> build(
      {required bool withBook, Stream<LibraryView>? stream}) async {
    final repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()), dir);
    if (withBook) {
      await repo.db.into(repo.db.books).insert(BooksCompanion.insert(
            id: 'a',
            title: 'Dune',
            needsPush: const Value(false),
            readerNotesNeedsPush: const Value(false),
          ));
    }
    SharedPreferences.setMockInitialValues({});
    final settings = await AppSettingsStore.load();
    final app = MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: LibraryPage(
        repository: repo,
        profile: await UserProfileStore.load(),
        settings: settings,
        connection: await ServerConnection.load(),
        libraryStreamForTesting: stream,
      ),
    );
    return (app, settings);
  }

  Future<void> letStreamsAnswer(WidgetTester tester) async {
    await tester.runAsync(
        () => Future<void>.delayed(const Duration(milliseconds: 300)));
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

  testWidgets('until the stream answers there is no empty-library page',
      (tester) async {
    late Widget app;
    final controller = StreamController<LibraryView>.broadcast();
    addTearDown(controller.close);
    await tester.runAsync(() async {
      app = (await build(withBook: true, stream: controller.stream)).$1;
    });
    await tester.pumpWidget(app);
    await tester.pump(const Duration(milliseconds: 250));
    expect(find.text('Your shelf is empty'), findsNothing);
    expect(find.text('Add your first book to see it here.'), findsNothing);
    expect(find.byType(CircularProgressIndicator), findsNothing);

    // The stream really says zero books: now, and only now, the invitation.
    controller.add(LibraryView.empty);
    await tester.pump();
    await tester.pump();
    expect(find.text('Your shelf is empty'), findsOneWidget);
    await letStreamsAnswer(tester); // let the page's other queries settle
    await dispose(tester);
  });

  testWidgets('an empty library shows the empty-library page once answered',
      (tester) async {
    late Widget app;
    await tester.runAsync(() async => app = (await build(withBook: false)).$1);
    await tester.pumpWidget(app);
    await letStreamsAnswer(tester);
    expect(find.text('Your shelf is empty'), findsOneWidget);
    await dispose(tester);
  });

  testWidgets('a library with books shows them, and no first-run sheet',
      (tester) async {
    late Widget app;
    late AppSettingsStore settings;
    await tester.runAsync(() async {
      final built = await build(withBook: true);
      app = built.$1;
      settings = built.$2;
    });
    await tester.pumpWidget(app);
    await letStreamsAnswer(tester);
    expect(find.byType(BookSpine), findsOneWidget);
    expect(find.text('Your shelf is empty'), findsNothing);
    expect(find.text('Welcome to Vellum'), findsNothing);
    expect(settings.hasSeenFirstRun, isTrue);
    await dispose(tester);
  });
}
