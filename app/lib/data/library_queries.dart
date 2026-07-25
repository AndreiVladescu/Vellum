import 'package:drift/drift.dart';

import 'database.dart';

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
  Stream<Map<String, List<String>>> watchGenresByBook() {
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
}
