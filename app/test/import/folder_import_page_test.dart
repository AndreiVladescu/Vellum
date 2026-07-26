// The import wizard's own behaviour (plan 5 #15): the dry-run step shows what
// would happen and imports nothing until asked, duplicates arrive deselected,
// and the review can be abandoned with no trace.
//
// Driven with `initialFolder`, which skips the native folder picker (a platform
// channel no widget test can answer).
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/import/folder_import_page.dart';
import 'package:vellum/settings/app_settings.dart';

void main() {
  late Directory dataDir;
  late Directory folder;

  setUp(() {
    dataDir = Directory.systemTemp.createTempSync('vellum_wizard_data');
    folder = Directory.systemTemp.createTempSync('vellum_wizard_folder');
    SharedPreferences.setMockInitialValues({});
  });
  tearDown(() {
    dataDir.deleteSync(recursive: true);
    folder.deleteSync(recursive: true);
  });

  void write(String name, String contents) =>
      File(p.join(folder.path, name)).writeAsStringSync(contents);

  /// Drives the wizard's real file I/O to completion.
  ///
  /// `pumpAndSettle` can't be used (the progress indicator animates forever) and
  /// neither half alone is enough: each `runAsync` lets one pending dart:io
  /// operation finish, and the following `pump` drains the continuation it
  /// scheduled. A scan is several operations per file, so this needs many more
  /// rounds than a typical widget test — hence the generous count rather than a
  /// tight one.
  Future<void> settle(WidgetTester tester, {int rounds = 40}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<Widget> wizard(LibraryRepository repo) async => MaterialApp(
        home: FolderImportPage(
          repository: repo,
          settings: await AppSettingsStore.load(),
          initialFolder: folder.path,
        ),
      );

  testWidgets('the review step lists what was found and imports nothing yet',
      (tester) async {
    write('Frank Herbert - Dune-Ace (1965).pdf', 'dune');
    write('Ursula K Le Guin - The Dispossessed.epub', 'dispossessed');

    late LibraryRepository repo;
    late Widget app;
    await tester.runAsync(() async {
      repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dataDir,
      );
      app = await wizard(repo);
    });

    await tester.pumpWidget(app);
    await settle(tester);

    // The parsed titles, not the raw file names.
    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('The Dispossessed'), findsOneWidget);
    expect(find.text('Import 2'), findsOneWidget);
    expect(await repo.db.select(repo.db.books).get(), isEmpty,
        reason: 'the dry run must not have written anything');
  });

  testWidgets('a duplicate is listed but not selected', (tester) async {
    late LibraryRepository repo;
    late Widget app;
    final existing = File(p.join(folder.path, 'already.pdf'))
      ..writeAsStringSync('same bytes');
    write('a copy.pdf', 'same bytes');
    write('Someone - A New One.pdf', 'new bytes');

    await tester.runAsync(() async {
      repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dataDir,
      );
      final db = repo.db;
      await db.into(db.books).insert(BooksCompanion.insert(
            id: 'b1',
            title: 'Already Here',
            coverPath: const Value('covers/b1.jpg'),
          ));
      await repo.attachFile('b1', existing.path);
      app = await wizard(repo);
    });

    await tester.pumpWidget(app);
    await settle(tester);

    expect(find.text('Already here'), findsWidgets, reason: 'status label shown');
    // Only the genuinely new file is queued: 3 files found, 1 selected.
    expect(find.text('Import 1'), findsOneWidget);
    expect(find.textContaining('1 of 3 selected'), findsOneWidget);
  });

  testWidgets('importing writes the selected books', (tester) async {
    write('Frank Herbert - Dune-Ace (1965).pdf', 'dune');

    late LibraryRepository repo;
    late Widget app;
    await tester.runAsync(() async {
      repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dataDir,
      );
      app = await wizard(repo);
    });

    await tester.pumpWidget(app);
    await settle(tester);

    // "Look up metadata online" is on by default for a small folder; turn it
    // off so the test makes no network calls.
    await tester.tap(find.text('Look up covers and descriptions online'));
    await tester.pump();
    await tester.tap(find.text('Import 1'));
    await settle(tester);
    await settle(tester);

    final books = await repo.db.select(repo.db.books).get();
    expect(books.single.title, 'Dune');
    expect(books.single.publishedYear, 1965);
    expect(find.textContaining('Imported 1 book'), findsOneWidget);
    // The watched-folder offer is on the summary, off by default.
    expect(find.text('Watch this folder'), findsOneWidget);
  });

  testWidgets('an empty folder says so instead of showing a blank list',
      (tester) async {
    write('notes.txt', 'not a book');

    late Widget app;
    await tester.runAsync(() async {
      final repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dataDir,
      );
      app = await wizard(repo);
    });

    await tester.pumpWidget(app);
    await settle(tester);

    expect(find.text('No PDFs or EPUBs here'), findsOneWidget);
    // No review bar at all — nothing to select, nothing to import. (The app bar
    // still says "Import a folder", so this checks the bar's own text.)
    expect(find.textContaining('selected'), findsNothing);
    expect(find.textContaining('Look up covers'), findsNothing);
  });
}
