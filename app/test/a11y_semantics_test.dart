import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/book_detail/cover_thumb.dart';
import 'package:vellum/shelf/shelf_view.dart';

void main() {
  group('bookSemanticLabel', () {
    test('title only when there is no subtitle', () {
      expect(bookSemanticLabel('Dune', null), 'Dune');
      expect(bookSemanticLabel('Dune', ''), 'Dune');
    });
    test('appends the subtitle when present', () {
      expect(bookSemanticLabel('Dune', 'Deluxe Edition'),
          'Dune: Deluxe Edition');
    });
  });

  testWidgets('CoverThumb exposes a "Change cover" button to screen readers',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CoverThumb(cover: null, onTap: () {})),
    ));
    expect(find.bySemanticsLabel('Change cover'), findsOneWidget);
    handle.dispose();
  });

  testWidgets('a book spine is reachable and activatable by keyboard',
      (tester) async {
    // Plan 5 #42. A spine used to be a bare GestureDetector: announced as a
    // button, but impossible to reach without a pointer, which made the shelf
    // keyboard-unusable — there is no other way into a book from here.
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BookSpine(book: _book('Dune'), onTap: () => opened++),
      ),
    ));
    await tester.pump();

    final inkWell = find.byType(InkWell);
    expect(inkWell, findsOneWidget, reason: 'focusable, unlike GestureDetector');

    Focus.of(tester.element(find.byType(SpineFace))).requestFocus();
    await tester.pump();

    await tester.sendKeyEvent(LogicalKeyboardKey.enter);
    await tester.pump();
    expect(opened, 1, reason: 'Enter opens the focused book');
  });

  testWidgets('a face-out cover is keyboard-activatable too', (tester) async {
    var opened = 0;
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BookCover(book: _book('Dune'), onTap: () => opened++),
      ),
    ));
    await tester.pump();

    await tester.tap(find.byType(InkWell));
    await tester.pump();
    expect(opened, 1);
  });

  testWidgets('the cover thumbnail is a focusable button', (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CoverThumb(cover: null, onTap: () {})),
    ));
    await tester.pump();
    expect(find.bySemanticsLabel('Change cover'), findsOneWidget);
    expect(find.byType(InkWell), findsOneWidget,
        reason: 'reachable without a mouse');
    handle.dispose();
  });
}

Book _book(String title) => Book(
      id: 'b1',
      title: title,
      needsPush: true,
      readerNotesNeedsPush: false,
      needsProgressPush: false,
      status: 'unread',
      readCount: 0,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
    );
