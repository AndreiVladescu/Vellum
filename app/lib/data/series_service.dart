import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import 'database.dart';
import 'wishlist_service.dart';

/// A book's place in its series, plus what's missing around it (plan 5 #17).
class SeriesPlace {
  const SeriesPlace({
    required this.name,
    required this.index,
    required this.owned,
    required this.wanted,
    required this.gaps,
  });

  final String name;

  /// This book's own number, if it has one.
  final double? index;

  /// Every volume number owned in this series, ascending. Wishlist entries are
  /// not in here — they're what [wanted] is for.
  final List<double> owned;

  /// Volume numbers already on the wishlist (plan 5 #21a), so the gap list
  /// doesn't keep offering a book you've already said you want.
  final List<double> wanted;

  /// Whole numbers between the lowest and highest owned volume that are missing.
  ///
  /// The most useful thing this feature can say: not "you own 1, 3, 4" but
  /// "you're missing 2". Only whole numbers are reported — a missing 2.5 is
  /// usually a novella nobody intended to own, and guessing otherwise would
  /// invent gaps.
  final List<int> gaps;

  bool get hasGaps => gaps.isNotEmpty;

  /// The gaps you haven't already wished for — what the detail page offers to
  /// add to the wishlist.
  List<int> get openGaps =>
      [for (final g in gaps) if (!wanted.contains(g.toDouble())) g];
}

/// Series membership and gap detection (plan 5 #17).
class SeriesService {
  SeriesService(this.db);

  final VellumDatabase db;

  static const _uuid = Uuid();

  /// Every known series name, for autocomplete in the edit sheet.
  Stream<List<String>> watchNames() => (db.select(db.series)
        ..orderBy([(s) => OrderingTerm.asc(s.name)]))
      .watch()
      .map((rows) => [for (final r in rows) r.name]);

  /// Puts [bookId] in [name] at [index]; a blank name clears the membership.
  ///
  /// Get-or-create by name, exactly like authors and genres — and for the same
  /// reason: two devices must converge on one series rather than two rows that
  /// happen to read the same.
  ///
  /// [markDirty] must be **false** when applying a series that just came *from*
  /// the server. Bumping `updatedAt` there would make the freshly-pulled row look
  /// newer than the server's, so the next genuine remote edit would be skipped by
  /// the LWW compare — silent data loss, and exactly what
  /// `test/sync_model_test.dart` caught when this defaulted to true everywhere.
  Future<void> setSeries(
    String bookId,
    String? name,
    double? index, {
    bool markDirty = true,
  }) async {
    final trimmed = name?.trim();
    String? seriesId;
    if (trimmed != null && trimmed.isNotEmpty) {
      final existing = await (db.select(db.series)
            ..where((s) => s.name.equals(trimmed)))
          .getSingleOrNull();
      seriesId = existing?.id ?? _uuid.v4();
      if (existing == null) {
        await db.into(db.series).insert(
              SeriesCompanion.insert(id: seriesId, name: trimmed),
              mode: InsertMode.insertOrIgnore,
            );
        // A racing insert may have won; re-read so the join points at the row
        // that actually exists.
        seriesId = (await (db.select(db.series)
                  ..where((s) => s.name.equals(trimmed)))
                .getSingle())
            .id;
      }
    }
    await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(
        seriesId: Value(seriesId),
        seriesIndex: Value(seriesId == null ? null : index),
        updatedAt: markDirty ? Value(DateTime.now()) : const Value.absent(),
        needsPush: markDirty ? const Value(true) : const Value.absent(),
      ),
    );
    await _gcOrphanSeries();
  }

  /// The series name for a book, or null.
  Future<String?> nameOf(String bookId) async {
    final rows = await (db.select(db.books).join([
      innerJoin(db.series, db.series.id.equalsExp(db.books.seriesId)),
    ])..where(db.books.id.equals(bookId)))
        .get();
    return rows.isEmpty ? null : rows.first.readTable(db.series).name;
  }

  /// Where [book] sits in its series and which volumes are missing, or null when
  /// it belongs to no series.
  Future<SeriesPlace?> placeOf(Book book) async {
    final seriesId = book.seriesId;
    if (seriesId == null) return null;
    final row = await (db.select(db.series)..where((s) => s.id.equals(seriesId)))
        .getSingleOrNull();
    if (row == null) return null;
    // Trashed siblings are gone as far as the shelf is concerned (plan 5 #52),
    // so counting them would report volumes you can't reach.
    final siblings = await (db.select(db.books)
          ..where((b) => b.seriesId.equals(seriesId) & b.deletedAt.isNull()))
        .get();
    // Wishlist entries sit in the same series but are explicitly *not* owned
    // (plan 5 #21a) — keeping them separate is what lets the gap list say
    // "missing 2" and "already on your wishlist" as different things.
    final owned = [
      for (final b in siblings)
        if (b.seriesIndex != null && !WishlistService.isWanted(b))
          b.seriesIndex!,
    ]..sort();
    final wanted = [
      for (final b in siblings)
        if (b.seriesIndex != null && WishlistService.isWanted(b))
          b.seriesIndex!,
    ]..sort();
    return SeriesPlace(
      name: row.name,
      index: book.seriesIndex,
      owned: owned,
      wanted: wanted,
      gaps: gapsIn(owned),
    );
  }

  /// The whole numbers missing between the lowest and highest owned volume.
  static List<int> gapsIn(List<double> owned) {
    if (owned.length < 2) return const [];
    final present = owned.map((v) => v).toSet();
    final lowest = owned.first.ceil();
    final highest = owned.last.floor();
    return [
      for (var n = lowest; n <= highest; n++)
        if (!present.contains(n.toDouble())) n,
    ];
  }

  /// Drops series rows no book references — the same housekeeping authors and
  /// genres get, so a renamed series doesn't leave a ghost in the autocomplete.
  Future<void> _gcOrphanSeries() => db.customStatement(
        'DELETE FROM series WHERE id NOT IN '
        '(SELECT series_id FROM books WHERE series_id IS NOT NULL)',
      );
}
