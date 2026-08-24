/// Filling in a book that arrived with almost nothing (8/23 requests: ISBN
/// lookup from the wishlist, and "for added books with no pdf or epub, search
/// the image online — right now this wishlisted book has no image").
///
/// A book added by hand — a title jotted down in a shop, a gap in a series —
/// has no cover and no details, and unlike an imported PDF there is no file to
/// take a cover from. So it is asked about online: by its ISBN when it has one
/// (the reliable key), otherwise by title and author.
///
/// **Only the blanks are filled.** What the reader typed is what the reader
/// meant; a lookup that overwrote a corrected title with the catalogue's would
/// be the "fetch metadata undoes my edit" bug in a new coat. The cover is the
/// exception the request is about — a book with no cover has nothing to lose.
library;

import 'package:drift/drift.dart';

import '../add_book/isbn.dart';
import 'database.dart';
import 'metadata.dart';
import 'sync_clock.dart';

/// What a lookup changed, so the caller can say so.
enum EnrichOutcome {
  /// Nothing online matched.
  notFound,

  /// Found, and something on the book changed.
  filled,

  /// Found, but the book already knew everything it said.
  alreadyComplete,
}

class CatalogueEnrich {
  CatalogueEnrich(this.db, this.metadata, this.covers, this.idForName);

  final VellumDatabase db;
  final MetadataService metadata;

  /// Where a downloaded cover goes — `CoverService.setCoverBytes`, passed as a
  /// function so this stays testable without a data directory.
  final Future<void> Function(String bookId, Uint8List bytes) covers;

  /// `BookWriteService.idForName`: the one place author ids are minted. A
  /// second scheme here would mean two devices deriving different ids for the
  /// same author, and a duplicate that syncs.
  final Future<String> Function(TableInfo table, String name) idForName;

  /// Looks [book] up and fills what it is missing.
  ///
  /// [isbn] overrides whatever the book carries — that is the "look this up by
  /// ISBN" case, where the reader has the barcode in front of them and the book
  /// row is the thing that is wrong.
  Future<EnrichOutcome> fill(Book book, {String? isbn}) async {
    final key = toIsbn13(isbn ?? book.isbn ?? '');
    BookSearchResult? found;
    if (key != null) found = await metadata.lookupByIsbn(key);
    found ??= await _byTitle(book);
    if (found == null) return EnrichOutcome.notFound;

    var changed = false;
    final authors = await _authorsOf(book.id);

    // Blanks only — see the note at the top of the file.
    final update = BooksCompanion(
      subtitle: _blank(book.subtitle) && found.subtitle != null
          ? Value(found.subtitle)
          : const Value.absent(),
      isbn: _blank(book.isbn) && (key ?? found.isbn) != null
          ? Value(key ?? found.isbn)
          : const Value.absent(),
      publisher: _blank(book.publisher) && found.publisher != null
          ? Value(found.publisher)
          : const Value.absent(),
      publishedYear: book.publishedYear == null && found.firstPublishYear != null
          ? Value(found.firstPublishYear)
          : const Value.absent(),
      pageCount: book.pageCount == null && found.pageCount != null
          ? Value(found.pageCount)
          : const Value.absent(),
    );
    if (update != const BooksCompanion()) {
      await (db.update(db.books)..where((b) => b.id.equals(book.id)))
          .write(update);
      changed = true;
    }

    if (_blank(book.description)) {
      final description = await metadata.descriptionOf(found);
      if (description != null && description.trim().isNotEmpty) {
        await (db.update(db.books)..where((b) => b.id.equals(book.id)))
            .write(BooksCompanion(description: Value(description.trim())));
        changed = true;
      }
    }

    if (authors.isEmpty && found.authors.isNotEmpty) {
      var position = 0;
      for (final name in found.authors) {
        final authorId = await idForName(db.authors, name);
        await db.into(db.bookAuthors).insert(
              BookAuthorsCompanion.insert(
                bookId: book.id,
                authorId: authorId,
                position: Value(position++),
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
      changed = true;
    }

    // The cover last: it is the slow part, and the part the request is about.
    if (_blank(book.coverPath)) {
      final bytes = await metadata.downloadCover(found);
      if (bytes != null && bytes.isNotEmpty) {
        await covers(book.id, bytes);
        changed = true;
      }
    }

    if (changed) await stampSyncClock(db, SyncedRow.book, book.id);
    return changed ? EnrichOutcome.filled : EnrichOutcome.alreadyComplete;
  }

  /// The fallback when there is no ISBN: the title, and the author if known.
  ///
  /// Only an exact-ish title match is accepted. A search for "Dune" returns
  /// twenty things, and quietly attaching the cover of a Dune *companion book*
  /// to your copy is worse than leaving it blank.
  Future<BookSearchResult?> _byTitle(Book book) async {
    final title = book.title.trim();
    if (title.isEmpty) return null;
    final authors = await _authorsOf(book.id);
    final query = [title, ...authors.take(1)].join(' ');
    final results = await metadata.search(query);
    final wanted = _loose(title);
    for (final result in results) {
      if (_loose(result.title) == wanted) return result;
    }
    return null;
  }

  Future<List<String>> _authorsOf(String bookId) async {
    final rows = await (db.select(db.bookAuthors).join([
      innerJoin(db.authors, db.authors.id.equalsExp(db.bookAuthors.authorId)),
    ])
          ..where(db.bookAuthors.bookId.equals(bookId))
          ..orderBy([OrderingTerm.asc(db.bookAuthors.position)]))
        .get();
    return [for (final row in rows) row.readTable(db.authors).name];
  }

  static bool _blank(String? value) => value == null || value.trim().isEmpty;

  /// Case, punctuation and articles removed: "The Dispossessed" and
  /// "Dispossessed, The" are the same book with different cataloguers.
  static String _loose(String title) => title
      .toLowerCase()
      .replaceAll(RegExp(r'[^a-z0-9 ]'), '')
      .replaceAll(RegExp(r'^(the|a|an) '), '')
      .replaceAll(RegExp(r'\s+'), ' ')
      .trim();
}
