import 'package:flutter/material.dart';

/// A page-turn strip down one edge of a reader: the whole strip is the target,
/// with a chevron at the vertical middle as its affordance.
///
/// Deliberately faint — it is a hint that the edge does something, not a control
/// competing with the page. It brightens on hover so a mouse user can find it,
/// which a touch user never needs.
///
/// Shared by both readers so a PDF and an EPUB turn the same way. Nothing about
/// it knows what a page is; the caller decides what "forward" means.
class ReaderEdgeTurn extends StatefulWidget {
  const ReaderEdgeTurn({
    super.key,
    required this.width,
    required this.alignment,
    required this.icon,
    required this.tooltip,
    required this.colour,
    required this.onTap,
  });

  final double width;
  final Alignment alignment;
  final IconData icon;
  final String tooltip;
  final Color colour;
  final VoidCallback onTap;

  /// How wide the strip should be given the page width and the text column in
  /// it. The strip lives in the *margin* beside the column wherever there is
  /// one, so it doesn't sit on top of words you might want to select; on a
  /// narrow window there is no margin and a minimum wins anyway, because turning
  /// the page is the thing you do a thousand times more often than selecting a
  /// passage.
  static double stripWidth(double available, double column) {
    final margin = (available - column) / 2;
    return margin < 44 ? 44 : (margin > 96 ? 96 : margin);
  }

  @override
  State<ReaderEdgeTurn> createState() => _ReaderEdgeTurnState();
}

class _ReaderEdgeTurnState extends State<ReaderEdgeTurn> {
  bool _hovered = false;

  @override
  Widget build(BuildContext context) {
    return Align(
      alignment: widget.alignment,
      child: MouseRegion(
        cursor: SystemMouseCursors.click,
        onEnter: (_) => setState(() => _hovered = true),
        onExit: (_) => setState(() => _hovered = false),
        child: GestureDetector(
          // Opaque: a tap here turns the page and does not also fall through to
          // whatever is underneath.
          behavior: HitTestBehavior.opaque,
          onTap: widget.onTap,
          child: Tooltip(
            message: widget.tooltip,
            child: SizedBox(
              width: widget.width,
              height: double.infinity,
              child: Center(
                child: AnimatedOpacity(
                  opacity: _hovered ? 0.7 : 0.22,
                  duration: const Duration(milliseconds: 120),
                  child: Icon(widget.icon, size: 32, color: widget.colour),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
