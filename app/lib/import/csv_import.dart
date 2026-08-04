import 'dart:convert';
import 'dart:io';

import 'catalog_entry.dart';

/// Reads a CSV or JSON catalogue (plan 5 #21c).
///
/// The shape that must round-trip is the **console's export**
/// (`server/web/console.js`): `title, subtitle, authors, published_year,
/// publisher, isbn, page_count, file_count, has_cover, tags, created_at` for
/// CSV, and the raw `/api/books` objects for JSON. Export from the console,
/// import here, and the catalogue survives.
///
/// Column mapping is **header-driven and forgiving** rather than positional, so
/// an export from somewhere else (Goodreads and friends all use `Title`,
/// `Author`, `ISBN`) lands on its feet instead of producing a library of books
/// called "9780441013593". Unknown columns are ignored; a file with no
/// recognisable title column is rejected outright, because every other outcome
/// is a silent mess.
///
/// Entries carry no [CatalogEntry.filePath]: a catalogue export describes books
/// whose bytes are somewhere else. That is a real import — a record of physical
/// books, or of a library that lives on a server — not a degraded one.
class CsvImport {
  /// Reads either format, chosen by the file's first non-space character
  /// rather than its extension: a `.txt` holding JSON is still JSON, and an
  /// export saved with the wrong suffix is a common way to lose an afternoon.
  static Future<List<CatalogEntry>> readFile(File file) async {
    final text = await file.readAsString();
    return read(text);
  }

  static List<CatalogEntry> read(String text) {
    final trimmed = text.trimLeft();
    if (trimmed.startsWith('[') || trimmed.startsWith('{')) {
      return _readJson(trimmed);
    }
    return _readCsv(text);
  }

  static List<CatalogEntry> _readJson(String text) {
    final Object? decoded;
    try {
      decoded = jsonDecode(text);
    } catch (e) {
      throw CsvImportException('That JSON could not be parsed: $e');
    }
    // The console exports a bare array; a hand-rolled file might wrap it.
    final list = switch (decoded) {
      final List<dynamic> l => l,
      final Map<String, dynamic> m when m['books'] is List =>
        m['books'] as List<dynamic>,
      _ => throw const CsvImportException(
          'Expected a list of books, or an object with a "books" list.'),
    };
    final entries = <CatalogEntry>[];
    for (final item in list) {
      if (item is! Map<String, dynamic>) continue;
      final entry = _fromMap({
        for (final e in item.entries) e.key.toLowerCase(): e.value,
      });
      if (entry != null) entries.add(entry);
    }
    if (entries.isEmpty) {
      throw const CsvImportException('No books with a title in that file.');
    }
    return entries;
  }

  static List<CatalogEntry> _readCsv(String text) {
    final rows = parseCsv(text);
    if (rows.isEmpty) throw const CsvImportException('That file is empty.');
    final header = [for (final h in rows.first) h.trim().toLowerCase()];
    if (!header.any((h) => _titleKeys.contains(h))) {
      throw const CsvImportException(
        'No "title" column — the first row must be a header.',
      );
    }
    final entries = <CatalogEntry>[];
    for (final row in rows.skip(1)) {
      if (row.every((cell) => cell.trim().isEmpty)) continue;
      final map = <String, Object?>{};
      for (var i = 0; i < header.length && i < row.length; i++) {
        map[header[i]] = row[i];
      }
      final entry = _fromMap(map);
      if (entry != null) entries.add(entry);
    }
    if (entries.isEmpty) {
      throw const CsvImportException('No books with a title in that file.');
    }
    return entries;
  }

  // Header aliases. Deliberately short lists of what other exporters actually
  // use, not an attempt at every catalogue format in existence.
  static const _titleKeys = {'title', 'book title'};
  static const _authorKeys = {'authors', 'author', 'author_sort', 'creator'};
  static const _isbnKeys = {'isbn', 'isbn13', 'isbn-13', 'isbn_13'};
  static const _yearKeys = {
    'published_year',
    'year',
    'year published',
    'original publication year',
  };
  static const _publisherKeys = {'publisher'};
  static const _subtitleKeys = {'subtitle'};
  static const _pagesKeys = {'page_count', 'pages', 'number of pages'};
  static const _tagKeys = {'tags', 'genres', 'bookshelves', 'subjects'};
  static const _descriptionKeys = {'description', 'comments', 'summary'};
  static const _seriesKeys = {'series'};
  static const _seriesIndexKeys = {'series_index', 'volume'};
  // ---- The personal columns a reading-tracker export actually carries ------
  //
  // These are what makes a Goodreads or StoryGraph export worth more than a
  // list of titles. `exclusive shelf` is Goodreads' one-of-three shelf;
  // `read status` is StoryGraph's equivalent.
  static const _statusKeys = {
    'exclusive shelf',
    'read status',
    'status',
  };
  static const _ratingKeys = {'my rating', 'star rating', 'rating'};
  static const _dateReadKeys = {'date read', 'last date read', 'date_read'};
  static const _readCountKeys = {'read count', 'times read'};
  // Goodreads splits the public review from the private note; either is yours.
  static const _reviewKeys = {'my review', 'review', 'private notes'};
  // Goodreads' `Additional Authors`, StoryGraph's `Contributors`.
  static const _extraAuthorKeys = {'additional authors', 'contributors'};

  static CatalogEntry? _fromMap(Map<String, Object?> row) {
    final title = _string(row, _titleKeys)?.trim();
    if (title == null || title.isEmpty) return null;
    return CatalogEntry(
      title: title,
      authors: [..._list(row, _authorKeys), ..._list(row, _extraAuthorKeys)],
      subtitle: _string(row, _subtitleKeys),
      isbn: _cleanIsbn(_string(row, _isbnKeys)),
      publisher: _string(row, _publisherKeys),
      description: _string(row, _descriptionKeys),
      series: _string(row, _seriesKeys),
      seriesIndex: _double(row, _seriesIndexKeys),
      year: _int(row, _yearKeys),
      pageCount: _int(row, _pagesKeys),
      genres: _list(row, _tagKeys),
      status: readingStatusFromExport(_string(row, _statusKeys)),
      rating: ratingFromExport(_double(row, _ratingKeys)),
      finishedAt: dateFromExport(_string(row, _dateReadKeys)),
      readCount: _int(row, _readCountKeys),
      review: _string(row, _reviewKeys),
    );
  }

  static Object? _raw(Map<String, Object?> row, Set<String> keys) {
    for (final key in keys) {
      final value = row[key];
      if (value != null && '$value'.trim().isNotEmpty) return value;
    }
    return null;
  }

  static String? _string(Map<String, Object?> row, Set<String> keys) {
    final value = _raw(row, keys);
    if (value == null) return null;
    final text = '$value'.trim();
    return text.isEmpty ? null : text;
  }

  /// Splits a joined list. The console writes authors as `A, B` and tags as
  /// `A; B`, and JSON gives a real list — all three land here.
  static List<String> _list(Map<String, Object?> row, Set<String> keys) {
    final value = _raw(row, keys);
    if (value == null) return const [];
    if (value is List) {
      return [
        for (final v in value)
          if ('$v'.trim().isNotEmpty) '$v'.trim(),
      ];
    }
    return [
      for (final part in '$value'.split(RegExp(r'[;,]|\s+&\s+')))
        if (part.trim().isNotEmpty) part.trim(),
    ];
  }

  static int? _int(Map<String, Object?> row, Set<String> keys) {
    final value = _raw(row, keys);
    if (value is int) return value;
    if (value is num) return value.toInt();
    if (value == null) return null;
    return int.tryParse('$value'.trim());
  }

  static double? _double(Map<String, Object?> row, Set<String> keys) {
    final value = _raw(row, keys);
    if (value is num) return value.toDouble();
    if (value == null) return null;
    return double.tryParse('$value'.trim());
  }

  /// Goodreads writes ISBNs as `="9780441013593"`, an Excel escape. Strip that
  /// and any punctuation, and reject what's left if it isn't ISBN-shaped.
  static String? _cleanIsbn(String? raw) {
    if (raw == null) return null;
    final digits = raw.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
    if (digits.length != 10 && digits.length != 13) return null;
    return digits;
  }
}

/// A minimal RFC 4180 CSV reader: quoted fields, `""` escapes, and newlines
/// inside quotes.
///
/// Hand-written rather than a dependency because this is the whole of what the
/// format needs and the alternative is a package for forty lines — the same
/// call the plan made about the OPDS client.
List<List<String>> parseCsv(String text) {
  final rows = <List<String>>[];
  var row = <String>[];
  final field = StringBuffer();
  var inQuotes = false;
  var i = 0;

  void endField() {
    row.add(field.toString());
    field.clear();
  }

  void endRow() {
    endField();
    rows.add(row);
    row = <String>[];
  }

  while (i < text.length) {
    final char = text[i];
    if (inQuotes) {
      if (char == '"') {
        if (i + 1 < text.length && text[i + 1] == '"') {
          field.write('"');
          i += 2;
          continue;
        }
        inQuotes = false;
        i++;
        continue;
      }
      field.write(char);
      i++;
      continue;
    }
    switch (char) {
      case '"':
        inQuotes = true;
      case ',':
        endField();
      case '\r':
        // Swallow CR; the LF that follows ends the row (a lone CR does too).
        if (i + 1 < text.length && text[i + 1] == '\n') i++;
        endRow();
      case '\n':
        endRow();
      default:
        field.write(char);
    }
    i++;
  }
  // A file not ending in a newline still has a last row.
  if (field.isNotEmpty || row.isNotEmpty) endRow();
  return rows;
}

class CsvImportException implements Exception {
  const CsvImportException(this.message);

  final String message;

  @override
  String toString() => message;
}

// ---------------------------------------------------------------------------
// Turning a reading tracker's vocabulary into ours.
//
// Top-level so they can be tested directly, and so the mapping lives in one
// readable place rather than being spread through the row parser.
// ---------------------------------------------------------------------------

/// Maps an exporter's shelf onto a [ReadingStatus] name, or null when it says
/// nothing we understand.
///
/// The one worth arguing about is **`to-read` becoming `wishlist`** rather than
/// `unread`. A Goodreads want-to-read pile is books you do not own; dropping
/// four hundred of them onto the shelf as "unread" would bury the books you
/// actually have, which is exactly what the wishlist exists to prevent.
String? readingStatusFromExport(String? raw) {
  final v = raw?.trim().toLowerCase().replaceAll('_', '-');
  if (v == null || v.isEmpty) return null;
  return switch (v) {
    'read' || 'finished' || 'completed' => 'finished',
    'currently-reading' || 'currently reading' || 'reading' => 'reading',
    'to-read' || 'to read' || 'want to read' || 'wishlist' => 'wishlist',
    'did-not-finish' || 'did not finish' || 'dnf' || 'abandoned' => 'abandoned',
    'reference' => 'reference',
    _ => null,
  };
}

/// A 1–5 rating, or null for unrated.
///
/// Goodreads writes `0` for "not rated", which is not a rating of nought.
/// StoryGraph allows halves, and this column is an integer, so 4.5 rounds to 5
/// — rounding rather than truncating, because a 4.5 is much closer to the
/// person's meaning at 5 than at 4.
int? ratingFromExport(double? raw) {
  if (raw == null || raw <= 0) return null;
  return raw.round().clamp(1, 5);
}

/// A date from an export, or null.
///
/// Goodreads writes `2019/03/14`, StoryGraph writes `2019-03-14`; neither
/// carries a time, so these land at local midnight. Anything unparseable is
/// null rather than a guess — a wrong date in reading insights is worse than
/// no date.
DateTime? dateFromExport(String? raw) {
  final v = raw?.trim();
  if (v == null || v.isEmpty) return null;
  final m = RegExp(r'^(\d{4})[/-](\d{1,2})[/-](\d{1,2})').firstMatch(v);
  if (m == null) return null;
  final year = int.parse(m.group(1)!);
  final month = int.parse(m.group(2)!);
  final day = int.parse(m.group(3)!);
  if (month < 1 || month > 12 || day < 1 || day > 31) return null;
  final parsed = DateTime(year, month, day);
  // DateTime rolls 31 February over into March; reject rather than accept a
  // date the export did not contain.
  if (parsed.month != month || parsed.day != day) return null;
  return parsed;
}
