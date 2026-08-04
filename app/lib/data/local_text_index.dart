/// Full-text search over book *contents*, held locally.
///
/// **Why this exists when the server already does it.** `content_search.dart`
/// is the connected half of search, and its own note says indexing is "the one
/// thing a server can do that a phone genuinely cannot". That is true of a
/// phone and false of a desktop: the files are already on local disk, the
/// machine has the room, and a reference library is searched by *concept*
/// ("which of my books covers `LD_PRELOAD`?") far more often than by title. So
/// this is the same capability, on the side that can afford it, and the app
/// keeps working offline — which is the whole premise.
///
/// **Desktop only, and opt-in.** [supportedHere] gates it off Android for the
/// reason above; [AppSettings.indexBookText] gates it off by default even
/// there, mirroring the server's `VELLUM_INDEX_TEXT`. An index roughly the size
/// of the text it holds should not appear on someone's disk unasked.
///
/// **The queue is the table**, taken from `server/src/text_index.rs`: a
/// `book_text` row with `status = 'pending'` *is* the work item, so an app
/// killed mid-extraction resumes where it stopped with no in-memory job state.
///
/// **No OCR.** A scanned PDF records `no_text` — an outcome, not a failure.
library;

import 'dart:async';
import 'dart:io';

import 'package:drift/drift.dart';
import 'package:pdfrx/pdfrx.dart';

import '../reader/epub_book.dart';
import 'database.dart';
import 'search_index.dart';

/// Extraction statuses. Same vocabulary as the server's, so the two indexes
/// can be reasoned about with one set of words.
abstract final class TextStatus {
  static const pending = 'pending';
  static const ok = 'ok';
  static const noText = 'no_text';
  static const failed = 'failed';
  static const skipped = 'skipped';
}

/// Whether local indexing is possible on this platform.
///
/// Android is excluded deliberately rather than by omission: extracting a few
/// hundred PDFs is heat and battery a phone should not spend, and a phone with
/// a server configured already has content search through it.
bool get textIndexSupportedHere =>
    Platform.isLinux || Platform.isMacOS || Platform.isWindows;

/// One hit: which book, where inside it, and the text around the match.
class LocalContentHit {
  const LocalContentHit({
    required this.bookId,
    required this.title,
    required this.page,
    required this.snippet,
  });

  final String bookId;
  final String title;

  /// 1-based page for a PDF, or spine-section index for an EPUB.
  final int page;

  /// The matching text with `[` … `]` around the hit, from FTS5's `snippet()`.
  final String snippet;
}

/// How much of one file's text to keep. A 900-page technical PDF is a few
/// megabytes of text; this bounds a pathological file without truncating
/// anything anyone would search for. Same figure as the server's.
const _maxTextBytes = 24 * 1024 * 1024;

/// Cap on page/section rows per file, for the same reason.
const _maxPages = 5000;

/// Text shorter than this on a whole file means "no real text" — a scanned
/// PDF still yields a few stray characters from page furniture.
const _minMeaningfulChars = 64;

class LocalTextIndex {
  LocalTextIndex(this.db, {required this.dataDir});

  final VellumDatabase db;
  final Directory dataDir;

  /// Guards against two extraction passes running at once — the scheduler
  /// starts one at launch and the settings screen can start another.
  bool _running = false;

  /// Rows whose file has no `book_text` row yet become `pending`.
  ///
  /// Idempotent, and cheap enough to call on every launch: it is one
  /// `INSERT … SELECT` over files, not a scan of their bytes.
  Future<void> enqueueMissing() async {
    await db.customStatement(
      "INSERT INTO book_text (file_id, book_id, status, extracted_at) "
      "SELECT f.id, f.book_id, '${TextStatus.pending}', datetime('now') "
      'FROM book_files f '
      'WHERE NOT EXISTS (SELECT 1 FROM book_text t WHERE t.file_id = f.id)',
    );
  }

  /// Puts every row back to `pending`, for "rebuild the index".
  Future<void> reindexAll() async {
    await db.customStatement(
      "UPDATE book_text SET status = '${TextStatus.pending}'",
    );
  }

  /// How many files are indexed, waiting, or gave no text.
  Future<Map<String, int>> statusCounts() async {
    final rows = await db
        .customSelect('SELECT status, COUNT(*) AS n FROM book_text GROUP BY status')
        .get();
    return {
      for (final r in rows) r.read<String>('status'): r.read<int>('n'),
    };
  }

  /// Extracts up to [limit] pending files.
  ///
  /// Bounded per call rather than draining the queue, so the work spreads over
  /// launches instead of pinning a core for minutes the first time a big
  /// library is indexed. Returns how many files it processed.
  Future<int> processPending({int limit = 5}) async {
    if (!textIndexSupportedHere || _running) return 0;
    _running = true;
    try {
      final rows = await db
          .customSelect(
            'SELECT t.file_id, t.book_id, f.path, f.format FROM book_text t '
            'JOIN book_files f ON f.id = t.file_id '
            "WHERE t.status = '${TextStatus.pending}' LIMIT $limit",
          )
          .get();
      for (final row in rows) {
        await _indexOne(
          fileId: row.read<String>('file_id'),
          bookId: row.read<String>('book_id'),
          relativePath: row.read<String>('path'),
          format: row.read<String>('format'),
        );
      }
      return rows.length;
    } finally {
      _running = false;
    }
  }

  Future<void> _indexOne({
    required String fileId,
    required String bookId,
    required String relativePath,
    required String format,
  }) async {
    final file = File(
      relativePath.startsWith('/') ? relativePath : '${dataDir.path}/$relativePath',
    );
    if (!await file.exists()) {
      // Not a failure worth retrying every launch: the row is recorded as
      // skipped, and re-adding the file writes a new book_files row anyway.
      await _record(fileId, TextStatus.skipped, 0);
      return;
    }

    List<({int page, String body})> pages;
    try {
      pages = switch (format.toLowerCase()) {
        'pdf' => await _extractPdf(file),
        'epub' => await _extractEpub(file),
        _ => const [],
      };
    } catch (_) {
      // One unreadable file must not stop the queue, and the reason is not
      // actionable by the person using the app.
      await _record(fileId, TextStatus.failed, 0);
      return;
    }

    if (format.toLowerCase() != 'pdf' && format.toLowerCase() != 'epub') {
      await _record(fileId, TextStatus.skipped, 0);
      return;
    }

    final total = pages.fold<int>(0, (n, p) => n + p.body.length);
    if (total < _minMeaningfulChars) {
      // A scanned PDF. A real outcome, recorded as one, so it is not retried
      // on every launch for ever.
      await _record(fileId, TextStatus.noText, 0);
      return;
    }

    await db.transaction(() async {
      await db.customStatement(
        'DELETE FROM book_text_fts WHERE file_id = ?',
        [fileId],
      );
      for (final p in pages) {
        await db.customStatement(
          'INSERT INTO book_text_fts (body, page, file_id, book_id) '
          'VALUES (?, ?, ?, ?)',
          [p.body, p.page, fileId, bookId],
        );
      }
      await _record(fileId, TextStatus.ok, pages.length);
    });
  }

  Future<void> _record(String fileId, String status, int pages) async {
    await db.customStatement(
      'UPDATE book_text SET status = ?, pages = ?, '
      "extracted_at = datetime('now') WHERE file_id = ?",
      [status, pages, fileId],
    );
  }

  Future<List<({int page, String body})>> _extractPdf(File file) async {
    // Required before any pdfrx call, exactly as `pdf_cover.dart` does it.
    // Without it `openFile` never completes — which looks like a very slow
    // book rather than a missing call, so it is worth stating why it is here.
    await pdfrxFlutterInitialize();
    final document = await PdfDocument.openFile(file.path);
    try {
      final out = <({int page, String body})>[];
      var bytes = 0;
      for (final page in document.pages) {
        if (out.length >= _maxPages || bytes >= _maxTextBytes) break;
        final text = await page.loadText();
        final body = _collapse(text?.fullText ?? '');
        if (body.isEmpty) continue;
        bytes += body.length;
        out.add((page: page.pageNumber, body: body));
      }
      return out;
    } finally {
      await document.dispose();
    }
  }

  Future<List<({int page, String body})>> _extractEpub(File file) async {
    final book = await EpubBook.open(file);
    final out = <({int page, String body})>[];
    var bytes = 0;
    for (var i = 0; i < book.chapters.length; i++) {
      if (out.length >= _maxPages || bytes >= _maxTextBytes) break;
      // `plainText` is the same extraction the in-book search and the
      // annotation anchors use, so a content hit and a highlight agree about
      // what the text of a chapter is.
      final body = _collapse(book.chapters[i].plainText);
      if (body.isEmpty) continue;
      bytes += body.length;
      out.add((page: i + 1, body: body));
    }
    return out;
  }

  /// Runs of whitespace to single spaces. PDF extraction is full of layout
  /// newlines that would otherwise bloat the index and spoil snippets.
  static String _collapse(String raw) =>
      raw.replaceAll(RegExp(r'\s+'), ' ').trim();

  /// Searches the indexed text. Returns [] when nothing is indexed yet, which
  /// reads the same as "no matches" and needs no special case at the call site.
  Future<List<LocalContentHit>> search(String query, {int limit = 40}) async {
    final match = ftsMatchQuery(query, column: 'body');
    if (match == null) return const [];
    final rows = await db
        .customSelect(
          'SELECT f.book_id AS book_id, f.page AS page, b.title AS title, '
          "snippet(book_text_fts, 0, '[', ']', '…', 12) AS snippet "
          'FROM book_text_fts f '
          'JOIN books b ON b.id = f.book_id '
          'WHERE book_text_fts MATCH ? AND b.deleted_at IS NULL '
          'ORDER BY rank LIMIT ?',
          variables: [Variable.withString(match), Variable.withInt(limit)],
        )
        .get();
    return [
      for (final r in rows)
        LocalContentHit(
          bookId: r.read<String>('book_id'),
          title: r.read<String>('title'),
          page: r.read<int>('page'),
          snippet: r.read<String>('snippet'),
        ),
    ];
  }
}
