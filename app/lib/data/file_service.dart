import 'dart:io';

import 'package:crypto/crypto.dart';
import 'package:drift/drift.dart';
import 'package:path/path.dart' as p;
import 'package:uuid/uuid.dart';

import '../reader/epub_book.dart';
import 'cover_service.dart';
import 'database.dart';
import 'pdf_cover.dart';

/// Attaching/detaching digital files, hashing, and page count. Split out of
/// `LibraryRepository` (plan 5 §A10). Depends on [CoverService] because
/// attaching the first PDF/EPUB to a coverless book derives a cover from it.
class FileService {
  FileService(this.db, this._dataDir, this._covers);

  final VellumDatabase db;
  final Directory _dataDir;
  final CoverService _covers;

  static const _uuid = Uuid();

  Stream<List<BookFile>> watchFilesOf(String bookId) =>
      (db.select(db.bookFiles)..where((f) => f.bookId.equals(bookId))).watch();

  /// Absolute file for an attached digital copy.
  File fileOf(BookFile file) => File(p.join(_dataDir.path, file.path));

  /// Copies a picked file into the library store and records it.
  ///
  /// Atomic in both directions (plan 5 #14). The bytes land in
  /// `files/<id>.<fmt>.part` and are flushed to disk before being renamed into
  /// place, so a crash or a full disk can never leave a *complete-looking* file
  /// that is actually truncated; and the row is written in a transaction whose
  /// failure unlinks the blob again. The two orderings that would leave a mess —
  /// a row pointing at a partial file, or a blob no row knows about — are both
  /// unreachable. Stale `.part` files are swept at startup
  /// (`LibraryRepository._withDataDir`), which covers a crash mid-copy.
  Future<void> attachFile(String bookId, String sourcePath) async {
    final source = File(sourcePath);
    final ext = p.extension(sourcePath).replaceFirst('.', '').toLowerCase();
    final id = _uuid.v4();
    final relPath = p.join('files', '$id.$ext');
    final dest = File(p.join(_dataDir.path, relPath));
    final part = File('${dest.path}.part');

    try {
      await _copyAndFlush(source, part);
      await part.rename(dest.path);
    } catch (_) {
      await _deleteQuietly(part);
      rethrow; // Nothing was recorded, so there is nothing to roll back.
    }

    try {
      // Hash and size come from what actually landed, not from the source: a
      // short read or a full disk has to be caught here rather than recorded as
      // a valid file with a hash that no longer matches its bytes (which sync
      // dedupes on).
      final digest = await sha256.bind(dest.openRead()).first;
      final size = await dest.length();
      await db.transaction(() async {
        await db.into(db.bookFiles).insert(
              BookFilesCompanion.insert(
                id: id,
                bookId: bookId,
                format: ext.isEmpty ? 'unknown' : ext,
                path: relPath,
                sizeBytes: size,
                sha256: digest.toString(),
              ),
            );
        // A new file is synced data, so the book needs pushing
        // (setCoverFromEmbedded below also marks it, but a cover-having book
        // wouldn't). Inside the transaction: the row and the flag land together.
        await _markNeedsPush(bookId);
      });
    } catch (_) {
      // The transaction rolled back, so the blob is now an orphan — remove it.
      await _deleteQuietly(dest);
      rethrow;
    }
    // A newly attached EPUB invalidates any cached parse for this book.
    if (ext == 'epub') EpubBook.invalidateCache(bookId);
    // A cover-less book that just got a PDF or EPUB: derive a cover from it (the
    // PDF's first page, or the EPUB's declared cover image).
    if (ext == 'pdf' || ext == 'epub') {
      final book = await (db.select(
        db.books,
      )..where((b) => b.id.equals(bookId))).getSingleOrNull();
      if (book != null && book.coverPath == null) {
        await _covers.setCoverFromEmbedded(bookId);
      }
    }
  }

  /// The page count read from one of the book's attached PDFs, or null if it
  /// has no PDF or the file can't be read.
  Future<int?> pageCountFromFile(String bookId) async {
    final files = await (db.select(db.bookFiles)
          ..where((f) => f.bookId.equals(bookId) & f.format.equals('pdf')))
        .get();
    if (files.isEmpty) return null;
    try {
      return await pdfPageCount(p.join(_dataDir.path, files.first.path));
    } catch (_) {
      return null;
    }
  }

  /// Streams [source] into [dest] and **flushes it to disk** before returning.
  /// Streamed rather than `copy`d so a 500 MB PDF isn't buffered in memory, and
  /// flushed so the following rename publishes durable bytes.
  static Future<void> _copyAndFlush(File source, File dest) async {
    await dest.parent.create(recursive: true);
    final out = await dest.open(mode: FileMode.writeOnly);
    try {
      await for (final chunk in source.openRead()) {
        await out.writeFrom(chunk);
      }
      await out.flush();
    } finally {
      await out.close();
    }
  }

  /// Best-effort unlink for a file we're abandoning. A failure here can't be
  /// acted on (the caller is already unwinding) and the startup sweeper catches
  /// a leftover `.part` anyway.
  static Future<void> _deleteQuietly(File file) async {
    try {
      if (await file.exists()) await file.delete();
    } catch (_) {
      // Locked or already gone — nothing useful to do.
    }
  }

  /// Marks a book's synced data as changed since the last push, so the next
  /// sync uploads it. Local-only setters never call this.
  Future<void> _markNeedsPush(String bookId) async {
    await (db.update(
      db.books,
    )..where((b) => b.id.equals(bookId))).write(
      const BooksCompanion(needsPush: Value(true)),
    );
  }
}
