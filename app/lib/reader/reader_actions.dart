/// The reader's toolbar, and how much of it fits.
///
/// **The bug this exists for.** The bar grew one button at a time — highlight,
/// colour, note, look up, ask, translate, mode, bookmark, self-scroll, pen,
/// reading mode, annotations, search — and on a phone the row simply ran out of
/// screen and drew over the back arrow. An `AppBar` gives its actions their
/// intrinsic width and squeezes the *title*, so nothing complains: it just
/// overlaps.
///
/// So the bar is given a budget and told how many buttons it may show. What
/// does not fit goes into the overflow menu, in the same order, with its name —
/// which is also why every action carries a label, not just an icon.
library;

import 'package:flutter/material.dart';

/// What the leading control (the back arrow) and its padding cost.
const kLeadingWidth = 64.0;

/// What the reader's page counter is allowed to cost. It is capped at this in
/// the bar itself, so the two numbers cannot disagree.
const kCounterWidth = 116.0;

/// One thing the bar can do.
class ReaderAction {
  const ReaderAction({
    required this.icon,
    required this.label,
    required this.onPressed,
    this.color,
    this.selected = false,
    this.widget,
  });

  final IconData icon;

  /// What it is called in the overflow menu — and, as a tooltip, on the button.
  final String label;

  /// Null disables the button and greys the menu entry, rather than hiding it:
  /// a control that vanishes when it is unavailable is one you go looking for.
  final VoidCallback? onPressed;

  final Color? color;
  final bool selected;

  /// Shown in place of the plain icon button when there is room for it — the
  /// highlighter's colour swatch is a widget, not an icon. It still needs
  /// [icon] and [onPressed] for the day it lands in the menu instead.
  final Widget? widget;
}

/// How many of [total] actions fit in a bar of [width], once [reserved] is
/// taken out for the leading control and anything else sharing the row.
///
/// The overflow button costs a slot of its own, so a bar that can show seven
/// buttons shows six and a menu — showing seven and hiding the eighth with no
/// way to reach it is the failure this is here to prevent.
int fittingActions({
  required double width,
  required double reserved,
  required int total,
  bool alwaysMenu = false,
  double itemWidth = 48,
  double menuWidth = 48,
}) {
  final room = width - reserved;
  if (room <= 0 || total <= 0) return 0;
  final everythingFits = !alwaysMenu && total * itemWidth <= room;
  if (everythingFits) return total;
  final usable = room - menuWidth;
  if (usable <= 0) return 0;
  return (usable / itemWidth).floor().clamp(0, total);
}

/// The bar itself: as many buttons as fit, then a menu with the rest.
class ReaderActionBar extends StatelessWidget {
  const ReaderActionBar({
    super.key,
    required this.actions,
    this.reserved = 64,
    this.menuExtras = const [],
    this.foreground,
  });

  final List<ReaderAction> actions;

  /// Width already spoken for in this row — the back arrow, and whatever sits
  /// beside it (the reader's page counter).
  final double reserved;

  /// Entries that live in the menu whatever happens: "Go to page…" and the
  /// rest of what was already there.
  final List<PopupMenuEntry<VoidCallback?>> menuExtras;

  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final shown = fittingActions(
      width: MediaQuery.sizeOf(context).width,
      reserved: reserved,
      total: actions.length,
      alwaysMenu: menuExtras.isNotEmpty,
    );
    final hidden = actions.sublist(shown);
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final action in actions.take(shown))
          action.widget ??
              IconButton(
                icon: Icon(action.icon, color: action.color),
                tooltip: action.label,
                isSelected: action.selected,
                color: foreground,
                onPressed: action.onPressed,
              ),
        if (hidden.isNotEmpty || menuExtras.isNotEmpty)
          PopupMenuButton<VoidCallback?>(
            tooltip: 'More',
            // The value *is* the thing to do: an enum of choices here would be
            // a second list to keep in step with the first.
            onSelected: (run) => run?.call(),
            itemBuilder: (context) => [
              for (final action in hidden)
                PopupMenuItem(
                  value: action.onPressed,
                  enabled: action.onPressed != null,
                  child: Row(
                    children: [
                      Icon(action.icon, size: 20, color: action.color),
                      const SizedBox(width: 12),
                      Expanded(child: Text(action.label)),
                      if (action.selected) const Icon(Icons.check, size: 18),
                    ],
                  ),
                ),
              if (hidden.isNotEmpty && menuExtras.isNotEmpty)
                const PopupMenuDivider(),
              ...menuExtras,
            ],
          ),
      ],
    );
  }
}
