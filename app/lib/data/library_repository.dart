import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../physical/layout_repository.dart';
import '../reader/epub_book.dart';
import '../shelf/cover_color.dart';
import '../shelf/spine_style.dart';
import 'database.dart';
import 'metadata.dart';
import 'pdf_cover.dart';

// Physical-layout CRUD lives in LayoutRepository (reached via `.layout`);
// re-export the pieces callers still import from here so their imports are
// unchanged.
export '../physical/layout_repository.dart' show LayoutRepository, PlacedBook;

/// Author names and genre names for a book, for the detail view.
typedef BookDetails = ({List<String> authors, List<String> genres});

/// A loan joined with the book it's for, for the cross-library Loans overview.
typedef LoanEntry = ({Loan loan, Book book});

/// All library operations the UI needs. Wraps the local database, the
/// filesystem store (covers, later book files), and the metadata client.
class LibraryRepository {
  LibraryRepository._(this.db, this.metadata, this._dataDir)
    : layout = LayoutRepository(db);

  final VellumDatabase db;
  final MetadataService metadata;
  final Directory _dataDir;

  /// Physical-layout (environments / shelves / placements) CRUD. Reached as
  /// `repository.layout` — this class no longer owns those methods.
  final LayoutRepository layout;

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
    final filesDir = Directory(p.join(dir.path, 'files'));
    await filesDir.create(recursive: true);
    // Sweep leftover `*.part` files from downloads a previous run couldn't
    // finish — any that survive are by definition incomplete, so deleting them
    // just frees space and lets the next pull re-download cleanly.
    try {
      await for (final entry in filesDir.list()) {
        if (entry is File && entry.path.endsWith('.part')) {
          try {
            await entry.delete();
          } catch (_) {
            // Best-effort; a locked/racing file is harmless to leave.
          }
        }
      }
    } catch (_) {
      // Listing failed (e.g. dir vanished) — nothing to sweep.
    }
    return LibraryRepository._(db, MetadataService(), dir);
  }

  Stream<List<Book>> watchAllBooks() => db.watchAllBooks();

  // ---- Custom shelves (app-local collections; not synced) -----------------
  // These are manual panes/collections, distinct from genres and from the
  // physical-layout "shelves". They order books explicitly and never delete the
  // books they hold.

  Stream<List<Shelf>> watchShelves() => (db.select(db.shelves)
        ..orderBy([
          (s) => OrderingTerm.asc(s.sortOrder),
          (s) => OrderingTerm.asc(s.name),
        ]))
      .watch();

  Future<String> createShelf(String name) async {
    final id = _uuid.v4();
    final existing = await db.select(db.shelves).get();
    await db.into(db.shelves).insert(ShelvesCompanion.insert(
          id: id,
          name: name.trim(),
          sortOrder: Value(existing.length),
        ));
    return id;
  }

  Future<void> renameShelf(String id, String name) async {
    await (db.update(db.shelves)..where((s) => s.id.equals(id)))
        .write(ShelvesCompanion(name: Value(name.trim())));
  }

  /// Deletes the shelf and its membership rows — never the books themselves.
  Future<void> deleteShelf(String id) async {
    await db.transaction(() async {
      await (db.delete(db.shelfBooks)..where((sb) => sb.shelfId.equals(id))).go();
      await (db.delete(db.shelves)..where((s) => s.id.equals(id))).go();
    });
  }

  /// Appends [bookId] to [shelfId] (no-op if already present).
  Future<void> addToShelf(String bookId, String shelfId) async {
    final existing = await (db.select(db.shelfBooks)
          ..where((sb) => sb.shelfId.equals(shelfId)))
        .get();
    if (existing.any((sb) => sb.bookId == bookId)) return;
    await db.into(db.shelfBooks).insert(ShelfBooksCompanion.insert(
          shelfId: shelfId,
          bookId: bookId,
          position: Value(existing.length),
        ));
  }

  Future<void> removeFromShelf(String bookId, String shelfId) async {
    await (db.delete(db.shelfBooks)
          ..where((sb) => sb.shelfId.equals(shelfId) & sb.bookId.equals(bookId)))
        .go();
  }

  /// The books on [shelfId], in the shelf's explicit order.
  Stream<List<Book>> watchBooksOnShelf(String shelfId) {
    final query = db.select(db.shelfBooks).join([
      innerJoin(db.books, db.books.id.equalsExp(db.shelfBooks.bookId)),
    ])
      ..where(db.shelfBooks.shelfId.equals(shelfId))
      ..orderBy([OrderingTerm.asc(db.shelfBooks.position)]);
    return query.watch().map(
          (rows) => [for (final r in rows) r.readTable(db.books)],
        );
  }

  /// The set of shelf ids [bookId] currently belongs to (for the detail-page
  /// "Add to shelf" checkmarks).
  Stream<Set<String>> watchShelfIdsFor(String bookId) =>
      (db.select(db.shelfBooks)..where((sb) => sb.bookId.equals(bookId)))
          .watch()
          .map((rows) => {for (final sb in rows) sb.shelfId});

  /// `bookId -> author names` (cover order) for the whole library, as a stream,
  /// so the shelf can search by author without an N+1 of per-book queries.
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
    // A new file is synced data, so the book needs pushing (setCoverFromEmbedded
    // below also marks it, but a cover-having book wouldn't).
    await _markNeedsPush(bookId);
    // A cover-less book that just got a PDF or EPUB: derive a cover from it (the
    // PDF's first page, or the EPUB's declared cover image).
    if (ext == 'pdf' || ext == 'epub') {
      final book = await (db.select(
        db.books,
      )..where((b) => b.id.equals(bookId))).getSingleOrNull();
      if (book != null && book.coverPath == null) {
        await setCoverFromEmbedded(bookId);
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
        needsPush: const Value(true),
      ),
    );
  }

  /// Marks a book's synced data as changed since the last push, so the next
  /// sync uploads it. Used by mutations that don't already write the books row
  /// (author/genre joins, file attaches). Local-only setters never call this.
  Future<void> _markNeedsPush(String bookId) async {
    await (db.update(
      db.books,
    )..where((b) => b.id.equals(bookId))).write(
      const BooksCompanion(needsPush: Value(true)),
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
      await _gcOrphanAuthors();
    });
    await _markNeedsPush(bookId);
  }

  /// Replaces a book's genres with [names]. Blank names are ignored. Mirror of
  /// [setAuthors]; genres carry no explicit order (the server sorts by name).
  Future<void> setGenres(String bookId, List<String> names) async {
    await db.transaction(() async {
      await db.customStatement(
        'DELETE FROM book_genres WHERE book_id = ?',
        [bookId],
      );
      for (final raw in names) {
        final name = raw.trim();
        if (name.isEmpty) continue;
        final genreId = await _idForName(db.genres, name);
        await db
            .into(db.bookGenres)
            .insert(BookGenresCompanion.insert(bookId: bookId, genreId: genreId));
      }
      await _gcOrphanGenres();
    });
    await _markNeedsPush(bookId);
  }

  /// Removes author/genre name rows no book references any more, so the
  /// unique-name tables don't grow monotonically as books are re-tagged or
  /// deleted. Sub-millisecond at this scale (the subselect hits the join PK).
  Future<void> _gcOrphanAuthors() => db.customStatement(
    'DELETE FROM authors WHERE id NOT IN (SELECT author_id FROM book_authors)',
  );

  Future<void> _gcOrphanGenres() => db.customStatement(
    'DELETE FROM genres WHERE id NOT IN (SELECT genre_id FROM book_genres)',
  );

  /// Personal notes — stored locally only, never pushed to a server.
  Future<void> setReaderNotes(String bookId, String? notes) async {
    await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(readerNotes: Value(_blankToNull(notes))),
    );
  }

  /// Replaces a book's cover from raw image bytes. Also extracts the cover's
  /// dominant colour into the spine style, for the "Dominant colour" spine
  /// preference.
  Future<void> setCoverBytes(String bookId, Uint8List bytes) async {
    final rel = p.join('covers', '$bookId.jpg');
    await File(p.join(_dataDir.path, rel)).writeAsBytes(bytes);
    await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(
        coverPath: Value(rel),
        updatedAt: Value(DateTime.now()),
        needsPush: const Value(true),
      ),
    );
    await updateCoverColor(bookId, bytes);
  }

  /// Stores the dominant colour of [coverBytes] in the book's spine style.
  /// Purely cosmetic and device-derivable, so it deliberately does NOT bump
  /// the sync clock or the dirty flag. A no-op when the bytes don't decode.
  Future<void> updateCoverColor(String bookId, Uint8List coverBytes) async {
    final color = await dominantColorOf(coverBytes);
    if (color == null) return;
    final row = await (db.select(
      db.books,
    )..where((b) => b.id.equals(bookId))).getSingleOrNull();
    if (row == null) return;
    final style = SpineStyle.fromJson(row.spineStyle, title: row.title)
        .withCoverColor(color);
    await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(spineStyle: Value(style.toJson())),
    );
  }

  /// One-time catch-up for covers that predate dominant-colour extraction:
  /// computes and stores the colour for every covered book whose spine style
  /// lacks one. Cheap when there's nothing to do; run fire-and-forget at
  /// startup.
  Future<void> backfillCoverColors() async {
    final rows = await (db.select(
      db.books,
    )..where((b) => b.coverPath.isNotNull())).get();
    for (final row in rows) {
      final style = SpineStyle.fromJson(row.spineStyle, title: row.title);
      if (style.coverColor != null) continue;
      final cover = coverFileOf(row);
      if (cover == null || !await cover.exists()) continue;
      try {
        await updateCoverColor(row.id, await cover.readAsBytes());
      } catch (_) {
        // A single unreadable cover shouldn't stop the sweep.
      }
    }
  }

  Future<void> setCoverFromFile(String bookId, String sourcePath) async =>
      setCoverBytes(bookId, await File(sourcePath).readAsBytes());

  /// Derives a cover from the book's own attached files, no network needed: a
  /// PDF's rendered first page, else an EPUB's declared cover image. Returns
  /// false when neither is available or extraction fails.
  Future<bool> setCoverFromEmbedded(String bookId) async {
    if (await setCoverFromFirstPage(bookId)) return true;
    return setCoverFromEpub(bookId);
  }

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

  /// Extracts the declared cover image from one of the book's attached EPUBs
  /// (a plain zip read, no renderer) and uses it. Returns false if the book has
  /// no EPUB, the EPUB declares no cover, or extraction fails.
  Future<bool> setCoverFromEpub(String bookId) async {
    final files = await (db.select(
      db.bookFiles,
    )..where((f) => f.bookId.equals(bookId) & f.format.equals('epub'))).get();
    if (files.isEmpty) return false;
    try {
      final bytes = await EpubBook.coverBytes(
        File(p.join(_dataDir.path, files.first.path)),
      );
      if (bytes == null) return false;
      await setCoverBytes(bookId, bytes);
      return true;
    } catch (_) {
      return false;
    }
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
        needsPush: const Value(true),
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

  /// Every loan across the library joined with the book it's for, most recent
  /// first — for the cross-library Loans overview. The UI splits active
  /// (`returnedAt == null`) from returned history.
  Stream<List<LoanEntry>> watchAllLoans() {
    final query = db.select(db.loans).join([
      innerJoin(
        db.physicalCopies,
        db.physicalCopies.id.equalsExp(db.loans.copyId),
      ),
      innerJoin(db.books, db.books.id.equalsExp(db.physicalCopies.bookId)),
    ])
      ..orderBy([OrderingTerm.desc(db.loans.loanedAt)]);
    return query.watch().map(
          (rows) => [
            for (final r in rows)
              (loan: r.readTable(db.loans), book: r.readTable(db.books)),
          ],
        );
  }

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
      // A deleted book may have held the last reference to an author or genre.
      await _gcOrphanAuthors();
      await _gcOrphanGenres();
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
