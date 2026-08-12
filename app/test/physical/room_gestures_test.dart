import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/physical/room_gestures.dart';

/// The two room rules from issue #10, items 5 and 7.
void main() {
  group('what a press on a book does', () {
    test('the selected book moves', () {
      expect(bookAcceptsDrag(bookId: 'b1', selectedBookId: 'b1'), isTrue);
    });

    test('an unselected one does not, so the press pans instead', () {
      // The whole point on a phone: dragging across the room to look around
      // must not quietly rearrange somebody's shelf.
      expect(bookAcceptsDrag(bookId: 'b1', selectedBookId: 'b2'), isFalse);
      expect(bookAcceptsDrag(bookId: 'b1', selectedBookId: null), isFalse);
    });
  });

  group('the Add books button', () {
    test('shows when the room is just sitting there', () {
      expect(showAddBooksButton(bookSelected: false, grouping: false), isTrue);
    });

    test('stands down for the selected-book toolbar', () {
      expect(showAddBooksButton(bookSelected: true, grouping: false), isFalse);
    });

    test('and for the grouping bar — the reported bug', () {
      // It knew about the first mode and not the second, and sat on top of
      // that bar's Cancel and Group buttons.
      expect(showAddBooksButton(bookSelected: false, grouping: true), isFalse);
    });

    test('and for both at once', () {
      expect(showAddBooksButton(bookSelected: true, grouping: true), isFalse);
    });
  });
}
