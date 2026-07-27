import 'package:flutter/material.dart';

/// The highlighter colours, and how to draw with them.
///
/// **Four, not a colour wheel.** A highlighter is a physical object with a
/// handful of colours, and people use them categorically — yellow for "this
/// matters", pink for "disagree", and so on. A free picker would turn a
/// one-tap gesture into a decision, and the resulting library of near-identical
/// yellows would carry no meaning at all.
///
/// Chosen to stay legible over dark *and* light page backgrounds, which is why
/// they are stored and drawn at low alpha over the text rather than as opaque
/// fills — a marker stains the page, it doesn't cover the words.
enum HighlightColor {
  yellow('Yellow', 0xFFF6D75B),
  green('Green', 0xFF8FD48A),
  blue('Blue', 0xFF86BEF0),
  pink('Pink', 0xFFEF9BC0);

  const HighlightColor(this.label, this.argb);

  final String label;

  /// The stored value: a full-opacity ARGB int, so the database keeps the
  /// *identity* of the colour and every surface decides its own opacity.
  final int argb;

  Color get color => Color(argb);

  /// What a marker actually looks like on the page. Alpha rather than a solid
  /// fill so the glyphs stay black and readable underneath.
  Color get inkColor => color.withValues(alpha: 0.42);

  /// The default when no colour was chosen — including for highlights made
  /// before there was a choice, so they don't render as invisible.
  static const fallback = HighlightColor.yellow;

  /// Reads a stored value back. An unrecognised colour (hand-edited, or written
  /// by a future version) falls back rather than disappearing.
  static HighlightColor fromArgb(int? argb) {
    if (argb == null) return fallback;
    for (final c in values) {
      if (c.argb == argb) return c;
    }
    return fallback;
  }

  /// The ink for a stored annotation colour.
  static Color inkFor(int? argb) => fromArgb(argb).inkColor;
}

/// The marker currently in hand: shows its colour, and switches it.
///
/// **Why this is not a prompt.** Asking which colour on every highlight makes
/// the common case — highlight this, in the colour I have been using all
/// afternoon — cost two decisions instead of none. A physical highlighter is
/// picked up once and then simply used, and the only thing you need on screen
/// is which one you are holding. So this sits beside the highlight button, is
/// the swatch itself, and changing it is a deliberate second act.
class HighlightColorButton extends StatelessWidget {
  const HighlightColorButton({
    super.key,
    required this.selected,
    required this.onChanged,
  });

  final HighlightColor selected;
  final ValueChanged<HighlightColor> onChanged;

  @override
  Widget build(BuildContext context) {
    return PopupMenuButton<HighlightColor>(
      tooltip: 'Highlighter colour — ${selected.label}',
      onSelected: onChanged,
      // A row of swatches rather than a list of names: the thing being chosen
      // is a colour, so the colour is the label.
      itemBuilder: (context) => [
        for (final choice in HighlightColor.values)
          PopupMenuItem(
            value: choice,
            child: Row(
              children: [
                _Swatch(choice: choice, size: 22),
                const SizedBox(width: 12),
                Text(choice.label),
                if (choice == selected) ...[
                  const Spacer(),
                  const Icon(Icons.check, size: 18),
                ],
              ],
            ),
          ),
      ],
      child: Tooltip(
        message: 'Highlighter colour — ${selected.label}',
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: _Swatch(choice: selected, size: 20),
        ),
      ),
    );
  }
}

class _Swatch extends StatelessWidget {
  const _Swatch({required this.choice, required this.size});

  final HighlightColor choice;
  final double size;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      label: '${choice.label} highlighter',
      child: Container(
        width: size,
        height: size,
        decoration: BoxDecoration(
          color: choice.color,
          shape: BoxShape.circle,
          border: Border.all(
            color: Theme.of(context).colorScheme.outlineVariant,
          ),
        ),
      ),
    );
  }
}
