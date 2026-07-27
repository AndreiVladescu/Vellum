import 'dart:io';

import 'package:drift/drift.dart';
import 'package:drift/native.dart';
import 'package:path/path.dart' as p;

import 'catalog_entry.dart';

/// Reads a Calibre library's `metadata.db` (plan 5 #21c).
///
/// This is the on-ramp for anyone who already has a library: Calibre users
/// have often spent years on their metadata, and asking them to re-derive it
/// from file names would throw away the very thing that makes their library
/// theirs. So the catalogue is read as stated — title, authors, series,
/// publisher, tags, ISBN, description — and the files are resolved through
/// Calibre's own layout rather than by scanning the folder.
///
/// **Opened read-only, on a copy.** Calibre may be running, and a live SQLite
/// file with a hot WAL is not something to open for writes from another
/// process; copying first also means a corrupt or unexpected schema can only
/// break the import, never the user's library.
class CalibreImport {
  /// Where a Calibre library lives: the folder containing `metadata.db`.
  static const metadataFileName = 'metadata.db';

  /// Whether [directory] looks like a Calibre library.
  static Future<bool> looksLikeLibrary(Directory directory) =>
      File(p.join(directory.path, metadataFileName)).exists();

  /// Reads every book in the library at [root].
  ///
  /// File paths are resolved but **not** verified to exist: a Calibre library
  /// whose files were moved should still import its metadata, and the import
  /// step reports a missing file per row rather than refusing the whole
  /// catalogue. [formats] limits which of Calibre's formats are taken — the
  /// app can only open PDF and EPUB, and importing a `.mobi` would create a
  /// book with a file nothing can read.
  static Future<List<CatalogEntry>> read(
    Directory root, {
    Set<String> formats = const {'pdf', 'epub'},
  }) async {
    final source = File(p.join(root.path, metadataFileName));
    if (!await source.exists()) {
      throw const CalibreImportException('No metadata.db in that folder — '
          'pick the folder that contains your Calibre library.');
    }
    final workspace =
        await Directory.systemTemp.createTemp('vellum_calibre_read');
    final copy = File(p.join(workspace.path, metadataFileName));
    try {
      await source.copy(copy.path);
      final db = _CalibreDatabase(NativeDatabase(copy));
      try {
        return await _readFrom(db, root, formats);
      } finally {
        await db.close();
      }
    } on CalibreImportException {
      rethrow;
    } catch (e) {
      throw CalibreImportException('Could not read that Calibre library: $e');
    } finally {
      try {
        await workspace.delete(recursive: true);
      } catch (_) {
        // A temp copy we can't remove is the OS's problem, not the import's.
      }
    }
  }

  static Future<List<CatalogEntry>> _readFrom(
    _CalibreDatabase db,
    Directory root,
    Set<String> formats,
  ) async {
    final books = await db.rows(
      'SELECT id, title, sort, pubdate, path, series_index, has_cover '
      'FROM books ORDER BY sort, title',
    );
    if (books.isEmpty) return const [];

    final authors = await _multi(
      db,
      'SELECT bal.book AS book, a.name AS value FROM books_authors_link bal '
      'JOIN authors a ON a.id = bal.author ORDER BY bal.id',
    );
    final tags = await _multi(
      db,
      'SELECT btl.book AS book, t.name AS value FROM books_tags_link btl '
      'JOIN tags t ON t.id = btl.tag ORDER BY t.name',
    );
    final publishers = await _single(
      db,
      'SELECT bpl.book AS book, pub.name AS value FROM books_publishers_link '
      'bpl JOIN publishers pub ON pub.id = bpl.publisher',
    );
    final series = await _single(
      db,
      'SELECT bsl.book AS book, s.name AS value FROM books_series_link bsl '
      'JOIN series s ON s.id = bsl.series',
    );
    final comments =
        await _single(db, 'SELECT book, text AS value FROM comments');
    // Modern Calibre keeps the ISBN in `identifiers`; very old libraries had a
    // `books.isbn` column. Try the table, and don't fail if it isn't there.
    final isbns = await _single(
      db,
      "SELECT book, val AS value FROM identifiers WHERE type = 'isbn'",
    );

    // `data` is Calibre's format table: one row per (book, format), with the
    // file's stem in `name`. The path on disk is <root>/<books.path>/<name>.<ext>.
    final dataRows = await db.rows(
      'SELECT book, format, name FROM data ORDER BY book',
    );
    final filesByBook = <int, List<({String format, String name})>>{};
    for (final row in dataRows) {
      final format = (row['format'] as String? ?? '').toLowerCase();
      final name = row['name'] as String?;
      final book = _asInt(row['book']);
      if (name == null || book == null) continue;
      if (!formats.contains(format)) continue;
      (filesByBook[book] ??= []).add((format: format, name: name));
    }

    final entries = <CatalogEntry>[];
    for (final row in books) {
      final id = _asInt(row['id']);
      if (id == null) continue;
      final title = (row['title'] as String? ?? '').trim();
      if (title.isEmpty) continue;
      final bookPath = row['path'] as String?;

      // One entry per *format*: two files of the same book are two rows in the
      // review table, deduplicated by the same hash check every other source
      // gets. Calibre lists them separately and so should the import.
      final files = filesByBook[id] ?? const [];
      String? firstFile;
      if (files.isNotEmpty && bookPath != null) {
        firstFile = p.join(
          root.path,
          bookPath,
          '${files.first.name}.${files.first.format}',
        );
      }
      final coverPath = (_asInt(row['has_cover']) ?? 0) != 0 && bookPath != null
          ? p.join(root.path, bookPath, 'cover.jpg')
          : null;

      entries.add(CatalogEntry(
        title: title,
        authors: authors[id] ?? const [],
        isbn: isbns[id],
        publisher: publishers[id],
        description: _stripHtml(comments[id]),
        series: series[id],
        seriesIndex: series[id] == null ? null : _asDouble(row['series_index']),
        year: _yearOf(row['pubdate']),
        genres: tags[id] ?? const [],
        filePath: firstFile,
        coverPath: coverPath,
        sourceId: '$id',
      ));

      // Extra formats of the same book, after the first.
      for (final extra in files.skip(1)) {
        if (bookPath == null) break;
        entries.add(CatalogEntry(
          title: title,
          authors: authors[id] ?? const [],
          isbn: isbns[id],
          publisher: publishers[id],
          description: _stripHtml(comments[id]),
          series: series[id],
          seriesIndex:
              series[id] == null ? null : _asDouble(row['series_index']),
          year: _yearOf(row['pubdate']),
          genres: tags[id] ?? const [],
          filePath:
              p.join(root.path, bookPath, '${extra.name}.${extra.format}'),
          coverPath: coverPath,
          sourceId: '$id',
        ));
      }
    }
    return entries;
  }

  /// `book id -> [values]`, for the link tables. Returns an empty map rather
  /// than throwing when the table is missing: Calibre's schema has grown over
  /// many versions, and a library without `identifiers` is old, not broken.
  static Future<Map<int, List<String>>> _multi(
    _CalibreDatabase db,
    String sql,
  ) async {
    final out = <int, List<String>>{};
    for (final row in await db.rows(sql)) {
      final book = _asInt(row['book']);
      final value = (row['value'] as String?)?.trim();
      if (book == null || value == null || value.isEmpty) continue;
      (out[book] ??= []).add(value);
    }
    return out;
  }

  static Future<Map<int, String>> _single(
    _CalibreDatabase db,
    String sql,
  ) async {
    final out = <int, String>{};
    for (final row in await db.rows(sql)) {
      final book = _asInt(row['book']);
      final value = (row['value'] as String?)?.trim();
      if (book == null || value == null || value.isEmpty) continue;
      out.putIfAbsent(book, () => value);
    }
    return out;
  }

  static int? _asInt(Object? v) => switch (v) {
        final int i => i,
        final num n => n.toInt(),
        final String s => int.tryParse(s),
        _ => null,
      };

  static double? _asDouble(Object? v) => switch (v) {
        final double d => d,
        final num n => n.toDouble(),
        final String s => double.tryParse(s),
        _ => null,
      };

  /// Calibre stores `pubdate` as an ISO timestamp; only the year is useful
  /// here, and its "unset" sentinel is year 101, which must not become a book
  /// published in 101 AD.
  static int? _yearOf(Object? value) {
    if (value is! String || value.isEmpty) return null;
    final parsed = DateTime.tryParse(value);
    final year = parsed?.year;
    if (year == null || year < 500) return null;
    return year;
  }

  /// Calibre comments are HTML. The app's description field is plain text, so
  /// tags are stripped rather than shown as markup — imperfect on exotic
  /// markup and much better than `<p>` on every paragraph.
  static String? _stripHtml(String? html) {
    if (html == null) return null;
    final text = html
        .replaceAll(RegExp(r'<br\s*/?>', caseSensitive: false), '\n')
        .replaceAll(RegExp(r'</p>', caseSensitive: false), '\n\n')
        .replaceAll(RegExp(r'<[^>]+>'), '')
        .replaceAll('&amp;', '&')
        .replaceAll('&lt;', '<')
        .replaceAll('&gt;', '>')
        .replaceAll('&quot;', '"')
        .replaceAll('&#39;', "'")
        .replaceAll('&nbsp;', ' ')
        .trim();
    return text.isEmpty ? null : text;
  }
}

class CalibreImportException implements Exception {
  const CalibreImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// A drift database with no schema of its own, used only to run raw SQL
/// against someone else's SQLite file.
///
/// `allSchemaEntities` is empty on purpose, so drift's `createAll` on a fresh
/// open is a no-op and the migration callbacks below can never write anything
/// to the file — this must stay a reader.
class _CalibreDatabase extends GeneratedDatabase {
  _CalibreDatabase(super.executor);

  @override
  Iterable<TableInfo<Table, dynamic>> get allTables => const [];

  @override
  int get schemaVersion => 1;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onCreate: (m) async {},
        onUpgrade: (m, from, to) async {},
      );

  /// Runs [sql], returning plain maps. Missing tables answer with an empty
  /// list: Calibre's schema differs across versions, and one absent optional
  /// table must not fail the whole read.
  Future<List<Map<String, Object?>>> rows(String sql) async {
    try {
      final result = await customSelect(sql).get();
      return [for (final row in result) row.data];
    } catch (_) {
      return const [];
    }
  }
}
