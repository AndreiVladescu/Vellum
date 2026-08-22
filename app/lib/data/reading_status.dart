import 'package:drift/drift.dart';

import 'database.dart';

/// Where a book stands with its reader (plan 5 #18).
///
/// Stored as the string in `books.status`, not an index: an enum's ordinal is a
/// terrible thing to persist, and the strings are what a future server column
/// would carry anyway.
enum ReadingStatus {
  unread('Unread', 'Not started'),
  reading('Reading', 'In progress'),
  finished('Finished', 'Read to the end'),
  abandoned('Abandoned', 'Started, then put down'),
  reference('Reference', 'Dipped into, never "finished"'),

  /// Not a reading state at all: a book you *want* and don't own (plan 5 #21a).
  ///
  /// It rides this column rather than getting one of its own because a wishlist
  /// entry is a book in every other respect — title, author, cover, series
  /// number — and giving it a separate table would mean duplicating all of that
  /// and then migrating a row across when you finally buy it. The one rule that
  /// follows: a wishlist book is **not in the library**, so it stays out of the
  /// shelf, the palette, and the copy pickers until it's owned.
  wishlist('Wishlist', 'Wanted, not owned yet');

  const ReadingStatus(this.label, this.description);

  final String label;
  final String description;

  /// The states a book you actually own can be in — what the shelf's status
  /// facet and the detail page offer. [wishlist] is deliberately not among
  /// them: it has its own view, and offering it as a "reading status" would
  /// invite marking an owned book as wanted.
  static List<ReadingStatus> get ownedStates =>
      [for (final s in values) if (s != wishlist) s];

  static ReadingStatus parse(String? raw) =>
      ReadingStatus.values.where((s) => s.name == raw).firstOrNull ??
      ReadingStatus.unread;
}

/// Reading status, ratings and finish dates (plan 5 #18).
///
/// The rule that shapes every method here: **transitions are offered, never
/// silently applied**, with one exception. Opening a book sets `reading`, because
/// that is unambiguous and reversible. Reaching the end does *not* set
/// `finished` — a reader who skims the last chapter, or stops at the
/// bibliography, has not finished the book, and the app deciding otherwise is
/// both wrong and annoying to undo. [shouldOfferFinished] exists so the UI can
/// ask instead.
class ReadingStatusService {
  ReadingStatusService(this.db);

  final VellumDatabase db;

  /// Progress past which finishing is worth offering. Not 1.0: a PDF's last page
  /// frequently never reports a full fraction.
  static const finishedThreshold = 0.98;

  /// Sets the status explicitly (the user's own choice).
  ///
  /// Keeps the dates honest as a side effect: choosing `reading` stamps
  /// `startedAt` if it was never set, choosing `finished` stamps `finishedAt`
  /// and bumps `readCount`, and moving *back* out of `finished` clears
  /// `finishedAt` so the two can't disagree.
  Future<void> setStatus(String bookId, ReadingStatus status) async {
    final book = await (db.select(db.books)..where((b) => b.id.equals(bookId)))
        .getSingleOrNull();
    if (book == null) return;
    final current = ReadingStatus.parse(book.status);
    if (current == status) return;

    final now = DateTime.now();
    final becomingFinished = status == ReadingStatus.finished;
    await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(
        status: Value(status.name),
        // The status is personal data with its own channel and its own clock —
        // see `Books.statusUpdatedAt`. Every write that changes it stamps both,
        // or the other devices never hear.
        statusUpdatedAt: Value(now),
        statusNeedsPush: const Value(true),
        startedAt: book.startedAt == null && status != ReadingStatus.unread
            ? Value(now)
            : const Value.absent(),
        finishedAt: becomingFinished
            ? Value(now)
            : (current == ReadingStatus.finished
                ? const Value(null)
                : const Value.absent()),
        readCount: becomingFinished
            ? Value(book.readCount + 1)
            : const Value.absent(),
      ),
    );
  }

  /// 1–5, or null to clear. A rating is app-local judgement like the status, and
  /// deliberately does **not** touch the sync clock.
  Future<void> setRating(String bookId, int? rating) =>
      (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
        BooksCompanion(
          rating: Value(rating?.clamp(1, 5)),
        ),
      );

  /// Called when a book is opened for reading: `unread` becomes `reading` and
  /// `startedAt` is stamped. Anything else is left alone — re-opening a book you
  /// marked `abandoned` or `reference` must not quietly reclassify it.
  Future<void> noteOpened(String bookId) async {
    final book = await (db.select(db.books)..where((b) => b.id.equals(bookId)))
        .getSingleOrNull();
    if (book == null) return;
    if (ReadingStatus.parse(book.status) != ReadingStatus.unread) return;
    await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(
        status: Value(ReadingStatus.reading.name),
        startedAt: Value(book.startedAt ?? DateTime.now()),
        statusUpdatedAt: Value(DateTime.now()),
        statusNeedsPush: const Value(true),
      ),
    );
  }

  /// Whether the UI should offer "mark as finished" for [book] — near the end,
  /// and not already resolved one way or the other.
  static bool shouldOfferFinished(Book book) {
    final status = ReadingStatus.parse(book.status);
    if (status == ReadingStatus.finished ||
        status == ReadingStatus.abandoned ||
        status == ReadingStatus.reference) {
      return false;
    }
    return (book.readingProgress ?? 0) >= finishedThreshold;
  }

  /// Books grouped by status, for the default views.
  Stream<List<Book>> watchByStatus(ReadingStatus status) =>
      (db.select(db.books)
            ..where((b) => b.status.equals(status.name))
            ..orderBy([(b) => OrderingTerm.desc(b.lastReadAt)]))
          .watch();
}
