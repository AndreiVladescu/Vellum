import 'dart:io';

import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;

import '../import/import_plan.dart';
import 'database.dart';
import 'library_repository.dart';

/// A kind of inconsistency the doctor looks for (plan 5 #11).
enum DefectKind {
  missingFile,
  missingCover,
  orphanBlob,
  danglingPlacement,
  duplicateFileRow,
  staleTombstone,
  // ---- Advisory (see `isRepairable`) ---------------------------------------
  duplicateBook,
  noCover,
  incompleteMetadata;

  String get label => switch (this) {
        DefectKind.missingFile => 'Books whose file is gone',
        DefectKind.missingCover => 'Books whose cover image is gone',
        DefectKind.orphanBlob => 'Files on disk no book refers to',
        DefectKind.danglingPlacement => 'Placements of copies that no longer exist',
        DefectKind.duplicateFileRow => 'The same file attached twice to one book',
        DefectKind.staleTombstone => 'Old delete markers with no server to tell',
        DefectKind.duplicateBook => 'Books that look like the same book',
        DefectKind.noCover => 'Books with no cover at all',
        DefectKind.incompleteMetadata => 'Books missing an author or a year',
      };

  /// Whether the app can fix this on its own.
  ///
  /// The original six are *inconsistencies*: the database and the file tree
  /// disagree, there is one correct answer, and the app can apply it. The three
  /// below are **judgements** — which of two near-identical books to keep, what
  /// the missing author's name is — and guessing at them would quietly destroy
  /// something a person meant. They are reported and left alone; the scan is
  /// worth having for them precisely because nothing else surfaces them.
  bool get isRepairable => switch (this) {
        DefectKind.duplicateBook ||
        DefectKind.noCover ||
        DefectKind.incompleteMetadata =>
          false,
        _ => true,
      };

  /// What the repair does — shown before it runs, because several are
  /// destructive and the user is entitled to know which.
  String get repairLabel => switch (this) {
        DefectKind.missingFile => 'Detach the file record',
        DefectKind.missingCover => 'Clear the cover so a new one can be set',
        DefectKind.orphanBlob => 'Delete the file from disk',
        DefectKind.danglingPlacement => 'Remove the placement',
        DefectKind.duplicateFileRow => 'Keep one record, drop the duplicates',
        DefectKind.staleTombstone => 'Forget the marker',
        // Advisory: what to do about it, since there is no button.
        DefectKind.duplicateBook => 'Open them and merge or trash one yourself',
        DefectKind.noCover => 'Set one from the book’s page',
        DefectKind.incompleteMetadata => 'Fill it in on the book’s page',
      };

  bool get isDestructive =>
      this == DefectKind.orphanBlob || this == DefectKind.duplicateFileRow;
}

/// One thing found wrong, with enough identity to repair exactly it.
class Defect {
  const Defect({
    required this.kind,
    required this.description,
    this.bookId,
    this.rowId,
    this.path,
    this.sizeBytes = 0,
  });

  final DefectKind kind;

  /// Human-readable, e.g. `Dune — files/abc.pdf`.
  final String description;

  final String? bookId;

  /// The offending row's id (a `book_files.id`, a `book_placements.id`, …).
  final String? rowId;

  /// Data-dir-relative path, for the blob-level defects.
  final String? path;

  /// Bytes reclaimable, for orphan blobs — "delete 4 files" is a worse question
  /// than "reclaim 812 MB".
  final int sizeBytes;
}

/// The result of a scan: defects grouped by kind, plus what it looked at.
class DoctorReport {
  DoctorReport({required this.defects, required this.checkedBlobs});

  final List<Defect> defects;
  final int checkedBlobs;

  /// Whether the library's *integrity* is sound: the database and the file
  /// tree agree.
  ///
  /// Deliberately blind to the advisory findings. Most real libraries always
  /// have some — a book with no year, two editions of the same title kept on
  /// purpose — and folding those in would mean the check never once said
  /// "everything checks out", which would train you to ignore it. A missing
  /// year is not damage.
  bool get isHealthy => defects.every((d) => !d.kind.isRepairable);

  List<Defect> of(DefectKind kind) =>
      [for (final d in defects) if (d.kind == kind) d];

  Map<DefectKind, int> get counts {
    final out = <DefectKind, int>{};
    for (final d in defects) {
      out[d.kind] = (out[d.kind] ?? 0) + 1;
    }
    return out;
  }

  /// The counts, split the way the screen shows them: things to fix, and
  /// things merely worth knowing.
  Map<DefectKind, int> get repairableCounts => {
        for (final e in counts.entries)
          if (e.key.isRepairable) e.key: e.value,
      };

  Map<DefectKind, int> get adviceCounts => {
        for (final e in counts.entries)
          if (!e.key.isRepairable) e.key: e.value,
      };

  /// Bytes recoverable by deleting every orphan blob.
  int get reclaimableBytes => of(DefectKind.orphanBlob)
      .fold(0, (sum, d) => sum + d.sizeBytes);
}

/// Finds and repairs inconsistencies between the database and the file store
/// (plan 5 #11).
///
/// The library is a database *plus* a file tree, and they can diverge: a file
/// deleted by hand, a partial restore, a failed import leaving bytes nobody
/// references. None of it is detected today, and the shelf hides the loss — a
/// book whose cover vanished just draws a generated spine.
///
/// Two rules, both load-bearing:
///
/// - **Read-only by default.** [scan] never writes. Every repair is a separate,
///   explicit call, and the destructive ones say so ([DefectKind.isDestructive]).
/// - **Cancellable.** A scan stats every blob, so on a large library it is slow;
///   [isCancelled] is polled between items and a cancelled scan simply returns
///   what it found so far.
class LibraryDoctor {
  LibraryDoctor(this.repository);

  final LibraryRepository repository;

  VellumDatabase get _db => repository.db;
  Directory get _dataDir => repository.dataDir;

  /// Tombstones older than this with no server configured are pointless: there
  /// is nothing left to tell about the delete.
  static const staleTombstoneAge = Duration(days: 90);

  /// Looks for every kind of defect without changing anything.
  ///
  /// [hasServer] suppresses the stale-tombstone check when a server *is*
  /// configured — there, an old tombstone is simply one that hasn't synced yet,
  /// and pruning it would resurrect a deleted book on the next pull.
  Future<DoctorReport> scan({
    bool hasServer = false,
    DateTime? now,
    Future<bool> Function()? isCancelled,
  }) async {
    final defects = <Defect>[];
    var checkedBlobs = 0;
    final db = _db;

    final books = await db.select(db.books).get();
    final titles = {for (final b in books) b.id: b.title};

    // ---- files: rows whose bytes are gone, and duplicates ----
    final files = await db.select(db.bookFiles).get();
    final referenced = <String>{};
    final seenHashes = <String, String>{}; // "bookId|sha256" -> first row id
    for (final file in files) {
      if (await isCancelled?.call() ?? false) {
        return DoctorReport(defects: defects, checkedBlobs: checkedBlobs);
      }
      referenced.add(p.normalize(file.path));
      final onDisk = File(p.join(_dataDir.path, file.path));
      checkedBlobs++;
      if (!await onDisk.exists()) {
        defects.add(Defect(
          kind: DefectKind.missingFile,
          description: '${titles[file.bookId] ?? file.bookId} — ${file.path}',
          bookId: file.bookId,
          rowId: file.id,
          path: file.path,
        ));
        continue;
      }
      final key = '${file.bookId}|${file.sha256}';
      final first = seenHashes[key];
      if (first == null) {
        seenHashes[key] = file.id;
      } else {
        defects.add(Defect(
          kind: DefectKind.duplicateFileRow,
          description:
              '${titles[file.bookId] ?? file.bookId} — ${file.path} duplicates '
              'the same content',
          bookId: file.bookId,
          rowId: file.id,
          path: file.path,
        ));
      }
    }

    // ---- covers: a cover_path pointing at nothing ----
    for (final book in books) {
      if (await isCancelled?.call() ?? false) {
        return DoctorReport(defects: defects, checkedBlobs: checkedBlobs);
      }
      final rel = book.coverPath;
      if (rel == null || rel.isEmpty) continue;
      referenced.add(p.normalize(rel));
      checkedBlobs++;
      if (!await File(p.join(_dataDir.path, rel)).exists()) {
        defects.add(Defect(
          kind: DefectKind.missingCover,
          description: '${book.title} — $rel',
          bookId: book.id,
          path: rel,
        ));
      }
    }

    // ---- advisory: things only a person can decide ----
    //
    // Trashed books are on their way out, and a wishlist entry is a book you do
    // not own yet — neither is missing a cover or an author in any sense worth
    // reporting. Filtering here rather than in the checks below keeps the three
    // of them agreeing about what counts as a book.
    final live = [
      for (final b in books)
        if (b.deletedAt == null && b.status != 'wishlist') b,
    ];

    final authorsByBook = <String, List<String>>{};
    for (final row in await (_db.select(_db.bookAuthors).join([
      innerJoin(_db.authors, _db.authors.id.equalsExp(_db.bookAuthors.authorId)),
    ])
          ..orderBy([OrderingTerm.asc(_db.bookAuthors.position)]))
        .get()) {
      (authorsByBook[row.readTable(_db.bookAuthors).bookId] ??= [])
          .add(row.readTable(_db.authors).name);
    }

    // Books that look like the same book. The rules are `import_plan`'s, on
    // purpose: the importer already decides what "probably the same book" means
    // when it warns you before an import, and a health check that disagreed
    // with it would be telling you two different stories about one library.
    final byKey = <String, List<Book>>{};
    for (final book in live) {
      final isbn = normalizeIsbn(book.isbn);
      final key = isbn != null
          ? 'isbn:$isbn'
          // No ISBN: title plus first author, both normalised. Title alone is
          // too eager — "Selected Poems" is a dozen different books.
          : 'ta:${normalizeForMatch(book.title)}|'
              '${normalizeForMatch((authorsByBook[book.id] ?? const []).firstOrNull ?? '')}';
      // A book with neither an ISBN nor an author has nothing to match on;
      // grouping those by bare title would flag every untitled import.
      if (key == 'ta:${normalizeForMatch(book.title)}|' &&
          (authorsByBook[book.id] ?? const []).isEmpty) {
        continue;
      }
      (byKey[key] ??= []).add(book);
    }
    for (final group in byKey.values) {
      if (group.length < 2) continue;
      defects.add(Defect(
        kind: DefectKind.duplicateBook,
        description: '${group.first.title} — ${group.length} entries',
        bookId: group.first.id,
      ));
    }

    for (final book in live) {
      if (book.coverPath == null || book.coverPath!.isEmpty) {
        defects.add(Defect(
          kind: DefectKind.noCover,
          description: book.title,
          bookId: book.id,
        ));
      }
      final missing = [
        if ((authorsByBook[book.id] ?? const []).isEmpty) 'author',
        if (book.publishedYear == null) 'year',
      ];
      if (missing.isNotEmpty) {
        defects.add(Defect(
          kind: DefectKind.incompleteMetadata,
          description: '${book.title} — no ${missing.join(', no ')}',
          bookId: book.id,
        ));
      }
    }

    // ---- blobs on disk nobody references ----
    for (final sub in ['covers', 'files']) {
      final dir = Directory(p.join(_dataDir.path, sub));
      if (!await dir.exists()) continue;
      await for (final entry in dir.list()) {
        if (await isCancelled?.call() ?? false) {
          return DoctorReport(defects: defects, checkedBlobs: checkedBlobs);
        }
        if (entry is! File) continue;
        // `.part` leftovers are swept at startup and are not the doctor's
        // business; a hidden snapshot/staging file isn't either.
        final name = p.basename(entry.path);
        if (name.endsWith('.part') || name.startsWith('.')) continue;
        final rel = p.normalize(p.join(sub, name));
        checkedBlobs++;
        if (referenced.contains(rel)) continue;
        var size = 0;
        try {
          size = await entry.length();
        } catch (_) {
          // Unreadable: still an orphan, just of unknown size.
        }
        defects.add(Defect(
          kind: DefectKind.orphanBlob,
          description: rel,
          path: rel,
          sizeBytes: size,
        ));
      }
    }

    // ---- placements whose copy (or its book) is gone ----
    final placements = await db.select(db.bookPlacements).get();
    final copyIds = {
      for (final c in await db.select(db.physicalCopies).get()) c.id,
    };
    for (final placement in placements) {
      if (!copyIds.contains(placement.copyId)) {
        defects.add(Defect(
          kind: DefectKind.danglingPlacement,
          description: 'A placement in the physical layout with no copy behind it',
          rowId: placement.id,
        ));
      }
    }

    // ---- tombstones nobody will ever be told about ----
    if (!hasServer) {
      final cutoff = (now ?? DateTime.now()).subtract(staleTombstoneAge);
      for (final tombstone in await db.select(db.localDeletions).get()) {
        if (tombstone.deletedAt.isBefore(cutoff)) {
          defects.add(Defect(
            kind: DefectKind.staleTombstone,
            description: '${tombstone.kind} ${tombstone.bookId}, deleted '
                '${tombstone.deletedAt.toLocal().toString().split(' ').first}',
            rowId: tombstone.bookId,
          ));
        }
      }
    }

    return DoctorReport(defects: defects, checkedBlobs: checkedBlobs);
  }

  /// Applies the repair for [defect]. Returns whether anything changed.
  ///
  /// One defect at a time on purpose: the UI repairs a whole category by looping,
  /// which keeps a partial failure partial instead of aborting the rest.
  Future<bool> repair(Defect defect) async {
    final db = _db;
    switch (defect.kind) {
      case DefectKind.missingFile:
      case DefectKind.duplicateFileRow:
        final id = defect.rowId;
        if (id == null) return false;
        final removed = await (db.delete(db.bookFiles)
              ..where((f) => f.id.equals(id)))
            .go();
        // The book's file list changed, which is synced data.
        final bookId = defect.bookId;
        if (removed > 0 && bookId != null) {
          await (db.update(db.books)..where((b) => b.id.equals(bookId)))
              .write(const BooksCompanion(needsPush: Value(true)));
        }
        return removed > 0;

      case DefectKind.missingCover:
        final bookId = defect.bookId;
        if (bookId == null) return false;
        // Clear the pointer rather than inventing a cover: the shelf then draws
        // a generated spine, and the user can set a real one.
        await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
          const BooksCompanion(
            coverPath: Value(null),
            coverEtag: Value(null),
            needsPush: Value(true),
          ),
        );
        return true;

      case DefectKind.orphanBlob:
        final rel = defect.path;
        if (rel == null) return false;
        final file = File(p.join(_dataDir.path, rel));
        if (!await file.exists()) return false;
        await file.delete();
        return true;

      case DefectKind.danglingPlacement:
        final id = defect.rowId;
        if (id == null) return false;
        return await (db.delete(db.bookPlacements)
                  ..where((pl) => pl.id.equals(id)))
                .go() >
            0;

      case DefectKind.staleTombstone:
        final id = defect.rowId;
        if (id == null) return false;
        return await (db.delete(db.localDeletions)
                  ..where((t) => t.bookId.equals(id)))
                .go() >
            0;
      case DefectKind.duplicateBook:
      case DefectKind.noCover:
      case DefectKind.incompleteMetadata:
        // Advisory — see `DefectKind.isRepairable`. Listed rather than left to
        // a `default:` so that adding a kind is a compile error here, which is
        // how the other six stay honest about having a repair.
        return false;
    }
  }

  /// Repairs every defect of one kind, returning how many succeeded.
  Future<int> repairAll(
    Iterable<Defect> defects, {
    Future<bool> Function()? isCancelled,
  }) async {
    var fixed = 0;
    for (final defect in defects) {
      if (await isCancelled?.call() ?? false) break;
      try {
        if (await repair(defect)) fixed++;
      } catch (_) {
        // One stubborn file (locked, permissions) must not stop the rest.
      }
    }
    return fixed;
  }
}
