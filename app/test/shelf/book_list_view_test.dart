import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_queries.dart';
import 'package:vellum/settings/book_face.dart';
import 'package:vellum/shelf/book_list_view.dart';

/// The library as a list rather than as a picture of a shelf.
///
/// The point of the mode is density and the things a spine cannot say, so
/// that is what these pin: no artwork, and the author / file / status that the
/// shelf hides until you tap a book.
Book _book(
  String id,
  String title, {
  int? year,
  String status = 'unread',
  int? rating,
  double? progress,
}) =>
    Book(
      id: id,
      title: title,
      publishedYear: year,
      status: status,
      rating: rating,
      readingProgress: progress,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      needsPush: false,
      syncExcluded: false,
      readerNotesNeedsPush: false,
      statusNeedsPush: false,
      needsProgressPush: false,
      readCount: 0,
    );

LibraryEntry _entry(
  Book book, {
  List<String> authors = const [],
  bool hasFile = true,
}) =>
    LibraryEntry(
      book: book,
      authors: authors,
      genres: const [],
      hasFile: hasFile,
    );

void main() {
  Future<void> pump(WidgetTester tester, List<LibraryEntry> entries,
      {Set<String> selected = const {}, void Function(Book)? onToggle}) async {
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: BookListView(
          entries: entries,
          selected: selected,
          onToggleSelected: onToggle,
          selectionMode: selected.isNotEmpty,
          detailBuilder: (b) => Scaffold(body: Text('detail:${b.title}')),
        ),
      ),
    ));
    await tester.pumpAndSettle();
  }

  testWidgets('shows the title and the author, and draws no cover',
      (tester) async {
    await pump(tester, [
      _entry(_book('b1', 'The Dispossessed', year: 1974),
          authors: ['Ursula K. Le Guin']),
    ]);

    expect(find.text('The Dispossessed'), findsOneWidget);
    expect(find.text('Ursula K. Le Guin · 1974'), findsOneWidget);
    // The whole reason for the mode: no artwork, so hundreds of rows fit.
    expect(find.byType(Image), findsNothing);
  });

  testWidgets('says which books have no file to open', (tester) async {
    await pump(tester, [
      _entry(_book('b1', 'Has a file')),
      _entry(_book('b2', 'Paper only'), hasFile: false),
    ]);

    // On the shelf a fileless book looks identical to one you can read, and
    // you only find out by tapping it.
    expect(find.byIcon(Icons.menu_book_outlined), findsOneWidget);
    expect(find.byIcon(Icons.bookmark_border), findsOneWidget);
  });

  testWidgets('progress is shown while reading, and not otherwise',
      (tester) async {
    await pump(tester, [
      _entry(_book('b1', 'In progress', status: 'reading', progress: 0.43)),
      // A finished book at 100% would just be a column of "100%", and an
      // unread one has nothing to report.
      _entry(_book('b2', 'Done', status: 'finished', progress: 1.0)),
    ]);

    expect(find.textContaining('43%'), findsOneWidget);
    expect(find.textContaining('100%'), findsNothing);
  });

  testWidgets('a rating shows, and "unread" does not', (tester) async {
    await pump(tester, [
      _entry(_book('b1', 'Rated', status: 'finished', rating: 4)),
      _entry(_book('b2', 'Plain')),
    ]);

    expect(find.text('4'), findsOneWidget);
    expect(find.text('Finished'), findsOneWidget);
    // True of most of the library, so printing it every row is a column of
    // the same word.
    expect(find.text('Unread'), findsNothing);
  });

  testWidgets('tapping opens the book', (tester) async {
    await pump(tester, [_entry(_book('b1', 'Dune'))]);
    await tester.tap(find.text('Dune'));
    await tester.pumpAndSettle();
    expect(find.text('detail:Dune'), findsOneWidget);
  });

  testWidgets('in selection mode a tap ticks instead of opening',
      (tester) async {
    final toggled = <String>[];
    await pump(
      tester,
      [_entry(_book('b1', 'Dune')), _entry(_book('b2', 'Piranesi'))],
      selected: {'b1'},
      onToggle: (b) => toggled.add(b.id),
    );

    expect(find.byType(Checkbox), findsNWidgets(2));
    await tester.tap(find.text('Piranesi'));
    await tester.pumpAndSettle();
    expect(toggled, ['b2']);
    expect(find.text('detail:Piranesi'), findsNothing);
  });

  test('the list is one of the book faces, with its own icon', () {
    // The preference selector and the cycle shortcut both walk
    // `BookFace.values`, so adding a face has to be enough on its own.
    expect(BookFace.values, contains(BookFace.list));
    expect({for (final f in BookFace.values) f.icon}.length,
        BookFace.values.length,
        reason: 'each face needs a distinguishable icon');
  });
}
