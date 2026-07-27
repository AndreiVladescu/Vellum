// The trash screen (plan 5 #52). The service tests pin the semantics; what
// matters here is that the screen offers the *recoverable* action without a
// confirmation and the irreversible one only behind a dialog — the whole point
// of the grace period is undone if "delete now" is as easy as "restore".
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/settings/trash_page.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_trash_ui'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> settle(WidgetTester tester, {int rounds = 8}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Unmounts the page inside the test's own async window. The trash list is a
  /// live drift `.watch()`, and cancelling that subscription schedules a
  /// zero-duration timer — left until teardown it trips the "pending timers"
  /// check, so each test ends by taking the tree down itself.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  }

  Future<LibraryRepository> pumpTrash(WidgetTester tester) async {
    late LibraryRepository repo;
    await tester.runAsync(() async {
      repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dir,
      );
      final db = repo.db;
      await db
          .into(db.books)
          .insert(BooksCompanion.insert(id: 'b1', title: 'Dune'));
      await repo.trashBook('b1');
    });
    await tester.pumpWidget(MaterialApp(home: TrashPage(repository: repo)));
    await settle(tester);
    return repo;
  }

  testWidgets('lists a trashed book with how long it has left', (tester) async {
    await pumpTrash(tester);
    expect(find.text('Dune'), findsOneWidget);
    // 29, not 30: the countdown starts the moment the book is trashed, so a
    // truncated day has already elapsed by the time the row is built.
    expect(find.textContaining('Deleted in 29 days'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('restore takes the book back with no confirmation',
      (tester) async {
    final repo = await pumpTrash(tester);
    await tester.tap(find.byTooltip('Restore'));
    await settle(tester);

    // Database reads go through runAsync: the fake clock a widget test runs on
    // never advances sqlite's real I/O, so awaiting a query directly hangs.
    await tester.runAsync(() async {
      expect(await repo.trash.watchTrashed().first, isEmpty);
      expect(
        [for (final b in await repo.watchAllBooks().first) b.id],
        ['b1'],
        reason: 'and it is back on the shelf',
      );
    });
    expect(find.text('The trash is empty'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('delete now needs a confirmation, and cancelling changes nothing',
      (tester) async {
    final repo = await pumpTrash(tester);
    await tester.tap(find.byTooltip('Delete now'));
    await tester.pumpAndSettle();
    expect(find.text('Delete “Dune” for good?'), findsOneWidget);

    await tester.tap(find.widgetWithText(TextButton, 'Cancel'));
    await settle(tester);
    await tester.runAsync(() async {
      expect(await repo.trash.watchTrashed().first, hasLength(1),
          reason: 'cancelling leaves the book in the trash');
    });

    await tester.tap(find.byTooltip('Delete now'));
    await tester.pumpAndSettle();
    await tester.tap(find.widgetWithText(FilledButton, 'Delete'));
    await settle(tester);

    await tester.runAsync(() async {
      expect(await repo.db.select(repo.db.books).get(), isEmpty);
      expect(await repo.db.select(repo.db.localDeletions).get(), hasLength(1),
          reason: 'the real delete tombstones so the server hears about it');
    });
    await unmount(tester);
  });
}
