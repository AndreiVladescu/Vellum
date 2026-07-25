import 'dart:async';

import 'package:drift/drift.dart';

import '../settings/shelf_sort.dart';
import 'database.dart';
import 'search_index.dart';

/// One shelf row's worth of data, denormalised once in the data layer so the
/// shelf never has to look authors/genres up per book.
class LibraryEntry {
  const LibraryEntry({
    required this.book,
    required this.authors,
    required this.genres,
    required this.hasFile,
  });

  final Book book;
  final List<String> authors; // ordered by book_authors.position
  final List<String> genres;
  final bool hasFile;
}

/// One snapshot of everything the shelf UI needs: already filtered and
/// sorted, so `build()` does no per-frame work over the library.
class LibraryView {
  const LibraryView({
    required this.entries,
    required this.shelves,
    required this.allGenres,
    required this.scopeEmpty,
  });

  final List<LibraryEntry> entries; // already filtered + sorted
  final List<Shelf> shelves;
  final List<String> allGenres; // for the facet menu

  /// True when the *unfiltered* scope (the whole library, or the selected
  /// shelf) has no books at all — as opposed to [entries] being empty because
  /// a search/genre filter matched nothing. The shelf UI shows a different
  /// message for each case.
  final bool scopeEmpty;

  static const empty = LibraryView(
    entries: [],
    shelves: [],
    allGenres: [],
    scopeEmpty: true,
  );
}

/// The library's read/watch side — the multi-table streams the shelf UI
/// consumes. Split out of `LibraryRepository` (plan 5 §A10) so it can be
/// tested and extended (§A1's view-model, §A2's search) in isolation from the
/// write-side services.
class LibraryQueries {
  LibraryQueries(this.db)
      : _authorsByBook = _Cached(() => _rawAuthorsByBook(db)),
        _genresByBook = _Cached(() => _rawGenresByBook(db)),
        _shelvesOrdered = _Cached(() => _rawShelvesOrdered(db)),
        _allGenreNames = _Cached(() => _rawAllGenreNames(db));

  final VellumDatabase db;

  // watchLibrary() is called fresh in main.dart's build() (a new stream
  // object per debounced keystroke) — these four don't depend on
  // query/genre/sort/shelfId at all, so caching them means a rebuild only
  // re-runs the one query that's actually parameter-dependent
  // (_watchFilteredSortedBooks) instead of all six. Measured: without this,
  // 20 fresh watchLibrary() subscriptions on a 1k-book library cost ~294ms —
  // *worse* than the Dart implementation #A1 replaced — vs ~40ms cached. See
  // docs/PERFORMANCE.md.
  final _Cached<Map<String, List<String>>> _authorsByBook;
  final _Cached<Map<String, List<String>>> _genresByBook;
  final _Cached<List<Shelf>> _shelvesOrdered;
  final _Cached<List<String>> _allGenreNames;

  /// All books, alphabetically — reactive: the shelf UI rebuilds on changes.
  Stream<List<Book>> watchAllBooks() => db.watchAllBooks();

  /// A live count of everything waiting to be pushed to the server: dirty
  /// books plus pending local deletions. Drives the debounced background
  /// auto-push.
  Stream<int> watchDirtyCount() => db
      .customSelect(
        'SELECT (SELECT COUNT(*) FROM books WHERE needs_push = 1) + '
        '(SELECT COUNT(*) FROM local_deletions) AS n',
        readsFrom: {db.books, db.localDeletions},
      )
      .watchSingle()
      .map((row) => row.read<int>('n'));

  /// `bookId -> author names` (cover order) for the whole library, as a
  /// stream, so the shelf can search by author without an N+1 of per-book
  /// queries. Cached (see [_authorsByBook]) — every call shares one
  /// underlying subscription.
  Stream<Map<String, List<String>>> watchAuthorsByBook() =>
      _authorsByBook.stream;

  static Stream<Map<String, List<String>>> _rawAuthorsByBook(
    VellumDatabase db,
  ) {
    final query = db.select(db.bookAuthors).join([
      innerJoin(db.authors, db.authors.id.equalsExp(db.bookAuthors.authorId)),
    ])
      ..orderBy([OrderingTerm.asc(db.bookAuthors.position)]);
    return query.watch().map((rows) {
      final map = <String, List<String>>{};
      for (final r in rows) {
        final bookId = r.readTable(db.bookAuthors).bookId;
        (map[bookId] ??= []).add(r.readTable(db.authors).name);
      }
      return map;
    });
  }

  /// `bookId -> genre names` for the whole library, for the `genre:` filter.
  /// Cached (see [_genresByBook]).
  Stream<Map<String, List<String>>> watchGenresByBook() => _genresByBook.stream;

  static Stream<Map<String, List<String>>> _rawGenresByBook(
    VellumDatabase db,
  ) {
    final query = db.select(db.bookGenres).join([
      innerJoin(db.genres, db.genres.id.equalsExp(db.bookGenres.genreId)),
    ]);
    return query.watch().map((rows) {
      final map = <String, List<String>>{};
      for (final r in rows) {
        final bookId = r.readTable(db.bookGenres).bookId;
        (map[bookId] ??= []).add(r.readTable(db.genres).name);
      }
      return map;
    });
  }

  static Stream<List<Shelf>> _rawShelvesOrdered(VellumDatabase db) =>
      (db.select(db.shelves)
            ..orderBy([
              (s) => OrderingTerm.asc(s.sortOrder),
              (s) => OrderingTerm.asc(s.name),
            ]))
          .watch();

  static Stream<List<String>> _rawAllGenreNames(VellumDatabase db) {
    final q = db.selectOnly(db.genres, distinct: true)
      ..addColumns([db.genres.name])
      ..orderBy([OrderingTerm(expression: db.genres.name)]);
    return q.watch().map(
          (rows) => [for (final r in rows) r.read(db.genres.name)!]
            ..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase())),
        );
  }

  /// One snapshot of the shelf: filtered (by [shelfId], [genre] facet, and
  /// [query]) and sorted (by [sort]) in SQL, joined with each book's authors
  /// and genres. Replaces `main.dart`'s four nested `StreamBuilder`s and the
  /// per-rebuild `filterBooks`/`sortBooks` scan over the whole library
  /// (plan 5 §A1) — those pure functions stay defined in `shelf_filter.dart`
  /// as the fallback for in-memory filtering (tests, small lists), but the
  /// shelf itself no longer calls them.
  ///
  /// [genre] is an exact match; [query]'s `genre:<name>` form and free-text
  /// match go through the `book_search` FTS5 index (see `search_index.dart`,
  /// plan 5 §A2): each whitespace-separated token becomes a quoted prefix
  /// match, ANDed together, diacritics-folded by the `unicode61` tokenizer.
  /// This is **prefix** matching, not the old Dart implementation's
  /// arbitrary-substring matching — typing "her" matches "Herbert" (a
  /// token-prefix), but "erbert" alone no longer would. Sorting matches
  /// `shelf_filter.dart`'s contract: author-less/year-less books sort last,
  /// ties break on title, all case-insensitive (SQL `LOWER()`, ASCII-only —
  /// unlike the FTS5 index, sort order doesn't get diacritic folding).
  ///
  /// Combines several independently-invalidating streams rather than one
  /// query reading every relevant table: reading position writes to `books`
  /// on every page turn (never touching authors/genres/shelves), and an
  /// earlier version that re-ran the authors/genres joins on any `books`
  /// write cost ~180ms per keystroke-unrelated page turn on a 3k-book
  /// library — see docs/PERFORMANCE.md. Splitting means a page turn now only
  /// re-runs the filtered/sorted books query (~28ms at that scale), not the
  /// joins.
  Stream<LibraryView> watchLibrary({
    String? shelfId,
    String query = '',
    String? genre,
    ShelfSort sort = ShelfSort.title,
  }) {
    return _combine6(
      _watchFilteredSortedBooks(shelfId: shelfId, query: query, genre: genre, sort: sort),
      _authorsByBook.stream,
      _genresByBook.stream,
      _shelvesOrdered.stream,
      _allGenreNames.stream,
      _watchScopeEmpty(shelfId),
      (books, authorsByBook, genresByBook, shelves, allGenres, scopeEmpty) {
        final entries = [
          for (final b in books)
            LibraryEntry(
              book: b.book,
              authors: authorsByBook[b.book.id] ?? const [],
              genres: genresByBook[b.book.id] ?? const [],
              hasFile: b.hasFile,
            ),
        ];
        return LibraryView(
          entries: entries,
          shelves: shelves,
          allGenres: allGenres,
          scopeEmpty: scopeEmpty,
        );
      },
    );
  }

  /// True when [shelfId] (or the whole library, if null) has zero books —
  /// independent of any search/genre filter, so a page turn or a genre edit
  /// never invalidates it, only a book actually entering/leaving the scope.
  Stream<bool> _watchScopeEmpty(String? shelfId) {
    final sql = shelfId == null
        ? 'SELECT NOT EXISTS(SELECT 1 FROM books) AS empty'
        : 'SELECT NOT EXISTS(SELECT 1 FROM shelf_books WHERE shelf_id = ?) AS empty';
    return db
        .customSelect(
          sql,
          variables: shelfId == null ? [] : [Variable.withString(shelfId)],
          readsFrom: shelfId == null
              ? {db.books}
              : {db.shelfBooks},
        )
        .watchSingle()
        .map((row) => row.read<bool>('empty'));
  }

  Stream<List<({Book book, bool hasFile})>> _watchFilteredSortedBooks({
    String? shelfId,
    String query = '',
    String? genre,
    ShelfSort sort = ShelfSort.title,
  }) {
    final where = <String>[];
    final vars = <Variable>[];

    if (shelfId != null) {
      where.add(
        'books.id IN (SELECT book_id FROM shelf_books WHERE shelf_id = ?)',
      );
      vars.add(Variable.withString(shelfId));
    }
    if (genre != null && genre.isNotEmpty) {
      where.add(
        'EXISTS (SELECT 1 FROM book_genres bg JOIN genres g '
        'ON g.id = bg.genre_id WHERE bg.book_id = books.id AND g.name = ?)',
      );
      vars.add(Variable.withString(genre));
    }
    final q = query.trim();
    if (q.isNotEmpty) {
      final lower = q.toLowerCase();
      if (lower.startsWith('genre:')) {
        final wanted = lower.substring('genre:'.length).trim();
        final match = ftsMatchQuery(wanted, column: 'genres');
        if (match != null) {
          where.add(
            'books.id IN (SELECT book_id FROM book_search WHERE book_search MATCH ?)',
          );
          vars.add(Variable.withString(match));
        }
      } else {
        final match = ftsMatchQuery(q);
        if (match != null) {
          where.add(
            'books.id IN (SELECT book_id FROM book_search WHERE book_search MATCH ?)',
          );
          vars.add(Variable.withString(match));
        }
      }
    }

    // The first author's name (by position), for the author sort — exposed as
    // a select-list alias so ORDER BY can reference it without repeating the
    // subquery.
    const authorSortExpr = '(SELECT LOWER(a.name) FROM book_authors ba '
        'JOIN authors a ON a.id = ba.author_id '
        'WHERE ba.book_id = books.id ORDER BY ba.position LIMIT 1)';

    final orderBy = switch (sort) {
      ShelfSort.title => 'LOWER(books.title)',
      ShelfSort.author =>
        'sort_author IS NULL, sort_author, LOWER(books.title)',
      ShelfSort.year =>
        'books.published_year IS NULL, books.published_year, '
            'LOWER(books.title)',
    };

    final sql =
        'SELECT books.*, $authorSortExpr AS sort_author, '
        'EXISTS(SELECT 1 FROM book_files bf WHERE bf.book_id = books.id) '
        'AS has_file '
        'FROM books '
        '${where.isEmpty ? '' : 'WHERE ${where.join(' AND ')}'} '
        'ORDER BY $orderBy';

    // genre/text filtering reads book_authors/authors/book_genres/genres too
    // (via EXISTS), so this must stay in readsFrom even though a plain
    // unfiltered query wouldn't otherwise touch them.
    return db
        .customSelect(
          sql,
          variables: vars,
          readsFrom: {
            db.books,
            db.bookAuthors,
            db.authors,
            db.bookGenres,
            db.genres,
            db.shelfBooks,
            db.bookFiles,
          },
        )
        .watch()
        .map((rows) => [
              for (final row in rows)
                (book: db.books.map(row.data), hasFile: row.read<bool>('has_file')),
            ]);
  }
}

/// Subscribes to [source] once, lazily, on first use — not at construction —
/// and keeps that one subscription alive for as long as the owning
/// `LibraryQueries` lives (there is no "nobody's listening any more" signal
/// worth tearing down for here; the shelf is the app's home screen). Every
/// caller of [stream] shares that subscription: a late subscriber gets the
/// last known value immediately (no waiting for the next write before the
/// first frame), then live updates alongside everyone else.
class _Cached<T> {
  _Cached(this._source);

  final Stream<T> Function() _source;
  final _controller = StreamController<T>.broadcast();
  StreamSubscription<T>? _sub;
  T? _last;
  bool _hasValue = false;

  Stream<T> get stream {
    _sub ??= _source().listen(
      (v) {
        _last = v;
        _hasValue = true;
        _controller.add(v);
      },
      onError: _controller.addError,
    );
    return _hasValue ? _replay() : _controller.stream;
  }

  Stream<T> _replay() async* {
    yield _last as T;
    yield* _controller.stream;
  }
}

/// Combines six streams into one, re-emitting `combine(...)` of the latest
/// value from each whenever any of them fires, once all six have emitted at
/// least once. A small hand-rolled `combineLatest` (no rxdart dependency) —
/// `watchLibrary` is its only user.
Stream<R> _combine6<A, B, C, D, E, F, R>(
  Stream<A> sa,
  Stream<B> sb,
  Stream<C> sc,
  Stream<D> sd,
  Stream<E> se,
  Stream<F> sf,
  R Function(A, B, C, D, E, F) combine,
) {
  late final StreamController<R> controller;
  A? a;
  B? b;
  C? c;
  D? d;
  E? e;
  F? f;
  var hasA = false, hasB = false, hasC = false, hasD = false, hasE = false, hasF = false;
  final subs = <StreamSubscription<void>>[];

  void emitIfReady() {
    if (hasA && hasB && hasC && hasD && hasE && hasF) {
      controller.add(combine(a as A, b as B, c as C, d as D, e as E, f as F));
    }
  }

  controller = StreamController<R>(
    onListen: () {
      subs.add(sa.listen((v) {
        a = v;
        hasA = true;
        emitIfReady();
      }, onError: controller.addError));
      subs.add(sb.listen((v) {
        b = v;
        hasB = true;
        emitIfReady();
      }, onError: controller.addError));
      subs.add(sc.listen((v) {
        c = v;
        hasC = true;
        emitIfReady();
      }, onError: controller.addError));
      subs.add(sd.listen((v) {
        d = v;
        hasD = true;
        emitIfReady();
      }, onError: controller.addError));
      subs.add(se.listen((v) {
        e = v;
        hasE = true;
        emitIfReady();
      }, onError: controller.addError));
      subs.add(sf.listen((v) {
        f = v;
        hasF = true;
        emitIfReady();
      }, onError: controller.addError));
    },
    onCancel: () async {
      for (final s in subs) {
        await s.cancel();
      }
      subs.clear();
    },
  );
  return controller.stream;
}
