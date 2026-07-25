import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../physical/layout_repository.dart';
import 'book_write_service.dart';
import 'cover_service.dart';
import 'database.dart';
import 'file_service.dart';
import 'library_queries.dart';
import 'metadata.dart';
import 'physical_service.dart';
import 'shelf_service.dart';

// Physical-layout CRUD lives in LayoutRepository (reached via `.layout`);
// re-export the pieces callers still import from here so their imports are
// unchanged. Likewise the typedefs and Uint8List moved with their owning
// services.
export '../physical/layout_repository.dart' show LayoutRepository, PlacedBook;
export 'book_write_service.dart' show BookDetails;
export 'physical_service.dart' show LoanEntry;

/// All library operations the UI needs. A thin facade over the local
/// database and filesystem store: each concern (queries, book lifecycle,
/// covers, files, shelves, physical copies/loans, physical layouts) lives in
/// its own collaborator (plan 5 §A10); this class wires them together and
/// forwards their methods so no call site has to change.
class LibraryRepository {
  LibraryRepository._({
    required this.db,
    required this.metadata,
    required this._dataDir,
    required this.layout,
    required this.queries,
    required this.covers,
    required this.shelves,
    required this.physical,
    required this.files,
    required this.writes,
  });

  final VellumDatabase db;
  final MetadataService metadata;
  final Directory _dataDir;

  /// Physical-layout (environments / shelves / placements) CRUD. Reached as
  /// `repository.layout`.
  final LayoutRepository layout;

  /// The library's read/watch side. Reached as `repository.queries`.
  final LibraryQueries queries;

  /// Cover bytes/files and the dominant-colour backfill. Reached as
  /// `repository.covers`.
  final CoverService covers;

  /// Custom shelves (app-local collections). Reached as `repository.shelves`.
  final ShelfService shelves;

  /// Physical copies and loan history. Reached as `repository.physical`.
  final PhysicalService physical;

  /// Attached digital files. Reached as `repository.files`.
  final FileService files;

  /// Book lifecycle: create/update/delete, authors, genres, reading position,
  /// revert-to-default, online-search import. Reached as `repository.writes`.
  final BookWriteService writes;

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
    final metadata = MetadataService();
    final covers = CoverService(db, dir);
    return LibraryRepository._(
      db: db,
      metadata: metadata,
      dataDir: dir,
      layout: LayoutRepository(db),
      queries: LibraryQueries(db),
      covers: covers,
      shelves: ShelfService(db),
      physical: PhysicalService(db),
      files: FileService(db, dir, covers),
      writes: BookWriteService(db, dir, metadata, covers),
    );
  }

  // ---- Queries --------------------------------------------------------
  Stream<List<Book>> watchAllBooks() => queries.watchAllBooks();
  Stream<int> watchDirtyCount() => queries.watchDirtyCount();
  Stream<Map<String, List<String>>> watchAuthorsByBook() =>
      queries.watchAuthorsByBook();
  Stream<Map<String, List<String>>> watchGenresByBook() =>
      queries.watchGenresByBook();

  // ---- Shelves ----------------------------------------------------------
  Stream<List<Shelf>> watchShelves() => shelves.watchShelves();
  Future<String> createShelf(String name) => shelves.createShelf(name);
  Future<void> renameShelf(String id, String name) =>
      shelves.renameShelf(id, name);
  Future<void> deleteShelf(String id) => shelves.deleteShelf(id);
  Future<void> addToShelf(String bookId, String shelfId) =>
      shelves.addToShelf(bookId, shelfId);
  Future<void> removeFromShelf(String bookId, String shelfId) =>
      shelves.removeFromShelf(bookId, shelfId);
  Stream<List<Book>> watchBooksOnShelf(String shelfId) =>
      shelves.watchBooksOnShelf(shelfId);
  Stream<Set<String>> watchShelfIdsFor(String bookId) =>
      shelves.watchShelfIdsFor(bookId);

  // ---- Book lifecycle -----------------------------------------------------
  Stream<Book?> watchBook(String id) => writes.watchBook(id);
  Future<String> createCustomBook({
    required String title,
    String? author,
    int? publishedYear,
    String? description,
  }) => writes.createCustomBook(
    title: title,
    author: author,
    publishedYear: publishedYear,
    description: description,
  );
  Future<void> updateBookDetails(
    String id, {
    required String title,
    String? subtitle,
    int? publishedYear,
    int? pageCount,
    String? description,
  }) => writes.updateBookDetails(
    id,
    title: title,
    subtitle: subtitle,
    publishedYear: publishedYear,
    pageCount: pageCount,
    description: description,
  );
  Future<void> setAuthors(String bookId, List<String> names) =>
      writes.setAuthors(bookId, names);
  Future<void> setGenres(String bookId, List<String> names) =>
      writes.setGenres(bookId, names);
  Future<void> addGenre(String bookId, String name) =>
      writes.addGenre(bookId, name);
  Future<void> removeGenre(String bookId, String name) =>
      writes.removeGenre(bookId, name);
  Stream<List<String>> watchGenresOf(String bookId) =>
      writes.watchGenresOf(bookId);
  Stream<List<String>> watchAllGenreNames() => writes.watchAllGenreNames();
  Future<void> setReaderNotes(String bookId, String? notes) =>
      writes.setReaderNotes(bookId, notes);
  bool canRevert(Book book) => writes.canRevert(book);
  Future<void> revertToDefault(Book book) => writes.revertToDefault(book);
  Future<void> saveReadingPosition(String bookId, int page, int pageCount) =>
      writes.saveReadingPosition(bookId, page, pageCount);
  Future<void> saveEpubPosition(
    String bookId, {
    required int chapterIndex,
    required int chapterCount,
    required double scrollFraction,
  }) => writes.saveEpubPosition(
    bookId,
    chapterIndex: chapterIndex,
    chapterCount: chapterCount,
    scrollFraction: scrollFraction,
  );
  Future<String> addFromSearch(
    BookSearchResult result, {
    bool importGenres = false,
  }) => writes.addFromSearch(result, importGenres: importGenres);
  Future<BookDetails> detailsFor(String bookId) => writes.detailsFor(bookId);
  Future<void> deleteBook(Book book, {bool recordTombstone = true}) =>
      writes.deleteBook(book, recordTombstone: recordTombstone);

  // ---- Covers ---------------------------------------------------------
  File? coverFileOf(Book book) => covers.coverFileOf(book);
  Future<void> setCoverBytes(String bookId, Uint8List bytes) =>
      covers.setCoverBytes(bookId, bytes);
  Future<void> updateCoverColor(String bookId, Uint8List coverBytes) =>
      covers.updateCoverColor(bookId, coverBytes);
  Future<void> backfillCoverColors() => covers.backfillCoverColors();
  Future<void> setCoverFromFile(String bookId, String sourcePath) =>
      covers.setCoverFromFile(bookId, sourcePath);
  Future<bool> setCoverFromEmbedded(String bookId) =>
      covers.setCoverFromEmbedded(bookId);
  Future<bool> setCoverFromFirstPage(String bookId) =>
      covers.setCoverFromFirstPage(bookId);
  Future<bool> setCoverFromEpub(String bookId) =>
      covers.setCoverFromEpub(bookId);

  // ---- Files ------------------------------------------------------------
  Stream<List<BookFile>> watchFilesOf(String bookId) =>
      files.watchFilesOf(bookId);
  File fileOf(BookFile file) => files.fileOf(file);
  Future<void> attachFile(String bookId, String sourcePath) =>
      files.attachFile(bookId, sourcePath);
  Future<int?> pageCountFromFile(String bookId) =>
      files.pageCountFromFile(bookId);

  // ---- Physical copies & loans --------------------------------------------
  Stream<List<PhysicalCopy>> watchCopiesOf(String bookId) =>
      physical.watchCopiesOf(bookId);
  Future<String> addPhysicalCopy(
    String bookId, {
    String? location,
    String? notes,
  }) => physical.addPhysicalCopy(bookId, location: location, notes: notes);
  Stream<List<Loan>> watchLoansOf(String copyId) =>
      physical.watchLoansOf(copyId);
  Stream<List<LoanEntry>> watchAllLoans() => physical.watchAllLoans();
  Future<void> lendCopy(String copyId, String borrower) =>
      physical.lendCopy(copyId, borrower);
  Future<void> returnLoan(String loanId) => physical.returnLoan(loanId);

  /// The library's data directory (covers/ and files/ live under it). Exposed
  /// for the sync service and tests.
  Directory get dataDir => _dataDir;

  // Sync (pull/push) lives in `server/sync_service.dart`, which drives this
  // repository's database and file store.
}
