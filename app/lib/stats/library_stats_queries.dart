import 'package:drift/drift.dart';

import '../data/database.dart';
import '../onboarding/sample_library.dart';
import 'library_stats.dart';

/// Feeds [LibraryStatsCalculator] from the database.
///
/// **One query, not N.** The genres, authors, formats and copies of every book
/// come back as columns of a single `SELECT`, built with correlated
/// subqueries and `group_concat`, so 5,000 books cost one statement and one
/// pass. `watch()` on a `customSelect` re-runs it whenever one of the tables
/// named in `readsFrom` changes, which keeps the page live.
///
/// **Excluded here:** trashed books (`deleted_at` set) and the bundled samples.
/// A sample is a book that is `sync_excluded` *and* sits on the shelf called
/// [SampleLibrary.shelfName] -- the same two markers `SampleLibrary.remove`
/// uses -- so a book the user merely kept off the server still counts.
class LibraryStatsQueries {
  const LibraryStatsQueries._();

  // char(31), the ASCII "unit separator", cannot appear in a name, unlike a
  // comma, so the joined string splits back without ambiguity.
  static const _sep = '\u001f';

  static const _sql = '''
SELECT b.id, b.published_year, b.page_count, b.status, b.created_at,
  (SELECT group_concat(g.name, char(31)) FROM book_genres bg
     JOIN genres g ON g.id = bg.genre_id WHERE bg.book_id = b.id) AS genres,
  (SELECT group_concat(a.name, char(31)) FROM book_authors ba
     JOIN authors a ON a.id = ba.author_id WHERE ba.book_id = b.id) AS authors,
  (SELECT group_concat(f.format, char(31)) FROM book_files f
     WHERE f.book_id = b.id) AS formats,
  (SELECT COALESCE(SUM(f.size_bytes), 0) FROM book_files f
     WHERE f.book_id = b.id) AS file_bytes,
  (SELECT COUNT(*) FROM physical_copies c WHERE c.book_id = b.id) AS copies
FROM books b
WHERE b.deleted_at IS NULL
  AND NOT (b.sync_excluded = 1 AND EXISTS (
    SELECT 1 FROM shelf_books sb JOIN shelves s ON s.id = sb.shelf_id
    WHERE sb.book_id = b.id AND s.name = ?))
''';

  /// The books, live. Emits again when any table the query reads changes.
  static Stream<List<LibraryStatsBook>> watchBooks(VellumDatabase db) {
    return db
        .customSelect(
          _sql,
          variables: [Variable.withString(SampleLibrary.shelfName)],
          readsFrom: {
            db.books,
            db.bookGenres,
            db.genres,
            db.bookAuthors,
            db.authors,
            db.bookFiles,
            db.physicalCopies,
            db.shelfBooks,
            db.shelves,
          },
        )
        .watch()
        .map((rows) => rows.map(_fromRow).toList());
  }

  static LibraryStatsBook _fromRow(QueryRow r) {
    List<String> split(String? s) =>
        s == null || s.isEmpty ? const [] : s.split(_sep);
    return LibraryStatsBook(
      id: r.read<String>('id'),
      publishedYear: r.readNullable<int>('published_year'),
      pageCount: r.readNullable<int>('page_count'),
      status: r.read<String>('status'),
      // drift stores DateTime as unix seconds by default.
      createdAt: DateTime.fromMillisecondsSinceEpoch(
          r.read<int>('created_at') * 1000),
      genres: split(r.readNullable<String>('genres')),
      authors: split(r.readNullable<String>('authors')),
      formats: split(r.readNullable<String>('formats')),
      fileBytes: r.read<int>('file_bytes'),
      copies: r.read<int>('copies'),
    );
  }
}
