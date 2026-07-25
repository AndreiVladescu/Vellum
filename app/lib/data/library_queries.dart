import 'package:drift/drift.dart';

import '../settings/shelf_sort.dart';
import 'database.dart';

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
  });

  final List<LibraryEntry> entries; // already filtered + sorted
  final List<Shelf> shelves;
  final List<String> allGenres; // for the facet menu

  static const empty = LibraryView(entries: [], shelves: [], allGenres: []);
}

/// The library's read/watch side — the multi-table streams the shelf UI
/// consumes. Split out of `LibraryRepository` (plan 5 §A10) so it can be
/// tested and extended (§A1's view-model, §A2's search) in isolation from the
/// write-side services.
class LibraryQueries {
  LibraryQueries(this.db);

  final VellumDatabase db;

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
  /// queries.
  Stream<Map<String, List<String>>> watchAuthorsByBook() {
    final query = db.select(db.bookAuthors).join([
      innerJoin(db.authors, db.authors.id.equalsExp(db.bookAuthors.authorId)),
    ])
      ..orderBy([OrderingTerm.asc(db.bookAuthors.position)]);
    return query.watch().map(_groupAuthors);
  }

  Future<Map<String, List<String>>> _authorsByBookOnce() async {
    final query = db.select(db.bookAuthors).join([
      innerJoin(db.authors, db.authors.id.equalsExp(db.bookAuthors.authorId)),
    ])
      ..orderBy([OrderingTerm.asc(db.bookAuthors.position)]);
    return _groupAuthors(await query.get());
  }

  Map<String, List<String>> _groupAuthors(List<TypedResult> rows) {
    final map = <String, List<String>>{};
    for (final r in rows) {
      final bookId = r.readTable(db.bookAuthors).bookId;
      (map[bookId] ??= []).add(r.readTable(db.authors).name);
    }
    return map;
  }

  /// `bookId -> genre names` for the whole library, for the `genre:` filter.
  Stream<Map<String, List<String>>> watchGenresByBook() {
    final query = db.select(db.bookGenres).join([
      innerJoin(db.genres, db.genres.id.equalsExp(db.bookGenres.genreId)),
    ]);
    return query.watch().map(_groupGenres);
  }

  Future<Map<String, List<String>>> _genresByBookOnce() async {
    final query = db.select(db.bookGenres).join([
      innerJoin(db.genres, db.genres.id.equalsExp(db.bookGenres.genreId)),
    ]);
    return _groupGenres(await query.get());
  }

  Map<String, List<String>> _groupGenres(List<TypedResult> rows) {
    final map = <String, List<String>>{};
    for (final r in rows) {
      final bookId = r.readTable(db.bookGenres).bookId;
      (map[bookId] ??= []).add(r.readTable(db.genres).name);
    }
    return map;
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
  /// match are substring, case-insensitive for ASCII (SQLite's `LIKE`
  /// default — non-ASCII case-folding is deferred to #2's FTS5 index, which
  /// replaces this method's free-text half). Sorting matches
  /// `shelf_filter.dart`'s contract: author-less/year-less books sort last,
  /// ties break on title, all case-insensitive.
  Stream<LibraryView> watchLibrary({
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
        if (wanted.isNotEmpty) {
          where.add(
            'EXISTS (SELECT 1 FROM book_genres bg JOIN genres g '
            'ON g.id = bg.genre_id WHERE bg.book_id = books.id '
            "AND g.name LIKE ? ESCAPE '\\')",
          );
          vars.add(Variable.withString('%${_escapeLike(wanted)}%'));
        }
      } else {
        where.add(
          "(books.title LIKE ? ESCAPE '\\' OR books.subtitle LIKE ? ESCAPE '\\' OR "
          'EXISTS (SELECT 1 FROM book_authors ba JOIN authors a '
          "ON a.id = ba.author_id WHERE ba.book_id = books.id AND a.name LIKE ? ESCAPE '\\'))",
        );
        final pattern = '%${_escapeLike(q)}%';
        vars.addAll([
          Variable.withString(pattern),
          Variable.withString(pattern),
          Variable.withString(pattern),
        ]);
      }
    }

    // The first author's name (by position), for the author sort — exposed as
    // a select-list alias so ORDER BY can reference it without repeating the
    // subquery (and without an extra query per book).
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
        .asyncMap((rows) async {
          final authorsByBook = await _authorsByBookOnce();
          final genresByBook = await _genresByBookOnce();
          final shelves = await (db.select(db.shelves)
                ..orderBy([
                  (s) => OrderingTerm.asc(s.sortOrder),
                  (s) => OrderingTerm.asc(s.name),
                ]))
              .get();
          final allGenres = [
            for (final g in await (db.select(db.genres)
                  ..orderBy([(g) => OrderingTerm.asc(g.name)]))
                .get())
              g.name,
          ]..sort((a, b) => a.toLowerCase().compareTo(b.toLowerCase()));

          final entries = [
            for (final row in rows)
              LibraryEntry(
                book: db.books.map(row.data),
                authors: authorsByBook[row.read<String>('id')] ?? const [],
                genres: genresByBook[row.read<String>('id')] ?? const [],
                hasFile: row.read<bool>('has_file'),
              ),
          ];
          return LibraryView(
            entries: entries,
            shelves: shelves,
            allGenres: allGenres,
          );
        });
  }

  static String _escapeLike(String s) => s
      .replaceAll('\\', '\\\\')
      .replaceAll('%', '\\%')
      .replaceAll('_', '\\_');
}
