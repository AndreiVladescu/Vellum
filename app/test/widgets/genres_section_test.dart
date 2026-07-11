import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/book_detail/genres_section.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';

/// Drives the real [GenresSection] + its add sheet against a real (in-memory)
/// drift database and real taps — the closest faithful GUI exercise available
/// in this environment (no OS click tool for the desktop window).
Future<LibraryRepository> _repo(Directory dir) async =>
    LibraryRepository.forTesting(VellumDatabase(NativeDatabase.memory()), dir);

Future<void> _seedBook(LibraryRepository repo, String id) async {
  await repo.db.into(repo.db.books).insert(
        BooksCompanion.insert(id: id, title: id, needsPush: const Value(false)),
      );
}

Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 6; i++) {
    await tester.pump(const Duration(milliseconds: 80));
  }
}

/// Lets a just-triggered native-DB write (addGenre/removeGenre) and the drift
/// `.watch()` emission complete on the *real* event loop, then renders the
/// resulting rebuild — pump() alone only advances the test's FakeAsync clock.
Future<void> _drainDb(WidgetTester tester) async {
  await tester.runAsync(() async {
    await Future<void>.delayed(const Duration(milliseconds: 250));
  });
  await _settle(tester);
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_genres_ui'));
  tearDown(() => dir.deleteSync(recursive: true));

  Widget host(LibraryRepository repo, String bookId) => MaterialApp(
        home: Scaffold(
          body: Center(
            child: GenresSection(repository: repo, bookId: bookId),
          ),
        ),
      );

  testWidgets('add a genre through the sheet, then remove it via the chip',
      (tester) async {
    late LibraryRepository repo;
    await tester.runAsync(() async {
      repo = await _repo(dir);
      await _seedBook(repo, 'b1');
    });

    await tester.pumpWidget(host(repo, 'b1'));
    await _settle(tester);

    // A book with no genres shows just the "Add" affordance.
    expect(find.text('Add'), findsOneWidget);
    expect(find.byType(InputChip), findsNothing);

    // Open the add sheet, type a genre, submit.
    await tester.tap(find.text('Add'));
    await _settle(tester);
    expect(find.text('Add genre'), findsOneWidget, reason: 'sheet is open');

    await tester.enterText(find.byType(TextField), 'engineering');
    await tester.testTextInput.receiveAction(TextInputAction.done);
    await _drainDb(tester);

    // Canonicalized to Title Case and shown as a removable chip on the book.
    expect(find.widgetWithText(InputChip, 'Engineering'), findsOneWidget);

    // Close the sheet.
    await tester.tap(find.text('Done'));
    await _settle(tester);
    expect(find.text('Add genre'), findsNothing);

    // Remove via the chip's delete (✕) icon → chip disappears reactively.
    // (The Engineering InputChip has no avatar, so its only Icon is delete.)
    await tester.tap(find.descendant(
      of: find.widgetWithText(InputChip, 'Engineering'),
      matching: find.byType(Icon),
    ));
    await _drainDb(tester);
    expect(find.widgetWithText(InputChip, 'Engineering'), findsNothing,
        reason: 'removed and the section updated live');

    await tester.runAsync(() async => tester.pumpWidget(const SizedBox()));
  });

  testWidgets('the add sheet suggests genres already used elsewhere',
      (tester) async {
    late LibraryRepository repo;
    await tester.runAsync(() async {
      repo = await _repo(dir);
      await _seedBook(repo, 'b1');
      await _seedBook(repo, 'b2');
      await repo.addGenre('b2', 'History'); // used by another book
    });

    await tester.pumpWidget(host(repo, 'b1'));
    await _settle(tester);

    await tester.tap(find.text('Add'));
    await _settle(tester);

    // "History" appears as a tappable suggestion (an ActionChip in the sheet).
    final suggestion = find.widgetWithText(ActionChip, 'History');
    expect(suggestion, findsOneWidget, reason: 'reuse existing tags');

    await tester.tap(suggestion);
    await _drainDb(tester);

    // Now book b1 carries it too, shown as its own removable chip.
    expect(find.widgetWithText(InputChip, 'History'), findsOneWidget);

    await tester.runAsync(() async => tester.pumpWidget(const SizedBox()));
  });
}
