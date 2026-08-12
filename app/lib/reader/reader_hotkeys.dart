import 'package:flutter/services.dart';
import 'package:flutter/widgets.dart';

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
    this.isPaged,
    this.onPageStep,
    this.onNudge,
    bool Function()? isTextFieldFocused,
  }) : isTextFieldFocused = isTextFieldFocused ?? _editableHasFocus;

  /// Whether this reader should be answering right now — false once a dialog or
  /// another page is on top of it. Without this every reader left on the
  /// navigation stack would react at once.
  final bool Function() isActive;

  final void Function() onFind;
  final void Function() onGoTo;

  /// Returns true if Escape did something, so it isn't swallowed when it
  /// didn't — Escape still has to be able to close things above us.
  final bool Function() onEscape;

  /// Whether the reader is showing one page at a time. Arrows mean different
  /// things in the two modes: turning a page is the whole gesture in paged
  /// mode, while in a continuous scroll it would be a lurch, so there they
  /// nudge instead. Page Up/Down mean a page in both.
  final bool Function()? isPaged;

  /// Move by whole pages. +1 is forward.
  final void Function(int delta)? onPageStep;

  /// Move by a little — a few lines' worth of scrolling. +1 is downward.
  final void Function(int delta)? onNudge;

  /// Whether something that takes typing holds focus.
  ///
  /// **The reason navigation keys are guarded at all.** Handlers here run
  /// before the focus system, so a claimed key never reaches a text field —
  /// and the reader has one in its own app bar for searching. Claiming Left
  /// while someone is editing a query would stop the caret moving, which is a
  /// worse bug than the one this fixes.
  final bool Function() isTextFieldFocused;

  static bool _editableHasFocus() =>
      FocusManager.instance.primaryFocus?.context?.widget is EditableText;

  void attach() => HardwareKeyboard.instance.addHandler(handle);
  void detach() => HardwareKeyboard.instance.removeHandler(handle);

  /// Returns true when the event was consumed. Handlers run *before* the focus
  /// system, so anything claimed here never reaches a text field — which is why
  /// only these three combinations are claimed, and only on the way down.
  bool handle(KeyEvent event) {
    if (event is! KeyDownEvent || !isActive()) return false;

    if (event.logicalKey == LogicalKeyboardKey.escape) return onEscape();

    if (_navigate(event.logicalKey)) return true;

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

  /// Moving through the book with no modifier held. Returns true when the key
  /// was ours.
  bool _navigate(LogicalKeyboardKey key) {
    final step = onPageStep;
    final nudge = onNudge;
    if (step == null || nudge == null) return false;
    // A modifier turns these into somebody else's shortcut (Ctrl+Home, and
    // whatever the platform does with Ctrl+PageDown), so leave them alone.
    if (HardwareKeyboard.instance.isControlPressed ||
        HardwareKeyboard.instance.isMetaPressed ||
        HardwareKeyboard.instance.isAltPressed) {
      return false;
    }
    if (isTextFieldFocused()) return false;

    if (key == LogicalKeyboardKey.pageDown) {
      step(1);
      return true;
    }
    if (key == LogicalKeyboardKey.pageUp) {
      step(-1);
      return true;
    }

    final forward = key == LogicalKeyboardKey.arrowRight ||
        key == LogicalKeyboardKey.arrowDown;
    final back = key == LogicalKeyboardKey.arrowLeft ||
        key == LogicalKeyboardKey.arrowUp;
    if (!forward && !back) return false;

    final delta = forward ? 1 : -1;
    if (isPaged?.call() ?? false) {
      step(delta);
    } else {
      nudge(delta);
    }
    return true;
  }
}
