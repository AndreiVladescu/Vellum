// The annotations list where it is embedded in a page, rather than shown as a
// sheet of its own (request 8/19 #11).
//
// The point of the inline mode is that the book's detail page scrolls as one
// piece: a reader with fifty highlights should not push the rest of the page
// away, and the list must not be a fixed-height box that eats the page's scroll.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/reader/annotations/annotation_locator.dart';
import 'package:vellum/reader/annotations/annotation_store.dart';
import 'package:vellum/reader/annotations/annotations_panel.dart';

void main() {
  late Directory dir;
  late VellumDatabase db;
  late LibraryRepository repo;

  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_panel'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Drift answers on a real isolate while the widget clock is fake — see the
  /// same helper in `author_page_test.dart`.
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
    await db.close();
  }

  /// [count] highlights on one book, and the panel inside a scrolling page the
  /// way the detail page holds it.
  Future<void> pumpPanel(WidgetTester tester, int count,
      {int? maxInline = 3}) async {
    late Book book;
    await tester.runAsync(() async {
      db = VellumDatabase(NativeDatabase.memory());
      repo = await LibraryRepository.forTesting(db, dir);
      await db.into(db.books).insert(BooksCompanion.insert(
            id: 'b1',
            title: 'Dune',
            needsPush: const Value(false),
            readerNotesNeedsPush: const Value(false),
          ));
      for (var i = 1; i <= count; i++) {
        await repo.annotations.add(
          bookId: 'b1',
          kind: AnnotationKind.highlight,
          page: i,
          locator: PdfTextLocator(page: i, start: 0, end: 5),
          quotedText: 'Highlight number $i',
        );
      }
      book = (await repo.watchBook('b1').first)!;
    });
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ListView(
          children: [
            AnnotationsPanel(
              book: book,
              store: repo.annotations,
              maxInline: maxInline,
            ),
          ],
        ),
      ),
    ));
    await settle(tester);
  }

  testWidgets('a short list is shown whole, with no button', (tester) async {
    await pumpPanel(tester, 3);

    expect(find.text('Highlight number 1'), findsOneWidget);
    expect(find.text('Highlight number 3'), findsOneWidget);
    expect(find.textContaining('Show all'), findsNothing);
    await unmount(tester);
  });

  testWidgets('past the limit, the rest go behind a button', (tester) async {
    await pumpPanel(tester, 7);

    expect(find.text('Highlight number 3'), findsOneWidget);
    expect(find.text('Highlight number 4'), findsNothing,
        reason: 'the fourth entry is the button, not an entry');
    expect(find.text('Show all 7 annotations'), findsOneWidget);
    expect(find.text('7 annotations'), findsOneWidget,
        reason: 'the heading still says how many there really are');
    await unmount(tester);
  });

  testWidgets('the button opens the full list in a sheet', (tester) async {
    await pumpPanel(tester, 7);

    await tester.tap(find.text('Show all 7 annotations'));
    await settle(tester);

    // The fourth entry — the one the inline list stopped short of — is here,
    // and the sheet scrolls through the rest rather than truncating again.
    expect(find.text('Highlight number 4'), findsOneWidget);
    expect(
      find.descendant(
        of: find.byType(BottomSheet),
        matching: find.textContaining('Show all'),
      ),
      findsNothing,
      reason: 'the sheet lists everything, so it needs no button of its own',
    );
    await tester.drag(find.text('Highlight number 4'), const Offset(0, -300));
    await settle(tester);
    expect(find.text('Highlight number 7'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('inline, the panel takes only the room it needs', (tester) async {
    await pumpPanel(tester, 2);

    // Well short of the 600px test screen: the detail page can still put its
    // own content below.
    expect(tester.getSize(find.byType(AnnotationsPanel)).height, lessThan(400));
    await unmount(tester);
  });

  testWidgets('an empty book says what to do, either way', (tester) async {
    await pumpPanel(tester, 0);

    expect(find.text('No annotations yet'), findsOneWidget);
    expect(find.textContaining('Show all'), findsNothing);
    await unmount(tester);
  });
}
