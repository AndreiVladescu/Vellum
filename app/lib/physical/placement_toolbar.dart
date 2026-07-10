import 'package:flutter/material.dart';

/// The bottom toolbar shown while a placed book is selected: open, rotate,
/// resize, remove, deselect.
class SelectionBar extends StatelessWidget {
  const SelectionBar({
    super.key,
    required this.title,
    required this.onOpen,
    required this.onRotate,
    required this.onResize,
    required this.onRemove,
    required this.onClose,
  });

  final String title;
  final VoidCallback onOpen;
  final VoidCallback onRotate;
  final VoidCallback onResize;
  final VoidCallback onRemove;
  final VoidCallback onClose;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Material(
      elevation: 3,
      borderRadius: BorderRadius.circular(12),
      color: theme.colorScheme.surfaceContainerHighest,
      child: Padding(
        padding: const EdgeInsets.fromLTRB(14, 6, 6, 6),
        child: Row(
          children: [
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: theme.textTheme.titleSmall,
              ),
            ),
            IconButton(
              tooltip: 'Open book',
              onPressed: onOpen,
              icon: const Icon(Icons.menu_book_outlined),
            ),
            IconButton.filledTonal(
              tooltip: 'Rotate 90°',
              onPressed: onRotate,
              iconSize: 28,
              icon: const Icon(Icons.rotate_90_degrees_cw),
            ),
            const SizedBox(width: 4),
            IconButton(
              tooltip: 'Resize',
              onPressed: onResize,
              icon: const Icon(Icons.straighten),
            ),
            IconButton(
              tooltip: 'Remove',
              onPressed: onRemove,
              icon: const Icon(Icons.delete_outline),
            ),
            IconButton(
              tooltip: 'Done',
              onPressed: onClose,
              icon: const Icon(Icons.close),
            ),
          ],
        ),
      ),
    );
  }
}

/// A metric scale readout for the canvas corner: a bar sized to a round
/// number of centimetres at the current zoom.
class ScaleBar extends StatelessWidget {
  const ScaleBar({super.key, required this.scale});
  final double scale;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    // Pick a round number of centimetres that fits ~a finger-width.
    final metres = (80 / scale);
    final cm = metres * 100;
    final nice = cm >= 100
        ? 100.0
        : cm >= 50
            ? 50.0
            : cm >= 20
                ? 20.0
                : 10.0;
    final width = (nice / 100) * scale;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: width,
          height: 4,
          decoration: BoxDecoration(
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
            borderRadius: BorderRadius.circular(2),
          ),
        ),
        const SizedBox(height: 2),
        Text(
          nice >= 100 ? '1 m' : '${nice.toStringAsFixed(0)} cm',
          style: TextStyle(
            fontSize: 11,
            color: theme.colorScheme.onSurface.withValues(alpha: 0.7),
          ),
        ),
      ],
    );
  }
}
