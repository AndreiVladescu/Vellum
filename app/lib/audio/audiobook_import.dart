import 'package:drift/drift.dart';

import '../data/background_work.dart';
import '../data/database.dart';
import '../data/file_service.dart';
import '../data/library_repository.dart';
import '../data/sync_clock.dart';
import 'audio_formats.dart';
import 'audiobook_scan.dart';

/// Turns scanned audio files into a book's audio parts (docs/AUDIOBOOKS.md §3).
///
/// Each part becomes a `book_files` row with its duration, order, label and
/// narrator; its chapter marks go into the derived `audio_chapters` table.
class AudiobookImporter {
  AudiobookImporter(this.repository);

  final LibraryRepository repository;

  VellumDatabase get _db => repository.db;

  /// Reads the files' tags, durations, chapters and cover off the UI isolate.
  Future<AudiobookScan> scan(List<String> paths) =>
      inBackground(() => scanAudiobook(paths));

  /// The book's audio parts, in playing order.
  Future<List<BookFile>> audioFilesOf(String bookId) async {
    final files = await (_db.select(_db.bookFiles)
          ..where((f) => f.bookId.equals(bookId)))
        .get();
    return orderAudioFiles(files);
  }

  /// Whether the book already has audio — importing more asks first, since a
  /// book has one audio edition in 1.5.
  Future<bool> hasAudio(String bookId) async =>
      (await audioFilesOf(bookId)).isNotEmpty;

  /// Creates a book from [scan] and attaches its parts. Returns the book id.
  Future<String> importAsNewBook(AudiobookScan scan, {bool localOnly = false}) async {
    final bookId = await repository.createCustomBook(
      title: scan.title,
      author: scan.author,
    );
    if (localOnly) {
      await (_db.update(_db.books)..where((b) => b.id.equals(bookId)))
          .write(const BooksCompanion(syncExcluded: Value(true)));
    }
    await attachTo(bookId, scan);
    return bookId;
  }

  /// Attaches [scan]'s parts to [bookId]. With [replace], the book's existing
  /// audio parts (and their chapters) are removed first, so it keeps one
  /// audio edition. Gives a cover-less book the audiobook's cover.
  Future<void> attachTo(String bookId, AudiobookScan scan, {bool replace = false}) async {
    if (replace) await removeAudio(bookId);
    for (var i = 0; i < scan.parts.length; i++) {
      final part = scan.parts[i];
      final fileId = await repository.files.attachFile(
        bookId,
        part.path,
        audio: AudioPartFields(
          track: i + 1,
          durationMs: part.durationMs,
          label: part.label,
          narrator: scan.narrator ?? part.narrator,
        ),
      );
      await _db.batch((b) {
        final chapters = AudiobookScan.chaptersOf(part);
        for (var c = 0; c < chapters.length; c++) {
          b.insert(
            _db.audioChapters,
            AudioChaptersCompanion.insert(
              fileId: fileId,
              idx: c,
              title: Value(chapters[c].title),
              startMs: chapters[c].startMs,
            ),
            mode: InsertMode.insertOrReplace,
          );
        }
      });
    }
    await repository.wishlist.noteAcquired(bookId);
    final cover = scan.cover;
    if (cover != null) {
      final book = await (_db.select(_db.books)..where((b) => b.id.equals(bookId)))
          .getSingleOrNull();
      if (book != null && book.coverPath == null) {
        try {
          await repository.setCoverBytes(bookId, cover);
        } catch (_) {
          // A cover that will not decode is cosmetic; the parts are in.
        }
      }
    }
  }

  /// Removes the book's audio parts: rows (chapters cascade) and blobs.
  Future<void> removeAudio(String bookId) async {
    final parts = await audioFilesOf(bookId);
    if (parts.isEmpty) return;
    await _db.transaction(() async {
      await (_db.delete(_db.bookFiles)
            ..where((f) => f.id.isIn([for (final f in parts) f.id])))
          .go();
      await stampSyncClock(_db, SyncedRow.book, bookId);
    });
    for (final part in parts) {
      try {
        final file = repository.fileOf(part);
        if (await file.exists()) await file.delete();
      } catch (_) {
        // Locked or gone: the row is what mattered.
      }
    }
  }

  /// The chapters of [files] (a book's audio parts, in order), keyed by file.
  Future<Map<String, List<AudioChapter>>> chaptersOf(List<BookFile> files) async {
    if (files.isEmpty) return const {};
    final rows = await (_db.select(_db.audioChapters)
          ..where((c) => c.fileId.isIn([for (final f in files) f.id]))
          ..orderBy([(c) => OrderingTerm(expression: c.idx)]))
        .get();
    final out = <String, List<AudioChapter>>{};
    for (final row in rows) {
      out.putIfAbsent(row.fileId, () => []).add(row);
    }
    return out;
  }
}

/// [files]' audio parts, in playing order: by `track`, then by path for any
/// without one (a part pulled from an older server).
List<BookFile> orderAudioFiles(Iterable<BookFile> files) {
  final audio = [for (final f in files) if (isAudioFormat(f.format)) f];
  audio.sort((a, b) {
    final c = (a.track ?? 1 << 30).compareTo(b.track ?? 1 << 30);
    return c != 0 ? c : a.addedAt.compareTo(b.addedAt);
  });
  return audio;
}
