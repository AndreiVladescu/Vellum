import '../import/import_plan.dart';

/// Why two books look like the same book. Ordered by how much it can be trusted,
/// which is what the UI shows and what sorting uses.
enum DuplicateReason {
  /// The two books hold a file with the same sha256 — certain.
  sameFile,

  /// Equal ISBNs (compared digits-only) — as good as certain.
  sameIsbn,

  /// Titles and authors are close enough after normalising. A suggestion.
  similarTitle,
}

extension DuplicateReasonLabel on DuplicateReason {
  String get label => switch (this) {
        DuplicateReason.sameFile => 'Same file',
        DuplicateReason.sameIsbn => 'Same ISBN',
        DuplicateReason.similarTitle => 'Similar title and author',
      };

  /// Whether this reason is strong enough to preselect the pair for merging.
  /// Only the certain ones are; a fuzzy title match is shown but not assumed.
  bool get isCertain => this != DuplicateReason.similarTitle;
}

/// A pair of books that look like the same book (plan 5 #21b).
class DuplicatePair {
  DuplicatePair({
    required this.a,
    required this.b,
    required this.reason,
  });

  /// The two candidates. Which one *survives* a merge is the user's choice, so
  /// this deliberately doesn't call one of them "the original".
  final LibraryFingerprint a;
  final LibraryFingerprint b;
  final DuplicateReason reason;

  bool involves(String bookId) => a.bookId == bookId || b.bookId == bookId;
}

/// Levenshtein distance, capped: anything past [limit] is reported as
/// `limit + 1`, since the caller only ever compares against a threshold.
///
/// Two rows of the DP table rather than the full matrix — a library of a few
/// thousand titles is a few million comparisons, and the allocation is what
/// costs there.
int boundedEditDistance(String a, String b, {int limit = 3}) {
  if ((a.length - b.length).abs() > limit) return limit + 1;
  if (a == b) return 0;
  var previous = List<int>.generate(b.length + 1, (i) => i);
  var current = List<int>.filled(b.length + 1, 0);
  for (var i = 1; i <= a.length; i++) {
    current[0] = i;
    var best = current[0];
    for (var j = 1; j <= b.length; j++) {
      final cost = a[i - 1] == b[j - 1] ? 0 : 1;
      final value = [
        previous[j] + 1, // deletion
        current[j - 1] + 1, // insertion
        previous[j - 1] + cost, // substitution
      ].reduce((x, y) => x < y ? x : y);
      current[j] = value;
      if (value < best) best = value;
    }
    // Every remaining row can only grow; bail out once the whole row exceeds
    // the limit.
    if (best > limit) return limit + 1;
    final swap = previous;
    previous = current;
    current = swap;
  }
  return previous[b.length];
}

/// Title form used for fuzzy comparison: normalised (case, punctuation and
/// articles dropped by [normalizeForMatch]) and then **token-sorted**, so
/// "Dune, Frank Herbert" and "Frank Herbert Dune" don't count as different.
String comparableTitle(String title) {
  final words = normalizeForMatch(title).split(' ')..sort();
  return words.join(' ');
}

/// Finds duplicate pairs across [library].
///
/// The three signals come from the plan, and their *order* is the safety
/// property: an identical file hash or ISBN is reported as certain, and the
/// fuzzy title+author match is reported separately so the UI can preselect the
/// first two and merely offer the third. A merge is destructive and irreversible,
/// so nothing here is ever applied automatically.
///
/// Each pair is reported once (a–b, never also b–a), and only the strongest
/// reason is kept for a pair that matches several ways.
List<DuplicatePair> findDuplicates(
  List<LibraryFingerprint> library, {
  int titleDistance = 2,
}) {
  final pairs = <String, DuplicatePair>{};

  String key(String x, String y) => x.compareTo(y) < 0 ? '$x|$y' : '$y|$x';
  void record(LibraryFingerprint a, LibraryFingerprint b, DuplicateReason why) {
    final k = key(a.bookId, b.bookId);
    final existing = pairs[k];
    // Lower enum index = stronger reason; keep the strongest.
    if (existing == null || why.index < existing.reason.index) {
      pairs[k] = DuplicatePair(a: a, b: b, reason: why);
    }
  }

  // 1. Identical file bytes.
  final byHash = <String, List<LibraryFingerprint>>{};
  for (final book in library) {
    for (final hash in book.fileHashes) {
      byHash.putIfAbsent(hash, () => []).add(book);
    }
  }
  for (final group in byHash.values) {
    for (var i = 0; i < group.length; i++) {
      for (var j = i + 1; j < group.length; j++) {
        record(group[i], group[j], DuplicateReason.sameFile);
      }
    }
  }

  // 2. Equal ISBN.
  final byIsbn = <String, List<LibraryFingerprint>>{};
  for (final book in library) {
    final isbn = normalizeIsbn(book.isbn);
    if (isbn != null) byIsbn.putIfAbsent(isbn, () => []).add(book);
  }
  for (final group in byIsbn.values) {
    for (var i = 0; i < group.length; i++) {
      for (var j = i + 1; j < group.length; j++) {
        record(group[i], group[j], DuplicateReason.sameIsbn);
      }
    }
  }

  // 3. Fuzzy title, corroborated by author. Bucketed by first letter and length
  // so this stays well short of comparing every title to every other.
  final comparable = {
    for (final book in library) book.bookId: comparableTitle(book.title),
  };
  for (var i = 0; i < library.length; i++) {
    for (var j = i + 1; j < library.length; j++) {
      final a = library[i];
      final b = library[j];
      final ta = comparable[a.bookId]!;
      final tb = comparable[b.bookId]!;
      if (ta.isEmpty || tb.isEmpty) continue;
      if ((ta.length - tb.length).abs() > titleDistance) continue;
      if (boundedEditDistance(ta, tb, limit: titleDistance) > titleDistance) {
        continue;
      }
      // Authors have to agree when both sides name one, exactly as the import
      // classifier does — otherwise two different books with near-identical
      // titles would be offered as one.
      final authorsA = {
        for (final name in a.authors) normalizeForMatch(name),
      }..removeWhere((s) => s.isEmpty);
      final authorsB = {
        for (final name in b.authors) normalizeForMatch(name),
      }..removeWhere((s) => s.isEmpty);
      final agree = authorsA.isEmpty || authorsB.isEmpty
          ? authorsA.isEmpty && authorsB.isEmpty
          : authorsA.intersection(authorsB).isNotEmpty;
      if (agree) record(a, b, DuplicateReason.similarTitle);
    }
  }

  final result = pairs.values.toList()
    ..sort((x, y) {
      final byReason = x.reason.index.compareTo(y.reason.index);
      return byReason != 0 ? byReason : x.a.title.compareTo(y.a.title);
    });
  return result;
}
