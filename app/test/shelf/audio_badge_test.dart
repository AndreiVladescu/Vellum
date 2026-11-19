// The headphones badge (v1.5.2): on a spine (both materials), on a face-out
// cover and in the list; at large text; and the spine of a page-less audiobook
// gets its thickness from its duration.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_queries.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/shelf/book_list_view.dart';
import 'package:vellum/shelf/shelf_grouping.dart';
import 'package:vellum/shelf/shelf_view.dart';
import 'package:vellum/settings/shelf_group_by.dart';

Book _book(String id, String title, {int? pages}) => Book(
      id: id,
      title: title,
      pageCount: pages,
      status: 'unread',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      needsPush: false,
      syncExcluded: false,
      readerNotesNeedsPush: false,
      statusNeedsPush: false,
      statusInferred: false,
      needsProgressPush: false,
      readCount: 0,
    );

Widget _app(Widget body, {double textScale = 1.0}) => MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      builder: (context, child) => MediaQuery(
        data: MediaQuery.of(context)
            .copyWith(textScaler: TextScaler.linear(textScale)),
        child: child!,
      ),
      home: Scaffold(body: Center(child: body)),
    );

final _missingCover = File('/nonexistent/cover.jpg');

void main() {
  group('on a spine', () {
    for (final material in ['generated', 'cover slice']) {
      testWidgets('the badge shows on the $material spine', (tester) async {
        final cover = material == 'generated' ? null : _missingCover;
        await tester.pumpWidget(_app(Row(mainAxisSize: MainAxisSize.min, children: [
          BookSpine(book: _book('a', 'Dune'), audioMs: 3600000, coverFile: cover),
          BookSpine(book: _book('b', 'Emma'), coverFile: cover),
        ])));
        await tester.pump();

        final spines = find.byType(BookSpine);
        expect(
          find.descendant(
              of: spines.at(0), matching: find.byIcon(Icons.headphones)),
          findsWidgets,
        );
        expect(
          find.descendant(
              of: spines.at(1), matching: find.byIcon(Icons.headphones)),
          findsNothing,
          reason: 'a book with no audio is not badged',
        );
      });

      testWidgets('it stays inside the spine ($material)',
          (tester) async {
        final cover = material == 'generated' ? null : _missingCover;
        await tester.pumpWidget(_app(BookSpine(
            book: _book('a', 'Dune'), audioMs: 3600000, coverFile: cover)));
        await tester.pump();

        final spine = tester.getRect(find.byType(BookSpine));
        final badge = tester.getRect(find.byType(AudioBadge));
        expect(spine.contains(badge.topLeft), isTrue);
        expect(spine.contains(badge.bottomRight - const Offset(0.1, 0.1)), isTrue);
        // The narrowest spine (34 px) has room for it.
        expect(badge.width, lessThan(spine.width));
      });

      testWidgets('and survives large text ($material)', (tester) async {
        final cover = material == 'generated' ? null : _missingCover;
        await tester.pumpWidget(_app(
          BookSpine(
              book: _book('a', 'A very long title that will not fit at all'),
              audioMs: 3600000,
              coverFile: cover),
          textScale: 2.0,
        ));
        await tester.pump();
        expect(tester.takeException(), isNull);
        expect(find.byType(AudioBadge), findsOneWidget);
        final spine = tester.getRect(find.byType(BookSpine));
        final badge = tester.getRect(find.byType(AudioBadge));
        expect(badge.height, 14, reason: 'a glyph, not text: it does not scale');
        expect(spine.contains(badge.center), isTrue);
      });
    }

    testWidgets('a screen reader hears it', (tester) async {
      await tester.pumpWidget(
          _app(BookSpine(book: _book('a', 'Dune'), audioMs: 1000)));
      expect(find.bySemanticsLabel('Dune, audiobook'), findsOneWidget);
    });
  });

  testWidgets('on a face-out cover', (tester) async {
    await tester.pumpWidget(_app(Row(mainAxisSize: MainAxisSize.min, children: [
      BookCover(book: _book('a', 'Dune'), audio: true),
      BookCover(book: _book('b', 'Emma')),
    ])));
    await tester.pump();
    final covers = find.byType(BookCover);
    expect(
      find.descendant(of: covers.at(0), matching: find.byIcon(Icons.headphones)),
      findsWidgets,
    );
    expect(
      find.descendant(of: covers.at(1), matching: find.byIcon(Icons.headphones)),
      findsNothing,
    );
    final cover = tester.getRect(covers.at(0));
    expect(cover.contains(tester.getCenter(find.byType(AudioBadge))), isTrue);
  });

  testWidgets('in the list, beside the file icon', (tester) async {
    LibraryEntry entry(Book b, {int? audioMs}) => LibraryEntry(
        book: b,
        authors: const [],
        genres: const [],
        hasFile: true,
        audioMs: audioMs);
    await tester.pumpWidget(MaterialApp(
      localizationsDelegates: L10n.localizationsDelegates,
      supportedLocales: L10n.supportedLocales,
      home: Scaffold(
        body: BookListView(
          entries: [
            entry(_book('a', 'Dune'), audioMs: 3600000),
            entry(_book('b', 'Emma')),
          ],
          selected: const {},
          onToggleSelected: null,
          selectionMode: false,
          detailBuilder: (_) => const SizedBox(),
        ),
      ),
    ));
    await tester.pumpAndSettle();
    expect(find.byIcon(Icons.headphones), findsOneWidget);
    expect(find.byIcon(Icons.menu_book_outlined), findsNWidgets(2),
        reason: 'the file icon stays: a book can have text and audio');
  });

  testWidgets('a page-less audiobook is as thick as its length says',
      (tester) async {
    LibraryEntry entry(Book b, {int? audioMs}) => LibraryEntry(
        book: b,
        authors: const [],
        genres: const [],
        hasFile: true,
        audioMs: audioMs);
    final entries = [
      entry(_book('long', 'Long audio'), audioMs: 40 * 3600000), // 1200 "pages"
      entry(_book('short', 'Short audio'), audioMs: 3600000), // 30 "pages"
      entry(_book('paged', 'Has pages', pages: 300), audioMs: 40 * 3600000),
      entry(_book('plain', 'No audio')),
    ];
    await tester.pumpWidget(_app(SizedBox(
      width: 600,
      height: 400,
      child: ShelfView(
        groups: groupEntries(entries, ShelfGroupBy.none),
        detailBuilder: (_) => const SizedBox(),
      ),
    )));
    await tester.pump();

    double widthOf(String id) => tester
        .getSize(find.byWidgetPredicate(
            (w) => w is BookSpine && w.book.id == id))
        .width;

    expect(widthOf('long'), 62.0, reason: 'clamped like a huge page count');
    expect(widthOf('short'), 34.0);
    expect(widthOf('paged'), widthOf('plain'),
        reason: 'a real page count is not replaced by an estimate');
    expect(widthOf('long'), greaterThan(widthOf('plain')));
  });
}
