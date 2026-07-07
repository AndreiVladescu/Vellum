import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../shelf/spine_style.dart';
import 'database.dart';
import 'metadata.dart';

/// Author names and genre names for a book, for the detail view.
typedef BookDetails = ({List<String> authors, List<String> genres});

/// All library operations the UI needs. Wraps the local database, the
/// filesystem store (covers, later book files), and the metadata client.
class LibraryRepository {
  LibraryRepository._(this.db, this.metadata, this._dataDir);

  final VellumDatabase db;
  final OpenLibraryClient metadata;
  final Directory _dataDir;

  static const _uuid = Uuid();

  static Future<LibraryRepository> open(VellumDatabase db) async {
    final dir = await getApplicationSupportDirectory();
    await Directory(p.join(dir.path, 'covers')).create(recursive: true);
    await Directory(p.join(dir.path, 'files')).create(recursive: true);
    return LibraryRepository._(db, OpenLibraryClient(), dir);
  }

  Stream<List<Book>> watchAllBooks() => db.watchAllBooks();

  Stream<Book?> watchBook(String id) =>
      (db.select(db.books)..where((b) => b.id.equals(id))).watchSingleOrNull();

  Stream<List<BookFile>> watchFilesOf(String bookId) =>
      (db.select(db.bookFiles)..where((f) => f.bookId.equals(bookId))).watch();

  Stream<List<PhysicalCopy>> watchCopiesOf(String bookId) =>
      (db.select(db.physicalCopies)
            ..where((c) => c.bookId.equals(bookId)))
          .watch();

  /// Absolute file for an attached digital copy.
  File fileOf(BookFile file) => File(p.join(_dataDir.path, file.path));

  /// Copies a picked file into the library store and records it.
  Future<void> attachFile(String bookId, String sourcePath) async {
    final source = File(sourcePath);
    final ext = p.extension(sourcePath).replaceFirst('.', '').toLowerCase();
    final id = _uuid.v4();
    final relPath = p.join('files', '$id.$ext');
    await source.copy(p.join(_dataDir.path, relPath));
    final digest = await sha256.bind(source.openRead()).first;
    await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
          id: id,
          bookId: bookId,
          format: ext.isEmpty ? 'unknown' : ext,
          path: relPath,
          sizeBytes: await source.length(),
          sha256: digest.toString(),
        ));
  }

  Future<void> addPhysicalCopy(String bookId,
      {String? location, String? notes}) async {
    await db.into(db.physicalCopies).insert(PhysicalCopiesCompanion.insert(
          id: _uuid.v4(),
          bookId: bookId,
          location: Value(location),
          notes: Value(notes),
        ));
  }

  /// Loan history for a physical copy, most recent first. The active loan (if
  /// any) is the row whose returnedAt is null.
  Stream<List<Loan>> watchLoansOf(String copyId) => (db.select(db.loans)
        ..where((l) => l.copyId.equals(copyId))
        ..orderBy([(l) => OrderingTerm.desc(l.loanedAt)]))
      .watch();

  /// Lends a copy to [borrower]. Callers only offer this when the copy has no
  /// active loan, so no additional check is needed here.
  Future<void> lendCopy(String copyId, String borrower) async {
    await db.into(db.loans).insert(LoansCompanion.insert(
          id: _uuid.v4(),
          copyId: copyId,
          borrower: borrower,
        ));
  }

  /// Marks a loan returned as of now, keeping it in the history.
  Future<void> returnLoan(String loanId) async {
    await (db.update(db.loans)..where((l) => l.id.equals(loanId)))
        .write(LoansCompanion(returnedAt: Value(DateTime.now())));
  }

  /// Called by the reader as the user turns pages.
  Future<void> saveReadingPosition(
      String bookId, int page, int pageCount) async {
    final now = DateTime.now();
    await (db.update(db.books)..where((b) => b.id.equals(bookId)))
        .write(BooksCompanion(
      readingProgress: Value(pageCount == 0 ? 0 : page / pageCount),
      lastReadPage: Value(page),
      lastReadAt: Value(now),
      updatedAt: Value(now),
    ));
  }

  /// Absolute file for a book's cover, or null if it has none.
  File? coverFileOf(Book book) => book.coverPath == null
      ? null
      : File(p.join(_dataDir.path, book.coverPath!));

  /// Adds a book picked from online search results: fetches the description
  /// and cover over the network, generates a spine, and stores everything.
  Future<String> addFromSearch(BookSearchResult result) async {
    final id = _uuid.v4();

    // Network work first, outside the transaction.
    final description = await metadata.fetchDescription(result.workKey);
    String? coverPath;
    final coverBytes = await metadata.downloadCover(result.coverId);
    if (coverBytes != null) {
      coverPath = p.join('covers', '$id.jpg');
      await File(p.join(_dataDir.path, coverPath)).writeAsBytes(coverBytes);
    }

    final spine = SpineStyle.generate(
      title: result.title,
      author: result.authors.firstOrNull,
      pageCount: result.pageCount,
    );

    await db.transaction(() async {
      await db.into(db.books).insert(BooksCompanion.insert(
            id: id,
            title: result.title,
            subtitle: Value(result.subtitle),
            description: Value(description),
            isbn: Value(result.isbn),
            publisher: Value(result.publisher),
            publishedYear: Value(result.firstPublishYear),
            pageCount: Value(result.pageCount),
            coverPath: Value(coverPath),
            spineStyle: Value(spine.toJson()),
          ));

      var position = 0;
      for (final name in result.authors) {
        final authorId = await _idForName(db.authors, name);
        await db.into(db.bookAuthors).insert(BookAuthorsCompanion.insert(
              bookId: id,
              authorId: authorId,
              position: Value(position++),
            ));
      }

      // Open Library "subjects" are noisy; keep the first few short ones.
      final genres = result.subjects
          .where((s) => s.length <= 28 && !s.contains(':'))
          .take(3);
      for (final name in genres) {
        final genreId = await _idForName(db.genres, name);
        await db
            .into(db.bookGenres)
            .insert(BookGenresCompanion.insert(bookId: id, genreId: genreId));
      }
    });
    return id;
  }

  /// Get-or-create for the name-keyed lookup tables (authors, genres).
  Future<String> _idForName(TableInfo table, String name) async {
    final existing = await db
        .customSelect(
          'SELECT id FROM ${table.actualTableName} WHERE name = ?',
          variables: [Variable.withString(name)],
        )
        .getSingleOrNull();
    if (existing != null) return existing.read<String>('id');
    final id = _uuid.v4();
    await db.customStatement(
      'INSERT INTO ${table.actualTableName} (id, name) VALUES (?, ?)',
      [id, name],
    );
    return id;
  }

  Future<BookDetails> detailsFor(String bookId) async {
    // Note: drift table names are plural (books, authors, ...) while the
    // server's SQL schema uses singular names; sync happens over REST, so
    // only the column/relation structure needs to match.
    final authorRows = await db.customSelect(
      'SELECT a.name FROM authors a '
      'JOIN book_authors ba ON ba.author_id = a.id '
      'WHERE ba.book_id = ? ORDER BY ba.position',
      variables: [Variable.withString(bookId)],
    ).get();
    final genreRows = await db.customSelect(
      'SELECT g.name FROM genres g '
      'JOIN book_genres bg ON bg.genre_id = g.id '
      'WHERE bg.book_id = ? ORDER BY g.name',
      variables: [Variable.withString(bookId)],
    ).get();
    return (
      authors: [for (final r in authorRows) r.read<String>('name')],
      genres: [for (final r in genreRows) r.read<String>('name')],
    );
  }

  Future<void> deleteBook(Book book) async {
    final attachedFiles = await (db.select(db.bookFiles)
          ..where((f) => f.bookId.equals(book.id)))
        .get();
    await db.transaction(() async {
      // Explicit deletes rather than relying on FK cascades, so this works
      // on databases created before cascades were added to the schema.
      for (final table in [
        'book_authors',
        'book_genres',
        'book_files',
        'shelf_books',
      ]) {
        await db.customStatement(
            'DELETE FROM $table WHERE book_id = ?', [book.id]);
      }
      await db.customStatement(
          'DELETE FROM loans WHERE copy_id IN '
          '(SELECT id FROM physical_copies WHERE book_id = ?)',
          [book.id]);
      await db.customStatement(
          'DELETE FROM physical_copies WHERE book_id = ?', [book.id]);
      await (db.delete(db.books)..where((b) => b.id.equals(book.id))).go();
    });
    final cover = coverFileOf(book);
    if (cover != null && await cover.exists()) await cover.delete();
    for (final f in attachedFiles) {
      final file = fileOf(f);
      if (await file.exists()) await file.delete();
    }
  }
}
