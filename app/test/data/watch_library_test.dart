// watchLibrary() replaces main.dart's four nested StreamBuilders plus its
// per-rebuild filterBooks()/sortBooks() scan (plan 5 §A1) by doing the same
// filtering/sorting in SQL, and (§A2) its free-text/genre: matching runs
// through the book_search FTS5 index instead of Dart substring scans.
// shelf_filter_test.dart keeps covering filterBooks/sortBooks directly (they
// stay the in-memory fallback); this file checks watchLibrary() against
// hand-computed expectations, against filterBooks/sortBooks themselves where
// the two are expected to agree (the sweep near the bottom), and against the
// one place they're expected to *disagree* (FTS5 prefix vs. Dart substring
// matching, its own test below).
import 'package:drift/drift.dart' show InsertMode, Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_queries.dart';
import 'package:vellum/data/shelf_service.dart';
import 'package:vellum/settings/shelf_sort.dart';
import 'package:vellum/shelf/shelf_filter.dart';

Future<VellumDatabase> _seeded() async {
  final db = VellumDatabase(NativeDatabase.memory());

  Future<void> book(
    String id,
    String title, {
    String? subtitle,
    int? year,
    List<String> authors = const [],
    List<String> genres = const [],
  }) async {
    await db.into(db.books).insert(BooksCompanion.insert(
          id: id,
          title: title,
          subtitle: Value(subtitle),
          publishedYear: Value(year),
        ));
    var pos = 0;
    for (final name in authors) {
      final authorId = 'a-$name';
      await db.into(db.authors).insert(
            AuthorsCompanion.insert(id: authorId, name: name),
            mode: InsertMode.insertOrIgnore,
          );
      await db.into(db.bookAuthors).insert(BookAuthorsCompanion.insert(
            bookId: id,
            authorId: authorId,
            position: Value(pos++),
          ));
    }
    for (final name in genres) {
      final genreId = 'g-$name';
      await db.into(db.genres).insert(
            GenresCompanion.insert(id: genreId, name: name),
            mode: InsertMode.insertOrIgnore,
          );
      await db.into(db.bookGenres).insert(
            BookGenresCompanion.insert(bookId: id, genreId: genreId),
            mode: InsertMode.insertOrIgnore,
          );
    }
  }

  await book('b1', 'The Silent Garden',
      subtitle: 'A Story',
      year: 1965,
      authors: ['Frank Herbert', 'Ada Lovelace'],
      genres: ['Science Fiction', 'Classics']);
  await book('b2', 'another Book');
  await book('b3', 'Dune Messiah',
      year: 1969, authors: ['Frank Herbert'], genres: ['Science Fiction']);
  await book('b4', 'Zebra Notes',
      subtitle: 'Field guide', authors: ['Zoe Zephyr'], genres: ['Reference']);
  await book('b5', 'silent world',
      year: 1965, authors: ['Ada Lovelace'], genres: ['Classics']);

  return db;
}

List<String> _ids(LibraryView view) => [for (final e in view.entries) e.book.id];

void main() {
  test('sort=title orders case-insensitively', () async {
    final db = await _seeded();
    addTearDown(db.close);
    final view = await LibraryQueries(db).watchLibrary(sort: ShelfSort.title).first;
    expect(_ids(view), ['b2', 'b3', 'b5', 'b1', 'b4']);
  });

  test('sort=author: author-less last, ties by title', () async {
    final db = await _seeded();
    addTearDown(db.close);
    final view =
        await LibraryQueries(db).watchLibrary(sort: ShelfSort.author).first;
    expect(_ids(view), ['b5', 'b3', 'b1', 'b4', 'b2']);
  });

  test('sort=year: year-less last, ties by title', () async {
    final db = await _seeded();
    addTearDown(db.close);
    final view = await LibraryQueries(db).watchLibrary(sort: ShelfSort.year).first;
    expect(_ids(view), ['b5', 'b1', 'b3', 'b2', 'b4']);
  });

  test('genre facet is an exact match', () async {
    final db = await _seeded();
    addTearDown(db.close);
    final view = await LibraryQueries(db)
        .watchLibrary(genre: 'Classics', sort: ShelfSort.title)
        .first;
    expect(_ids(view), ['b5', 'b1']);
  });

  test('genre: query prefix is a token-prefix match on genre name', () async {
    final db = await _seeded();
    addTearDown(db.close);
    final view = await LibraryQueries(db)
        .watchLibrary(query: 'genre:science', sort: ShelfSort.title)
        .first;
    expect(_ids(view), ['b3', 'b1']);
  });

  test('free text matches title, subtitle, or author', () async {
    final db = await _seeded();
    addTearDown(db.close);
    final byAuthor = await LibraryQueries(db)
        .watchLibrary(query: 'herbert', sort: ShelfSort.title)
        .first;
    expect(_ids(byAuthor), ['b3', 'b1']);

    final byTitle = await LibraryQueries(db)
        .watchLibrary(query: 'silent', sort: ShelfSort.title)
        .first;
    expect(_ids(byTitle), ['b5', 'b1']);
  });

  test('FTS5 query-syntax characters in the query do not crash the query',
      () async {
    final db = await _seeded();
    addTearDown(db.close);
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'b6',
          title: 'Sci-Fi: A Retrospective (2020)',
        ));
    // Hyphen, colon, parens and a literal double-quote are FTS5 query-syntax
    // characters; ftsMatchQuery quotes every token, so these must be matched
    // (or safely not matched) rather than throwing.
    final view = await LibraryQueries(db)
        .watchLibrary(query: 'sci-fi: a "quote" (2020)', sort: ShelfSort.title)
        .first;
    expect(view, isNotNull);
  });

  // FTS5 does *prefix* matching, not the old Dart path's arbitrary-substring
  // matching — this is the one deliberate semantic change #A2 makes, so it
  // gets its own test rather than living inside the equivalence sweep below.
  test('a mid-word fragment no longer matches (intentional — search_index.dart)',
      () async {
    final db = await _seeded();
    addTearDown(db.close);
    final queries = LibraryQueries(db);

    // Sanity: the old path *would* match "erbert" against "Frank Herbert"
    // (arbitrary substring).
    final allBooks = await db.select(db.books).get();
    final authorsByBook = await queries.watchAuthorsByBook().first;
    final genresByBook = await queries.watchGenresByBook().first;
    expect(
      filterBooks(
        books: allBooks,
        query: 'erbert',
        authorsByBook: authorsByBook,
        genresByBook: genresByBook,
      ),
      isNotEmpty,
      reason: 'old substring path matches mid-word',
    );

    // The new FTS5 path only matches token prefixes, so it must not.
    final view =
        await queries.watchLibrary(query: 'erbert', sort: ShelfSort.title).first;
    expect(view.entries, isEmpty, reason: 'FTS5 prefix match, not substring');
  });

  test('shelfId scopes to the shelf, sort still applies', () async {
    final db = await _seeded();
    addTearDown(db.close);
    final shelfId = await ShelfService(db).createShelf('Pile');
    await ShelfService(db).addToShelf('b4', shelfId);
    await ShelfService(db).addToShelf('b1', shelfId);

    final view = await LibraryQueries(db)
        .watchLibrary(shelfId: shelfId, sort: ShelfSort.title)
        .first;
    expect(_ids(view), ['b1', 'b4']);
  });

  test('hasFile reflects an attached digital file', () async {
    final db = await _seeded();
    addTearDown(db.close);
    await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
          id: 'f1',
          bookId: 'b3',
          format: 'pdf',
          path: 'files/f1.pdf',
          sizeBytes: 10,
          sha256: 'x',
        ));
    final view = await LibraryQueries(db).watchLibrary(sort: ShelfSort.title).first;
    final byId = {for (final e in view.entries) e.book.id: e.hasFile};
    expect(byId['b3'], isTrue);
    expect(byId['b1'], isFalse);
  });

  test('scopeEmpty is independent of the active filter', () async {
    final db = VellumDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final queries = LibraryQueries(db);

    // Empty library: scopeEmpty true, regardless of a filter that would also
    // (trivially) match nothing.
    var view = await queries.watchLibrary(query: 'anything').first;
    expect(view.scopeEmpty, isTrue);
    expect(view.entries, isEmpty);

    // One book, but the query matches nothing: scopeEmpty must now be false —
    // this is the "no match" case, distinct from a genuinely empty shelf.
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'Dune'));
    view = await queries.watchLibrary(query: 'nonexistent').first;
    expect(view.scopeEmpty, isFalse);
    expect(view.entries, isEmpty);

    // Unfiltered, the book shows and scopeEmpty is false.
    view = await queries.watchLibrary().first;
    expect(view.scopeEmpty, isFalse);
    expect(view.entries, hasLength(1));
  });

  test('scopeEmpty is scoped to the shelf, not the whole library', () async {
    final db = await _seeded(); // 5 books in the library
    addTearDown(db.close);
    final shelfId = await ShelfService(db).createShelf('Empty shelf');

    final view = await LibraryQueries(db).watchLibrary(shelfId: shelfId).first;
    expect(view.scopeEmpty, isTrue, reason: 'shelf has no books yet');
    expect(
      await LibraryQueries(db).watchLibrary().first.then((v) => v.scopeEmpty),
      isFalse,
      reason: 'the library itself is not empty',
    );
  });

  test('a books-only write does not re-run the authors/genres joins',
      () async {
    // Regression guard: reading position writes to `books` on every page
    // turn. An earlier version re-ran the authors/genres join queries on any
    // `books` write (~180ms per emission on a 3k-book library); splitting
    // watchLibrary into independently-invalidating streams means a
    // books-only write only re-runs the cheaper filtered/sorted books query.
    // This asserts the *symptom* directly: watchAuthorsByBook/
    // watchGenresByBook (the expensive joins) must not re-emit from a write
    // that never touches book_authors/authors/book_genres/genres.
    final db = await _seeded();
    addTearDown(db.close);
    final queries = LibraryQueries(db);

    var authorEmissions = 0;
    var genreEmissions = 0;
    final subs = [
      queries.watchAuthorsByBook().listen((_) => authorEmissions++),
      queries.watchGenresByBook().listen((_) => genreEmissions++),
    ];
    await pumpEventQueue();
    authorEmissions = 0;
    genreEmissions = 0;

    // A books-only write, same shape as saveReadingPosition/
    // saveEpubPosition's non-relational columns.
    await (db.update(db.books)..where((b) => b.id.equals('b1'))).write(
      const BooksCompanion(readingProgress: Value(0.5)),
    );
    await pumpEventQueue();

    expect(authorEmissions, 0);
    expect(genreEmissions, 0);
    for (final s in subs) {
      await s.cancel();
    }
  });

  test('renaming an author refreshes the author sort', () async {
    // The author-sort ORDER BY reads book_authors/authors through a raw SQL
    // subquery, not drift's typed query builder — confirms the explicit
    // readsFrom on the core query (not static analysis of the SQL string) is
    // what drives invalidation here.
    final db = VellumDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'X'));
    await db.into(db.authors).insert(AuthorsCompanion.insert(id: 'a1', name: 'Zed'));
    await db.into(db.bookAuthors).insert(
        BookAuthorsCompanion.insert(bookId: 'b1', authorId: 'a1'));

    final events = <String>[];
    final sub = LibraryQueries(db)
        .watchLibrary(sort: ShelfSort.author)
        .listen((view) => events.add(view.entries.single.authors.single));
    await pumpEventQueue();
    expect(events, ['Zed']);

    await (db.update(db.authors)..where((a) => a.id.equals('a1')))
        .write(const AuthorsCompanion(name: Value('Amy')));
    await pumpEventQueue();

    expect(events.last, 'Amy');
    await sub.cancel();
  });

  test('a genre added after the cache is warm reaches a live subscription',
      () async {
    // watchGenresByBook is one of the four sources LibraryQueries caches
    // behind _Cached (library_queries.dart) so repeated watchLibrary() calls
    // -- main.dart makes a fresh one on every build -- don't re-run the
    // authors/genres joins each time. Nothing exercised that cached path
    // through to LibraryView before: this pins that a genre added *after*
    // the shared subscription is already warm still reaches an
    // already-listening watchLibrary() stream, not just a fresh one.
    final db = await _seeded();
    addTearDown(db.close);
    final queries = LibraryQueries(db);

    final views = <LibraryView>[];
    final sub = queries.watchLibrary(sort: ShelfSort.title).listen(views.add);
    await pumpEventQueue();
    expect(views, isNotEmpty); // cache now warm

    await db.into(db.genres).insert(GenresCompanion.insert(id: 'g-Poetry', name: 'Poetry'));
    await db.into(db.bookGenres).insert(
        BookGenresCompanion.insert(bookId: 'b2', genreId: 'g-Poetry'));
    await pumpEventQueue();

    final b2 = views.last.entries.firstWhere((e) => e.book.id == 'b2');
    expect(b2.genres, contains('Poetry'));
    await sub.cancel();
  });

  test('allGenres and shelves are populated', () async {
    final db = await _seeded();
    addTearDown(db.close);
    await ShelfService(db).createShelf('Pile');
    final view = await LibraryQueries(db).watchLibrary(sort: ShelfSort.title).first;
    expect(view.allGenres,
        ['Classics', 'Reference', 'Science Fiction']);
    expect(view.shelves.map((s) => s.name), ['Pile']);
  });

  // The equivalence sweep: for a matrix of (query, genre, sort), watchLibrary
  // must return the same book-id order as running filterBooks then sortBooks
  // over the raw table data. Since #A2, the two paths are only equivalent
  // where FTS5 prefix matching and Dart substring matching happen to agree —
  // every case below is a *whole word* (a token's own prefix is itself), so
  // they coincide here; the deliberate divergence (a mid-word fragment) has
  // its own test above rather than being folded into — or silently loosening
  // — this sweep.
  test('matches filterBooks/sortBooks across a matrix of queries', () async {
    final db = await _seeded();
    addTearDown(db.close);
    final queries = LibraryQueries(db);

    final allBooks = await db.select(db.books).get();
    final authorsByBook = await queries.watchAuthorsByBook().first;
    final genresByBook = await queries.watchGenresByBook().first;

    const cases = [
      ('', null),
      ('silent', null),
      ('herbert', null),
      ('genre:fiction', null),
      ('', 'Classics'),
      ('dune', 'Science Fiction'),
    ];

    for (final sort in ShelfSort.values) {
      for (final (query, genre) in cases) {
        final expected = sortBooks(
          books: filterBooks(
            books: allBooks,
            query: query,
            authorsByBook: authorsByBook,
            genresByBook: genresByBook,
            genre: genre,
          ),
          sort: sort,
          authorsByBook: authorsByBook,
        );
        final view =
            await queries.watchLibrary(query: query, genre: genre, sort: sort).first;
        expect(
          _ids(view),
          [for (final b in expected) b.id],
          reason: 'sort=$sort query="$query" genre=$genre',
        );
      }
    }
  });
}
