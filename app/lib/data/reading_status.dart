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
        // A choice, not a guess — see `Books.statusInferred`.
        statusInferred: const Value(false),
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

  /// 1–5, or null to clear.
  ///
  /// Personal like the status, and on its own clock rather than the book's:
  /// rating a book must never look like a catalogue edit (which would publish
  /// it on the shared row), but it must reach your other devices. Not on the
  /// status clock either — see `Books.ratingUpdatedAt` — and it leaves
  /// [Books.statusInferred] alone: rating a book says nothing about whether its
  /// "reading" was chosen.
  Future<void> setRating(String bookId, int? rating) async {
    final value = rating?.clamp(1, 5);
    final book = await (db.select(db.books)..where((b) => b.id.equals(bookId)))
        .getSingleOrNull();
    // Unchanged is not an edit: it must not stamp a clock that would then beat
    // another device's real change.
    if (book == null || book.rating == value) return;
    await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(
        rating: Value(value),
        ratingUpdatedAt: Value(DateTime.now()),
        statusNeedsPush: const Value(true),
      ),
    );
  }

  /// Called when a book is opened for reading: `unread` becomes `reading` and
  /// `startedAt` is stamped. Anything else is left alone — re-opening a book you
  /// marked `abandoned` or `reference` must not quietly reclassify it.
  ///
  /// Marked as inferred: this device only *thinks* the book was unread, and if
  /// it has been offline while the book was finished elsewhere it is wrong.
  /// [mergeStatus] lets a chosen status win over this one whatever the clocks.
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
        statusInferred: const Value(true),
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

/// Where a book stands with one reader, in the shape the sync merges: the five
/// personal fields plus the flag and the two clocks that decide between copies.
///
/// [ratingUpdatedAt] null means *no opinion*: a device that never rated the
/// book, or a server row no rating-aware app has written. Such a copy's
/// [rating] says nothing, and loses to any dated one.
class StatusState {
  const StatusState({
    required this.status,
    this.startedAt,
    this.finishedAt,
    this.readCount = 0,
    this.inferred = false,
    this.updatedAt,
    this.rating,
    this.ratingUpdatedAt,
  });

  /// This device's copy of [b].
  factory StatusState.ofBook(Book b) => StatusState(
        status: b.status,
        startedAt: b.startedAt,
        finishedAt: b.finishedAt,
        readCount: b.readCount,
        inferred: b.statusInferred,
        updatedAt: b.statusUpdatedAt,
        rating: b.rating,
        ratingUpdatedAt: b.ratingUpdatedAt,
      );

  final String status;
  final DateTime? startedAt;
  final DateTime? finishedAt;
  final int readCount;
  final bool inferred;

  /// The status's clock.
  final DateTime? updatedAt;

  /// 1–5, or null for unrated.
  final int? rating;

  /// The rating's own clock.
  final DateTime? ratingUpdatedAt;

  /// Whether [other] says the same thing, clocks aside — except whether the
  /// rating is dated at all, since an undated rating says nothing. [withRating]
  /// is false for a server that predates the rating (migration 0038): it sends
  /// neither the rating nor the inferred flag, so comparing them would find a
  /// difference on every pull and push the book forever.
  bool sameAs(StatusState other, {bool withRating = true}) {
    bool sameTime(DateTime? a, DateTime? b) =>
        a == null ? b == null : (b != null && a.isAtSameMomentAs(b));
    return status == other.status &&
        sameTime(startedAt, other.startedAt) &&
        sameTime(finishedAt, other.finishedAt) &&
        readCount == other.readCount &&
        (!withRating ||
            (rating == other.rating &&
                (ratingUpdatedAt == null) == (other.ratingUpdatedAt == null) &&
                inferred == other.inferred));
  }
}

/// How two copies of a reader's status combine — the same rules as the
/// server's `personal::merge_status`, so a device and the server never
/// disagree about the result. [incoming] is the copy arriving at [existing].
///
/// Two halves, each last-write-wins on its own clock: the status with its
/// dates (which move together, never separately), and the rating. They are
/// separate acts, so a stale device doing one must not undo the other. The
/// status half has two refinements:
///
/// * **A guess yields to a choice.** An inferred status (opening an unread
///   book) never replaces a chosen one that says something — anything but
///   `unread` — and a chosen one replaces a guess whichever is newer. That is
///   what stops a device that was offline while the book was finished elsewhere
///   from unfinishing it by opening it.
/// * **The read count only grows**: the larger of the two, not the newer. It
///   counts finishes and the app never lowers it, so a stale device's later
///   change must not take a finish back. Two devices that each mark the same
///   reading finished offline count it once.
StatusState mergeStatus(StatusState existing, StatusState incoming) {
  // A missing clock is the oldest possible one: it means "never changed".
  bool atLeast(DateTime? a, DateTime? b) =>
      b == null || (a != null && !a.isBefore(b));

  final newer = atLeast(incoming.updatedAt, existing.updatedAt);
  final bool takeStatus;
  if (incoming.inferred && !existing.inferred && existing.status != 'unread') {
    takeStatus = false;
  } else if (!incoming.inferred &&
      existing.inferred &&
      incoming.status != 'unread') {
    takeStatus = true;
  } else {
    takeStatus = newer;
  }
  final from = takeStatus ? incoming : existing;
  final takeRating = incoming.ratingUpdatedAt != null &&
      atLeast(incoming.ratingUpdatedAt, existing.ratingUpdatedAt);
  final rated = takeRating ? incoming : existing;
  return StatusState(
    status: from.status,
    startedAt: from.startedAt,
    finishedAt: from.finishedAt,
    inferred: from.inferred,
    readCount: existing.readCount > incoming.readCount
        ? existing.readCount
        : incoming.readCount,
    updatedAt: newer ? incoming.updatedAt : existing.updatedAt,
    rating: rated.rating,
    ratingUpdatedAt: rated.ratingUpdatedAt,
  );
}
