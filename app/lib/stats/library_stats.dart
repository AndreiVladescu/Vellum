import 'dart:math' as math;

/// How a book is held: the "format" breakdown of the library statistics.
enum HoldingKind { pdf, epub, otherDigital, physical, several, none }

/// One book, flattened to exactly what the library statistics need.
///
/// Built by [LibraryStatsQueries] from a single SQL query, or by hand in tests.
class LibraryStatsBook {
  const LibraryStatsBook({
    required this.id,
    this.publishedYear,
    this.pageCount,
    this.status = 'unread',
    required this.createdAt,
    this.genres = const [],
    this.authors = const [],
    this.formats = const [],
    this.fileBytes = 0,
    this.copies = 0,
  });

  final String id;
  final int? publishedYear;
  final int? pageCount;

  /// 'unread' | 'reading' | 'finished' | 'abandoned' | 'reference' | 'wishlist'.
  final String status;
  final DateTime createdAt;
  final List<String> genres;
  final List<String> authors;

  /// File formats attached, as stored ('pdf', 'epub', ...).
  final List<String> formats;
  final int fileBytes;

  /// Number of physical copies.
  final int copies;
}

/// One bar: a label and how many books fall under it.
class StatCount {
  const StatCount(this.label, this.count);
  final String label;
  final int count;
}

/// The books added in one calendar month.
class MonthCount {
  const MonthCount(this.month, this.count);

  /// First day of the month, local time.
  final DateTime month;
  final int count;
}

/// The unread pile: owned books whose status is still "unread".
class UnreadPile {
  const UnreadPile({
    required this.books,
    required this.totalBytes,
    required this.knownPages,
    required this.estimatedPages,
    required this.withoutPageCount,
  });

  final int books;
  final int totalBytes;

  /// Pages summed over the unread books that state a page count.
  final int knownPages;

  /// [knownPages] plus a guess for each book with no page count: the median
  /// page count of the unread books that do have one. Zero guesses when none
  /// does -- better an honest "unknown" than an invented figure.
  final int estimatedPages;
  final int withoutPageCount;
}

/// Everything the Library statistics page shows.
class LibraryStats {
  const LibraryStats({
    required this.total,
    required this.byGenre,
    required this.byDecade,
    required this.byYear,
    required this.byFormat,
    required this.topAuthors,
    required this.unread,
    required this.addedLastYear,
    required this.addedAllTime,
    required this.unknownYear,
  });

  final int total;
  final List<StatCount> byGenre;

  /// Label is the decade's first year ("1990"); ascending.
  final List<StatCount> byDecade;

  /// Label is the year ("1995"); ascending.
  final List<StatCount> byYear;
  final Map<HoldingKind, int> byFormat;
  final List<StatCount> topAuthors;
  final UnreadPile unread;

  /// The 12 months ending with the current one, oldest first, zeros included.
  final List<MonthCount> addedLastYear;

  /// Every month from the first book to now, oldest first, gaps filled.
  final List<MonthCount> addedAllTime;

  /// Books with no publication year (left out of [byDecade] and [byYear]).
  final int unknownYear;
}

/// The library statistics, computed in one pass over [LibraryStatsBook]s.
///
/// **Pure on purpose**, like `ReadingStats`: month arithmetic is where this goes
/// wrong, and it should be testable without a database.
///
/// **What is counted.** The caller drops trashed books and the sample shelf
/// before they get here (see `LibraryStatsQueries`), so a trashed or bundled
/// book never skews the picture. This function itself drops one more group:
/// wishlist books, which are not on the shelf yet.
class LibraryStatsCalculator {
  const LibraryStatsCalculator._();

  /// Authors / genres shown before the rest are cut off.
  static const topLimit = 10;

  static LibraryStats compute(
    Iterable<LibraryStatsBook> all, {
    required DateTime now,
    int limit = topLimit,
  }) {
    final books = all.where((b) => b.status != 'wishlist').toList();

    final genres = <String, int>{};
    final authors = <String, int>{};
    final years = <int, int>{};
    final decades = <int, int>{};
    final formats = {for (final k in HoldingKind.values) k: 0};
    final perMonth = <DateTime, int>{};
    var unknownYear = 0;

    final unreadBooks = <LibraryStatsBook>[];

    for (final b in books) {
      for (final g in b.genres.toSet()) {
        genres[g] = (genres[g] ?? 0) + 1;
      }
      for (final a in b.authors.toSet()) {
        authors[a] = (authors[a] ?? 0) + 1;
      }
      final y = b.publishedYear;
      if (y == null) {
        unknownYear++;
      } else {
        years[y] = (years[y] ?? 0) + 1;
        final d = y - (y % 10);
        decades[d] = (decades[d] ?? 0) + 1;
      }
      final kind = holdingKind(b);
      formats[kind] = formats[kind]! + 1;

      final m = monthOf(b.createdAt);
      perMonth[m] = (perMonth[m] ?? 0) + 1;

      if (b.status == 'unread') unreadBooks.add(b);
    }

    // The last 12 months, oldest first, with empty months kept as zeros.
    final thisMonth = monthOf(now);
    final lastYear = [
      for (var i = 11; i >= 0; i--)
        MonthCount(
          DateTime(thisMonth.year, thisMonth.month - i),
          perMonth[DateTime(thisMonth.year, thisMonth.month - i)] ?? 0,
        ),
    ];

    // All time: from the earliest month to now (a future-dated import still
    // extends the range rather than vanishing).
    final allTime = <MonthCount>[];
    if (perMonth.isNotEmpty) {
      final first = perMonth.keys.reduce((a, b) => a.isBefore(b) ? a : b);
      final last = perMonth.keys.fold(thisMonth, (a, b) => a.isAfter(b) ? a : b);
      for (var m = first; !m.isAfter(last); m = DateTime(m.year, m.month + 1)) {
        allTime.add(MonthCount(m, perMonth[m] ?? 0));
      }
    }

    return LibraryStats(
      total: books.length,
      byGenre: _top(genres, limit),
      byDecade: _ascending(decades),
      byYear: _ascending(years),
      byFormat: formats,
      topAuthors: _top(authors, limit),
      unread: _pile(unreadBooks),
      addedLastYear: lastYear,
      addedAllTime: allTime,
      unknownYear: unknownYear,
    );
  }

  /// First day of the (local) month a moment falls in.
  static DateTime monthOf(DateTime t) {
    final l = t.toLocal();
    return DateTime(l.year, l.month);
  }

  /// A book's one-word format: its single kind of holding, "several" when it
  /// has more than one (a PDF and an EPUB, or a file and a paper copy), or
  /// none when it has neither a file nor a copy.
  static HoldingKind holdingKind(LibraryStatsBook b) {
    final files = b.formats.map((f) => f.toLowerCase()).toSet();
    final kinds = <HoldingKind>{
      for (final f in files)
        switch (f) {
          'pdf' => HoldingKind.pdf,
          'epub' => HoldingKind.epub,
          _ => HoldingKind.otherDigital,
        },
      if (b.copies > 0) HoldingKind.physical,
    };
    if (kinds.isEmpty) return HoldingKind.none;
    // Two different "other" extensions collapse to one kind but are two files.
    if (kinds.length > 1 || files.length > 1) return HoldingKind.several;
    return kinds.single;
  }

  /// Highest counts first; ties alphabetically so the order is stable.
  static List<StatCount> _top(Map<String, int> counts, int limit) {
    final list = [for (final e in counts.entries) StatCount(e.key, e.value)]
      ..sort((a, b) {
        final c = b.count.compareTo(a.count);
        return c != 0 ? c : a.label.toLowerCase().compareTo(b.label.toLowerCase());
      });
    return list.take(limit).toList();
  }

  static List<StatCount> _ascending(Map<int, int> counts) {
    final keys = counts.keys.toList()..sort();
    return [for (final k in keys) StatCount('$k', counts[k]!)];
  }

  static UnreadPile _pile(List<LibraryStatsBook> unread) {
    final known = [
      for (final b in unread)
        if (b.pageCount != null && b.pageCount! > 0) b.pageCount!,
    ]..sort();
    final knownPages = known.fold<int>(0, (a, b) => a + b);
    final missing = unread.length - known.length;
    final median = known.isEmpty ? 0 : known[known.length ~/ 2];
    return UnreadPile(
      books: unread.length,
      totalBytes: unread.fold<int>(0, (a, b) => a + b.fileBytes),
      knownPages: knownPages,
      estimatedPages: knownPages + missing * median,
      withoutPageCount: missing,
    );
  }

  /// The tallest bar, for scaling; at least 1 so a chart never divides by zero.
  static int maxCount(Iterable<int> counts) =>
      math.max(1, counts.fold(0, math.max));
}
