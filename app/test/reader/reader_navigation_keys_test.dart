import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_hotkeys.dart';

/// Turning pages from the keyboard (issue #10, items 1–2).
///
/// Reported from Windows: in Pages mode the arrow keys did nothing. They did
/// nothing in either mode, in fact — the reader bound Ctrl+F and Ctrl+G and
/// no navigation at all, and continuous scrolling only worked because pdfrx
/// scrolls itself.
///
/// The rule the keys follow is the interesting part, so it lives in
/// [ReaderHotkeys] and is asserted here rather than on a rendered PDF:
///
/// - Page Up/Down move a whole page, in both modes.
/// - Arrows turn the page when pages are what you are looking at, and nudge
///   when you are in a continuous scroll — where a full page per press would
///   be a lurch.
///
/// And the guard that matters more than any of it: **a text field wins.**
/// Handlers here run before the focus system, so a claimed arrow key never
/// reaches the search box in the reader's own app bar.
void main() {
  // `_navigate` asks HardwareKeyboard whether a modifier is held, and that
  // needs a binding.
  TestWidgetsFlutterBinding.ensureInitialized();

  late List<String> moves;

  ReaderHotkeys hotkeys({
    bool paged = false,
    bool active = true,
    bool typing = false,
  }) =>
      ReaderHotkeys(
        isActive: () => active,
        onFind: () => moves.add('find'),
        onGoTo: () => moves.add('goto'),
        onEscape: () => false,
        isPaged: () => paged,
        onPageStep: (d) => moves.add('page $d'),
        onNudge: (d) => moves.add('nudge $d'),
        isTextFieldFocused: () => typing,
      );

  setUp(() => moves = []);

  KeyDownEvent down(LogicalKeyboardKey key) => KeyDownEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: key,
        timeStamp: Duration.zero,
      );

  group('paged', () {
    test('arrows turn the page, both axes', () {
      final keys = hotkeys(paged: true);
      for (final k in [
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.arrowDown,
      ]) {
        expect(keys.handle(down(k)), isTrue, reason: '$k should be claimed');
      }
      for (final k in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowUp,
      ]) {
        expect(keys.handle(down(k)), isTrue);
      }
      expect(moves, ['page 1', 'page 1', 'page -1', 'page -1']);
    });

    test('page up and down do the same', () {
      final keys = hotkeys(paged: true);
      keys.handle(down(LogicalKeyboardKey.pageDown));
      keys.handle(down(LogicalKeyboardKey.pageUp));
      expect(moves, ['page 1', 'page -1']);
    });
  });

  group('continuous scroll', () {
    test('arrows nudge rather than jumping a page', () {
      final keys = hotkeys();
      keys.handle(down(LogicalKeyboardKey.arrowDown));
      keys.handle(down(LogicalKeyboardKey.arrowUp));
      expect(moves, ['nudge 1', 'nudge -1']);
    });

    test('page up and down still move a page', () {
      final keys = hotkeys();
      keys.handle(down(LogicalKeyboardKey.pageDown));
      keys.handle(down(LogicalKeyboardKey.pageUp));
      expect(moves, ['page 1', 'page -1'],
          reason: 'Page Down means a screenful everywhere else too');
    });
  });

  group('what it must not claim', () {
    test('nothing while a text field has focus', () {
      // The reader's search box is a TextField in its own app bar. Stealing
      // Left from it would stop the caret moving — a worse bug than the one
      // these keys fix.
      final keys = hotkeys(paged: true, typing: true);
      for (final k in [
        LogicalKeyboardKey.arrowLeft,
        LogicalKeyboardKey.arrowRight,
        LogicalKeyboardKey.pageUp,
        LogicalKeyboardKey.pageDown,
      ]) {
        expect(keys.handle(down(k)), isFalse, reason: '$k belongs to the field');
      }
      expect(moves, isEmpty);
    });

    test('nothing while another page is on top', () {
      final keys = hotkeys(paged: true, active: false);
      expect(keys.handle(down(LogicalKeyboardKey.arrowRight)), isFalse);
      expect(moves, isEmpty);
    });

    test('a key up event, so one press moves one page', () {
      final keys = hotkeys(paged: true);
      final up = KeyUpEvent(
        physicalKey: PhysicalKeyboardKey.keyA,
        logicalKey: LogicalKeyboardKey.arrowRight,
        timeStamp: Duration.zero,
      );
      expect(keys.handle(up), isFalse);
      expect(moves, isEmpty);
    });

    test('a reader with no navigation wired up ignores them', () {
      // The EPUB reader shares this class and scrolls its own way.
      final keys = ReaderHotkeys(
        isActive: () => true,
        onFind: () {},
        onGoTo: () {},
        onEscape: () => false,
        isTextFieldFocused: () => false,
      );
      expect(keys.handle(down(LogicalKeyboardKey.arrowRight)), isFalse);
    });
  });
}
