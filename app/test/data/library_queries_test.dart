import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_queries.dart';

void main() {
  late VellumDatabase db;
  late LibraryQueries queries;
  setUp(() {
    db = VellumDatabase(NativeDatabase.memory());
    queries = LibraryQueries(db);
  });
  tearDown(() => db.close());

  test('watchAllBooks reflects inserts, alphabetically', () async {
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b2', title: 'Zed'));
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'Alpha'));
    final books = await queries.watchAllBooks().first;
    expect([for (final b in books) b.title], ['Alpha', 'Zed']);
  });

  test('watchAuthorsByBook and watchGenresByBook aggregate per book',
      () async {
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'Dune'));
    await db.into(db.authors).insert(
        AuthorsCompanion.insert(id: 'a1', name: 'Frank Herbert'));
    await db.into(db.bookAuthors).insert(
        BookAuthorsCompanion.insert(bookId: 'b1', authorId: 'a1'));
    await db
        .into(db.genres)
        .insert(GenresCompanion.insert(id: 'g1', name: 'Sci-Fi'));
    await db.into(db.bookGenres).insert(
        BookGenresCompanion.insert(bookId: 'b1', genreId: 'g1'));

    expect(await queries.watchAuthorsByBook().first,
        {'b1': ['Frank Herbert']});
    expect(await queries.watchGenresByBook().first, {'b1': ['Sci-Fi']});
  });

  // A lookup by one of these columns used to scan its whole table — the
  // shelf's `has_file` check did it once per book, on every page turn. Pinned
  // as query plans, because a dropped index is otherwise invisible until a
  // library is large enough to feel it.
  test('foreign-key lookups use an index, not a table scan', () async {
    const lookups = {
      'book_files': 'book_id',
      'book_authors': 'author_id',
      'book_genres': 'genre_id',
      'shelf_books': 'book_id',
      'physical_copies': 'book_id',
      'loans': 'copy_id',
      'copy_photos': 'copy_id',
      'annotations': 'book_id',
      'reading_sessions': 'book_id',
      'book_placements': 'copy_id',
      'physical_shelves': 'environment_id',
      'room_props': 'environment_id',
      'book_text': 'book_id',
    };
    for (final MapEntry(key: table, value: column) in lookups.entries) {
      final plan = await db
          .customSelect('EXPLAIN QUERY PLAN SELECT * FROM $table '
              "WHERE $column = 'x'")
          .get();
      final detail = plan.map((r) => r.read<String>('detail')).join('\n');
      expect(detail, contains('INDEX'), reason: '$table.$column: $detail');
    }
  });

  test('watchDirtyCount counts dirty books plus pending local deletions',
      () async {
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'b1',
          title: 'Clean',
          needsPush: const Value(false),
        ));
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b2', title: 'Dirty'));
    await db
        .into(db.localDeletions)
        .insert(LocalDeletionsCompanion.insert(bookId: 'gone'));

    expect(await queries.watchDirtyCount().first, 2);
  });
}
