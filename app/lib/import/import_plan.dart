import 'catalog_entry.dart';
import 'filename_metadata.dart';

/// What an import would do with one file — decided **before** anything is
/// written, so the user sees and can correct it (plan 5 #15).
enum ImportStatus {
  /// Nothing in the library looks like this file.
  newBook,

  /// A file with the identical sha256 is already attached to a book. Certain,
  /// not a guess: re-importing it would only duplicate bytes.
  duplicateFile,

  /// Same ISBN, or same title *and* author, as a book already here. Likely the
  /// same book in another format (or a re-download), but the user decides.
  probableDuplicate,

  /// Deselected by the user, or unreadable.
  skip,
}

/// A book already in the library, reduced to what duplicate detection needs.
class LibraryFingerprint {
  const LibraryFingerprint({
    required this.bookId,
    required this.title,
    this.isbn,
    this.authors = const [],
    this.fileHashes = const {},
  });

  final String bookId;
  final String title;
  final String? isbn;
  final List<String> authors;
  final Set<String> fileHashes;
}

/// One row of the dry-run table.
class ImportCandidate {
  ImportCandidate({
    required this.path,
    required this.sizeBytes,
    required this.format,
    required this.meta,
    required this.status,
    this.sha256,
    this.matchedBookId,
    this.matchedTitle,
    this.error,
    this.entry,
  });

  final String path;
  final int sizeBytes;

  /// 'pdf' or 'epub', lowercased without the dot.
  final String format;

  /// What the file name suggests; the user can edit it before importing.
  final FilenameMeta meta;

  final ImportStatus status;

  /// Null when hashing failed (then [error] says why and [status] is skip).
  final String? sha256;

  /// The library book this looks like, for the two duplicate statuses.
  final String? matchedBookId;
  final String? matchedTitle;

  final String? error;

  /// What an external catalogue said about this book (plan 5 #21c), when the
  /// row came from one. Null for a plain folder import, where [meta] — a guess
  /// from the file name — is all there is. When present it wins: a source that
  /// states the title has no reason to defer to a parse of the file name.
  final CatalogEntry? entry;

  /// Whether this row is imported by default. Duplicates are deselected but
  /// still shown — "nothing happened to 200 of my files" is worse than a list.
  bool get selectedByDefault => status == ImportStatus.newBook;

  ImportCandidate copyWith({
    ImportStatus? status,
    FilenameMeta? meta,
    String? matchedBookId,
    String? matchedTitle,
  }) =>
      ImportCandidate(
        path: path,
        sizeBytes: sizeBytes,
        format: format,
        meta: meta ?? this.meta,
        status: status ?? this.status,
        sha256: sha256,
        matchedBookId: matchedBookId ?? this.matchedBookId,
        matchedTitle: matchedTitle ?? this.matchedTitle,
        error: error,
        entry: entry,
      );
}

/// Normalized form for fuzzy title/author comparison: case-folded, punctuation
/// and articles dropped, whitespace collapsed. Deliberately crude — it decides
/// whether to *suggest* "probable duplicate", never whether to skip something
/// silently.
String normalizeForMatch(String value) {
  final lowered = value.toLowerCase().replaceAll(RegExp(r'[^a-z0-9\s]'), ' ');
  final words = [
    for (final w in lowered.split(RegExp(r'\s+')))
      if (w.isNotEmpty && !_stopWords.contains(w)) w,
  ];
  return words.join(' ');
}

const _stopWords = {'a', 'an', 'the'};

/// Digits only, so `978-0-441-01359-3` and `9780441013593` compare equal.
String? normalizeIsbn(String? isbn) {
  if (isbn == null) return null;
  final digits = isbn.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
  return digits.isEmpty ? null : digits;
}

/// Classifies one file against the current library.
///
/// Order matters and is the point: an identical **hash** is certain, so it wins;
/// only then do the heuristics run. A file that matches nothing is `newBook`.
/// Nothing here writes anything — the caller shows the result and asks.
ImportCandidate classify({
  required String path,
  required int sizeBytes,
  required String format,
  required String? sha256,
  required List<LibraryFingerprint> library,
  String? isbn,
  String? error,
  CatalogEntry? entry,
}) {
  // A catalogue's own statement beats a parse of the file name — that is the
  // whole reason to read Calibre rather than its folder (plan 5 #21c). It also
  // supplies the ISBN, which makes the decisive arm below live rather than
  // dormant for these sources.
  final meta = entry?.asFilenameMeta ?? parseFilename(filenameStem(path));
  isbn ??= entry?.isbn;
  // A catalogue row may legitimately bring no file (a CSV export describes
  // books whose bytes are elsewhere), so "no hash" there means "nothing to
  // hash", not "unreadable". A row that *does* name a file and still has no
  // hash is the error case this guard is for.
  final expectsFile = entry == null || entry.filePath != null;
  if (sha256 == null && expectsFile) {
    return ImportCandidate(
      path: path,
      sizeBytes: sizeBytes,
      format: format,
      meta: meta,
      status: ImportStatus.skip,
      error: error ?? 'unreadable',
      entry: entry,
    );
  }

  for (final book in library) {
    if (sha256 != null && book.fileHashes.contains(sha256)) {
      return ImportCandidate(
        path: path,
        sizeBytes: sizeBytes,
        format: format,
        meta: meta,
        status: ImportStatus.duplicateFile,
        sha256: sha256,
        matchedBookId: book.bookId,
        matchedTitle: book.title,
        entry: entry,
      );
    }
  }

  // An ISBN is only available once an online lookup has matched the file, so
  // this arm is dormant on a metadata-later import and decisive on a matched
  // one: the same ISBN is the same book, whatever either file is called.
  final wantedIsbn = normalizeIsbn(isbn);
  if (wantedIsbn != null) {
    for (final book in library) {
      if (normalizeIsbn(book.isbn) == wantedIsbn) {
        return ImportCandidate(
          path: path,
          sizeBytes: sizeBytes,
          format: format,
          meta: meta,
          status: ImportStatus.probableDuplicate,
          sha256: sha256,
          matchedBookId: book.bookId,
          matchedTitle: book.title,
          entry: entry,
        );
      }
    }
  }

  final title = meta.title == null ? null : normalizeForMatch(meta.title!);
  final authors = {for (final a in meta.authors) normalizeForMatch(a)}
    ..removeWhere((a) => a.isEmpty);
  for (final book in library) {
    final sameTitle = title != null &&
        title.isNotEmpty &&
        normalizeForMatch(book.title) == title;
    if (!sameTitle) continue;
    // Title alone is enough only when neither side names an author; otherwise
    // the authors have to agree, so two different books called "Physics" don't
    // collapse into one.
    final theirAuthors = {
      for (final a in book.authors) normalizeForMatch(a),
    }..removeWhere((a) => a.isEmpty);
    final authorsAgree = authors.isEmpty || theirAuthors.isEmpty
        ? theirAuthors.isEmpty && authors.isEmpty
        : authors.intersection(theirAuthors).isNotEmpty;
    if (authorsAgree) {
      return ImportCandidate(
        path: path,
        sizeBytes: sizeBytes,
        format: format,
        meta: meta,
        status: ImportStatus.probableDuplicate,
        sha256: sha256,
        matchedBookId: book.bookId,
        matchedTitle: book.title,
        entry: entry,
      );
    }
  }

  return ImportCandidate(
    path: path,
    sizeBytes: sizeBytes,
    format: format,
    meta: meta,
    status: ImportStatus.newBook,
    sha256: sha256,
    entry: entry,
  );
}

/// Counts per status, for the wizard's summary line.
Map<ImportStatus, int> summarize(Iterable<ImportCandidate> candidates) {
  final counts = {for (final s in ImportStatus.values) s: 0};
  for (final c in candidates) {
    counts[c.status] = counts[c.status]! + 1;
  }
  return counts;
}
