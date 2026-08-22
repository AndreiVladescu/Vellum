/// The clock a synced row is edited by.
///
/// **The bug this exists for.** The server stamps `updated_at` with its own
/// clock on every write, and then rejects a push whose `updated_at` is not
/// strictly newer than that stamp — silently, with a 200 and the stored row in
/// the body, which the app has no way to tell from success. Two ordinary things
/// then lose an edit for good:
///
///  * **An edit that doesn't move the clock.** Changing only a book's authors
///    or genres marked the row dirty without touching `updatedAt`, so the push
///    carried a timestamp the server had already passed. Those edits never once
///    reached the server.
///  * **A device whose clock trails the server's.** Every edit made within the
///    skew is stamped before the row it is editing, and is dropped the same way
///    — then replaced locally on the next pull, since the server's copy looks
///    newer.
///
/// So an edit is stamped *later than the row it edits*, not merely "now": the
/// wall clock where it can, one second past the row's own stamp where it
/// cannot. Written as one SQL statement rather than a read-then-write, because
/// the sync pass is clearing flags on these same rows at the same time.
library;

import 'database.dart';

/// The tables that carry an `updated_at`/`needs_push` pair to the server.
enum SyncedRow {
  book('books'),
  shelf('shelves'),
  physicalCopy('physical_copies'),
  loan('loans');

  const SyncedRow(this.table);

  /// Fixed strings, never anything from outside — these are interpolated into
  /// the statement below.
  final String table;
}

/// Marks one row as edited here and waiting to go: bumps its clock past its own
/// previous value and sets `needs_push`.
Future<void> stampSyncClock(
  VellumDatabase db,
  SyncedRow row,
  String id,
) =>
    db.customStatement(
      'UPDATE ${row.table} SET '
      // CAST because `strftime` answers text, and SQLite sorts every integer
      // before every string — so an uncast MAX() always picks the text and the
      // clock never moves.
      "updated_at = MAX(CAST(strftime('%s', 'now') AS INTEGER), updated_at + 1), "
      'needs_push = 1 '
      'WHERE id = ?',
      [id],
    );
