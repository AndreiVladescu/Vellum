/// Finding a physical book, tidying a shelf, and the shelf-label link format
/// (plan 5 #28).
///
/// Pure logic, no Flutter and no database types beyond drift's row classes, so
/// the parts worth arguing about — which books a search matches, what order a
/// tidy produces, where each book ends up — are unit-testable without a widget.
library;

import 'dart:math' as math;

import '../data/database.dart';

/// Where one copy of a book physically is: which room, and which shelf in it.
///
/// A book can have several — two copies in two rooms, or two copies on the same
/// shelf — which is exactly why *Find my copy* has to be able to say "this one
/// of three" rather than silently picking the first row it finds.
class BookSighting {
  const BookSighting({
    required this.placementId,
    required this.copyId,
    required this.environmentId,
    required this.environmentName,
    required this.x,
    required this.y,
    this.shelfLabel,
  });

  final String placementId;
  final String copyId;
  final String environmentId;
  final String environmentName;

  /// The placement's world position (metres, bottom-left), so the camera can
  /// be pointed at it.
  final double x;
  final double y;

  final String? shelfLabel;

  /// "Living room · Shelf 2", or just the room when the shelf is unlabelled.
  String get display =>
      shelfLabel == null ? environmentName : '$environmentName · $shelfLabel';
}

/// Whether [book] matches a physical-view search [query].
///
/// Deliberately dumber than the FTS5 index the digital shelf uses: this filter
/// runs against the handful of books in one room, has to survive a partially
/// typed word, and — since it *dims* the rest rather than hiding them — a false
/// positive costs nothing while a miss makes the feature look broken. Empty or
/// whitespace queries match everything, so an empty field is not a filter.
bool bookMatches(Book book, String query, {List<String> authors = const []}) {
  final needle = query.trim().toLowerCase();
  if (needle.isEmpty) return true;
  final haystacks = [
    book.title,
    book.subtitle ?? '',
    book.isbn ?? '',
    ...authors,
  ];
  return haystacks.any((h) => h.toLowerCase().contains(needle));
}

/// How a tidy orders the books on a shelf.
enum TidySort {
  author('By author'),
  title('By title'),
  series('By series');

  const TidySort(this.label);

  final String label;
}

/// One book about to be tidied: what it is, how wide its spine is, and where it
/// currently stands.
class TidyBook {
  const TidyBook({
    required this.placementId,
    required this.width,
    required this.title,
    this.author,
    this.seriesName,
    this.seriesIndex,
  });

  final String placementId;

  /// Spine thickness in metres, from `PhysicalMetrics.thickness`.
  final double width;

  final String title;
  final String? author;
  final String? seriesName;
  final double? seriesIndex;
}

/// Where a tidied book should end up.
typedef TidyMove = ({String placementId, double x});

/// Orders [books] by [sort].
///
/// Every ordering falls through to the title and then to the placement id, so a
/// tidy is **deterministic**: two books by the same author with the same title
/// must not swap places every time the button is pressed, or the shelf appears
/// to shuffle itself for no reason.
///
/// Books with no author (or no series, when sorting by series) go **last**
/// rather than first: an unknown value sorting to the front would put the
/// least-identifiable books at eye level, which is the opposite of useful.
List<TidyBook> tidyOrder(List<TidyBook> books, TidySort sort) {
  int byMissingLast(String? a, String? b) {
    final left = a?.trim();
    final right = b?.trim();
    final leftEmpty = left == null || left.isEmpty;
    final rightEmpty = right == null || right.isEmpty;
    if (leftEmpty && rightEmpty) return 0;
    if (leftEmpty) return 1;
    if (rightEmpty) return -1;
    return left.toLowerCase().compareTo(right.toLowerCase());
  }

  final ordered = [...books];
  ordered.sort((a, b) {
    switch (sort) {
      case TidySort.author:
        final byAuthor = byMissingLast(a.author, b.author);
        if (byAuthor != 0) return byAuthor;
      case TidySort.series:
        final bySeries = byMissingLast(a.seriesName, b.seriesName);
        if (bySeries != 0) return bySeries;
        // Within a series, volume order is the whole point — and a volume-less
        // book in a series (a companion, an omnibus) goes after the numbered
        // ones rather than pretending to be volume zero.
        final ai = a.seriesIndex;
        final bi = b.seriesIndex;
        if (ai != null && bi != null && ai != bi) return ai.compareTo(bi);
        if (ai == null && bi != null) return 1;
        if (ai != null && bi == null) return -1;
      case TidySort.title:
        break;
    }
    final byTitle = a.title.toLowerCase().compareTo(b.title.toLowerCase());
    if (byTitle != 0) return byTitle;
    return a.placementId.compareTo(b.placementId);
  });
  return ordered;
}

/// Packs [books] (already in the order you want) left-to-right along a shelf
/// spanning [shelfLeft]..[shelfRight], returning where each one goes.
///
/// Books are placed **flush against each other** starting at the left end —
/// that is what a tidied shelf looks like, and any gap would just be an
/// arbitrary number pretending to be a design.
///
/// When the books are wider than the shelf they still get packed in order and
/// the overflow runs past the right end, rather than being stacked or dropped:
/// the room editor's gravity pass will deal with anything left unsupported, and
/// silently hiding a book because the shelf is full would be much worse than
/// showing it sticking out. Only moves that actually change a position are
/// returned, so an already-tidy shelf writes nothing.
List<TidyMove> tidyPositions(
  List<TidyBook> books, {
  required double shelfLeft,
  required double shelfRight,
  required Map<String, double> currentX,
  double epsilon = 0.0005,
}) {
  final left = math.min(shelfLeft, shelfRight);
  var cursor = left;
  final moves = <TidyMove>[];
  for (final book in books) {
    final target = cursor;
    cursor += book.width;
    final now = currentX[book.placementId];
    if (now == null || (now - target).abs() > epsilon) {
      moves.add((placementId: book.placementId, x: target));
    }
  }
  return moves;
}

/// The deep link a shelf label carries: `vellum://shelf/<id>`.
///
/// Scanning one opens that shelf's room **in Vellum's own scanner** rather than
/// through an OS URL handler. That is a deliberate choice: registering a custom
/// scheme means per-platform manifest work on four platforms, and the scanner is
/// already there for ISBNs (#16). The trade is that you open the app first —
/// which you were going to do anyway, since the point is to look at the room.
String shelfLink(String shelfId) => 'vellum://shelf/$shelfId';

/// The shelf id inside a [shelfLink], or null if [raw] is any other barcode.
///
/// Tolerant of what a scanner actually hands back: surrounding whitespace, a
/// trailing slash, and mixed case in the scheme. Not tolerant of a *different*
/// host — `vellum://book/x` is not a shelf and must not be treated as one.
String? parseShelfLink(String raw) {
  final trimmed = raw.trim();
  final uri = Uri.tryParse(trimmed);
  if (uri == null) return null;
  if (uri.scheme.toLowerCase() != 'vellum') return null;
  if (uri.host.toLowerCase() != 'shelf') return null;
  final segments = [
    for (final s in uri.pathSegments)
      if (s.trim().isNotEmpty) s.trim(),
  ];
  if (segments.length != 1) return null;
  return segments.single;
}
