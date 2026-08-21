// The continue-reading / recently-added strip (plan 5 #25). Its selection logic
// is a pure function over the shelf's own LibraryView, which is what keeps it
// from costing a second set of queries — so most of this tests that function
// directly, plus a widget pass for the collapse-to-nothing behaviour.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_queries.dart';
import 'package:vellum/shelf/library_header.dart';

Book _book(
  String id,
  String title, {
  double? progress,
  int? page,
  DateTime? lastRead,
  DateTime? created,
}) =>
    Book(
      id: id,
      title: title,
      readingProgress: progress,
      lastReadPage: page,
      lastReadAt: lastRead,
      createdAt: created ?? DateTime(2024),
      updatedAt: DateTime(2024),
      needsPush: false, syncExcluded: false,
      readerNotesNeedsPush: false,
      needsProgressPush: false,
      status: 'unread',
      readCount: 0,
    );

LibraryView _view(List<Book> books) => LibraryView(
      entries: [
        for (final b in books)
          LibraryEntry(book: b, authors: const [], genres: const [], hasFile: true),
      ],
      shelves: const [],
      allGenres: const [],
      scopeEmpty: books.isEmpty,
    );

void main() {
  group('selection', () {
    test('in-progress books come first, most recently read first', () {
      final highlights = LibraryHighlights.from(_view([
        _book('a', 'Older', progress: 0.3, lastRead: DateTime(2026, 1, 1)),
        _book('b', 'Newer', progress: 0.5, lastRead: DateTime(2026, 6, 1)),
        _book('c', 'Untouched'),
      ]));

      expect(highlights.continueReading.map((b) => b.title), ['Newer', 'Older']);
    });

    test('a finished book drops off the strip', () {
      final highlights = LibraryHighlights.from(_view([
        _book('a', 'Finished', progress: 1.0, lastRead: DateTime(2026, 6, 1)),
        _book('b', 'Nearly', progress: 0.99, lastRead: DateTime(2026, 6, 1)),
        _book('c', 'Halfway', progress: 0.5, lastRead: DateTime(2026, 6, 1)),
      ]));

      expect(highlights.continueReading.map((b) => b.title), ['Halfway'],
          reason: '0.99 counts as finished — a PDF often never reports 1.0');
    });

    test('an unopened book is never in continue reading', () {
      final highlights = LibraryHighlights.from(_view([
        // Progress but no lastReadAt: an adopted server row, not something read
        // on this device.
        _book('a', 'No timestamp', progress: 0.4),
        _book('b', 'Zero progress', progress: 0, lastRead: DateTime(2026, 1, 1)),
      ]));

      expect(highlights.continueReading, isEmpty);
    });

    test('recently added is newest first and excludes in-progress books', () {
      final highlights = LibraryHighlights.from(_view([
        _book('a', 'Reading', progress: 0.4, lastRead: DateTime(2026, 6, 1),
            created: DateTime(2026, 6, 1)),
        _book('b', 'Old', created: DateTime(2020)),
        _book('c', 'Fresh', created: DateTime(2026, 5, 1)),
      ]));

      expect(highlights.recentlyAdded.map((b) => b.title), ['Fresh', 'Old']);
      expect(
        highlights.recentlyAdded.map((b) => b.title),
        isNot(contains('Reading')),
        reason: 'a book in both sections would just be noise',
      );
    });

    test('each section is capped', () {
      final highlights = LibraryHighlights.from(
        _view([
          for (var i = 0; i < 10; i++)
            _book('r$i', 'Reading $i',
                progress: 0.5, lastRead: DateTime(2026, 1, i + 1)),
          for (var i = 0; i < 10; i++) _book('n$i', 'New $i'),
        ]),
        limit: 3,
      );

      expect(highlights.continueReading, hasLength(3));
      expect(highlights.recentlyAdded, hasLength(3));
    });

    test('an empty library yields an empty strip', () {
      expect(LibraryHighlights.from(_view(const [])).isEmpty, true);
    });

    test('it narrows with the shelf, because it reads the same view', () {
      // The view handed in is already filtered; the strip must not reach past it
      // and show a book the shelf below is hiding.
      final filtered = _view([
        _book('a', 'Matches', progress: 0.5, lastRead: DateTime(2026, 6, 1)),
      ]);
      final highlights = LibraryHighlights.from(filtered);
      expect(highlights.continueReading.map((b) => b.title), ['Matches']);
    });
  });

  group('widget', () {
    Widget host(LibraryHighlights highlights, {VoidCallback? onDismiss}) =>
        MaterialApp(
          home: Scaffold(
            body: LibraryHeader(
              highlights: highlights,
              onOpen: (_) {},
              onDismiss: onDismiss,
            ),
          ),
        );

    /// The same header on a screen of a given height. `MediaQuery.sizeOf` is
    /// what the header asks, so that is what the test sets.
    Widget hostSized(LibraryHighlights highlights, Size screen) => MaterialApp(
          home: MediaQuery(
            data: MediaQueryData(size: screen),
            child: Scaffold(
              body: LibraryHeader(highlights: highlights, onOpen: (_) {}),
            ),
          ),
        );

    testWidgets('on a landscape phone it drops to one row and no headings',
        (tester) async {
      // The reported bug: the full header is ~200px tall, a landscape phone's
      // body is ~280, and the shelf underneath was left too short to scroll.
      final highlights = LibraryHighlights.from(_view([
        _book('a', 'Halfway', progress: 0.5, page: 120,
            lastRead: DateTime(2026, 6, 1)),
        _book('b', 'Just added', created: DateTime(2026, 6, 2)),
      ]));

      await tester.pumpWidget(hostSized(highlights, const Size(880, 400)));
      await tester.pump();

      expect(find.text('Continue reading'), findsNothing,
          reason: 'the headings are the first thing a short screen gives up');
      expect(find.text('Recently added'), findsNothing);
      expect(find.text('Halfway'), findsOneWidget,
          reason: 'what you were in the middle of survives');
    });

    testWidgets('a tall screen keeps the full header', (tester) async {
      final highlights = LibraryHighlights.from(_view([
        _book('a', 'Halfway', progress: 0.5, lastRead: DateTime(2026, 6, 1)),
      ]));
      await tester.pumpWidget(hostSized(highlights, const Size(400, 900)));
      await tester.pump();
      expect(find.text('Continue reading'), findsOneWidget);
    });

    testWidgets('the compact header leaves the shelf most of the screen',
        (tester) async {
      // The property that actually matters: whatever it draws, it must not eat
      // a short screen.
      tester.view.physicalSize = const Size(880, 400);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      final highlights = LibraryHighlights.from(_view([
        _book('a', 'Halfway', progress: 0.5, lastRead: DateTime(2026, 6, 1)),
        _book('b', 'Just added', created: DateTime(2026, 6, 2)),
      ]));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: Column(children: [
            LibraryHeader(highlights: highlights, onOpen: (_) {}),
            const Expanded(child: SizedBox.expand()),
          ]),
        ),
      ));
      await tester.pump();

      final headerHeight = tester.getSize(find.byType(LibraryHeader)).height;
      expect(headerHeight, lessThan(400 * 0.4),
          reason: 'the shelf keeps the rest, and stays scrollable');
    });

    testWidgets('renders both sections with progress', (tester) async {
      await tester.pumpWidget(host(LibraryHighlights.from(_view([
        _book('a', 'Halfway', progress: 0.5, page: 120,
            lastRead: DateTime(2026, 6, 1)),
        _book('b', 'Just added', created: DateTime(2026, 6, 2)),
      ]))));
      await tester.pump();

      expect(find.text('Continue reading'), findsOneWidget);
      expect(find.text('Halfway'), findsOneWidget);
      expect(find.text('50% · page 120'), findsOneWidget);
      expect(find.text('Recently added'), findsOneWidget);
      expect(find.text('Just added'), findsOneWidget);
    });

    testWidgets('collapses to nothing when there is nothing to show',
        (tester) async {
      await tester.pumpWidget(host(LibraryHighlights.from(_view(const []))));
      await tester.pump();

      expect(find.text('Continue reading'), findsNothing);
      expect(find.text('Recently added'), findsNothing);
      expect(find.byType(Divider), findsNothing,
          reason: 'not even a separator on an empty library');
    });

    testWidgets('tapping a card reports the book', (tester) async {
      Book? opened;
      final highlights = LibraryHighlights.from(_view([
        _book('a', 'Halfway', progress: 0.5, lastRead: DateTime(2026, 6, 1)),
      ]));
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          body: LibraryHeader(
            highlights: highlights,
            onOpen: (book) => opened = book,
          ),
        ),
      ));
      await tester.pump();

      await tester.tap(find.text('Halfway'));
      await tester.pump();

      expect(opened?.id, 'a');
    });

    testWidgets('dismiss is offered once, not per section', (tester) async {
      await tester.pumpWidget(host(
        LibraryHighlights.from(_view([
          _book('a', 'Halfway', progress: 0.5, lastRead: DateTime(2026, 6, 1)),
          _book('b', 'Just added'),
        ])),
        onDismiss: () {},
      ));
      await tester.pump();

      expect(find.byIcon(Icons.close), findsOneWidget);
    });
  });
}
