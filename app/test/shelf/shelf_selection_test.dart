// Selection mode on the digital shelf (next features #4).
//
// The promises worth pinning: a long-press starts a selection instead of
// opening the book, a tap then toggles rather than opening, and the selection
// is visible on the shelf rather than only as a count.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/shelf/shelf_view.dart';

Book _book(String id, String title) => Book(
      id: id,
      title: title,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      needsPush: false, syncExcluded: false,
      readerNotesNeedsPush: false,
      needsProgressPush: false,
      status: 'unread',
      readCount: 0,
    );

void main() {
  final books = [_book('b1', 'Dune'), _book('b2', 'Piranesi')];

  /// The shelf, wired the way the library screen wires it: the host owns the
  /// selection and rebuilds when it changes.
  Future<Set<String>> pumpShelf(WidgetTester tester) async {
    final selected = <String>{};
    await tester.pumpWidget(
      MaterialApp(
        home: StatefulBuilder(
          builder: (context, setState) => Scaffold(
            body: ShelfView(
              books: books,
              selected: selected,
              selectionMode: selected.isNotEmpty,
              onToggleSelected: (b) => setState(() {
                if (!selected.remove(b.id)) selected.add(b.id);
              }),
              detailBuilder: (b) => Scaffold(
                body: Center(child: Text('detail:${b.title}')),
              ),
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    return selected;
  }

  testWidgets('a long-press starts a selection instead of opening the book',
      (tester) async {
    final selected = await pumpShelf(tester);
    await tester.longPress(find.byType(BookSpine).first);
    await tester.pumpAndSettle();

    expect(selected, {'b1'});
    expect(find.text('detail:Dune'), findsNothing,
        reason: 'a long-press must not also open the book');
    expect(find.byIcon(Icons.check_circle), findsOneWidget);
  });

  testWidgets('once in selection mode a tap toggles rather than opens',
      (tester) async {
    final selected = await pumpShelf(tester);
    await tester.longPress(find.byType(BookSpine).first);
    await tester.pumpAndSettle();

    await tester.tap(find.byType(BookSpine).last);
    await tester.pumpAndSettle();
    expect(selected, {'b1', 'b2'});
    expect(find.text('detail:Piranesi'), findsNothing);

    // And tapping a ticked book unticks it.
    await tester.tap(find.byType(BookSpine).last);
    await tester.pumpAndSettle();
    expect(selected, {'b1'});
  });

  testWidgets('with nothing selected a tap still opens the book',
      (tester) async {
    await pumpShelf(tester);
    await tester.tap(find.byType(BookSpine).first);
    await tester.pumpAndSettle();
    expect(find.text('detail:Dune'), findsOneWidget);
  });

  testWidgets('a shelf with no selection handler ignores a long-press',
      (tester) async {
    // The physical view and any other embedder get the old behaviour for free.
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: ShelfView(
            books: books,
            detailBuilder: (b) => const SizedBox(),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();
    await tester.longPress(find.byType(BookSpine).first);
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.check_circle), findsNothing);
  });
}
