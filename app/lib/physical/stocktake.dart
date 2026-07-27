import '../data/database.dart';
import 'layout_repository.dart';

/// Reconciling the room's *map* against the actual shelf (plan 5 #30).
///
/// The physical model is deliberately "reference, not inventory": a placement
/// says *this copy sits here* so the room can be drawn, and a fresh
/// `physical_copy` is minted per placement. That is the right call for a visual
/// tool, and this does not change it. A stocktake answers a narrower question —
/// **does the map still match the shelf?** — and its output is a list of
/// discrepancies for a human to act on, never an automatic correction.
///
/// Pure logic and no Flutter, like `locate.dart`: the set maths is the part
/// worth arguing about, and it should be testable without a widget or a camera.

/// What a stocktake found, once the walking is done.
class StocktakeResult {
  const StocktakeResult({
    required this.confirmed,
    required this.missing,
    required this.unexpected,
  });

  /// Placed here, and found here. The boring, hoped-for case.
  final List<PlacedBook> confirmed;

  /// Placed here, but not found — the shelf disagrees with the map. Lent out,
  /// reshelved elsewhere, or genuinely lost.
  final List<PlacedBook> missing;

  /// Found here, but not placed here: books the map doesn't know are on this
  /// shelf. Either placed in another room, or in the library with no placement
  /// at all.
  final List<UnexpectedBook> unexpected;

  int get scanned => confirmed.length + unexpected.length;

  /// True when the map and the shelf agree completely — the one state that
  /// needs no follow-up.
  bool get isClean => missing.isEmpty && unexpected.isEmpty;
}

/// A book found on the shelf that the map didn't expect here.
class UnexpectedBook {
  const UnexpectedBook({required this.book, this.placedElsewhere});

  final Book book;

  /// Where the map thinks this book is, when it thinks anything — so the
  /// report can say "this is supposed to be in the study" rather than just
  /// "unexpected", which is the difference between an answer and a shrug.
  final String? placedElsewhere;

  bool get isUnplaced => placedElsewhere == null;
}

/// Reconciles what was found against what was placed.
///
/// [placed] is the scope being counted (one shelf, or a whole room);
/// [foundBookIds] is what the user actually ticked or scanned; [locationOf]
/// answers where else a book is placed, for the unexpected list.
///
/// Matching is by **book**, not by copy or placement: a person walking a shelf
/// identifies a book, and asking them to distinguish two copies of the same
/// title by placement id is asking for a number they cannot see. Two copies of
/// one book placed here are therefore confirmed together when it is found —
/// deliberately optimistic, and the alternative (reporting one of them missing
/// because only one was ticked) would be wrong far more often than right.
StocktakeResult reconcile({
  required List<PlacedBook> placed,
  required Set<String> foundBookIds,
  required List<Book> library,
  String? Function(String bookId)? locationOf,
}) {
  final confirmed = <PlacedBook>[];
  final missing = <PlacedBook>[];
  final placedBookIds = <String>{};

  for (final entry in placed) {
    placedBookIds.add(entry.book.id);
    if (foundBookIds.contains(entry.book.id)) {
      confirmed.add(entry);
    } else {
      missing.add(entry);
    }
  }

  final byId = {for (final b in library) b.id: b};
  final unexpected = <UnexpectedBook>[];
  for (final id in foundBookIds) {
    if (placedBookIds.contains(id)) continue;
    final book = byId[id];
    // A scan that matches no book in the library at all is not reported here:
    // "you own something you haven't catalogued" is the import flow's problem,
    // and mixing it into a stocktake would bury the discrepancies that matter.
    if (book == null) continue;
    unexpected.add(UnexpectedBook(
      book: book,
      placedElsewhere: locationOf?.call(id),
    ));
  }

  int byTitle(Book a, Book b) =>
      a.title.toLowerCase().compareTo(b.title.toLowerCase());
  confirmed.sort((a, b) => byTitle(a.book, b.book));
  missing.sort((a, b) => byTitle(a.book, b.book));
  unexpected.sort((a, b) => byTitle(a.book, b.book));

  return StocktakeResult(
    confirmed: confirmed,
    missing: missing,
    unexpected: unexpected,
  );
}

/// The books in [placed] that stand on [shelfId], for a shelf-scoped count.
///
/// Uses the same "standing on" rule the canvas and the accessible summary do
/// (`LayoutRepository.nearestShelf`), so a stocktake counts exactly the books a
/// person sees on that plank.
List<PlacedBook> onShelf({
  required String shelfId,
  required List<PlacedBook> placed,
  required List<PhysicalShelf> shelves,
}) =>
    [
      for (final entry in placed)
        if (LayoutRepository.nearestShelf(
              placement: entry.placement,
              shelves: shelves,
            )?.id ==
            shelfId)
          entry,
    ];
