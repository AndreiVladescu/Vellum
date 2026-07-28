import 'package:flutter/material.dart';

/// A snack bar that goes away by itself.
///
/// **Why this exists rather than `SnackBar(...)` at each call site.**
/// `SnackBar.persist` defaults to `action != null`, and the dismiss timer
/// returns early when it is set — so *any* snack bar with a button stays on
/// screen indefinitely, waiting to be swiped away. Every "Undo", "Review" and
/// "Open" in this app was therefore leaving a bar stuck at the bottom of the
/// window, over the content and the floating buttons.
///
/// Persisting is a reasonable default for a framework, which cannot know
/// whether the action is the only way to recover something. Here it is not:
/// undoing a trashed book is also on the trash screen, a finished import is
/// also on the import screen, and none of these is the last chance to act. So
/// they time out, and get [actionSnackDuration] rather than the usual four
/// seconds — long enough to notice a button and reach it.
SnackBar appSnackBar({
  required Widget content,
  SnackBarAction? action,
  Duration? duration,
}) =>
    SnackBar(
      content: content,
      action: action,
      // The whole point of this wrapper. Never remove without reading above.
      persist: false,
      duration: duration ?? (action == null ? _plain : actionSnackDuration),
    );

/// How long a snack bar with something to press stays up.
///
/// Longer than the four seconds a plain message gets: a button you did not
/// notice in time is the same as no button at all, and Material allows up to
/// ten seconds for exactly this case.
const actionSnackDuration = Duration(seconds: 6);

const _plain = Duration(seconds: 4);
