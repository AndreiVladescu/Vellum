import 'package:flutter/material.dart';

import '../data/database.dart';
import '../l10n/gen/app_localizations.dart';

/// The window width from which the shelf shows a book beside itself instead of
/// pushing its page.
///
/// 1200, not the 840 where the permanent drawer appears: the drawer (304) and
/// the pane (440) take 745 of it, and at 840 that would leave the shelf a
/// sliver. At 1200 the shelf keeps about 450, which still fits several spines
/// a row; narrower windows keep the pushed page exactly as before.
const double detailPaneFrom = 1200;

/// A fixed width, not a draggable one: the book page is built to be read in
/// roughly this much, and a splitter is more to get wrong than it earns.
const double detailPaneWidth = 440;

/// Which book the side pane shows, shared between the shelf (which sets it on a
/// tap) and the pane (which shows it).
///
/// A [ValueNotifier] rather than shell state on purpose: selecting a book
/// must not rebuild the shelf. Only the pane and the one highlighted spine
/// listen.
class DetailPaneController {
  /// The book shown, or null when the pane is empty.
  final ValueNotifier<Book?> selected = ValueNotifier(null);

  /// Whether the pane is currently on screen — set by the shell from the window
  /// width. A tap reads it: true selects, false pushes the page as ever.
  bool enabled = false;

  void select(Book book) {
    if (selected.value?.id != book.id) selected.value = book;
  }

  void close() => selected.value = null;

  void dispose() => selected.dispose();
}

/// Outlines the book [bookId] while it is the one in the pane.
///
/// Holds its own bit of state and only calls `setState` when *this* book's
/// answer changes, so selecting a book rebuilds two of these (the one losing
/// the outline and the one gaining it) and nothing else on the shelf.
class PaneHighlight extends StatefulWidget {
  const PaneHighlight({
    super.key,
    required this.controller,
    required this.bookId,
    required this.child,
  });

  final DetailPaneController? controller;
  final String bookId;
  final Widget child;

  @override
  State<PaneHighlight> createState() => _PaneHighlightState();
}

class _PaneHighlightState extends State<PaneHighlight> {
  bool _on = false;

  bool _compute() =>
      widget.controller?.selected.value?.id == widget.bookId;

  @override
  void initState() {
    super.initState();
    _on = _compute();
    widget.controller?.selected.addListener(_changed);
  }

  @override
  void didUpdateWidget(PaneHighlight old) {
    super.didUpdateWidget(old);
    if (old.controller != widget.controller) {
      old.controller?.selected.removeListener(_changed);
      widget.controller?.selected.addListener(_changed);
    }
    _on = _compute();
  }

  @override
  void dispose() {
    widget.controller?.selected.removeListener(_changed);
    super.dispose();
  }

  void _changed() {
    final on = _compute();
    if (on != _on) setState(() => _on = on);
  }

  @override
  Widget build(BuildContext context) {
    if (!_on) return widget.child;
    return DecoratedBox(
      position: DecorationPosition.foreground,
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(3),
        border: Border.all(
          color: Theme.of(context).colorScheme.primary,
          width: 2,
        ),
      ),
      child: widget.child,
    );
  }
}

/// The pane: a divider and [detailPaneWidth] showing the selected book's page
/// (built by [pageBuilder], given the close callback), or a hint when empty.
class DetailPane extends StatelessWidget {
  const DetailPane({
    super.key,
    required this.controller,
    required this.pageBuilder,
  });

  final DetailPaneController controller;
  final Widget Function(Book book, VoidCallback onClose) pageBuilder;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        const VerticalDivider(width: 1, thickness: 1),
        SizedBox(
          width: detailPaneWidth,
          child: ValueListenableBuilder<Book?>(
            valueListenable: controller.selected,
            builder: (context, book, _) {
              if (book == null) {
                return Material(
                  color: theme.colorScheme.surface,
                  child: Center(
                    child: Padding(
                      padding: const EdgeInsets.all(32),
                      child: Text(
                        L10n.of(context).detailPaneEmpty,
                        textAlign: TextAlign.center,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                  ),
                );
              }
              // Keyed by id so a different book starts a fresh page rather
              // than inheriting the last one's scroll position and edits.
              return KeyedSubtree(
                key: ValueKey(book.id),
                child: pageBuilder(book, controller.close),
              );
            },
          ),
        ),
      ],
    );
  }
}
