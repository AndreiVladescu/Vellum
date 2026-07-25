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
  Future<void> attachFile(String bookId, String sourcePath) async {
    final source = File(sourcePath);
    final ext = p.extension(sourcePath).replaceFirst('.', '').toLowerCase();
    final id = _uuid.v4();
    final relPath = p.join('files', '$id.$ext');
    await source.copy(p.join(_dataDir.path, relPath));
    final digest = await sha256.bind(source.openRead()).first;
    await db
        .into(db.bookFiles)
        .insert(
          BookFilesCompanion.insert(
            id: id,
            bookId: bookId,
            format: ext.isEmpty ? 'unknown' : ext,
            path: relPath,
            sizeBytes: await source.length(),
            sha256: digest.toString(),
          ),
        );
    // A new file is synced data, so the book needs pushing (setCoverFromEmbedded
    // below also marks it, but a cover-having book wouldn't).
    await _markNeedsPush(bookId);
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
