import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/scheduler.dart';
import 'package:path/path.dart' as p;

import '../reader/epub_book.dart';
import '../shelf/cover_color.dart';
import '../shelf/spine_style.dart';
import 'database.dart';
import 'pdf_cover.dart';

/// Cover bytes/files, embedded-cover extraction, and the dominant-colour
/// backfill. Split out of `LibraryRepository` (plan 5 §A10).
class CoverService {
  CoverService(this.db, this._dataDir);

  final VellumDatabase db;
  final Directory _dataDir;

  /// Absolute file for a book's cover, or null if it has none.
  File? coverFileOf(Book book) => book.coverPath == null
      ? null
      : File(p.join(_dataDir.path, book.coverPath!));

  /// Replaces a book's cover from raw image bytes. Also extracts the cover's
  /// dominant colour into the spine style, for the "Dominant colour" spine
  /// preference.
  Future<void> setCoverBytes(String bookId, Uint8List bytes) async {
    final rel = p.join('covers', '$bookId.jpg');
    await File(p.join(_dataDir.path, rel)).writeAsBytes(bytes);
    await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(
        coverPath: Value(rel),
        updatedAt: Value(DateTime.now()),
        needsPush: const Value(true),
      ),
    );
    await updateCoverColor(bookId, bytes);
  }

  /// Stores the dominant colour of [coverBytes] in the book's spine style.
  /// Purely cosmetic and device-derivable, so it deliberately does NOT bump
  /// the sync clock or the dirty flag. A no-op when the bytes don't decode.
  Future<void> updateCoverColor(String bookId, Uint8List coverBytes) async {
    final color = await dominantColorOf(coverBytes);
    if (color == null) return;
    final row = await (db.select(
      db.books,
    )..where((b) => b.id.equals(bookId))).getSingleOrNull();
    if (row == null) return;
    final style = SpineStyle.fromJson(row.spineStyle, title: row.title)
        .withCoverColor(color);
    await (db.update(db.books)..where((b) => b.id.equals(bookId))).write(
      BooksCompanion(spineStyle: Value(style.toJson())),
    );
  }

  /// How many covers the startup colour backfill decodes before yielding a
  /// frame. Small enough that a cold sweep of a large library can't monopolise
  /// the UI isolate; large enough that the sweep still finishes promptly.
  static const _colorBackfillBatch = 8;

  /// One-time catch-up for covers that predate dominant-colour extraction:
  /// computes and stores the colour for every covered book whose spine style
  /// lacks one. Cheap when there's nothing to do; run fire-and-forget at
  /// startup.
  ///
  /// The decode (`dominantColorOf`) needs the UI isolate's image codecs, so it
  /// can't move to a background isolate; instead the sweep yields to the frame
  /// scheduler every [_colorBackfillBatch] covers, so a cold first launch on a
  /// large library stays responsive (each decode also re-emits the shelf
  /// stream — batching per frame coalesces those rebuilds too).
  Future<void> backfillCoverColors() async {
    final rows = await (db.select(
      db.books,
    )..where((b) => b.coverPath.isNotNull())).get();
    var sinceYield = 0;
    for (final row in rows) {
      final style = SpineStyle.fromJson(row.spineStyle, title: row.title);
      if (style.coverColor != null) continue;
      final cover = coverFileOf(row);
      if (cover == null || !await cover.exists()) continue;
      try {
        await updateCoverColor(row.id, await cover.readAsBytes());
      } catch (_) {
        // A single unreadable cover shouldn't stop the sweep.
      }
      if (++sinceYield >= _colorBackfillBatch) {
        sinceYield = 0;
        await SchedulerBinding.instance.endOfFrame;
      }
    }
  }

  Future<void> setCoverFromFile(String bookId, String sourcePath) async =>
      setCoverBytes(bookId, await File(sourcePath).readAsBytes());

  /// Derives a cover from the book's own attached files, no network needed: a
  /// PDF's rendered first page, else an EPUB's declared cover image. Returns
  /// false when neither is available or extraction fails.
  Future<bool> setCoverFromEmbedded(String bookId) async {
    if (await setCoverFromFirstPage(bookId)) return true;
    return setCoverFromEpub(bookId);
  }

  /// Renders the first page of one of the book's attached PDFs and uses it as
  /// the cover. Returns false if the book has no PDF or rendering fails.
  Future<bool> setCoverFromFirstPage(String bookId) async {
    final files = await (db.select(
      db.bookFiles,
    )..where((f) => f.bookId.equals(bookId) & f.format.equals('pdf'))).get();
    if (files.isEmpty) return false;
    final png = await renderPdfFirstPagePng(
      p.join(_dataDir.path, files.first.path),
    );
    if (png == null) return false;
    await setCoverBytes(bookId, png);
    return true;
  }

  /// Extracts the declared cover image from one of the book's attached EPUBs
  /// (a plain zip read, no renderer) and uses it. Returns false if the book has
  /// no EPUB, the EPUB declares no cover, or extraction fails.
  Future<bool> setCoverFromEpub(String bookId) async {
    final files = await (db.select(
      db.bookFiles,
    )..where((f) => f.bookId.equals(bookId) & f.format.equals('epub'))).get();
    if (files.isEmpty) return false;
    try {
      final bytes = await EpubBook.coverBytes(
        File(p.join(_dataDir.path, files.first.path)),
      );
      if (bytes == null) return false;
      await setCoverBytes(bookId, bytes);
      return true;
    } catch (_) {
      return false;
    }
  }
}
