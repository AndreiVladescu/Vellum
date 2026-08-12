/// The two rules about what a press on the room does.
///
/// Small enough to read in one go, and separated from the editor because both
/// were reported as bugs by someone using the app rather than reading it — the
/// kind of rule that is easy to state, easy to get wrong in a 2,000-line
/// widget, and impossible to test in place.
library;

/// Whether a press on a book picks it up, or pans the room instead.
///
/// **Only the selected book moves.** On a desktop this makes a click that was
/// meant to select behave itself; on a phone it is the difference between
/// pushing the room around with your thumb and silently rearranging somebody's
/// shelf. Selecting first is one extra tap, and it is the same bargain the
/// editor already strikes with shelves, which have to be unanchored before
/// they will move.
///
/// A press on a book that is *not* selected does not reach whatever is behind
/// it either: the book is on top, so grabbing the prop underneath it would be
/// the same surprise wearing a different hat. The caller stops at the book.
bool bookAcceptsDrag({
  required String bookId,
  required String? selectedBookId,
}) =>
    bookId == selectedBookId;

/// Whether the "Add books" button belongs on screen.
///
/// It has to stand down for anything that owns the bottom of the screen. It
/// already knew about the selected-book toolbar; it did not know about the
/// grouping bar, and sat on top of that bar's Cancel and Group buttons. Stated
/// here so the next mode is one argument rather than one more thing to
/// remember.
bool showAddBooksButton({
  required bool bookSelected,
  required bool grouping,
}) =>
    !bookSelected && !grouping;
