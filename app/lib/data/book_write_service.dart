import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:http/http.dart' as http;
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../reader/epub_book.dart';
import '../shelf/spine_style.dart';
import 'cover_service.dart';
import 'database.dart';
import 'metadata.dart';

/// Author names and genre names for a book, for the detail view.
typedef BookDetails = ({List<String> authors, List<String> genres});

/// A book's core lifecycle — create/update/delete, authors, genres, reader
/// notes, reading position, and revert-to-default — plus the online-search
/// import path. Split out of `LibraryRepository` (plan 5 §A10). Depends on
/// [CoverService] for revert's cover re-fetch and for cleaning up a deleted
/// book's cover file.
class BookWriteService {
  BookWriteService(this.db, this._dataDir, this.metadata, this._covers);

  final VellumDatabase db;
  final Directory _dataDir;
  final MetadataService metadata;
  final CoverService _covers;

  static const _uuid = Uuid();

  Stream<Book?> watchBook(String id) =>
      (db.select(db.books)..where((b) => b.id.equals(id))).watchSingleOrNull();

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
  /// (author/genre joins). Local-only setters never call this.
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
        final name = canonicalGenreName(raw);
        if (name.isEmpty) continue;
        final genreId = await _idForName(db.genres, name);
        // insertOrIgnore: two input names may canonicalize to the same genre
        // (e.g. "Sci-Fi" and "sci-fi"), which would otherwise clash on the
        // (bookId, genreId) primary key.
        await db.into(db.bookGenres).insert(
              BookGenresCompanion.insert(bookId: bookId, genreId: genreId),
              mode: InsertMode.insertOrIgnore,
            );
      }
      await _gcOrphanGenres();
    });
    await _markNeedsPush(bookId);
  }

  /// Adds one genre to a book (get-or-create the genre by canonical name).
  /// No-op if the name is blank or the book already has it.
  Future<void> addGenre(String bookId, String name) async {
    final canon = canonicalGenreName(name);
    if (canon.isEmpty) return;
    await db.transaction(() async {
      final genreId = await _idForName(db.genres, canon);
      await db.into(db.bookGenres).insert(
            BookGenresCompanion.insert(bookId: bookId, genreId: genreId),
            mode: InsertMode.insertOrIgnore,
          );
    });
    await _markNeedsPush(bookId);
  }

  /// Removes one genre from a book, then sweeps the genre if no book uses it.
  Future<void> removeGenre(String bookId, String name) async {
    final canon = canonicalGenreName(name);
    if (canon.isEmpty) return;
    await db.transaction(() async {
      final genre = await (db.select(db.genres)
            ..where((g) => g.name.equals(canon)))
          .getSingleOrNull();
      if (genre == null) return;
      // Typed delete (not raw SQL) so drift invalidates the book_genres query
      // streams — watchGenresOf/watchAllGenreNames update immediately.
      await (db.delete(db.bookGenres)
            ..where((bg) =>
                bg.bookId.equals(bookId) & bg.genreId.equals(genre.id)))
          .go();
      await _gcOrphanGenres();
    });
    await _markNeedsPush(bookId);
  }

  /// The genre names on one book, ordered by name — reactive so the detail
  /// page's editable chips update the moment a genre is added or removed.
  Stream<List<String>> watchGenresOf(String bookId) {
    final q = db.select(db.genres).join([
      innerJoin(db.bookGenres, db.bookGenres.genreId.equalsExp(db.genres.id)),
    ])
      ..where(db.bookGenres.bookId.equals(bookId))
      ..orderBy([OrderingTerm(expression: db.genres.name)]);
    return q
        .watch()
        .map((rows) => [for (final r in rows) r.readTable(db.genres).name]);
  }

  /// Every genre name currently used by some book, ordered — powers the
  /// add-genre suggestions so you reuse existing tags instead of minting
  /// near-duplicates. Joined through book_genres (rather than reading the
  /// genres table directly) so drift refreshes it on any tag add/remove.
  Stream<List<String>> watchAllGenreNames() {
    final q = db.selectOnly(db.genres, distinct: true)
      ..addColumns([db.genres.name])
      ..join([
        innerJoin(db.bookGenres, db.bookGenres.genreId.equalsExp(db.genres.id)),
      ])
      ..orderBy([OrderingTerm(expression: db.genres.name)]);
    return q.watch().map((rows) => [for (final r in rows) r.read(db.genres.name)!]);
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
          await _covers.setCoverBytes(book.id, res.bodyBytes);
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
        // Queue the new position for the optional cross-device channel (plan 5
        // #5). App-local like the columns above until the user opts in — the
        // flag only decides *what* would be published, never that it is.
        needsProgressPush: const Value(true),
      ),
    );
  }

  /// EPUB reading position: [lastReadPage] stays the 1-based chapter (so the
  /// PDF-shaped "resume" logic still works), but [readingProgress] carries the
  /// *global* fraction including in-chapter scroll, so resume can land mid-page.
  /// App-local like [saveReadingPosition] — never bumps `updatedAt`.
  Future<void> saveEpubPosition(
    String bookId, {
    required int chapterIndex,
    required int chapterCount,
    required double scrollFraction,
  }) async {
    final progress = chapterCount == 0
        ? 0.0
        : ((chapterIndex + scrollFraction.clamp(0, 1)) / chapterCount)
            .clamp(0, 1)
            .toDouble();
    await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(
        readingProgress: Value(progress),
        lastReadPage: Value(chapterIndex + 1),
        lastReadAt: Value(DateTime.now()),
        // Queue the new position for the optional cross-device channel (plan 5
        // #5). App-local like the columns above until the user opts in — the
        // flag only decides *what* would be published, never that it is.
        needsProgressPush: const Value(true),
      ),
    );
  }

  /// Adds a book picked from online search results: fetches the description
  /// and cover over the network, generates a spine, and stores everything.
  /// [importGenres] controls whether Open Library's noisy "subjects" are
  /// pulled in as genres (off by default; the caller passes the user's
  /// preference); genres are otherwise manual.
  Future<String> addFromSearch(
    BookSearchResult result, {
    bool importGenres = false,
  }) async {
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

      if (importGenres) {
        // Open Library "subjects" are noisy; keep the first few short ones, and
        // canonicalize so case/spacing variants across books share one genre.
        final genres = result.subjects
            .where((s) => s.length <= 28 && !s.contains(':'))
            .map(canonicalGenreName)
            .where((s) => s.isNotEmpty)
            .take(3);
        for (final name in genres) {
          final genreId = await _idForName(db.genres, name);
          await db.into(db.bookGenres).insert(
                BookGenresCompanion.insert(bookId: id, genreId: genreId),
                mode: InsertMode.insertOrIgnore,
              );
        }
      }
    });
    return id;
  }

  /// Fills a book's blank fields from an online [result], leaving everything
  /// already set alone (plan 5 #15's enrichment pass).
  ///
  /// "Only blanks" is the whole contract: this runs unattended over books
  /// imported from file names, possibly long after the user has edited some of
  /// them by hand, and an enrichment that overwrote a corrected title would be
  /// worse than no enrichment. Authors are added only when the book has none,
  /// and the cover only when it has none — matching the server's
  /// `discover::enrich`.
  ///
  /// Records [BookSearchResult] as `sourceMetadata` when the book had none, so
  /// an enriched book gains "revert to library defaults" like a searched one.
  Future<void> enrichFromSearch(String bookId, BookSearchResult result) async {
    final book = await (db.select(
      db.books,
    )..where((b) => b.id.equals(bookId))).getSingleOrNull();
    if (book == null) return;

    // Network work first, outside the transaction.
    final description = book.description == null || book.description!.isEmpty
        ? await metadata.descriptionOf(result)
        : null;
    Uint8List? coverBytes;
    if (book.coverPath == null) {
      coverBytes = await metadata.downloadCover(result);
    }

    final hadAuthors = (await detailsFor(bookId)).authors.isNotEmpty;
    await db.transaction(() async {
      await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
        BooksCompanion(
          subtitle: book.subtitle == null
              ? Value(result.subtitle)
              : const Value.absent(),
          description:
              description == null ? const Value.absent() : Value(description),
          isbn: book.isbn == null ? Value(result.isbn) : const Value.absent(),
          publisher: book.publisher == null
              ? Value(result.publisher)
              : const Value.absent(),
          publishedYear: book.publishedYear == null
              ? Value(result.firstPublishYear)
              : const Value.absent(),
          pageCount: book.pageCount == null
              ? Value(result.pageCount)
              : const Value.absent(),
          sourceMetadata: book.sourceMetadata == null
              ? Value(jsonEncode({
                  'title': result.title,
                  'subtitle': result.subtitle,
                  'description': description ?? book.description,
                  'isbn': result.isbn,
                  'publisher': result.publisher,
                  'publishedYear': result.firstPublishYear,
                  'pageCount': result.pageCount,
                  'coverUrl': result.largeCoverUrl?.toString(),
                }))
              : const Value.absent(),
          updatedAt: Value(DateTime.now()),
          needsPush: const Value(true),
        ),
      );
      if (!hadAuthors) {
        var position = 0;
        for (final name in result.authors) {
          final authorId = await _idForName(db.authors, name);
          await db.into(db.bookAuthors).insert(
                BookAuthorsCompanion.insert(
                  bookId: bookId,
                  authorId: authorId,
                  position: Value(position++),
                ),
                mode: InsertMode.insertOrIgnore,
              );
        }
      }
    });
    // Outside the transaction: this writes a file and recomputes the spine's
    // dominant colour.
    if (coverBytes != null) await _covers.setCoverBytes(bookId, coverBytes);
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

  /// Deletes a book and its local data. [recordTombstone] leaves a
  /// [LocalDeletions] row so the next push tells the server to delete it too;
  /// pull-driven deletes (the server already knows) pass false to avoid
  /// re-pushing the deletion forever.
  Future<void> deleteBook(Book book, {bool recordTombstone = true}) async {
    EpubBook.invalidateCache(book.id);
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
        // Marginalia go with the book they annotate (plan 5 #22); they are
        // app-local, so there is no tombstone to record for them. Reading
        // sessions (plan 5 #19) are the same: local, and about this book.
        'annotations',
        'reading_sessions',
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
    final cover = _covers.coverFileOf(book);
    if (cover != null && await cover.exists()) await cover.delete();
    for (final f in attachedFiles) {
      final file = File(p.join(_dataDir.path, f.path));
      if (await file.exists()) await file.delete();
    }
  }
}
