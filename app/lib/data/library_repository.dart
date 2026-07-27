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
import 'copy_photo_service.dart';
import 'physical_service.dart';
import '../reader/annotations/annotation_store.dart';
import 'reading_position_service.dart';
import 'reading_status.dart';
import 'series_service.dart';
import 'shelf_service.dart';
import 'trash_service.dart';

// Physical-layout CRUD lives in LayoutRepository (reached via `.layout`);
// re-export the pieces callers still import from here so their imports are
// unchanged. Likewise the typedefs and Uint8List moved with their owning
// services.
export '../physical/layout_repository.dart'
    show CopyLocation, LayoutRepository, PlacedBook;
export 'book_write_service.dart' show BookDetails;
export 'copy_photo_service.dart' show CopyPhotoService;
export 'physical_service.dart' show LoanEntry;
export '../reader/annotations/annotation_store.dart'
    show AnnotationKind, AnnotationStore;
export '../stats/session_recorder.dart' show SessionRecorder;
export 'reading_position_service.dart'
    show ReadingJumpOffer, ReadingPositionService, readingUnitForFormats;
export 'reading_status.dart' show ReadingStatus, ReadingStatusService;
export 'series_service.dart' show SeriesPlace, SeriesService;
export 'trash_service.dart' show TrashService;

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
    required this.copyPhotos,
    required this.files,
    required this.writes,
    required this.readingPositions,
    required this.annotations,
    required this.readingStatus,
    required this.seriesService,
    required this.trash,
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

  /// Condition photos for physical copies (plan 5 #51). Reached as
  /// `repository.copyPhotos`.
  final CopyPhotoService copyPhotos;

  /// Attached digital files. Reached as `repository.files`.
  final FileService files;

  /// Book lifecycle: create/update/delete, authors, genres, reading position,
  /// revert-to-default, online-search import. Reached as `repository.writes`.
  final BookWriteService writes;

  /// The optional cross-device reading position (plan 5 #5): other devices'
  /// cached positions, the publish-dirty flag, and the jump offer. Reached as
  /// `repository.readingPositions`.
  final ReadingPositionService readingPositions;

  /// Bookmarks, highlights and notes (plan 5 #22). Reached as
  /// `repository.annotations`.
  final AnnotationStore annotations;

  /// Reading status, ratings and finish dates (plan 5 #18). Reached as
  /// `repository.readingStatus`.
  final ReadingStatusService readingStatus;

  /// Series membership and gap detection (plan 5 #17). Reached as
  /// `repository.seriesService`.
  final SeriesService seriesService;

  /// The trash and its 30-day grace period (plan 5 #52). Reached as
  /// `repository.trash`.
  final TrashService trash;

  static Future<LibraryRepository> open(VellumDatabase db) async {
    final dir = await getApplicationSupportDirectory();
    return _withDataDir(db, dir);
  }

  /// Builds a repository over an explicit data directory instead of the
  /// platform app-support dir — for tests that can't reach `path_provider`.
  ///
  /// [metadata] replaces the live online-lookup service, so a test can drive the
  /// search/ISBN paths against a `MockClient` instead of the network.
  @visibleForTesting
  static Future<LibraryRepository> forTesting(
    VellumDatabase db,
    Directory dataDir, {
    MetadataService? metadata,
  }) => _withDataDir(db, dataDir, metadata: metadata);

  static Future<LibraryRepository> _withDataDir(
    VellumDatabase db,
    Directory dir, {
    MetadataService? metadata,
  }) async {
    final coversDir = Directory(p.join(dir.path, 'covers'));
    await coversDir.create(recursive: true);
    final filesDir = Directory(p.join(dir.path, 'files'));
    await filesDir.create(recursive: true);
    // Sweep leftover `*.part` files from a transfer or import a previous run
    // couldn't finish — any that survive are by definition incomplete, so
    // deleting them just frees space and lets the next pull/import redo the
    // work cleanly. Both directories: downloads and local imports (plan 5 #14)
    // use the same temp-then-rename shape.
    for (final target in [filesDir, coversDir]) {
      try {
        await for (final entry in target.list()) {
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
    }
    final metadataService = metadata ?? MetadataService();
    final covers = CoverService(db, dir);
    final copyPhotos = CopyPhotoService(db, dir);
    final physical = PhysicalService(db, copyPhotos);
    final writes = BookWriteService(db, dir, metadataService, covers);
    return LibraryRepository._(
      db: db,
      metadata: metadataService,
      dataDir: dir,
      layout: LayoutRepository(db, physical),
      queries: LibraryQueries(db),
      covers: covers,
      shelves: ShelfService(db),
      physical: physical,
      copyPhotos: copyPhotos,
      files: FileService(db, dir, covers),
      writes: writes,
      readingPositions: ReadingPositionService(db),
      annotations: AnnotationStore(db),
      readingStatus: ReadingStatusService(db),
      seriesService: SeriesService(db),
      trash: TrashService(db, writes),
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
  Future<void> deleteShelf(String id, {bool recordTombstone = true}) =>
      shelves.deleteShelf(id, recordTombstone: recordTombstone);
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
  Future<void> enrichFromSearch(String bookId, BookSearchResult result) =>
      writes.enrichFromSearch(bookId, result);
  /// The permanent delete: tombstone, blobs, the lot. Reserved for the sweep,
  /// "delete now" in the trash, a pull that says the server deleted the book,
  /// and undoing an add that just happened. Everything a *user* calls "remove
  /// from my library" should go through [trashBook] instead (plan 5 #52).
  Future<void> deleteBook(Book book, {bool recordTombstone = true}) =>
      writes.deleteBook(book, recordTombstone: recordTombstone);

  // ---- Trash (plan 5 #52) -------------------------------------------------
  Future<void> trashBook(String bookId) => trash.trash(bookId);
  Future<void> restoreBook(String bookId) => trash.restore(bookId);
  Stream<List<Book>> watchTrashedBooks() => trash.watchTrashed();

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
  Future<void> lendCopy(
    String copyId,
    String borrower, {
    DateTime? dueAt,
    String? contact,
    String? notes,
  }) =>
      physical.lendCopy(
        copyId,
        borrower,
        dueAt: dueAt,
        contact: contact,
        notes: notes,
      );
  Future<void> updateLoan(
    String loanId, {
    required DateTime? dueAt,
    String? contact,
    String? notes,
  }) =>
      physical.updateLoan(loanId, dueAt: dueAt, contact: contact, notes: notes);
  Future<void> markReminderSent(String loanId) =>
      physical.markReminderSent(loanId);
  Future<void> returnLoan(String loanId) => physical.returnLoan(loanId);
  Future<void> deletePhysicalCopy(String id, {bool recordTombstone = true}) =>
      physical.deletePhysicalCopy(id, recordTombstone: recordTombstone);

  /// The library's data directory (covers/ and files/ live under it). Exposed
  /// for the sync service and tests.
  Directory get dataDir => _dataDir;

  // Sync (pull/push) lives in `server/sync_service.dart`, which drives this
  // repository's database and file store.
}
