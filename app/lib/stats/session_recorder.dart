import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../data/database.dart';

/// Records reading sessions (plan 5 #19).
///
/// One row per session, not per page turn: the readers already write a position
/// on every turn, and duplicating that volume into a history table would make a
/// long evening thousands of rows for no extra insight.
///
/// **Coalescing is the point.** A phone call, a look-up in another app, or simply
/// closing the book to answer the door should not chop one evening into six
/// sessions — so reopening within [coalesceGap] of the last session extends it
/// instead of starting a new one. Without that, every derived number (sessions
/// per day, average pages per session, streaks) would measure interruptions
/// rather than reading.
class SessionRecorder {
  SessionRecorder(this.db, {this.deviceId, this.deviceLabel});

  final VellumDatabase db;

  /// Which device this sitting happened on, so statistics stay answerable once
  /// they span three of them. Null in tests and anywhere the settings aren't
  /// to hand — the session is still recorded, just unattributed.
  final String? deviceId;
  final String? deviceLabel;

  static const _uuid = Uuid();

  /// Gaps shorter than this are treated as the same sitting.
  static const coalesceGap = Duration(minutes: 2);

  /// The session this recorder is currently extending, if any.
  String? _sessionId;

  /// Opens (or resumes) a session for [bookId] starting at [page].
  ///
  /// Returns the session id, so a caller can tell whether it resumed an existing
  /// one. Idempotent while a session is open.
  Future<String> begin(String bookId, {int? page, DateTime? now}) async {
    final at = now ?? DateTime.now();
    final open = _sessionId;
    if (open != null) return open;

    final recent = await (db.select(db.readingSessions)
          ..where((s) => s.bookId.equals(bookId))
          ..orderBy([(s) => OrderingTerm.desc(s.endedAt)])
          ..limit(1))
        .getSingleOrNull();
    if (recent != null &&
        at.difference(recent.endedAt).abs() <= coalesceGap) {
      // Same sitting: keep extending the existing row.
      _sessionId = recent.id;
      return recent.id;
    }

    final id = _uuid.v4();
    await db.into(db.readingSessions).insert(ReadingSessionsCompanion.insert(
          id: id,
          bookId: bookId,
          startedAt: at,
          endedAt: at,
          startPage: Value(page),
          endPage: Value(page),
          deviceId: Value(deviceId),
          deviceLabel: Value(deviceLabel),
          // Not yet: an open sitting is a fact still being made, and the row
          // defaults to dirty. A sync mid-read used to publish "ended at
          // 09:10, page 24" of a sitting that ran to 10:05 — and a server that
          // took the first version of a session and ignored the rest kept it
          // that way for good. See [end].
          needsPush: const Value(false),
        ));
    _sessionId = id;
    return id;
  }

  /// Extends the open session to [page] and *now*. Called as the reader turns
  /// pages; cheap enough to call per turn since it updates one row.
  Future<void> touch({int? page, DateTime? now}) async {
    final id = _sessionId;
    if (id == null) return;
    await (db.update(db.readingSessions)..where((s) => s.id.equals(id))).write(
      ReadingSessionsCompanion(
        endedAt: Value(now ?? DateTime.now()),
        endPage: page == null ? const Value.absent() : Value(page),
        // Deliberately not marked for push: a sitting is only worth publishing
        // once it is over, and [end] is what settles its final page and
        // duration. This comment used to sit above a line that did the
        // opposite.
      ),
    );
  }

  /// Closes the session. A session with no measurable duration *and* no page
  /// progress is deleted rather than kept: opening a book to check its cover is
  /// not reading, and a pile of zero-length rows would skew every average.
  Future<void> end({int? page, DateTime? now}) async {
    final id = _sessionId;
    if (id == null) return;
    // The final extend happens *before* the id is cleared — writing it through
    // [touch] after clearing would silently drop the last page and the end time,
    // making every session look empty (and therefore get discarded below).
    await touch(page: page, now: now);
    _sessionId = null;
    final row = await (db.select(db.readingSessions)
          ..where((s) => s.id.equals(id)))
        .getSingleOrNull();
    if (row == null) return;
    final duration = row.endedAt.difference(row.startedAt);
    final moved = (row.endPage ?? 0) != (row.startPage ?? 0);
    if (duration.inSeconds < 5 && !moved) {
      await (db.delete(db.readingSessions)..where((s) => s.id.equals(id))).go();
      return;
    }
    // Over, and therefore a fact: now it can go.
    await (db.update(db.readingSessions)..where((s) => s.id.equals(id)))
        .write(const ReadingSessionsCompanion(needsPush: Value(true)));
  }

  /// Wipes the history — the "Clear reading history" action. Behavioural data the
  /// user must be able to get rid of, on their own terms.
  Future<int> clearAll() => db.delete(db.readingSessions).go();
}
