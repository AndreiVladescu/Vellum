import '../data/database.dart';
import '../settings/shelf_sort.dart';

/// Filters [books] by an optional exact-match [genre] facet and the shelf
/// search [query], composed with AND:
///
/// - [genre] (from the genre-filter control) keeps only books tagged with that
///   exact genre name. Applied first, so text search runs within the facet.
/// - `genre:<name>` in [query] matches books having a genre that contains
///   `<name>` (a power-user shorthand kept for typing).
/// - otherwise the text matches the title, subtitle, or any author name.
///
/// All matching is case-insensitive and substring-based (the [genre] facet is
/// exact). [authorsByBook] and [genresByBook] map a book id to its author /
/// genre names.
List<Book> filterBooks({
  required List<Book> books,
  required String query,
  required Map<String, List<String>> authorsByBook,
  required Map<String, List<String>> genresByBook,
  String? genre,
}) {
  // Exact-match genre facet first, so the text query narrows within it.
  var pool = books;
  if (genre != null && genre.isNotEmpty) {
    pool = [
      for (final b in pool)
        if ((genresByBook[b.id] ?? const []).contains(genre)) b,
    ];
  }

  final q = query.trim().toLowerCase();
  if (q.isEmpty) return pool;
  if (q.startsWith('genre:')) {
    final wanted = q.substring('genre:'.length).trim();
    if (wanted.isEmpty) return pool;
    return [
      for (final b in pool)
        if ((genresByBook[b.id] ?? const [])
            .any((g) => g.toLowerCase().contains(wanted)))
          b,
    ];
  }
  return [
    for (final b in pool)
      if (b.title.toLowerCase().contains(q) ||
          (b.subtitle?.toLowerCase().contains(q) ?? false) ||
          (authorsByBook[b.id] ?? const [])
              .any((a) => a.toLowerCase().contains(q)))
        b,
  ];
}

/// Returns [books] ordered per [sort]. Author/year sorts put books that lack the
/// key (no author, no year) last; ties fall back to title. Case-insensitive.
/// Does not mutate [books].
List<Book> sortBooks({
  required List<Book> books,
  required ShelfSort sort,
  required Map<String, List<String>> authorsByBook,
}) {
  int byTitle(Book a, Book b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());

  final sorted = [...books];
  switch (sort) {
    case ShelfSort.title:
      sorted.sort(byTitle);
    case ShelfSort.author:
      String firstAuthor(Book b) =>
          (authorsByBook[b.id] ?? const []).firstOrNull?.toLowerCase() ?? '';
      sorted.sort((a, b) {
        final aa = firstAuthor(a);
        final bb = firstAuthor(b);
        // Author-less books sort last.
        if (aa.isEmpty != bb.isEmpty) return aa.isEmpty ? 1 : -1;
        final c = aa.compareTo(bb);
        return c != 0 ? c : byTitle(a, b);
      });
    case ShelfSort.year:
      sorted.sort((a, b) {
        final ay = a.publishedYear;
        final by = b.publishedYear;
        // Year-less books sort last.
        if ((ay == null) != (by == null)) return ay == null ? 1 : -1;
        final c = (ay ?? 0).compareTo(by ?? 0);
        return c != 0 ? c : byTitle(a, b);
      });
    case ShelfSort.series:
      // This helper sorts a plain list of books and has no series *names* — the
      // shelf's real sort happens in SQL (`LibraryQueries`), which joins them.
      // Ordering by index within a series id keeps the two consistent for the
      // callers that still use this path (search results, tests).
      sorted.sort((a, b) {
        final asId = a.seriesId;
        final bsId = b.seriesId;
        // Series-less books sort last.
        if ((asId == null) != (bsId == null)) return asId == null ? 1 : -1;
        if (asId != null && bsId != null && asId != bsId) {
          return asId.compareTo(bsId);
        }
        final ai = a.seriesIndex;
        final bi = b.seriesIndex;
        if ((ai == null) != (bi == null)) return ai == null ? 1 : -1;
        final c = (ai ?? 0).compareTo(bi ?? 0);
        return c != 0 ? c : byTitle(a, b);
      });
  }
  return sorted;
}
