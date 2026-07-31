// The bulk-add picker. Adding a bookcase to a room means putting thirty books
// on one shelf, and this is the screen that has to make that one gesture rather
// than thirty. What matters here: it returns *every* ticked book, "select
// these" respects the filter, and a book already in the room is marked and left
// out of a bulk select.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/physical/book_picker.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_picker_ui'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> settle(WidgetTester tester, {int rounds = 8}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Unmounted at the end of each test: cancelling a live drift `.watch()`
  /// schedules a zero-duration timer that trips the pending-timer check.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  }

  /// Pumps the picker inside a Navigator, so what it pops can be captured.
  /// [onDone] receives the picker's result when it closes.
  Future<LibraryRepository> pump(
    WidgetTester tester, {
    Set<String> alreadyPlaced = const {},
    List<String> titles = const ['Dune', 'Piranesi', 'Solaris'],
    void Function(List<Book>?)? onDone,
  }) async {
    late LibraryRepository repo;
    await tester.runAsync(() async {
      repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dir,
      );
      for (var i = 0; i < titles.length; i++) {
        await repo.db.into(repo.db.books).insert(
              BooksCompanion.insert(id: 'b$i', title: titles[i]),
            );
      }
    });
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: Builder(
            builder: (context) => TextButton(
              onPressed: () async {
                final picked = await showModalBottomSheet<List<Book>>(
                  context: context,
                  // Matches how the editor opens it: without this the sheet is
                  // capped at half the screen and the lower rows are off-stage.
                  isScrollControlled: true,
                  builder: (_) => BookPicker(
                    repository: repo,
                    alreadyPlacedIds: alreadyPlaced,
                  ),
                );
                onDone?.call(picked);
              },
              child: const Text('open picker'),
            ),
          ),
        ),
      ),
    );
    await settle(tester);
    await tester.tap(find.text('open picker'));
    await settle(tester);
    return repo;
  }

  testWidgets('confirming is disabled until something is ticked',
      (tester) async {
    await pump(tester);
    final button = tester.widget<FilledButton>(find.byType(FilledButton));
    expect(button.onPressed, isNull, reason: 'Add was live with nothing ticked');
    expect(find.text('Add'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('ticking books counts them and names the count on the button',
      (tester) async {
    await pump(tester);
    await tester.tap(find.text('Dune'));
    await settle(tester);
    await tester.tap(find.text('Solaris'));
    await settle(tester);

    expect(find.text('2 selected'), findsOneWidget);
    expect(find.text('Add 2'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('"select these" takes the whole list, then clears it',
      (tester) async {
    await pump(tester);
    expect(find.text('Select these 3'), findsOneWidget);

    await tester.tap(find.text('Select these 3'));
    await settle(tester);
    expect(find.text('3 selected'), findsOneWidget);

    // The same control now offers the opposite, which is what makes it usable
    // after a mis-tap on a long list.
    await tester.tap(find.text('Clear these 3'));
    await settle(tester);
    expect(find.text('3 selected'), findsNothing);
    await unmount(tester);
  });

  testWidgets('"select these" means the books the filter is showing',
      (tester) async {
    // The whole point of the filter in a bulk picker: type "Dune", select all,
    // and get one book — not the library.
    await pump(tester);
    await tester.enterText(find.byType(TextField), 'dun');
    await settle(tester);

    expect(find.text('Select these 1'), findsOneWidget);
    await tester.tap(find.text('Select these 1'));
    await settle(tester);
    expect(find.text('1 selected'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a book already in the room is marked and skipped by select all',
      (tester) async {
    await pump(tester, alreadyPlaced: {'b0'});

    expect(find.text('already in this room'), findsOneWidget);
    // Two of the three are selectable; the third stays tickable by hand, since
    // owning two copies is legitimate — it just isn't what a bulk add means.
    expect(find.text('Select these 2'), findsOneWidget);

    await tester.tap(find.text('Select these 2'));
    await settle(tester);
    expect(find.text('2 selected'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('an empty library says so instead of showing an empty list',
      (tester) async {
    await pump(tester, titles: const []);
    expect(find.text('No books.'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('hands back every ticked book, in list order', (tester) async {
    // The promise the whole flow rests on: what comes out is the full
    // selection, not the last thing tapped.
    List<Book>? picked;
    await pump(tester, onDone: (result) => picked = result);
    await tester.tap(find.text('Solaris'));
    await settle(tester);
    await tester.tap(find.text('Dune'));
    await settle(tester);

    await tester.tap(find.text('Add 2'));
    await settle(tester);

    expect([for (final b in picked!) b.title], ['Dune', 'Solaris'],
        reason: 'returned in list order, which is the order they are packed');
    await unmount(tester);
  });

  testWidgets('cancelling returns nothing, however much was ticked',
      (tester) async {
    List<Book>? picked;
    var called = false;
    await pump(tester, onDone: (result) {
      picked = result;
      called = true;
    });
    await tester.tap(find.text('Select these 3'));
    await settle(tester);
    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(called, isTrue);
    expect(picked, isNull);
    await unmount(tester);
  });
}
