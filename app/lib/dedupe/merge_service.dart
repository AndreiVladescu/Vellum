import 'package:drift/drift.dart';

import '../data/database.dart';
import '../data/library_repository.dart';

/// Which book's value to keep for a field where the two disagree.
enum MergeChoice { keeper, loser }

/// A field the two books disagree on, so the user can pick per field rather than
/// having one book silently win everything.
class MergeConflict {
  MergeConflict({
    required this.field,
    required this.label,
    required this.keeperValue,
    required this.loserValue,
  });

  /// Column name, used as the map key when applying choices.
  final String field;
  final String label;
  final String? keeperValue;
  final String? loserValue;
}

/// What a merge did, in the order it happened. Kept because a merge is
/// destructive and irreversible: when someone later asks "where did that PDF
/// go?", this is the answer.
class MergeLog {
  MergeLog({required this.keeperId, required this.loserId});

  final String keeperId;
  final String loserId;
  final List<String> entries = [];

  void add(String what) => entries.add(what);

  @override
  String toString() => entries.join('\n');
}

/// Merging two books into one (plan 5 #21b).
///
/// A library grown by bulk import will contain duplicates, and cleaning them up
/// by hand means re-attaching files, copies, shelves and loans — the work this
/// automates. Three rules shape it:
///
/// 1. **Everything moves before anything is deleted.** Files, physical copies
///    (and with them their placements and loan history), shelf memberships,
///    authors and genres are re-pointed at the keeper inside one transaction; the
///    loser is deleted last. A failure rolls the whole thing back.
/// 2. **Blanks are filled, never overwritten.** The keeper's own values stand
///    unless it has none; genuine disagreements are surfaced as [MergeConflict]s
///    for the user to resolve, because guessing which title is "better" is not
///    something code should do.
/// 3. **The loser is tombstoned**, so the merge reaches the server and other
///    devices instead of the duplicate coming back on the next pull.
class MergeService {
  MergeService(this.repository);

  final LibraryRepository repository;

  VellumDatabase get _db => repository.db;

  /// The fields where [keeper] and [loser] both have a value and the values
  /// differ. A field only the loser has is not a conflict — it just moves.
  Future<List<MergeConflict>> conflictsBetween(Book keeper, Book loser) async {
    final conflicts = <MergeConflict>[];
    void check(String field, String label, String? mine, String? theirs) {
      final a = (mine ?? '').trim();
      final b = (theirs ?? '').trim();
      if (a.isNotEmpty && b.isNotEmpty && a != b) {
        conflicts.add(MergeConflict(
          field: field,
          label: label,
          keeperValue: a,
          loserValue: b,
        ));
      }
    }

    check('title', 'Title', keeper.title, loser.title);
    check('subtitle', 'Subtitle', keeper.subtitle, loser.subtitle);
    check('description', 'Description', keeper.description, loser.description);
    check('isbn', 'ISBN', keeper.isbn, loser.isbn);
    check('publisher', 'Publisher', keeper.publisher, loser.publisher);
    check('publishedYear', 'Year', keeper.publishedYear?.toString(),
        loser.publishedYear?.toString());
    check('pageCount', 'Pages', keeper.pageCount?.toString(),
        loser.pageCount?.toString());
    check('coverPath', 'Cover', keeper.coverPath, loser.coverPath);
    return conflicts;
  }

  /// Merges [loserId] into [keeperId] and returns a log of what moved.
  ///
  /// [choices] resolves the conflicts from [conflictsBetween]; anything absent
  /// keeps the keeper's value. Throws if either book is missing or the two ids
  /// are the same.
  Future<MergeLog> merge({
    required String keeperId,
    required String loserId,
    Map<String, MergeChoice> choices = const {},
  }) async {
    if (keeperId == loserId) {
      throw ArgumentError('a book cannot be merged into itself');
    }
    final keeper = await repository.watchBook(keeperId).first;
    final loser = await repository.watchBook(loserId).first;
    if (keeper == null || loser == null) {
      throw StateError('both books must exist to merge them');
    }
    final log = MergeLog(keeperId: keeperId, loserId: loserId);
    final db = _db;

    await db.transaction(() async {
      // ---- fields: fill the keeper's blanks, plus anything the user chose ----
      String? pick(String field, String? mine, String? theirs) {
        final wantLoser = choices[field] == MergeChoice.loser;
        final mineEmpty = (mine ?? '').trim().isEmpty;
        if (wantLoser && (theirs ?? '').trim().isNotEmpty) {
          log.add('$field: took "${theirs!}" from the duplicate');
          return theirs;
        }
        if (mineEmpty && (theirs ?? '').trim().isNotEmpty) {
          log.add('$field: filled from the duplicate');
          return theirs;
        }
        return mine;
      }

      int? pickInt(String field, int? mine, int? theirs) {
        final wantLoser = choices[field] == MergeChoice.loser;
        if (wantLoser && theirs != null) {
          log.add('$field: took $theirs from the duplicate');
          return theirs;
        }
        if (mine == null && theirs != null) {
          log.add('$field: filled from the duplicate');
          return theirs;
        }
        return mine;
      }

      await (db.update(db.books)..where((b) => b.id.equals(keeperId))).write(
        BooksCompanion(
          title: Value(pick('title', keeper.title, loser.title) ?? keeper.title),
          subtitle: Value(pick('subtitle', keeper.subtitle, loser.subtitle)),
          description:
              Value(pick('description', keeper.description, loser.description)),
          isbn: Value(pick('isbn', keeper.isbn, loser.isbn)),
          publisher: Value(pick('publisher', keeper.publisher, loser.publisher)),
          publishedYear: Value(
              pickInt('publishedYear', keeper.publishedYear, loser.publishedYear)),
          pageCount:
              Value(pickInt('pageCount', keeper.pageCount, loser.pageCount)),
          coverPath: Value(pick('coverPath', keeper.coverPath, loser.coverPath)),
          // A merge changes synced data, so the result has to be pushed.
          updatedAt: Value(DateTime.now()),
          needsPush: const Value(true),
        ),
      );

      // ---- files ----
      final movedFiles = await db.customUpdate(
        'UPDATE book_files SET book_id = ? WHERE book_id = ?',
        variables: [Variable(keeperId), Variable(loserId)],
        updates: {db.bookFiles},
      );
      if (movedFiles > 0) log.add('moved $movedFiles file(s)');

      // ---- physical copies (placements and loans ride along, keyed by copy) --
      final movedCopies = await db.customUpdate(
        'UPDATE physical_copies SET book_id = ?, needs_push = 1 WHERE book_id = ?',
        variables: [Variable(keeperId), Variable(loserId)],
        updates: {db.physicalCopies},
      );
      if (movedCopies > 0) {
        log.add('moved $movedCopies physical copy/copies, with their '
            'placements and loan history');
      }

      // ---- shelf memberships ----
      // `INSERT OR IGNORE` then delete, rather than an UPDATE: the primary key
      // is (shelf_id, book_id), so a shelf holding *both* books would collide.
      // The keeper's existing position wins in that case.
      final shelfRows = await (db.select(db.shelfBooks)
            ..where((s) => s.bookId.equals(loserId)))
          .get();
      for (final row in shelfRows) {
        await db.into(db.shelfBooks).insert(
              ShelfBooksCompanion.insert(
                shelfId: row.shelfId,
                bookId: keeperId,
                position: Value(row.position),
              ),
              mode: InsertMode.insertOrIgnore,
            );
      }
      if (shelfRows.isNotEmpty) {
        log.add('moved ${shelfRows.length} shelf membership(s)');
        // The shelves themselves changed membership, so they need pushing.
        await db.customStatement(
          'UPDATE shelves SET needs_push = 1 WHERE id IN '
          '(SELECT shelf_id FROM shelf_books WHERE book_id = ?)',
          [keeperId],
        );
      }

      // ---- authors and genres: union, keeping the keeper's ordering ----
      final keeperAuthors = await (db.select(db.bookAuthors)
            ..where((a) => a.bookId.equals(keeperId)))
          .get();
      var nextPosition = keeperAuthors.fold<int>(
          -1, (max, a) => a.position > max ? a.position : max);
      final loserAuthors = await (db.select(db.bookAuthors)
            ..where((a) => a.bookId.equals(loserId))
            ..orderBy([(a) => OrderingTerm.asc(a.position)]))
          .get();
      var addedAuthors = 0;
      for (final row in loserAuthors) {
        if (keeperAuthors.any((a) => a.authorId == row.authorId)) continue;
        await db.into(db.bookAuthors).insert(
              BookAuthorsCompanion.insert(
                bookId: keeperId,
                authorId: row.authorId,
                position: Value(++nextPosition),
              ),
              mode: InsertMode.insertOrIgnore,
            );
        addedAuthors++;
      }
      if (addedAuthors > 0) log.add('added $addedAuthors author(s)');

      final loserGenres = await (db.select(db.bookGenres)
            ..where((g) => g.bookId.equals(loserId)))
          .get();
      var addedGenres = 0;
      for (final row in loserGenres) {
        final inserted = await db.into(db.bookGenres).insert(
              BookGenresCompanion.insert(
                bookId: keeperId,
                genreId: row.genreId,
              ),
              mode: InsertMode.insertOrIgnore,
            );
        if (inserted > 0) addedGenres++;
      }
      if (addedGenres > 0) log.add('added $addedGenres genre(s)');

      // ---- annotations ----
      // Highlights and notes are about the *book*, so they follow it. Moved
      // rather than dropped: losing someone's marginalia to a tidy-up would be
      // the worst thing this operation could do.
      final movedNotes = await db.customUpdate(
        'UPDATE annotations SET book_id = ? WHERE book_id = ?',
        variables: [Variable(keeperId), Variable(loserId)],
        updates: {db.annotations},
      );
      if (movedNotes > 0) log.add('moved $movedNotes annotation(s)');

      // ---- reading state: keep whichever is further along ----
      // Reading state is app-local and never synced, but losing "you were on
      // page 300" because the merge kept the other row would still be a loss.
      final loserProgress = loser.readingProgress;
      if (loserProgress != null &&
          loserProgress > (keeper.readingProgress ?? 0)) {
        await (db.update(db.books)..where((b) => b.id.equals(keeperId))).write(
          BooksCompanion(
            readingProgress: Value(loserProgress),
            lastReadPage: Value(loser.lastReadPage),
            lastReadAt: Value(loser.lastReadAt),
          ),
        );
        log.add('kept the duplicate’s reading position (further along)');
      }

      // ---- the loser's own rows, and the tombstone ----
      // Its joins are empty by now (moved above), so this only clears leftovers
      // and records the tombstone that makes the merge propagate.
      await db
          .into(db.localDeletions)
          .insertOnConflictUpdate(LocalDeletionsCompanion.insert(bookId: loserId));
      for (final table in [
        'book_authors',
        'book_genres',
        'book_files',
        'shelf_books',
        'annotations',
      ]) {
        await db.customStatement('DELETE FROM $table WHERE book_id = ?', [loserId]);
      }
      await db.customStatement(
        'DELETE FROM remote_reading_positions WHERE book_id = ?',
        [loserId],
      );
      await (db.delete(db.books)..where((b) => b.id.equals(loserId))).go();
      log.add('deleted the duplicate and tombstoned it so the merge syncs');
    });

    return log;
  }
}
