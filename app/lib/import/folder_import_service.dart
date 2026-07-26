import 'dart:async';
import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart' show Value;

import '../data/database.dart';
import '../data/library_repository.dart';
import 'filename_metadata.dart';
import 'import_plan.dart';

/// Collects the single digest a chunked hash conversion emits.
class _DigestSink implements Sink<Digest> {
  Digest? value;

  @override
  void add(Digest data) => value = data;

  @override
  void close() {}
}

/// sha256 of a file, read in bounded chunks.
///
/// Deliberately `RandomAccessFile` + a chunked digest rather than
/// `sha256.bind(file.openRead())`: a folder import hashes every file up front,
/// so memory has to stay flat over a 500 MB PDF, and plain future-based reads
/// also mean the scan can be driven to completion in a widget test (a stream's
/// events never arrive under `testWidgets`' fake async).
Future<String> sha256OfFile(File file, {int chunkSize = 64 * 1024}) async {
  final sink = _DigestSink();
  final hasher = sha256.startChunkedConversion(sink);
  final handle = await file.open();
  try {
    final buffer = Uint8List(chunkSize);
    while (true) {
      final read = await handle.readInto(buffer);
      if (read == 0) break;
      hasher.add(read == chunkSize ? buffer : Uint8List.sublistView(buffer, 0, read));
    }
  } finally {
    await handle.close();
  }
  hasher.close();
  return sink.value!.toString();
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
    final books = await db.select(db.books).get();
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
  }) async {
    final files = await findImportableFiles(root);
    final library = await libraryFingerprint();
    final candidates = <ImportCandidate>[];
    for (var i = 0; i < files.length; i++) {
      if (await isCancelled?.call() ?? false) break;
      final file = files[i];
      onProgress?.call(i, files.length, filenameStem(file.path));
      String? hash;
      String? error;
      var size = 0;
      try {
        // Every step here awaits real file I/O, which yields to the event loop
        // on its own — so the progress callback above stays responsive without
        // an artificial `Duration.zero` yield per file.
        size = await file.length();
        hash = await sha256OfFile(file);
      } catch (e) {
        error = '$e';
      }
      candidates.add(classify(
        path: file.path,
        sizeBytes: size,
        format: _formatOf(file.path),
        sha256: hash,
        library: library,
        error: error,
      ));
    }
    onProgress?.call(files.length, files.length, '');
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
  Future<ImportReport> import(
    List<ImportCandidate> candidates, {
    ImportProgress? onProgress,
    Future<bool> Function()? isCancelled,
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
        final bookId = await repository.createCustomBook(
          title: c.meta.title ?? filenameStem(c.path),
          author: c.meta.authors.isEmpty ? null : c.meta.authors.join(', '),
          publishedYear: c.meta.year,
        );
        if (c.meta.publisher != null) {
          await (repository.db.update(repository.db.books)
                ..where((b) => b.id.equals(bookId)))
              .write(BooksCompanion(publisher: Value(c.meta.publisher)));
        }
        await repository.attachFile(bookId, c.path);
        outcomes.add(ImportOutcome(path: c.path, bookId: bookId));
      } catch (e) {
        outcomes.add(ImportOutcome(path: c.path, error: '$e'));
      }
    }
    onProgress?.call(candidates.length, candidates.length, '');
    return ImportReport(outcomes: outcomes, cancelled: cancelled);
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
