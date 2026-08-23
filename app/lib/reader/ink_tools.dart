/// The pen, the eraser and the text tool, and the bar that offers them
/// (8/23 requests: "a pen writing feature, so you can draw on the pdf", and
/// "some text writing on top of the pdf, with the drawing, would be nicer").
library;

import 'package:flutter/material.dart';

import 'annotations/ink_markup.dart';

enum InkTool {
  pen('Pen', Icons.edit_outlined),
  eraser('Eraser', Icons.cleaning_services_outlined),
  text('Text', Icons.title);

  const InkTool(this.label, this.icon);

  final String label;
  final IconData icon;
}

/// What a pen can be. Deliberately few: a colour picker is a screen, and this
/// is a thing you reach for mid-sentence.
const inkColors = <int>[
  0xFF1A1A1A, // near-black, the default hand
  0xFF2F80ED, // blue
  0xFFD32F2F, // red
  0xFF2E7D32, // green
  0xFFF9A825, // highlighter yellow
];

/// Stroke widths, as fractions of the page height — see [InkStroke.width].
const inkWidths = <double>[0.0015, 0.003, 0.007];

/// How close the eraser has to come, as a fraction of the page.
const inkEraserRadius = 0.02;

/// The default size of a typed label, as a fraction of the page height. About
/// the size of body text on a paperback page.
const inkTextSize = 0.022;

/// The bar shown while writing is switched on.
class InkToolbar extends StatelessWidget {
  const InkToolbar({
    super.key,
    required this.tool,
    required this.color,
    required this.width,
    required this.onTool,
    required this.onColor,
    required this.onWidth,
    required this.onUndo,
    required this.onDone,
    this.canUndo = false,
  });

  final InkTool tool;
  final int color;
  final double width;
  final ValueChanged<InkTool> onTool;
  final ValueChanged<int> onColor;
  final ValueChanged<double> onWidth;
  final VoidCallback onUndo;
  final VoidCallback onDone;
  final bool canUndo;

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return Material(
      color: scheme.inverseSurface.withValues(alpha: 0.92),
      shape: const StadiumBorder(),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            for (final option in InkTool.values)
              IconButton(
                icon: Icon(option.icon),
                tooltip: option.label,
                isSelected: tool == option,
                color: tool == option ? scheme.inversePrimary : scheme.onInverseSurface,
                onPressed: () => onTool(option),
              ),
            const _Divider(),
            // Colour and thickness belong to the pen and to typed text; the
            // eraser has no use for either, so they go away with it rather
            // than sitting there doing nothing.
            if (tool != InkTool.eraser) ...[
              for (final swatch in inkColors)
                _Swatch(
                  color: swatch,
                  selected: swatch == color,
                  onTap: () => onColor(swatch),
                ),
              if (tool == InkTool.pen) ...[
                const _Divider(),
                for (final option in inkWidths)
                  _Nib(
                    width: option,
                    selected: option == width,
                    tint: scheme.onInverseSurface,
                    onTap: () => onWidth(option),
                  ),
              ],
              const _Divider(),
            ],
            IconButton(
              icon: const Icon(Icons.undo),
              tooltip: 'Undo',
              color: scheme.onInverseSurface,
              onPressed: canUndo ? onUndo : null,
            ),
            IconButton(
              icon: const Icon(Icons.check),
              tooltip: 'Done writing',
              color: scheme.onInverseSurface,
              onPressed: onDone,
            ),
          ],
        ),
      ),
    );
  }
}

class _Divider extends StatelessWidget {
  const _Divider();

  @override
  Widget build(BuildContext context) => Padding(
        padding: const EdgeInsets.symmetric(horizontal: 4),
        child: SizedBox(
          height: 22,
          child: VerticalDivider(
            width: 1,
            color: Theme.of(context)
                .colorScheme
                .onInverseSurface
                .withValues(alpha: 0.3),
          ),
        ),
      );
}

class _Swatch extends StatelessWidget {
  const _Swatch({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final int color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return IconButton(
      tooltip: 'Ink colour',
      onPressed: onTap,
      icon: Container(
        width: 18,
        height: 18,
        decoration: BoxDecoration(
          color: Color(color),
          shape: BoxShape.circle,
          border: Border.all(
            color: selected
                ? Theme.of(context).colorScheme.inversePrimary
                : Colors.white24,
            width: selected ? 3 : 1,
          ),
        ),
      ),
    );
  }
}

class _Nib extends StatelessWidget {
  const _Nib({
    required this.width,
    required this.selected,
    required this.tint,
    required this.onTap,
  });

  final double width;
  final bool selected;
  final Color tint;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    // The dot is drawn at the same *relative* scale the stroke will be, so the
    // three options look like what they do.
    final size = 4 + width * 900;
    return IconButton(
      tooltip: 'Nib',
      onPressed: onTap,
      icon: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: tint.withValues(alpha: selected ? 1 : 0.5),
          shape: BoxShape.circle,
        ),
      ),
    );
  }
}
