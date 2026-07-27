import '../data/database.dart';
import 'layout_repository.dart';

/// The room, as a screen reader hears it (plan 5 #42).
///
/// The physical editor is a drag-and-drop `CustomPaint`. A canvas like that can
/// never be directly navigable — there is no meaningful tab order through a
/// spatial arrangement, and "book at 1.4 m, 0.9 m" is not an answer to any
/// question a person asks. So the canvas gets a *parallel* representation
/// instead: the same room read out the way you would describe it aloud, shelf
/// by shelf, left to right.
///
/// Pure logic, no Flutter and no database types beyond drift's row classes (the
/// same rule `locate.dart` follows), so the part worth arguing about — which
/// shelf a book belongs to and in what order the titles come out — is testable
/// without a widget. Shelf assignment reuses [LayoutRepository.nearestShelf]
/// rather than restating the "standing on" rule, because two copies of that
/// rule would eventually disagree and the summary would describe a room the
/// canvas isn't drawing.

/// One shelf and the books standing on it, in reading order.
class ShelfSummary {
  const ShelfSummary({required this.name, required this.titles});

  /// The shelf's own label, or a positional name like "Shelf 2" when it has
  /// none. Never empty: an unnamed shelf still has to be referred to somehow.
  final String name;

  /// Titles left to right along the shelf.
  final List<String> titles;

  int get count => titles.length;

  /// "Shelf 2: 3 books — Dune, Neuromancer, Solaris".
  ///
  /// The count leads because it is the fact a listener can hold on to; the
  /// titles follow for as long as they last. An empty shelf says so rather
  /// than trailing off after the colon.
  String get spoken => titles.isEmpty
      ? '$name: empty'
      : '$name: $count book${count == 1 ? '' : 's'} — ${titles.join(', ')}';
}

/// Groups a room's placed books by the shelf they stand on.
///
/// Shelves come out top to bottom (that is how you read a bookcase), then left
/// to right for two at the same height. Books on no shelf — floating after an
/// edit, or not overlapping any plank — are collected last under "Not on a
/// shelf" rather than being dropped, because a book the canvas shows and the
/// summary omits is worse than an awkward heading.
List<ShelfSummary> summarizeRoom({
  required List<PhysicalShelf> shelves,
  required List<PlacedBook> placed,
}) {
  final ordered = [...shelves]..sort((a, b) {
      final byHeight = _top(b).compareTo(_top(a)); // higher first
      if (byHeight != 0) return byHeight;
      return _left(a).compareTo(_left(b));
    });

  // Positional names are assigned over the *ordered* list, so "Shelf 2" is the
  // second shelf you would reach reading downwards, not the second one created.
  final names = <String, String>{};
  for (var i = 0; i < ordered.length; i++) {
    final label = ordered[i].label?.trim();
    names[ordered[i].id] =
        (label == null || label.isEmpty) ? 'Shelf ${i + 1}' : label;
  }

  final byShelf = <String, List<PlacedBook>>{};
  final loose = <PlacedBook>[];
  for (final book in placed) {
    final shelf = LayoutRepository.nearestShelf(
      placement: book.placement,
      shelves: shelves,
    );
    if (shelf == null) {
      loose.add(book);
    } else {
      (byShelf[shelf.id] ??= []).add(book);
    }
  }

  List<String> titlesOf(List<PlacedBook> books) => [
        for (final b in [...books]
          ..sort((a, b) => a.placement.x.compareTo(b.placement.x)))
          b.book.title,
      ];

  return [
    for (final shelf in ordered)
      ShelfSummary(
        name: names[shelf.id]!,
        titles: titlesOf(byShelf[shelf.id] ?? const []),
      ),
    if (loose.isNotEmpty)
      ShelfSummary(name: 'Not on a shelf', titles: titlesOf(loose)),
  ];
}

/// The whole room in one string, for the canvas's `Semantics.label`.
String roomSemanticLabel(List<ShelfSummary> summaries) {
  if (summaries.isEmpty) return 'Empty room. Add a shelf, then place books.';
  return summaries.map((s) => s.spoken).join('. ');
}

double _top(PhysicalShelf s) => s.y1 > s.y2 ? s.y1 : s.y2;
double _left(PhysicalShelf s) => s.x1 < s.x2 ? s.x1 : s.x2;
