import '../data/database.dart';

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
