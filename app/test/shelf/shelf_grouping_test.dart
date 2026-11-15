// Shelf grouping (v1.4.1): the pure grouping rules, then headers in each view.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_queries.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/settings/book_face.dart';
import 'package:vellum/settings/shelf_group_by.dart';
import 'package:vellum/shelf/book_list_view.dart';
import 'package:vellum/shelf/group_header.dart';
import 'package:vellum/shelf/shelf_grouping.dart';
import 'package:vellum/shelf/shelf_view.dart';

LibraryEntry _e(
  String title, {
  List<String> authors = const [],
  List<String> genres = const [],
  String? series,
  double? index,
}) =>
    LibraryEntry(
      book: Book(
        id: title,
        title: title,
        seriesIndex: index,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
        needsPush: false,
        syncExcluded: false,
        readerNotesNeedsPush: false,
        statusNeedsPush: false,
        statusInferred: false,
        needsProgressPush: false,
        status: 'unread',
        readCount: 0,
      ),
      authors: authors,
      genres: genres,
      hasFile: true,
      seriesName: series,
    );

List<String> _titles(ShelfGroup g) => [for (final e in g.entries) e.book.title];

void main() {
  group('groupEntries', () {
    test('none is one header-less group holding everything', () {
      final es = [_e('A'), _e('B')];
      final g = groupEntries(es, ShelfGroupBy.none);
      expect(g, hasLength(1));
      expect(g.single.headed, isFalse);
      expect(g.single.entries, es);
    });

    test('a multi-author book appears under each author', () {
      final g = groupEntries([
        _e('Good Omens', authors: ['Terry Pratchett', 'Neil Gaiman']),
        _e('Mort', authors: ['Terry Pratchett']),
      ], ShelfGroupBy.author);
      expect([for (final x in g) x.name], ['Neil Gaiman', 'Terry Pratchett']);
      expect(_titles(g[0]), ['Good Omens']);
      expect(_titles(g[1]), ['Good Omens', 'Mort']);
    });

    test('names group case-insensitively; blanks and repeats are ignored', () {
      final g = groupEntries([
        _e('A', authors: ['Le Guin', ' le guin ', '']),
        _e('B', authors: ['LE GUIN']),
      ], ShelfGroupBy.author);
      expect(g, hasLength(1));
      expect(g.single.name, 'Le Guin');
      expect(_titles(g.single), ['A', 'B']);
    });

    test('books with no value close the list in a nameless group', () {
      final g = groupEntries([
        _e('Orphan'),
        _e('Zed', genres: ['Zoology']),
        _e('Alpha', genres: ['Art']),
      ], ShelfGroupBy.genre);
      expect([for (final x in g) x.name], ['Art', 'Zoology', null]);
      expect(_titles(g.last), ['Orphan']);
    });

    test('a series is ordered by index, unnumbered last, then title', () {
      final g = groupEntries([
        _e('Extra', series: 'Dune'),
        _e('Messiah', series: 'dune', index: 2),
        _e('Dune', series: 'Dune', index: 1),
        _e('Interlude', series: 'Dune', index: 1.5),
        _e('Solo'),
      ], ShelfGroupBy.series);
      expect(g, hasLength(2));
      expect(_titles(g[0]), ['Dune', 'Interlude', 'Messiah', 'Extra']);
      expect(g[1].name, isNull);
    });

    test('GroupMemo recomputes only when the list or mode changes', () {
      final memo = GroupMemo();
      final es = [
        _e('A', authors: ['X']),
      ];
      final first = memo.of(es, ShelfGroupBy.author);
      expect(identical(memo.of(es, ShelfGroupBy.author), first), isTrue);
      expect(identical(memo.of(es, ShelfGroupBy.genre), first), isFalse);
    });
  });

  group('headers render', () {
    final entries = [
      _e('Mort', authors: ['Terry Pratchett']),
      _e('Piranesi', authors: ['Susanna Clarke']),
      _e('Loose'),
    ];

    Future<void> pump(
      WidgetTester tester,
      Widget Function(List<ShelfGroup>) body,
    ) {
      // Tall enough for all three groups: the shelf is lazy, so anything past
      // the viewport (rightly) is not built.
      tester.view.physicalSize = const Size(800, 1600);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.reset);
      return tester.pumpWidget(MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(
          body: body(groupEntries(entries, ShelfGroupBy.author)),
        ),
      ));
    }

    void expectHeaders() {
      expect(find.byType(GroupHeader), findsNWidgets(3));
      expect(
        find.descendant(
            of: find.byType(GroupHeader), matching: find.text('Susanna Clarke')),
        findsOneWidget,
      );
      expect(find.text('Terry Pratchett'), findsWidgets);
      expect(find.text('No author'), findsOneWidget);
    }

    for (final face in [BookFace.spine, BookFace.cover]) {
      testWidgets('shelf, $face', (tester) async {
        await pump(
          tester,
          (g) => ShelfView(
            groups: g,
            bookFace: face,
            detailBuilder: (_) => const SizedBox(),
          ),
        );
        expectHeaders();
        expect(
          find.byType(face == BookFace.spine ? BookSpine : BookCover),
          findsNWidgets(3),
        );
      });
    }

    testWidgets('list', (tester) async {
      await pump(
        tester,
        (g) => BookListView(groups: g, detailBuilder: (_) => const SizedBox()),
      );
      expectHeaders();
      expect(find.text('Mort'), findsOneWidget);
    });

    testWidgets('tapping a header folds its group', (tester) async {
      await pump(
        tester,
        (g) => ShelfView(groups: g, detailBuilder: (_) => const SizedBox()),
      );
      expect(find.byType(BookSpine), findsNWidgets(3));
      await tester.tap(find.text('Terry Pratchett'));
      await tester.pump();
      expect(find.byType(BookSpine), findsNWidgets(2));
      await tester.tap(find.text('Terry Pratchett'));
      await tester.pump();
      expect(find.byType(BookSpine), findsNWidgets(3));
    });
  });
}
