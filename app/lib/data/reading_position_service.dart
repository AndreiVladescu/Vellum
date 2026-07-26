import 'package:drift/drift.dart';

import 'database.dart';

/// What a book's saved position counts, which differs by the format it opens
/// in: PDF pages, or EPUB chapters. Shared by the reader's label, the jump
/// prompt, and the cross-device push (plan 5 #5) so the three can't drift —
/// a remote row that says "page 214" when it meant chapter 214 is a lie.
String readingUnitForFormats(Iterable<String> formats) =>
    formats.contains('pdf') ? 'page' : 'chapter';

/// Another device is further along in a book than this one, by enough to be
/// worth offering to jump. Produced by [ReadingPositionService.offerFor].
class ReadingJumpOffer {
  ReadingJumpOffer({
    required this.progress,
    required this.page,
    required this.unit,
    required this.deviceLabel,
  });

  /// The remote global fraction (0..1) — the comparison key, since it means the
  /// same thing regardless of format.
  final double progress;

  /// The remote position in [unit]s, 1-based like the local column.
  final int page;

  /// 'page' or 'chapter'; always equal to the local unit (see [offerFor]).
  final String unit;

  /// Human name of the device that got there, e.g. "desktop".
  final String deviceLabel;

  /// "page 214 on desktop (72%)" — the prompt's middle clause.
  String get description =>
      '$unit $page on $deviceLabel (${(progress * 100).round()}%)';
}

/// The app's side of the optional cross-device reading position (plan 5 #5).
///
/// This device's own position stays on the book row, app-local and off the sync
/// clock exactly as before. What this service adds is the *other* direction:
/// a cache of other devices' positions (`remote_reading_positions`), the dirty
/// flag that decides what gets published, and the pure comparison behind the
/// "jump there?" prompt. Nothing here runs unless the user opts in.
class ReadingPositionService {
  ReadingPositionService(this.db);

  final VellumDatabase db;

  /// How far ahead a remote position has to be before it's worth interrupting
  /// the user for. A page or two of drift between devices is normal; offering
  /// to "jump" to a position they're already at would be noise.
  static const minLead = 0.01;

  /// Other devices' positions for one book, freshest first. Never contains this
  /// device's own row — the sync pass drops it on the way in.
  Stream<List<RemoteReadingPosition>> watchRemotePositions(String bookId) =>
      (db.select(db.remoteReadingPositions)
            ..where((r) => r.bookId.equals(bookId))
            ..orderBy([(r) => OrderingTerm.desc(r.updatedAt)]))
          .watch();

  /// The one remote position worth offering for [book], or null.
  ///
  /// Two rules, both deliberate:
  /// - **Strictly ahead by [minLead]**, compared on `progress` because it is
  ///   format-agnostic.
  /// - **Same unit only.** A device that read the EPUB while this one has the
  ///   PDF reports chapters, and converting chapters to a page number would
  ///   land the reader somewhere plausible but wrong. Offering nothing beats
  ///   offering a lie; the position still syncs and still shows up on a device
  ///   reading the same format.
  ReadingJumpOffer? offerFor({
    required Book book,
    required List<RemoteReadingPosition> remotes,
    required String localUnit,
  }) {
    final local = book.readingProgress ?? 0;
    RemoteReadingPosition? best;
    for (final r in remotes) {
      final progress = r.progress;
      if (progress == null || r.page == null) continue;
      if (r.unit != null && r.unit != localUnit) continue;
      if (progress <= local + minLead) continue;
      if (best == null || progress > best.progress!) best = r;
    }
    if (best == null) return null;
    return ReadingJumpOffer(
      progress: best.progress!,
      page: best.page!,
      unit: localUnit,
      deviceLabel: best.deviceLabel?.trim().isNotEmpty == true
          ? best.deviceLabel!.trim()
          : 'another device',
    );
  }

  /// Adopt [offer] as this device's position. Writes the same columns a reader
  /// would and, like them, leaves `updatedAt` alone — accepting a jump is still
  /// reading state, not a metadata edit (see `saveReadingPosition`).
  ///
  /// [needsProgressPush] is set so this device republishes where it now is;
  /// otherwise the two devices would disagree until the next page turn.
  Future<void> applyOffer(String bookId, ReadingJumpOffer offer) =>
      (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
        BooksCompanion(
          readingProgress: Value(offer.progress),
          lastReadPage: Value(offer.page),
          lastReadAt: Value(DateTime.now()),
          needsProgressPush: const Value(true),
        ),
      );

  /// Replace the cached remote rows for the books in [entries], dropping this
  /// device's own rows ([ownDeviceId]) so a local position never arrives back
  /// as a "remote" one. Called by the sync pass, never by the UI.
  Future<void> cacheRemotePositions(
    Iterable<RemoteReadingPositionsCompanion> entries, {
    required String ownDeviceId,
  }) async {
    final foreign = [
      for (final e in entries)
        if (e.deviceId.value != ownDeviceId) e,
    ];
    if (foreign.isEmpty) return;
    await db.batch((b) => b.insertAllOnConflictUpdate(
          db.remoteReadingPositions,
          foreign,
        ));
  }

  /// Books whose position still needs publishing: dirty *and* actually opened
  /// at least once (an unread book has no position to publish).
  Future<List<Book>> booksNeedingProgressPush() => (db.select(db.books)
        ..where((b) => b.needsProgressPush.equals(true) & b.readingProgress.isNotNull()))
      .get();

  Future<void> clearProgressDirty(String bookId) =>
      (db.update(db.books)..where((b) => b.id.equals(bookId)))
          .write(const BooksCompanion(needsProgressPush: Value(false)));

  /// Mark every already-read book for publishing — run when the user switches
  /// the feature on. Without this, "off" would have quietly published positions
  /// saved before the switch, and the opt-in wouldn't mean what it says.
  Future<void> markReadBooksForProgressPush() async {
    await (db.update(db.books)..where((b) => b.readingProgress.isNotNull()))
        .write(const BooksCompanion(needsProgressPush: Value(true)));
  }

  /// Forget everything this feature accumulated locally — the cached remote
  /// rows and every dirty flag. Run when the user switches the feature off, so
  /// no stale jump is offered and nothing is queued for a later push.
  Future<void> forgetLocally() async {
    await db.delete(db.remoteReadingPositions).go();
    await db
        .update(db.books)
        .write(const BooksCompanion(needsProgressPush: Value(false)));
  }
}
