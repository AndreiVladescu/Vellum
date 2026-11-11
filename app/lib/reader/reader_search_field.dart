import 'dart:async';

import 'package:flutter/material.dart';

/// The query box in a reader's app bar, drawn in the *reader's* colours.
///
/// **Why it does not just use the app theme.** The bar is painted with the
/// reader theme (a white page, a sepia one, night mode) while a bare
/// `TextField` takes its text, hint, caret and selection from the app theme.
/// Put a dark app theme over a light page and the typed text came out nearly
/// the colour of the bar it sat on. Everything here is derived from
/// [foreground], the colour the bar already uses for its title and icons, so the
/// field is legible whichever pair of themes is in force.
class ReaderSearchField extends StatelessWidget {
  const ReaderSearchField({
    super.key,
    required this.controller,
    required this.focusNode,
    required this.foreground,
    required this.onSubmitted,
    this.onChanged,
    this.hint = 'Search in this book',
  });

  final TextEditingController controller;

  /// Owned by the reader, which has to be able to focus the field from outside
  /// (Ctrl+F) — `autofocus` only works when nothing else in the scope holds
  /// focus, and a PDF you have clicked on does.
  final FocusNode focusNode;

  /// The reader theme's foreground: text, caret and the basis of the hint.
  final Color foreground;

  final ValueChanged<String>? onChanged;
  final ValueChanged<String> onSubmitted;
  final String hint;

  @override
  Widget build(BuildContext context) {
    return Theme(
      // Caret, selection highlight and the mobile handles all come from the
      // selection theme rather than from the text style.
      data: Theme.of(context).copyWith(
        textSelectionTheme: TextSelectionThemeData(
          cursorColor: foreground,
          selectionColor: foreground.withValues(alpha: 0.28),
          selectionHandleColor: foreground,
        ),
      ),
      child: TextField(
        controller: controller,
        focusNode: focusNode,
        style: TextStyle(color: foreground),
        cursorColor: foreground,
        textInputAction: TextInputAction.search,
        decoration: InputDecoration(
          hintText: hint,
          hintStyle: TextStyle(color: foreground.withValues(alpha: 0.6)),
          border: InputBorder.none,
          filled: false,
        ),
        // Supplying this (even empty) switches off the default "Enter ends
        // editing and drops focus". Enter here means "next match"; the caret
        // should stay in the box for the next one.
        onEditingComplete: () {},
        onChanged: onChanged,
        onSubmitted: onSubmitted,
      ),
    );
  }
}

/// Foreground for the bar's search buttons, disabled ones included: those
/// would otherwise take the app theme's disabled grey, which has no
/// relationship to the reader's page colour.
ButtonStyle readerSearchIconStyle(Color foreground) => IconButton.styleFrom(
      foregroundColor: foreground,
      disabledForegroundColor: foreground.withValues(alpha: 0.38),
    );

/// Puts the caret in [node]'s field with its text selected, so typing replaces
/// the old query and Ctrl+F again is "start a new search".
///
/// Safe to call before the field exists only if [node] is attached by the next
/// frame — the readers call it from a post-frame callback for that reason.
void focusSearchField(FocusNode node, TextEditingController controller) {
  node.requestFocus();
  controller.selection =
      TextSelection(baseOffset: 0, extentOffset: controller.text.length);
}

/// Runs the last thing it was given once [delay] has passed without another.
///
/// Search as you type: a PDF search walks every page's text, so one run per
/// pause in typing is the right amount of work, not one per keystroke.
class Debouncer {
  Debouncer(this.delay);

  final Duration delay;
  Timer? _timer;

  void run(void Function() action) {
    _timer?.cancel();
    _timer = Timer(delay, action);
  }

  void cancel() {
    _timer?.cancel();
    _timer = null;
  }
}
