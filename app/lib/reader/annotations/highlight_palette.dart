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

/// Asks which colour to highlight in.
///
/// A row of four swatches, not a menu: the choice is the gesture, and putting
/// it behind a dropdown would make highlighting slower than it was before there
/// were colours at all.
Future<HighlightColor?> pickHighlightColor(
  BuildContext context, {
  String title = 'Highlight',
}) =>
    showModalBottomSheet<HighlightColor>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: Padding(
          padding: const EdgeInsets.fromLTRB(20, 16, 20, 20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(title, style: Theme.of(sheetContext).textTheme.titleMedium),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceEvenly,
                children: [
                  for (final choice in HighlightColor.values)
                    _Swatch(
                      choice: choice,
                      onTap: () => Navigator.of(sheetContext).pop(choice),
                    ),
                ],
              ),
            ],
          ),
        ),
      ),
    );

class _Swatch extends StatelessWidget {
  const _Swatch({required this.choice, required this.onTap});

  final HighlightColor choice;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return Semantics(
      button: true,
      label: '${choice.label} highlight',
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(32),
        child: Padding(
          padding: const EdgeInsets.all(8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: choice.color,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: Theme.of(context).colorScheme.outlineVariant,
                  ),
                ),
              ),
              const SizedBox(height: 6),
              Text(choice.label, style: Theme.of(context).textTheme.labelSmall),
            ],
          ),
        ),
      ),
    );
  }
}
