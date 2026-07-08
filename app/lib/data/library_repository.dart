import 'dart:convert';
import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:uuid/uuid.dart';

import '../server/server_client.dart';
import '../shelf/spine_style.dart';
import 'database.dart';
import 'metadata.dart';
import 'pdf_cover.dart';

/// Author names and genre names for a book, for the detail view.
typedef BookDetails = ({List<String> authors, List<String> genres});

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
  /// description clear the field; a null [publishedYear] clears the year.
  Future<void> updateBookDetails(
    String id, {
    required String title,
    String? subtitle,
    int? publishedYear,
    String? description,
  }) async {
    await (db.update(db.books)..where((b) => b.id.equals(id))).write(
      BooksCompanion(
        title: Value(title.trim()),
        subtitle: Value(_blankToNull(subtitle)),
        publishedYear: Value(publishedYear),
        description: Value(_blankToNull(description)),
        updatedAt: Value(DateTime.now()),
      ),
    );
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

  /// Called by the reader as the user turns pages.
  Future<void> saveReadingPosition(
    String bookId,
    int page,
    int pageCount,
  ) async {
    final now = DateTime.now();
    await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(
        readingProgress: Value(pageCount == 0 ? 0 : page / pageCount),
        lastReadPage: Value(page),
        lastReadAt: Value(now),
        updatedAt: Value(now),
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

  /// Pulls the server library onto this device (a one-way sync for now):
  /// upserts book metadata, then downloads any covers we don't already hold.
  /// Locally-attached files are left untouched. Returns the number of books
  /// written.
  Future<int> pullFromServer(VellumServerClient client) async {
    final books = await client.listBooks();

    await db.transaction(() async {
      for (final b in books) {
        final spine =
            b.spineStyle ??
            SpineStyle.generate(
              title: b.title,
              pageCount: b.pageCount,
            ).toJson();
        await db
            .into(db.books)
            .insertOnConflictUpdate(
              BooksCompanion.insert(
                id: b.id,
                title: b.title,
                subtitle: Value(b.subtitle),
                description: Value(b.description),
                isbn: Value(b.isbn),
                publisher: Value(b.publisher),
                publishedYear: Value(b.publishedYear),
                pageCount: Value(b.pageCount),
                spineStyle: Value(spine),
              ),
            );
      }
    });

    // Fetch cover art outside the transaction; a failed cover never fails the
    // whole pull.
    for (final b in books.where((b) => b.hasCover)) {
      final local = File(p.join(_dataDir.path, 'covers', '${b.id}.jpg'));
      if (await local.exists()) continue;
      try {
        final bytes = await client.downloadCover(b.id);
        if (bytes == null) continue;
        await local.writeAsBytes(bytes);
        await (db.update(db.books)..where((x) => x.id.equals(b.id))).write(
          BooksCompanion(coverPath: Value(p.join('covers', '${b.id}.jpg'))),
        );
      } catch (_) {
        // Leave this book cover-less; it still shows a generated spine.
      }
    }

    // Download digital files the device doesn't already have. Dedup by content
    // hash, so a file pushed under a different id isn't downloaded twice.
    for (final b in books) {
      try {
        for (final f in await client.listFiles(b.id)) {
          final have =
              await (db.select(db.bookFiles)..where(
                    (x) => x.bookId.equals(b.id) & x.sha256.equals(f.sha256),
                  ))
                  .getSingleOrNull();
          if (have != null) continue;
          final bytes = await client.downloadFile(f.id);
          final rel = p.join('files', '${f.id}.${f.format}');
          await File(p.join(_dataDir.path, rel)).writeAsBytes(bytes);
          await db
              .into(db.bookFiles)
              .insertOnConflictUpdate(
                BookFilesCompanion.insert(
                  id: f.id,
                  bookId: b.id,
                  format: f.format,
                  path: rel,
                  sizeBytes: f.sizeBytes,
                  sha256: f.sha256,
                ),
              );
        }
      } catch (_) {
        // Metadata and cover are already pulled; skip files on error.
      }
    }

    // Give any cover-less PDF book a first-page cover (e.g. books uploaded on
    // the server, which can't render covers there).
    for (final b in books) {
      final row = await (db.select(
        db.books,
      )..where((x) => x.id.equals(b.id))).getSingleOrNull();
      if (row != null && row.coverPath == null) {
        try {
          await setCoverFromFirstPage(b.id);
        } catch (_) {}
      }
    }
    return books.length;
  }

  /// Pushes local books (and their covers) up to the server, upserting by id so
  /// pull and push stay consistent. Books the caller can't write on the server
  /// (e.g. shared read-only) are skipped. Returns the number pushed.
  Future<int> pushToServer(VellumServerClient client) async {
    final books = await db.select(db.books).get();
    var pushed = 0;
    for (final b in books) {
      try {
        await client.pushBook(
          id: b.id,
          title: b.title,
          subtitle: b.subtitle,
          description: b.description,
          isbn: b.isbn,
          publisher: b.publisher,
          publishedYear: b.publishedYear,
          pageCount: b.pageCount,
          spineStyle: b.spineStyle,
        );
        final cover = coverFileOf(b);
        if (cover != null && await cover.exists()) {
          await client.uploadCover(
            b.id,
            await cover.readAsBytes(),
            contentType: p.extension(cover.path).toLowerCase() == '.png'
                ? 'image/png'
                : 'image/jpeg',
          );
        }

        // Upload local files the server doesn't already have (dedup by hash).
        final localFiles = await (db.select(
          db.bookFiles,
        )..where((f) => f.bookId.equals(b.id))).get();
        if (localFiles.isNotEmpty) {
          final remoteHashes = (await client.listFiles(
            b.id,
          )).map((f) => f.sha256).toSet();
          for (final lf in localFiles) {
            if (remoteHashes.contains(lf.sha256)) continue;
            final file = fileOf(lf);
            if (await file.exists()) {
              await client.uploadFile(
                b.id,
                await file.readAsBytes(),
                format: lf.format,
              );
            }
          }
        }
        pushed++;
      } on ServerException {
        // Read-only or rejected — leave it and keep going.
      }
    }
    return pushed;
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

  Future<void> deleteBook(Book book) async {
    final attachedFiles = await (db.select(
      db.bookFiles,
    )..where((f) => f.bookId.equals(book.id))).get();
    await db.transaction(() async {
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
