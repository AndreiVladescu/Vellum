import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../shelf/spine_style.dart';
import 'database.dart';
import 'metadata.dart';
import 'pdf_cover.dart';

/// Author names and genre names for a book, for the detail view.
typedef BookDetails = ({List<String> authors, List<String> genres});

/// A placement joined with the book it shows, for rendering an environment.
typedef PlacedBook = ({BookPlacement placement, Book book});

/// All library operations the UI needs. Wraps the local database, the
/// filesystem store (covers, later book files), and the metadata client.
class LibraryRepository {
  LibraryRepository._(this.db, this.metadata, this._dataDir);

  final VellumDatabase db;
  final MetadataService metadata;
  final Directory _dataDir;

  static const _uuid = Uuid();

  static Future<LibraryRepository> open(VellumDatabase db) async {
    final dir = await getApplicationSupportDirectory();
    return _withDataDir(db, dir);
  }

  /// Builds a repository over an explicit data directory instead of the
  /// platform app-support dir — for tests that can't reach `path_provider`.
  @visibleForTesting
  static Future<LibraryRepository> forTesting(
    VellumDatabase db,
    Directory dataDir,
  ) => _withDataDir(db, dataDir);

  static Future<LibraryRepository> _withDataDir(
    VellumDatabase db,
    Directory dir,
  ) async {
    await Directory(p.join(dir.path, 'covers')).create(recursive: true);
    await Directory(p.join(dir.path, 'files')).create(recursive: true);
    return LibraryRepository._(db, MetadataService(), dir);
  }

  Stream<List<Book>> watchAllBooks() => db.watchAllBooks();

  Stream<Book?> watchBook(String id) =>
      (db.select(db.books)..where((b) => b.id.equals(id))).watchSingleOrNull();

  Stream<List<BookFile>> watchFilesOf(String bookId) =>
      (db.select(db.bookFiles)..where((f) => f.bookId.equals(bookId))).watch();

  Stream<List<PhysicalCopy>> watchCopiesOf(String bookId) => (db.select(
    db.physicalCopies,
  )..where((c) => c.bookId.equals(bookId))).watch();

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
    await db
        .into(db.bookFiles)
        .insert(
          BookFilesCompanion.insert(
            id: id,
            bookId: bookId,
            format: ext.isEmpty ? 'unknown' : ext,
            path: relPath,
            sizeBytes: await source.length(),
            sha256: digest.toString(),
          ),
        );
    // A cover-less book that just got a PDF: use its first page as the cover.
    if (ext == 'pdf') {
      final book = await (db.select(
        db.books,
      )..where((b) => b.id.equals(bookId))).getSingleOrNull();
      if (book != null && book.coverPath == null) {
        await setCoverFromFirstPage(bookId);
      }
    }
  }

  /// Creates a book by hand — for a PDF you can't find in an online library.
  /// It has no [sourceMetadata], so it offers no "revert to default".
  Future<String> createCustomBook({
    required String title,
    String? author,
    int? publishedYear,
    String? description,
  }) async {
    final id = _uuid.v4();
    final spine = SpineStyle.generate(title: title, author: author);
    await db.transaction(() async {
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
              id: id,
              title: title.trim(),
              description: Value(_blankToNull(description)),
              publishedYear: Value(publishedYear),
              spineStyle: Value(spine.toJson()),
            ),
          );
      final name = author?.trim();
      if (name != null && name.isNotEmpty) {
        final authorId = await _idForName(db.authors, name);
        await db
            .into(db.bookAuthors)
            .insert(
              BookAuthorsCompanion.insert(bookId: id, authorId: authorId),
            );
      }
    });
    return id;
  }

  /// Applies edited details (from the detail-page edit form). Empty subtitle /
  /// description clear the field; a null [publishedYear] / [pageCount] clears
  /// that field. The page count drives the physical spine width.
  Future<void> updateBookDetails(
    String id, {
    required String title,
    String? subtitle,
    int? publishedYear,
    int? pageCount,
    String? description,
  }) async {
    await (db.update(db.books)..where((b) => b.id.equals(id))).write(
      BooksCompanion(
        title: Value(title.trim()),
        subtitle: Value(_blankToNull(subtitle)),
        publishedYear: Value(publishedYear),
        pageCount: Value(pageCount),
        description: Value(_blankToNull(description)),
        updatedAt: Value(DateTime.now()),
      ),
    );
  }

  /// Replaces a book's authors with [names] (comma-splitting is the caller's
  /// job). Blank names are ignored; order is preserved.
  Future<void> setAuthors(String bookId, List<String> names) async {
    await db.transaction(() async {
      await db.customStatement(
        'DELETE FROM book_authors WHERE book_id = ?',
        [bookId],
      );
      var position = 0;
      for (final raw in names) {
        final name = raw.trim();
        if (name.isEmpty) continue;
        final authorId = await _idForName(db.authors, name);
        await db
            .into(db.bookAuthors)
            .insert(
              BookAuthorsCompanion.insert(
                bookId: bookId,
                authorId: authorId,
                position: Value(position++),
              ),
            );
      }
    });
  }

  /// Personal notes — stored locally only, never pushed to a server.
  Future<void> setReaderNotes(String bookId, String? notes) async {
    await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(readerNotes: Value(_blankToNull(notes))),
    );
  }

  /// Replaces a book's cover from raw image bytes.
  Future<void> setCoverBytes(String bookId, Uint8List bytes) async {
    final rel = p.join('covers', '$bookId.jpg');
    await File(p.join(_dataDir.path, rel)).writeAsBytes(bytes);
    await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(coverPath: Value(rel), updatedAt: Value(DateTime.now())),
    );
  }

  Future<void> setCoverFromFile(String bookId, String sourcePath) async =>
      setCoverBytes(bookId, await File(sourcePath).readAsBytes());

  /// Renders the first page of one of the book's attached PDFs and uses it as
  /// the cover. Returns false if the book has no PDF or rendering fails.
  Future<bool> setCoverFromFirstPage(String bookId) async {
    final files = await (db.select(
      db.bookFiles,
    )..where((f) => f.bookId.equals(bookId) & f.format.equals('pdf'))).get();
    if (files.isEmpty) return false;
    final png = await renderPdfFirstPagePng(
      p.join(_dataDir.path, files.first.path),
    );
    if (png == null) return false;
    await setCoverBytes(bookId, png);
    return true;
  }

  /// The page count read from one of the book's attached PDFs, or null if it
  /// has no PDF or the file can't be read.
  Future<int?> pageCountFromFile(String bookId) async {
    final files = await (db.select(db.bookFiles)
          ..where((f) => f.bookId.equals(bookId) & f.format.equals('pdf')))
        .get();
    if (files.isEmpty) return null;
    try {
      return await pdfPageCount(p.join(_dataDir.path, files.first.path));
    } catch (_) {
      return null;
    }
  }

  /// True when the book was imported from a library and can be reset.
  bool canRevert(Book book) => book.sourceMetadata != null;

  /// Restores the book's details (and cover, if online) to the official
  /// library snapshot captured at import.
  Future<void> revertToDefault(Book book) async {
    final raw = book.sourceMetadata;
    if (raw == null) return;
    final m = jsonDecode(raw) as Map<String, dynamic>;
    await (db.update(db.books)..where((b) => b.id.equals(book.id))).write(
      BooksCompanion(
        title: Value((m['title'] as String?) ?? book.title),
        subtitle: Value(m['subtitle'] as String?),
        description: Value(m['description'] as String?),
        isbn: Value(m['isbn'] as String?),
        publisher: Value(m['publisher'] as String?),
        publishedYear: Value(m['publishedYear'] as int?),
        pageCount: Value(m['pageCount'] as int?),
        updatedAt: Value(DateTime.now()),
      ),
    );
    final coverUrl = m['coverUrl'] as String?;
    if (coverUrl != null) {
      try {
        final res = await http.get(Uri.parse(coverUrl));
        if (res.statusCode == 200 && res.bodyBytes.isNotEmpty) {
          await setCoverBytes(book.id, res.bodyBytes);
        }
      } catch (_) {
        // Keep the reverted metadata even if the cover can't be re-fetched.
      }
    }
  }

  static String? _blankToNull(String? s) {
    final t = s?.trim();
    return (t == null || t.isEmpty) ? null : t;
  }

  Future<void> addPhysicalCopy(
    String bookId, {
    String? location,
    String? notes,
  }) async {
    await db
        .into(db.physicalCopies)
        .insert(
          PhysicalCopiesCompanion.insert(
            id: _uuid.v4(),
            bookId: bookId,
            location: Value(location),
            notes: Value(notes),
          ),
        );
  }

  /// Loan history for a physical copy, most recent first. The active loan (if
  /// any) is the row whose returnedAt is null.
  Stream<List<Loan>> watchLoansOf(String copyId) =>
      (db.select(db.loans)
            ..where((l) => l.copyId.equals(copyId))
            ..orderBy([(l) => OrderingTerm.desc(l.loanedAt)]))
          .watch();

  /// Lends a copy to [borrower]. Callers only offer this when the copy has no
  /// active loan, so no additional check is needed here.
  Future<void> lendCopy(String copyId, String borrower) async {
    await db
        .into(db.loans)
        .insert(
          LoansCompanion.insert(
            id: _uuid.v4(),
            copyId: copyId,
            borrower: borrower,
          ),
        );
  }

  /// Marks a loan returned as of now, keeping it in the history.
  Future<void> returnLoan(String loanId) async {
    await (db.update(db.loans)..where((l) => l.id.equals(loanId))).write(
      LoansCompanion(returnedAt: Value(DateTime.now())),
    );
  }

  // ---- Physical layouts (app-local; see database.dart) --------------------

  Stream<List<PhysicalEnvironment>> watchEnvironments() =>
      (db.select(db.physicalEnvironments)
            ..orderBy([
              (e) => OrderingTerm.asc(e.sortOrder),
              (e) => OrderingTerm.asc(e.createdAt),
            ]))
          .watch();

  Future<String> createEnvironment(String name) async {
    final id = _uuid.v4();
    final existing = await db.select(db.physicalEnvironments).get();
    await db
        .into(db.physicalEnvironments)
        .insert(
          PhysicalEnvironmentsCompanion.insert(
            id: id,
            name: name.trim(),
            sortOrder: Value(existing.length),
          ),
        );
    return id;
  }

  Future<void> renameEnvironment(String id, String name) async {
    await (db.update(db.physicalEnvironments)..where((e) => e.id.equals(id)))
        .write(PhysicalEnvironmentsCompanion(name: Value(name.trim())));
  }

  /// Removes an environment along with its shelves, placements, and the copies
  /// those placements created.
  Future<void> deleteEnvironment(String id) async {
    await db.transaction(() async {
      final placements = await (db.select(
        db.bookPlacements,
      )..where((p) => p.environmentId.equals(id))).get();
      await (db.delete(db.bookPlacements)
            ..where((p) => p.environmentId.equals(id)))
          .go();
      for (final placement in placements) {
        await _deleteCopy(placement.copyId);
      }
      await (db.delete(db.physicalShelves)
            ..where((s) => s.environmentId.equals(id)))
          .go();
      await (db.delete(db.physicalEnvironments)..where((e) => e.id.equals(id)))
          .go();
    });
  }

  Stream<List<PhysicalShelf>> watchShelves(String environmentId) =>
      (db.select(db.physicalShelves)
            ..where((s) => s.environmentId.equals(environmentId)))
          .watch();

  Future<void> addShelf(
    String environmentId, {
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    String? label,
  }) async {
    await db
        .into(db.physicalShelves)
        .insert(
          PhysicalShelvesCompanion.insert(
            id: _uuid.v4(),
            environmentId: environmentId,
            x1: x1,
            y1: y1,
            x2: x2,
            y2: y2,
            label: Value(label),
          ),
        );
  }

  Future<void> updateShelf(
    String id, {
    double? x1,
    double? y1,
    double? x2,
    double? y2,
    Value<String?>? label,
  }) async {
    await (db.update(db.physicalShelves)..where((s) => s.id.equals(id))).write(
      PhysicalShelvesCompanion(
        x1: x1 == null ? const Value.absent() : Value(x1),
        y1: y1 == null ? const Value.absent() : Value(y1),
        x2: x2 == null ? const Value.absent() : Value(x2),
        y2: y2 == null ? const Value.absent() : Value(y2),
        label: label ?? const Value.absent(),
      ),
    );
  }

  Future<void> deleteShelf(String id) async {
    await (db.delete(db.physicalShelves)..where((s) => s.id.equals(id))).go();
  }

  /// Placements joined with their books, for rendering.
  Stream<List<PlacedBook>> watchPlacedBooks(String environmentId) {
    final query =
        db.select(db.bookPlacements).join([
            innerJoin(
              db.physicalCopies,
              db.physicalCopies.id.equalsExp(db.bookPlacements.copyId),
            ),
            innerJoin(
              db.books,
              db.books.id.equalsExp(db.physicalCopies.bookId),
            ),
          ])
          ..where(db.bookPlacements.environmentId.equals(environmentId));
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          (
            placement: r.readTable(db.bookPlacements),
            book: r.readTable(db.books),
          ),
      ],
    );
  }

  /// Drops a book into an environment: creates a fresh physical copy (so the
  /// same title can be placed several times) and a placement at `(x, y)`.
  Future<void> placeBook(
    String environmentId,
    String bookId, {
    required double x,
    required double y,
  }) async {
    await db.transaction(() async {
      final copyId = _uuid.v4();
      await db
          .into(db.physicalCopies)
          .insert(
            PhysicalCopiesCompanion.insert(id: copyId, bookId: bookId),
          );
      await db
          .into(db.bookPlacements)
          .insert(
            BookPlacementsCompanion.insert(
              id: _uuid.v4(),
              environmentId: environmentId,
              copyId: copyId,
              x: x,
              y: y,
            ),
          );
    });
  }

  /// Partial update of a placement; omitted arguments are left unchanged.
  /// Pass a `Value(null)` for a size override to clear it back to the default.
  Future<void> updatePlacement(
    String id, {
    double? x,
    double? y,
    int? rotation,
    Value<double?>? widthOverride,
    Value<double?>? heightOverride,
    Value<String?>? format,
  }) async {
    await (db.update(db.bookPlacements)..where((p) => p.id.equals(id))).write(
      BookPlacementsCompanion(
        x: x == null ? const Value.absent() : Value(x),
        y: y == null ? const Value.absent() : Value(y),
        rotation: rotation == null ? const Value.absent() : Value(rotation),
        widthOverride: widthOverride ?? const Value.absent(),
        heightOverride: heightOverride ?? const Value.absent(),
        format: format ?? const Value.absent(),
      ),
    );
  }

  /// Removes a placement and the copy it created.
  Future<void> removePlacement(BookPlacement placement) async {
    await db.transaction(() async {
      await (db.delete(db.bookPlacements)
            ..where((p) => p.id.equals(placement.id)))
          .go();
      await _deleteCopy(placement.copyId);
    });
  }

  Future<void> _deleteCopy(String copyId) async {
    await db.customStatement('DELETE FROM loans WHERE copy_id = ?', [copyId]);
    await (db.delete(db.physicalCopies)..where((c) => c.id.equals(copyId))).go();
  }

  /// Called by the reader as the user turns pages. Reading state is app-local
  /// and never synced, so it must NOT bump [Book.updatedAt] — that column is
  /// the sync conflict clock, and bumping it here would make a mere page-turn
  /// win the next push over a genuine remote edit (see IMPROVEMENT_PLAN_2 §A1).
  Future<void> saveReadingPosition(
    String bookId,
    int page,
    int pageCount,
  ) async {
    await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(
        readingProgress: Value(pageCount == 0 ? 0 : page / pageCount),
        lastReadPage: Value(page),
        lastReadAt: Value(DateTime.now()),
      ),
    );
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
    final description = await metadata.descriptionOf(result);
    String? coverPath;
    final coverBytes = await metadata.downloadCover(result);
    if (coverBytes != null) {
      coverPath = p.join('covers', '$id.jpg');
      await File(p.join(_dataDir.path, coverPath)).writeAsBytes(coverBytes);
    }

    final spine = SpineStyle.generate(
      title: result.title,
      author: result.authors.firstOrNull,
      pageCount: result.pageCount,
    );

    // Snapshot the official metadata so later edits can be reverted to it.
    final source = jsonEncode({
      'title': result.title,
      'subtitle': result.subtitle,
      'description': description,
      'isbn': result.isbn,
      'publisher': result.publisher,
      'publishedYear': result.firstPublishYear,
      'pageCount': result.pageCount,
      'coverUrl': result.largeCoverUrl?.toString(),
    });

    await db.transaction(() async {
      await db
          .into(db.books)
          .insert(
            BooksCompanion.insert(
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
              sourceMetadata: Value(source),
            ),
          );

      var position = 0;
      for (final name in result.authors) {
        final authorId = await _idForName(db.authors, name);
        await db
            .into(db.bookAuthors)
            .insert(
              BookAuthorsCompanion.insert(
                bookId: id,
                authorId: authorId,
                position: Value(position++),
              ),
            );
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

  /// The library's data directory (covers/ and files/ live under it). Exposed
  /// for the sync service and tests; app code uses [coverFileOf] / [fileOf].
  Directory get dataDir => _dataDir;

  // Sync (pull/push) lives in `server/sync_service.dart`, which drives this
  // repository's database and file store.

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
    final authorRows = await db
        .customSelect(
          'SELECT a.name FROM authors a '
          'JOIN book_authors ba ON ba.author_id = a.id '
          'WHERE ba.book_id = ? ORDER BY ba.position',
          variables: [Variable.withString(bookId)],
        )
        .get();
    final genreRows = await db
        .customSelect(
          'SELECT g.name FROM genres g '
          'JOIN book_genres bg ON bg.genre_id = g.id '
          'WHERE bg.book_id = ? ORDER BY g.name',
          variables: [Variable.withString(bookId)],
        )
        .get();
    return (
      authors: [for (final r in authorRows) r.read<String>('name')],
      genres: [for (final r in genreRows) r.read<String>('name')],
    );
  }

  /// Deletes a book and its local data. [recordTombstone] leaves a
  /// [LocalDeletions] row so the next push tells the server to delete it too;
  /// pull-driven deletes (the server already knows) pass false to avoid
  /// re-pushing the deletion forever.
  Future<void> deleteBook(Book book, {bool recordTombstone = true}) async {
    final attachedFiles = await (db.select(
      db.bookFiles,
    )..where((f) => f.bookId.equals(book.id))).get();
    await db.transaction(() async {
      if (recordTombstone) {
        await db
            .into(db.localDeletions)
            .insertOnConflictUpdate(
              LocalDeletionsCompanion.insert(bookId: book.id),
            );
      }
      // Explicit deletes rather than relying on FK cascades, so this works
      // on databases created before cascades were added to the schema.
      for (final table in [
        'book_authors',
        'book_genres',
        'book_files',
        'shelf_books',
      ]) {
        await db.customStatement('DELETE FROM $table WHERE book_id = ?', [
          book.id,
        ]);
      }
      await db.customStatement(
        'DELETE FROM loans WHERE copy_id IN '
        '(SELECT id FROM physical_copies WHERE book_id = ?)',
        [book.id],
      );
      // Placements reference physical_copies (no ON DELETE), and foreign keys
      // are enforced, so drop them before their copies or the delete aborts
      // with an FK violation for any book placed in a physical environment.
      await db.customStatement(
        'DELETE FROM book_placements WHERE copy_id IN '
        '(SELECT id FROM physical_copies WHERE book_id = ?)',
        [book.id],
      );
      await db.customStatement(
        'DELETE FROM physical_copies WHERE book_id = ?',
        [book.id],
      );
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
