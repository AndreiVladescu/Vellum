// The readers' Ctrl+F / Ctrl+G / Escape.
//
// These run on HardwareKeyboard rather than through a Focus node, because a
// reader has nothing focusable in it and primary focus stays on the root scope
// until something is clicked — so a `CallbackShortcuts` descendant never saw
// the event. Handlers run before the focus system, so what this claims never
// reaches a text field; that is what the tests below are really about.
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_hotkeys.dart';

KeyEvent _down(LogicalKeyboardKey key) => KeyDownEvent(
      physicalKey: PhysicalKeyboardKey.keyF,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

KeyEvent _up(LogicalKeyboardKey key) => KeyUpEvent(
      physicalKey: PhysicalKeyboardKey.keyF,
      logicalKey: key,
      timeStamp: Duration.zero,
    );

void main() {
  late List<String> calls;
  late bool active;
  late bool searchOpen;
  late ReaderHotkeys hotkeys;

  setUp(() {
    calls = [];
    active = true;
    searchOpen = false;
    hotkeys = ReaderHotkeys(
      isActive: () => active,
      onFind: () => calls.add('find'),
      onGoTo: () => calls.add('goto'),
      onEscape: () {
        if (!searchOpen) return false;
        calls.add('escape');
        return true;
      },
    );
  });

  /// Presses [key] with the command modifier held, the way the platform
  /// reports it — the handler asks HardwareKeyboard what is down.
  Future<bool> pressWithModifier(LogicalKeyboardKey key) async {
    final modifier = LogicalKeyboardKey.controlLeft;
    await simulateKeyDownEvent(modifier);
    final handled = hotkeys.handle(_down(key));
    await simulateKeyUpEvent(modifier);
    return handled;
  }

  test('the modifier plus F asks for the search', () async {
    expect(await pressWithModifier(LogicalKeyboardKey.keyF), isTrue);
    expect(calls, ['find']);
  });

  test('the modifier plus G asks for the page box', () async {
    expect(await pressWithModifier(LogicalKeyboardKey.keyG), isTrue);
    expect(calls, ['goto']);
  });

  test('a bare letter is left alone, so typing still works', () {
    // The handler runs *before* the focus system: claiming plain F would mean
    // the letter never reached the search field it just opened.
    expect(hotkeys.handle(_down(LogicalKeyboardKey.keyF)), isFalse);
    expect(hotkeys.handle(_down(LogicalKeyboardKey.keyG)), isFalse);
    expect(calls, isEmpty);
  });

  test('key-up is not a second press', () {
    expect(hotkeys.handle(_up(LogicalKeyboardKey.keyF)), isFalse);
    expect(calls, isEmpty);
  });

  test('a reader under a dialog or another page stays quiet', () async {
    // Every reader left on the navigation stack still has its handler
    // attached; without this they would all answer at once.
    active = false;
    expect(await pressWithModifier(LogicalKeyboardKey.keyF), isFalse);
    expect(calls, isEmpty);
  });

  test('Escape closes the search, and only then', () {
    // Unclaimed when there is nothing to close, so Escape can still reach
    // whatever else would use it.
    expect(hotkeys.handle(_down(LogicalKeyboardKey.escape)), isFalse);
    expect(calls, isEmpty);

    searchOpen = true;
    expect(hotkeys.handle(_down(LogicalKeyboardKey.escape)), isTrue);
    expect(calls, ['escape']);
  });

  test('an unrelated combination is not swallowed', () async {
    expect(await pressWithModifier(LogicalKeyboardKey.keyC), isFalse);
    expect(calls, isEmpty);
  });

  testWidgets('attaching and detaching leaves no handler behind',
      (tester) async {
    // A reader that kept its handler after being popped would keep answering
    // shortcuts for a book that is no longer open.
    hotkeys.attach();
    await pressWithModifier(LogicalKeyboardKey.keyF);
    hotkeys.detach();

    await simulateKeyDownEvent(LogicalKeyboardKey.controlLeft);
    await simulateKeyDownEvent(LogicalKeyboardKey.keyF);
    await simulateKeyUpEvent(LogicalKeyboardKey.keyF);
    await simulateKeyUpEvent(LogicalKeyboardKey.controlLeft);
    expect(calls, ['find'], reason: 'only the press made while attached');
  });
}
