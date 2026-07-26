// The duplicates screen and its merge dialog (plan 5 #21b). A merge is
// irreversible, so what matters here is that it takes an explicit confirmation,
// that cancelling really changes nothing, and that the survivor is the one the
// user picked — not whichever book happened to be listed first.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/dedupe/duplicates_page.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_dupes_ui'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> settle(WidgetTester tester, {int rounds = 12}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Two books that differ only in publisher/year, so they're a fuzzy-title
  /// duplicate pair with two conflicting fields.
  Future<LibraryRepository> seedPair(WidgetTester tester) async {
    late LibraryRepository repo;
    await tester.runAsync(() async {
      repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dir,
      );
      final db = repo.db;
      await db.into(db.books).insert(BooksCompanion.insert(
            id: 'first',
            title: 'Dune',
            publisher: const Value('Gollancz'),
            publishedYear: const Value(1966),
            needsPush: const Value(false),
          ));
      await db.into(db.books).insert(BooksCompanion.insert(
            id: 'second',
            title: 'Dune',
            publisher: const Value('Ace'),
            publishedYear: const Value(1965),
            needsPush: const Value(false),
          ));
      await repo.setAuthors('first', ['Frank Herbert']);
      await repo.setAuthors('second', ['Frank Herbert']);
    });
    return repo;
  }

  testWidgets('a pair is listed with why it matched', (tester) async {
    final repo = await seedPair(tester);
    await tester.pumpWidget(MaterialApp(home: DuplicatesPage(repository: repo)));
    await settle(tester);

    expect(find.textContaining('Similar title and author'), findsOneWidget);
  });

  testWidgets('cancelling the dialog changes nothing', (tester) async {
    final repo = await seedPair(tester);
    await tester.pumpWidget(MaterialApp(home: DuplicatesPage(repository: repo)));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await settle(tester);
    expect(find.text('Merge these books?'), findsOneWidget);

    await tester.tap(find.text('Cancel'));
    await settle(tester);

    expect(await repo.db.select(repo.db.books).get(), hasLength(2));
    expect(await repo.db.select(repo.db.localDeletions).get(), isEmpty);
  });

  testWidgets('merging keeps the chosen survivor and the chosen field values',
      (tester) async {
    final repo = await seedPair(tester);
    await tester.pumpWidget(MaterialApp(home: DuplicatesPage(repository: repo)));
    await settle(tester);

    await tester.tap(find.byIcon(Icons.chevron_right));
    await settle(tester);

    // The conflicting fields are offered; publisher and year both differ.
    expect(find.text('Publisher'), findsOneWidget);
    expect(find.text('Year'), findsOneWidget);

    // Take the second book's publisher (Ace) while keeping the first as the
    // survivor — the case that proves the choice is per field, not per book.
    await tester.tap(find.text('Ace'));
    await settle(tester);
    await tester.tap(find.text('Merge'));
    await settle(tester);

    final books = await repo.db.select(repo.db.books).get();
    expect(books, hasLength(1));
    expect(books.single.id, 'first', reason: 'the default survivor was kept');
    expect(books.single.publisher, 'Ace', reason: 'the per-field choice applied');
    expect(books.single.publishedYear, 1966,
        reason: 'the field left alone keeps the survivor’s value');
    expect(
      (await repo.db.select(repo.db.localDeletions).get()).map((t) => t.bookId),
      contains('second'),
    );
  });

  testWidgets('the list empties out once the pair is merged', (tester) async {
    final repo = await seedPair(tester);
    await tester.pumpWidget(MaterialApp(home: DuplicatesPage(repository: repo)));
    await settle(tester);
    await tester.tap(find.byIcon(Icons.chevron_right));
    await settle(tester);
    await tester.tap(find.text('Merge'));
    await settle(tester);

    expect(find.text('No duplicates left'), findsOneWidget);
  });

  testWidgets('a clean library says so', (tester) async {
    late LibraryRepository repo;
    await tester.runAsync(() async {
      repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dir,
      );
      final db = repo.db;
      await db.into(db.books).insert(
          BooksCompanion.insert(id: 'a', title: 'Dune'));
      await db.into(db.books).insert(
          BooksCompanion.insert(id: 'b', title: 'Neuromancer'));
    });

    await tester.pumpWidget(MaterialApp(home: DuplicatesPage(repository: repo)));
    await settle(tester);

    expect(find.text('No duplicates found'), findsOneWidget);
  });
}
