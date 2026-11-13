// Library statistics (roadmap v1.3.5): the pure arithmetic, the one SQL query
// behind it (trash, samples, live updates), and a smoke test of the page.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/l10n/gen/app_localizations.dart';
import 'package:vellum/onboarding/sample_library.dart';
import 'package:vellum/stats/library_stats.dart';
import 'package:vellum/stats/library_stats_page.dart';
import 'package:vellum/stats/library_stats_queries.dart';

LibraryStatsBook book(
  String id, {
  int? year,
  int? pages,
  String status = 'unread',
  DateTime? added,
  List<String> genres = const [],
  List<String> authors = const [],
  List<String> formats = const [],
  int bytes = 0,
  int copies = 0,
}) =>
    LibraryStatsBook(
      id: id,
      publishedYear: year,
      pageCount: pages,
      status: status,
      createdAt: added ?? DateTime(2026, 11, 1),
      genres: genres,
      authors: authors,
      formats: formats,
      fileBytes: bytes,
      copies: copies,
    );

void main() {
  final now = DateTime(2026, 11, 13);

  group('LibraryStatsCalculator', () {
    test('counts genres and authors, most first, ties alphabetical', () {
      final s = LibraryStatsCalculator.compute([
        book('1', genres: ['Sci-Fi', 'Classics'], authors: ['Wells']),
        book('2', genres: ['Sci-Fi'], authors: ['Wells', 'Shelley']),
        book('3', genres: ['Classics'], authors: ['Shelley']),
        book('4', genres: ['Poetry', 'Poetry'], authors: ['Zed']),
      ], now: now);
      expect(s.byGenre.map((c) => '${c.label}:${c.count}'),
          ['Classics:2', 'Sci-Fi:2', 'Poetry:1']);
      expect(s.topAuthors.map((c) => c.label), ['Shelley', 'Wells', 'Zed']);
    });

    test('limit cuts the top lists', () {
      final s = LibraryStatsCalculator.compute(
        [for (var i = 0; i < 15; i++) book('$i', authors: ['A$i'])],
        now: now,
        limit: 3,
      );
      expect(s.topAuthors, hasLength(3));
    });

    test('decades and years ascending; unknown year counted apart', () {
      final s = LibraryStatsCalculator.compute([
        book('1', year: 1995),
        book('2', year: 1999),
        book('3', year: 1818),
        book('4'),
      ], now: now);
      expect(s.byDecade.map((c) => '${c.label}:${c.count}'),
          ['1810:1', '1990:2']);
      expect(s.byYear.map((c) => c.label), ['1818', '1995', '1999']);
      expect(s.unknownYear, 1);
    });

    test('format: single kinds, several, none', () {
      final s = LibraryStatsCalculator.compute([
        book('pdf', formats: ['pdf']),
        book('epub', formats: ['EPUB']),
        book('both', formats: ['pdf', 'epub']),
        book('phys', copies: 1),
        book('mixed', formats: ['epub'], copies: 2),
        book('mobi', formats: ['mobi']),
        book('bare'),
      ], now: now);
      expect(s.byFormat[HoldingKind.pdf], 1);
      expect(s.byFormat[HoldingKind.epub], 1);
      expect(s.byFormat[HoldingKind.several], 2);
      expect(s.byFormat[HoldingKind.physical], 1);
      expect(s.byFormat[HoldingKind.otherDigital], 1);
      expect(s.byFormat[HoldingKind.none], 1);
    });

    test('unread pile: only unread, size, pages with a median estimate', () {
      final s = LibraryStatsCalculator.compute([
        book('a', pages: 100, bytes: 1000),
        book('b', pages: 300, bytes: 2000),
        book('c', pages: 200),
        book('d'), // unknown pages -> median (200)
        book('e', status: 'finished', pages: 999, bytes: 5000),
        book('f', status: 'reading', pages: 999),
      ], now: now);
      expect(s.unread.books, 4);
      expect(s.unread.totalBytes, 3000);
      expect(s.unread.knownPages, 600);
      expect(s.unread.withoutPageCount, 1);
      expect(s.unread.estimatedPages, 800);
    });

    test('unread pile with no page counts invents nothing', () {
      final s = LibraryStatsCalculator.compute([book('a'), book('b')], now: now);
      expect(s.unread.estimatedPages, 0);
      expect(s.unread.withoutPageCount, 2);
    });

    test('wishlist books are not part of the library', () {
      final s = LibraryStatsCalculator.compute(
          [book('a'), book('w', status: 'wishlist', genres: ['X'])],
          now: now);
      expect(s.total, 1);
      expect(s.byGenre, isEmpty);
      expect(s.unread.books, 1);
    });

    test('added per month: 12 months across a year boundary, zeros kept', () {
      final s = LibraryStatsCalculator.compute([
        book('1', added: DateTime(2026, 11, 2)),
        book('2', added: DateTime(2026, 11, 30, 23, 59)),
        book('3', added: DateTime(2025, 12, 31)),
        book('4', added: DateTime(2025, 11, 20)), // 13 months ago: out
        book('5', added: DateTime(2026, 3, 5)),
      ], now: now);
      final m = s.addedLastYear;
      expect(m, hasLength(12));
      expect(m.first.month, DateTime(2025, 12));
      expect(m.last.month, DateTime(2026, 11));
      expect(m.first.count, 1);
      expect(m.last.count, 2);
      expect(m.firstWhere((x) => x.month == DateTime(2026, 3)).count, 1);
      expect(m.firstWhere((x) => x.month == DateTime(2026, 5)).count, 0);
    });

    test('added all time spans first book to now with gaps filled', () {
      final s = LibraryStatsCalculator.compute([
        book('1', added: DateTime(2025, 11, 20)),
        book('2', added: DateTime(2026, 1, 1)),
      ], now: now);
      expect(s.addedAllTime, hasLength(13));
      expect(s.addedAllTime.first.month, DateTime(2025, 11));
      expect(s.addedAllTime.last.month, DateTime(2026, 11));
      expect(s.addedAllTime.fold<int>(0, (a, m) => a + m.count), 2);
    });

    test('empty library', () {
      final s = LibraryStatsCalculator.compute([], now: now);
      expect(s.total, 0);
      expect(s.addedAllTime, isEmpty);
      expect(s.addedLastYear, hasLength(12));
    });
  });

  group('LibraryStatsQueries', () {
    late VellumDatabase db;
    setUp(() => db = VellumDatabase(NativeDatabase.memory()));
    tearDown(() => db.close());

    Future<void> add(String id, {DateTime? deletedAt, bool excluded = false}) =>
        db.into(db.books).insert(BooksCompanion.insert(
              id: id,
              title: id,
              deletedAt: Value(deletedAt),
              syncExcluded: Value(excluded),
            ));

    test('joins genres, authors, files and copies; drops trash and samples',
        () async {
      await add('live');
      await add('trashed', deletedAt: DateTime(2026, 1, 1));
      await add('sample', excluded: true);
      await add('private', excluded: true); // excluded from sync, not a sample

      await db.into(db.shelves).insert(
          ShelvesCompanion.insert(id: 's', name: SampleLibrary.shelfName));
      await db.into(db.shelfBooks).insert(
          ShelfBooksCompanion.insert(shelfId: 's', bookId: 'sample'));

      await db.into(db.genres).insert(GenresCompanion.insert(id: 'g', name: 'Poetry'));
      await db.into(db.bookGenres).insert(
          BookGenresCompanion.insert(bookId: 'live', genreId: 'g'));
      await db.into(db.authors).insert(AuthorsCompanion.insert(id: 'a', name: 'Ana'));
      await db.into(db.bookAuthors).insert(
          BookAuthorsCompanion.insert(bookId: 'live', authorId: 'a'));
      for (final f in ['pdf', 'epub']) {
        await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
              id: f,
              bookId: 'live',
              format: f,
              path: '/x.$f',
              sizeBytes: 500,
              sha256: f,
            ));
      }
      await db.into(db.physicalCopies).insert(
          PhysicalCopiesCompanion.insert(id: 'c', bookId: 'live'));

      final rows = await LibraryStatsQueries.watchBooks(db).first;
      expect(rows.map((b) => b.id).toSet(), {'live', 'private'});
      final live = rows.firstWhere((b) => b.id == 'live');
      expect(live.genres, ['Poetry']);
      expect(live.authors, ['Ana']);
      expect(live.formats.toSet(), {'pdf', 'epub'});
      expect(live.fileBytes, 1000);
      expect(live.copies, 1);
      expect(live.createdAt.year, greaterThan(2000));
    });

    test('the stream updates when a book is added', () async {
      await add('one');
      final seen = <int>[];
      final sub = LibraryStatsQueries.watchBooks(db)
          .listen((rows) => seen.add(rows.length));
      await pumpEventQueue();
      await add('two');
      await pumpEventQueue();
      await sub.cancel();
      expect(seen.first, 1);
      expect(seen.last, 2);
    });
  });

  group('LibraryStatsView', () {
    Future<void> pump(WidgetTester tester, LibraryStats stats) async {
      tester.view.physicalSize = const Size(800, 3000);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(MaterialApp(
        localizationsDelegates: L10n.localizationsDelegates,
        supportedLocales: L10n.supportedLocales,
        home: Scaffold(body: LibraryStatsView(stats: stats)),
      ));
    }

    testWidgets('shows the sections for a populated library', (tester) async {
      await pump(
        tester,
        LibraryStatsCalculator.compute([
          book('1', genres: ['Poetry'], authors: ['Ana'], year: 1990, pages: 100),
          book('2', formats: ['pdf'], added: DateTime(2026, 10, 1)),
        ], now: DateTime(2026, 11, 13)),
      );
      expect(find.text('2 books in your library'), findsOneWidget);
      expect(find.text('Poetry'), findsOneWidget);
      expect(find.text('Ana'), findsOneWidget);
      expect(find.text('1990'), findsOneWidget);
      expect(find.text('2 unread books'), findsOneWidget);
      await tester.tap(find.text('All time'));
      await tester.pump();
      expect(tester.takeException(), isNull);
    });

    testWidgets('empty library shows the empty state', (tester) async {
      await pump(tester,
          LibraryStatsCalculator.compute([], now: DateTime(2026, 11, 13)));
      expect(find.textContaining('Add some books'), findsOneWidget);
    });
  });
}
