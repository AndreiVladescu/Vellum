import '../data/database.dart';
import '../settings/shelf_sort.dart';

/// Filters [books] by the shelf search [query]:
///
/// - `genre:<name>` matches books having a genre that contains `<name>`.
/// - otherwise the text matches the title, subtitle, or any author name.
///
/// All matching is case-insensitive and substring-based. [authorsByBook] and
/// [genresByBook] map a book id to its author / genre names.
List<Book> filterBooks({
  required List<Book> books,
  required String query,
  required Map<String, List<String>> authorsByBook,
  required Map<String, List<String>> genresByBook,
}) {
  final q = query.trim().toLowerCase();
  if (q.isEmpty) return books;
  if (q.startsWith('genre:')) {
    final wanted = q.substring('genre:'.length).trim();
    if (wanted.isEmpty) return books;
    return [
      for (final b in books)
        if ((genresByBook[b.id] ?? const [])
            .any((g) => g.toLowerCase().contains(wanted)))
          b,
    ];
  }
  return [
    for (final b in books)
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
  }
  return sorted;
}
