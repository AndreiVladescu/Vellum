import 'package:drift/drift.dart';

import 'book_write_service.dart';
import 'database.dart';
import 'metadata.dart';
import 'reading_status.dart';
import 'series_service.dart';

/// Books you want but don't own yet (plan 5 #21a).
///
/// A wishlist entry is an ordinary `books` row with `status = 'wishlist'` and
/// no file and no physical copy — see the note on [ReadingStatus.wishlist] for
/// why it isn't its own table. Everything that shows "the library" filters it
/// out; this service is the only way in and out.
///
/// **Owning is an observation, not a command.** [noteAcquired] is called
/// wherever a book gains a file or a copy, because that *is* what owning
/// means — a wishlist entry you attach a PDF to has stopped being a wish, and
/// making the user also remember to tick a box would just produce a wishlist
/// full of books they own.
class WishlistService {
  WishlistService(this.db, this._writes, this._series);

  final VellumDatabase db;
  final BookWriteService _writes;
  final SeriesService _series;

  /// The wishlist, newest first — a wishlist is a queue of intentions, and the
  /// thing you just added is the thing you were just thinking about.
  Stream<List<Book>> watchWishlist() => (db.select(db.books)
        ..where((b) =>
            b.status.equals(ReadingStatus.wishlist.name) & b.deletedAt.isNull())
        ..orderBy([(b) => OrderingTerm.desc(b.createdAt)]))
      .watch();

  Stream<int> watchCount() {
    final q = db.selectOnly(db.books)
      ..addColumns([db.books.id.count()])
      ..where(db.books.status.equals(ReadingStatus.wishlist.name) &
          db.books.deletedAt.isNull());
    return q.watch().map((rows) => rows.first.read(db.books.id.count()) ?? 0);
  }

  /// Adds a book you want, by hand.
  Future<String> add({
    required String title,
    String? author,
    int? publishedYear,
    String? note,
    String? series,
    double? seriesIndex,
  }) async {
    final id = await _writes.createCustomBook(
      title: title,
      author: author,
      publishedYear: publishedYear,
    );
    await _markWanted(id, note);
    if (series != null && series.trim().isNotEmpty) {
      await _series.setSeries(id, series, seriesIndex);
    }
    return id;
  }

  /// Adds a book you want from an online search result or an ISBN scan — the
  /// bookshop case the plan is named for: you're standing in a shop, you scan
  /// the barcode, and you want the record without pretending you bought it.
  ///
  /// Reuses [BookWriteService.addFromSearch] so a wishlist entry arrives with
  /// the same metadata, cover and spine as any other book, and turns into an
  /// owned book later without re-fetching anything.
  Future<String> addFromSearch(
    BookSearchResult result, {
    bool importGenres = false,
    String? note,
  }) async {
    final id = await _writes.addFromSearch(result, importGenres: importGenres);
    await _markWanted(id, note);
    return id;
  }

  /// Adds the missing volume of a series (plan 5 #17's gap detection feeding
  /// #21a). The title is a placeholder the user can correct — the point is the
  /// *slot*, not a guess at what the book is called.
  Future<String> addSeriesGap({
    required String seriesName,
    required int volume,
    String? author,
  }) async {
    return add(
      title: '$seriesName vol. $volume',
      author: author,
      series: seriesName,
      seriesIndex: volume.toDouble(),
      note: 'Missing volume $volume of $seriesName',
    );
  }

  /// Moves a wishlist entry into the library as an owned, unread book.
  Future<void> markOwned(String bookId) =>
      (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
        BooksCompanion(
          status: Value(ReadingStatus.unread.name),
          readerNotes: const Value(null),
          statusUpdatedAt: Value(DateTime.now()),
          statusNeedsPush: const Value(true),
        ),
      );

  /// Puts an owned book back on the wishlist — for a book you lent and lost,
  /// or added by mistake.
  Future<void> markWanted(String bookId) => _markWanted(bookId, null);

  /// Called when a book gains a file or a physical copy. A wishlist entry that
  /// has either is owned by definition, so it graduates; anything else is left
  /// alone.
  ///
  /// Returns true when it actually promoted something, so the caller can say so.
  Future<bool> noteAcquired(String bookId) async {
    final book = await (db.select(db.books)..where((b) => b.id.equals(bookId)))
        .getSingleOrNull();
    if (book == null) return false;
    if (ReadingStatus.parse(book.status) != ReadingStatus.wishlist) return false;
    await markOwned(bookId);
    return true;
  }

  /// True for a book that is on the wishlist rather than in the library.
  static bool isWanted(Book book) =>
      ReadingStatus.parse(book.status) == ReadingStatus.wishlist;

  Future<void> _markWanted(String bookId, String? note) async {
    await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(
        status: Value(ReadingStatus.wishlist.name),
        statusUpdatedAt: Value(DateTime.now()),
        statusNeedsPush: const Value(true),
        // Reading state on a book you haven't got is meaningless; clear it so
        // a re-wished book doesn't claim you're halfway through it.
        readingProgress: const Value(null),
        lastReadPage: const Value(null),
        lastReadAt: const Value(null),
        startedAt: const Value(null),
        finishedAt: const Value(null),
        readerNotes: note == null || note.trim().isEmpty
            ? const Value.absent()
            : Value(note.trim()),
      ),
    );
  }

}
