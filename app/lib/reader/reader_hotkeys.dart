import 'package:flutter/services.dart';

import '../shortcuts.dart';

/// The readers' keyboard shortcuts, independent of what holds focus.
///
/// **Why not `CallbackShortcuts`.** That is a `Focus` node, so it only sees a
/// key event that bubbles up from a focused descendant — and a reader has
/// nothing focusable in it. Until you clicked something, primary focus stayed on
/// the root scope, which is an *ancestor*, and Ctrl+F did nothing. Wrapping the
/// page in `Focus(autofocus: true)` only moved the problem: autofocus is applied
/// when the enclosing scope next gains focus, so whether it took effect depended
/// on timing, and the shortcut worked or didn't depending on how fast the book
/// opened.
///
/// A handler on [HardwareKeyboard] sees every key press whatever has focus,
/// which is what "Ctrl+F opens the search" has to mean in a page whose whole
/// content is a rendered document.
class ReaderHotkeys {
  ReaderHotkeys({
    required this.isActive,
    required this.onFind,
    required this.onGoTo,
    required this.onEscape,
  });

  /// Whether this reader should be answering right now — false once a dialog or
  /// another page is on top of it. Without this every reader left on the
  /// navigation stack would react at once.
  final bool Function() isActive;

  final void Function() onFind;
  final void Function() onGoTo;

  /// Returns true if Escape did something, so it isn't swallowed when it
  /// didn't — Escape still has to be able to close things above us.
  final bool Function() onEscape;

  void attach() => HardwareKeyboard.instance.addHandler(handle);
  void detach() => HardwareKeyboard.instance.removeHandler(handle);

  /// Returns true when the event was consumed. Handlers run *before* the focus
  /// system, so anything claimed here never reaches a text field — which is why
  /// only these three combinations are claimed, and only on the way down.
  bool handle(KeyEvent event) {
    if (event is! KeyDownEvent || !isActive()) return false;

    if (event.logicalKey == LogicalKeyboardKey.escape) return onEscape();

    final modifier = usesMetaModifier
        ? HardwareKeyboard.instance.isMetaPressed
        : HardwareKeyboard.instance.isControlPressed;
    if (!modifier) return false;

    if (event.logicalKey == LogicalKeyboardKey.keyF) {
      onFind();
      return true;
    }
    if (event.logicalKey == LogicalKeyboardKey.keyG) {
      onGoTo();
      return true;
    }
    return false;
  }
}
