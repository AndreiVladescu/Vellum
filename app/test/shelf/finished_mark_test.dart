// The mark on a book you have read (v1.1.5 request: "a little blue checkmark
// in a hexagonal star on its top right corner, but be small not to go over the
// next book").
//
// The size constraint is the test worth having: a spine is about thirty pixels
// wide, and a badge that hangs off the corner sits on the book beside it.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/shelf/shelf_view.dart';

void main() {
  late Directory dir;
  late VellumDatabase db;

  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_finished'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<Book> book(WidgetTester tester, ReadingStatus status) async {
    late Book row;
    await tester.runAsync(() async {
      db = VellumDatabase(NativeDatabase.memory());
      await LibraryRepository.forTesting(db, dir);
      await db.into(db.books).insert(BooksCompanion.insert(
            id: 'b1',
            title: 'Dune',
            status: Value(status.name),
          ));
      row = await (db.select(db.books)..where((b) => b.id.equals('b1')))
          .getSingle();
    });
    return row;
  }

  Future<void> pumpSpine(WidgetTester tester, Book row) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: Center(child: BookSpine(book: row))),
    ));
    await tester.pump();
  }

  testWidgets('a finished book is marked on the shelf', (tester) async {
    await pumpSpine(tester, await book(tester, ReadingStatus.finished));

    expect(find.byIcon(Icons.verified), findsWidgets);
    expect(
      find.bySemanticsLabel('Dune, finished'),
      findsOneWidget,
      reason: 'a colour alone is not a label — the spine says it too',
    );
    await db.close();
  });

  testWidgets('an unfinished one is not', (tester) async {
    await pumpSpine(tester, await book(tester, ReadingStatus.reading));

    expect(find.byIcon(Icons.verified), findsNothing);
    await db.close();
  });

  testWidgets('nor is one you put down or keep for reference',
      (tester) async {
    for (final status in [ReadingStatus.abandoned, ReadingStatus.reference]) {
      await pumpSpine(tester, await book(tester, status));
      expect(find.byIcon(Icons.verified), findsNothing, reason: status.name);
      await db.close();
    }
  });

  testWidgets('the mark stays inside the spine it belongs to', (tester) async {
    final row = await book(tester, ReadingStatus.finished);
    await pumpSpine(tester, row);

    final spine = tester.getRect(find.byType(BookSpine));
    final mark = tester.getRect(find.byIcon(Icons.verified).first);
    expect(mark.right, lessThanOrEqualTo(spine.right),
        reason: 'past the right edge is the next book’s shelf space');
    expect(mark.top, greaterThanOrEqualTo(spine.top));
    expect(mark.width, lessThan(spine.width),
        reason: 'and it is a mark on a spine, not a badge over one');
    await db.close();
  });
}
