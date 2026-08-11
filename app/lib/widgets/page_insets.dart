import 'package:flutter/material.dart';

/// Padding for a full-page scroll view, clear of the system navigation bar.
///
/// **Why this is needed at all.** The app draws edge-to-edge
/// (`SystemUiMode.edgeToEdge` in `main.dart`), which is both the modern Android
/// look and mandatory from Android 15. Content therefore scrolls *underneath*
/// the gesture bar — which is the point — but whatever comes to rest at the
/// bottom of a page ends up behind it. That is how "Move to trash" on a book's
/// page became unreachable: it is the last item in a `ListView` whose padding
/// was a flat 24.
///
/// **Why not `SafeArea`.** Wrapping the list would stop content passing under
/// the bar at all, which loses the effect and leaves a dead strip. Only the
/// *resting* padding is wrong, so only that is adjusted.
///
/// Nothing is added on a device with no system inset — desktop, or a phone with
/// hardware buttons — so this is a no-op everywhere it isn't needed.
EdgeInsets pageInsets(BuildContext context, EdgeInsets base) =>
    base + EdgeInsets.only(bottom: MediaQuery.viewPaddingOf(context).bottom);

/// How much room a bottom sheet must leave under its content: the keyboard,
/// plus the system navigation bar.
///
/// Sheets used to count only the keyboard, which is the half you notice while
/// developing — type in a field, watch the sheet rise. The other half only
/// shows up on a phone with a gesture bar and nothing focused, and it is what
/// put the buttons at the foot of a book's edit sheet underneath it.
///
/// [MediaQuery.paddingOf], not `viewPaddingOf`: `padding` is what is left of
/// the system inset *after* the keyboard has covered part of it, so it falls to
/// zero exactly when the keyboard is up and the gesture bar is drawn over the
/// keyboard instead of the sheet. Adding `viewPadding` would count that strip
/// twice and leave a gap above the keyboard.
double sheetBottomInset(BuildContext context) =>
    MediaQuery.viewInsetsOf(context).bottom + MediaQuery.paddingOf(context).bottom;
