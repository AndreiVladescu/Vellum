import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart' show Value;

import '../data/background_work.dart';
import '../data/database.dart';
import '../data/file_hash.dart';
import '../data/library_repository.dart';
import 'catalog_entry.dart';
import 'filename_metadata.dart';
import 'import_plan.dart';

/// Runs [task] for every index below [count], [backgroundSlots] at a time,
/// and returns what they made in index order (performance round #8).
///
/// A scan used to hash one file at a time on the UI isolate: seconds of frames
/// held up per big PDF, and one core doing what four could. Each task's hash
/// now runs in a background isolate, several at once.
///
/// Stops handing out work once [isCancelled] says so — checked as each task
/// starts *and* as it finishes, because with several in flight a cancel lands
/// while some are still hashing, and a cancelled scan should stop at what it
/// had then rather than finish them all and report everything.
Future<List<T>> _inParallel<T extends Object>(
  int count,
  Future<T> Function(int index) task, {
  Future<bool> Function()? isCancelled,
  void Function(int done, int index)? onDone,
}) async {
  final results = List<T?>.filled(count, null);
  var next = 0;
  var done = 0;
  var cancelled = false;
  Future<bool> stopping() async =>
      cancelled = cancelled || (await isCancelled?.call() ?? false);

  Future<void> worker() async {
    while (true) {
      // Claimed before any await: checking `next < count` and then awaiting
      // would let another worker take the last index in between.
      final i = next++;
      if (i >= count || await stopping()) return;
      final result = await task(i);
      if (await stopping()) return;
      results[i] = result;
      onDone?.call(++done, i);
    }
  }

  await Future.wait([for (var w = 0; w < backgroundSlots; w++) worker()]);
  return [for (final r in results) ?r];
}

/// Progress of a scan or an import: [done] of [total], naming the current file.
typedef ImportProgress = void Function(int done, int total, String label);

/// What happened to one file during the import itself.
class ImportOutcome {
  ImportOutcome({required this.path, this.bookId, this.error});

  final String path;

  /// The book created for this file, or null when it failed.
  final String? bookId;
  final String? error;

  bool get failed => error != null;
}

/// The result of running an import: the successes, the failures, and whether the
/// user cancelled partway.
class ImportReport {
  ImportReport({required this.outcomes, required this.cancelled});

  final List<ImportOutcome> outcomes;
  final bool cancelled;

  int get imported => outcomes.where((o) => !o.failed).length;
  List<ImportOutcome> get failures =>
      [for (final o in outcomes) if (o.failed) o];
}

/// Bulk folder import (plan 5 #15): scan a folder into a reviewable plan, then
/// execute the rows the user kept.
///
/// Split from the UI so the two halves are testable without a widget tree, and
/// so the scan (slow, cancellable, all I/O) never runs inside a build.
class FolderImportService {
  FolderImportService(this.repository);

  final LibraryRepository repository;

  /// Extensions the library can actually open. Anything else in the folder is
  /// ignored outright rather than imported as an unreadable "book".
  static const supportedFormats = {'pdf', 'epub'};

  /// Recursively lists importable files under [root], newest-first by name so
  /// the dry-run table has a stable order.
  ///
  /// Symlinks are **not** followed: a folder of downloads can contain a link to
  /// a parent directory, and following it turns a scan into an infinite walk.
  Future<List<File>> findImportableFiles(Directory root) async {
    final found = <File>[];
    await for (final entry in root.list(recursive: true, followLinks: false)) {
      if (entry is! File) continue;
      final ext = _formatOf(entry.path);
      if (supportedFormats.contains(ext)) found.add(entry);
    }
    found.sort((a, b) => a.path.compareTo(b.path));
    return found;
  }

  static String _formatOf(String path) {
    final dot = path.lastIndexOf('.');
    if (dot < 0) return '';
    return path.substring(dot + 1).toLowerCase();
  }

  /// A fingerprint of the current library, for duplicate detection.
  Future<List<LibraryFingerprint>> libraryFingerprint() async {
    final db = repository.db;
    // Live books only: a book you trashed must not make its own file look like
    // a duplicate, or re-importing it is silently skipped and the only way back
    // is the trash screen.
    final books = await (db.select(db.books)
          ..where((b) => b.deletedAt.isNull()))
        .get();
    final files = await db.select(db.bookFiles).get();
    final hashes = <String, Set<String>>{};
    for (final f in files) {
      hashes.putIfAbsent(f.bookId, () => {}).add(f.sha256);
    }
    final authorsByBook = await repository.queries.watchAuthorsByBook().first;
    return [
      for (final b in books)
        LibraryFingerprint(
          bookId: b.id,
          title: b.title,
          isbn: b.isbn,
          authors: authorsByBook[b.id] ?? const [],
          fileHashes: hashes[b.id] ?? const {},
        ),
    ];
  }

  /// Hashes and classifies every file under [root], without writing anything.
  ///
  /// Hashing is the slow part (it reads every byte), which is exactly why it
  /// happens here rather than during the import: the user gets a truthful
  /// "duplicate" verdict *before* committing, and the import that follows is
  /// then only as slow as the copying.
  Future<List<ImportCandidate>> scan(
    Directory root, {
    ImportProgress? onProgress,
    Future<bool> Function()? isCancelled,
  }) async =>
      scanFiles(
        await findImportableFiles(root),
        onProgress: onProgress,
        isCancelled: isCancelled,
      );

  /// The same dry run over an explicit list of files rather than a folder — what
  /// a multi-file share hands over (plan 5 #20), which has paths but no folder.
  /// Unsupported formats are dropped here too: a share sheet will offer Vellum
  /// anything once the user has picked it.
  Future<List<ImportCandidate>> scanFiles(
    List<File> requested, {
    ImportProgress? onProgress,
    Future<bool> Function()? isCancelled,
  }) async {
    final files = [
      for (final f in requested)
        if (supportedFormats.contains(_formatOf(f.path))) f,
    ];
    final library = await libraryFingerprint();
    onProgress?.call(0, files.length, '');
    final candidates = await _inParallel(
      files.length,
      isCancelled: isCancelled,
      onDone: (done, i) =>
          onProgress?.call(done, files.length, filenameStem(files[i].path)),
      (i) async {
        final file = files[i];
        String? hash;
        String? error;
        var size = 0;
        try {
          size = await file.length();
          hash = await sha256OfFileInBackground(file.path);
        } catch (e) {
          error = '$e';
        }
        return classify(
          path: file.path,
          sizeBytes: size,
          format: _formatOf(file.path),
          sha256: hash,
          library: library,
          error: error,
        );
      },
    );
    onProgress?.call(files.length, files.length, '');
    return candidates;
  }

  /// The dry run over rows from an external catalogue (plan 5 #21c).
  ///
  /// Same duplicate check and same review table as a folder scan — that is the
  /// point of converging on [CatalogEntry] first. Entries that bring a file are
  /// hashed (so re-importing a Calibre library you already imported reports
  /// duplicates rather than doubling it); metadata-only entries skip straight
  /// to the title/author/ISBN heuristics, which is all there is to go on.
  Future<List<ImportCandidate>> scanEntries(
    List<CatalogEntry> entries, {
    ImportProgress? onProgress,
    Future<bool> Function()? isCancelled,
  }) async {
    final library = await libraryFingerprint();
    onProgress?.call(0, entries.length, '');
    final candidates = await _inParallel(
      entries.length,
      isCancelled: isCancelled,
      onDone: (done, i) =>
          onProgress?.call(done, entries.length, entries[i].title),
      (i) async {
        final entry = entries[i];
        String? hash;
        String? error;
        var size = 0;
        final path = entry.filePath;
        if (path != null) {
          try {
            size = await File(path).length();
            hash = await sha256OfFileInBackground(path);
          } catch (e) {
            // The catalogue names a file that isn't there — a moved Calibre
            // library, most often. Say so on the row rather than dropping it.
            error = 'file not readable: $e';
          }
        } else {
          // Nothing to read, so nothing to yield to; keep the progress callback
          // responsive over a long metadata-only import.
          await Future<void>.delayed(Duration.zero);
        }
        return classify(
          path: path ?? entry.title,
          sizeBytes: size,
          format: path == null ? '' : _formatOf(path),
          sha256: hash,
          library: library,
          entry: entry,
          error: error,
        );
      },
    );
    onProgress?.call(entries.length, entries.length, '');
    return candidates;
  }

  /// Creates a book per candidate and attaches its file.
  ///
  /// Each row is independent: a failure is recorded and the run continues, the
  /// same contract sync uses for a per-book issue. The file copy itself is
  /// atomic (plan 5 #14), so a cancelled or failed row leaves no half-written
  /// file behind. Metadata comes from the file name only — the online lookup is
  /// a separate, resumable pass (see [enrich]), so importing 500 books doesn't
  /// depend on 500 network calls succeeding.
  /// Imports [candidates], optionally putting every one of them on [shelfId].
  ///
  /// The shelf is the one that was open when the import was started. A bulk
  /// import is the one place where that could genuinely surprise someone — 500
  /// books landing on a shelf they had forgotten was selected — so the review
  /// step says where they are going before anything is written.
  Future<ImportReport> import(
    List<ImportCandidate> candidates, {
    ImportProgress? onProgress,
    Future<bool> Function()? isCancelled,
    String? shelfId,
  }) async {
    final outcomes = <ImportOutcome>[];
    var cancelled = false;
    for (var i = 0; i < candidates.length; i++) {
      if (await isCancelled?.call() ?? false) {
        cancelled = true;
        break;
      }
      final c = candidates[i];
      onProgress?.call(i, candidates.length, c.meta.title ?? filenameStem(c.path));
      try {
        final bookId = await _createBook(c);
        // A catalogue row may bring no file at all (a CSV export describes
        // books whose bytes live elsewhere); that is a complete import, not a
        // failure, so the attach is conditional rather than assumed.
        final file = c.entry?.filePath ?? (c.entry == null ? c.path : null);
        if (file != null) await repository.attachFile(bookId, file);
        final cover = c.entry?.coverPath;
        if (cover != null) {
          try {
            await repository.setCoverFromFile(bookId, cover);
          } catch (_) {
            // A missing or unreadable cover must not lose the book.
          }
        }
        if (shelfId != null) await repository.addToShelf(bookId, shelfId);
        outcomes.add(ImportOutcome(path: c.path, bookId: bookId));
      } catch (e) {
        outcomes.add(ImportOutcome(path: c.path, error: '$e'));
      }
    }
    onProgress?.call(candidates.length, candidates.length, '');
    return ImportReport(outcomes: outcomes, cancelled: cancelled);
  }

  /// Creates the book row for one candidate.
  ///
  /// A catalogue entry (plan 5 #21c) states far more than a file name can
  /// guess, so everything it carries is written: ISBN and description make the
  /// book immediately useful without an online lookup, and series and genres
  /// are the two things a Calibre user would most notice losing.
  Future<String> _createBook(ImportCandidate c) async {
    final entry = c.entry;
    final db = repository.db;
    final bookId = await repository.createCustomBook(
      title: entry?.title ?? c.meta.title ?? filenameStem(c.path),
      author: (entry?.authors ?? c.meta.authors).isEmpty
          ? null
          : (entry?.authors ?? c.meta.authors).join(', '),
      publishedYear: entry?.year ?? c.meta.year,
      description: entry?.description,
    );
    final publisher = entry?.publisher ?? c.meta.publisher;
    if (publisher != null || entry != null) {
      await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
        BooksCompanion(
          publisher: Value(publisher),
          subtitle: Value(entry?.subtitle),
          isbn: Value(entry?.isbn),
          pageCount: Value(entry?.pageCount),
        ),
      );
    }
    if (entry != null) {
      if (entry.genres.isNotEmpty) {
        await repository.setGenres(bookId, entry.genres);
      }
      final series = entry.series;
      if (series != null && series.trim().isNotEmpty) {
        await repository.seriesService
            .setSeries(bookId, series, entry.seriesIndex);
      }
      await _applyPersonal(bookId, entry);
    }
    return bookId;
  }

  /// Carries across what a reading tracker's export says *you* thought.
  ///
  /// Written straight to the row rather than through the edit paths because
  /// this is an import: there is no prior value to conflict with, and marking
  /// four hundred freshly created books as needing a push for a rating they
  /// were born with would be noise. The review is the exception — see below.
  Future<void> _applyPersonal(String bookId, CatalogEntry entry) async {
    final db = repository.db;
    final hasAny = entry.status != null ||
        entry.rating != null ||
        entry.finishedAt != null ||
        entry.readCount != null;
    if (hasAny) {
      await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
        BooksCompanion(
          status: entry.status == null ? const Value.absent() : Value(entry.status!),
          rating: Value(entry.rating),
          finishedAt: Value(entry.finishedAt),
          readCount: entry.readCount == null
              ? const Value.absent()
              : Value(entry.readCount!),
          // A book the export says you finished, with no progress recorded
          // here, is at the end of it — otherwise "finished" and a progress
          // bar at 0% would contradict each other on the book's own page.
          readingProgress:
              entry.status == 'finished' ? const Value(1.0) : const Value.absent(),
        ),
      );
    }
    final review = entry.review?.trim();
    if (review != null && review.isNotEmpty) {
      // Through `setReaderNotes`, not the companion above: a review belongs to
      // the *person*, and that path is what sets `readerNotesUpdatedAt` and
      // `readerNotesNeedsPush` so it travels on the per-user channel instead of
      // the shared book row. Importing straight onto the row would publish your
      // reviews to everyone the library is shared with.
      await repository.setReaderNotes(bookId, review);
    }
  }

  /// Fills in online metadata for books imported from file names, one at a time
  /// with a pause between lookups.
  ///
  /// Resumable and interruptible by design: it works from the *current* list of
  /// candidates each time it runs, and a book that already has a description is
  /// left alone, so re-running after a cancel or a dropped connection picks up
  /// where it stopped. Rate-limited to one request at a time because Open
  /// Library is a free service and a 500-book import must not look like abuse.
  Future<int> enrich(
    List<String> bookIds, {
    Duration delay = const Duration(milliseconds: 400),
    ImportProgress? onProgress,
    Future<bool> Function()? isCancelled,
  }) async {
    var enriched = 0;
    for (var i = 0; i < bookIds.length; i++) {
      if (await isCancelled?.call() ?? false) break;
      final book = await repository.watchBook(bookIds[i]).first;
      if (book == null) continue;
      onProgress?.call(i, bookIds.length, book.title);
      // Already enriched (by an earlier run, or by hand): skip, don't re-fetch.
      if (book.description != null && book.description!.isNotEmpty) continue;
      try {
        // Title plus whatever authors the file name gave us: Open Library
        // matches an author+title query far better than a bare title.
        final authors = (await repository.detailsFor(book.id)).authors;
        final query = [book.title, ...authors.take(1)].join(' ');
        final results = await repository.metadata.search(query);
        if (results.isEmpty) continue;
        await repository.enrichFromSearch(book.id, results.first);
        enriched++;
      } catch (_) {
        // Offline or no match — the book keeps its file-name metadata, and a
        // later run will try again.
      }
      if (i < bookIds.length - 1) await Future<void>.delayed(delay);
    }
    onProgress?.call(bookIds.length, bookIds.length, '');
    return enriched;
  }
}
