import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'room_measure.dart';

import '../data/database.dart';
import 'physical_metrics.dart';

/// What the shelf dialog returns: endpoints, height, and an optional label.
class ShelfSpec {
  ShelfSpec(this.left, this.right, this.y, this.label, this.kind, {double? y2})
      : y2 = y2 ?? y;
  final double left;
  final double right;
  final double y;

  /// The other end of the segment vertically. Equal to [y] for a shelf, which
  /// is flat; an upright (a side panel, a divider) runs between two heights,
  /// and before this existed it collapsed to a flat line and drew as a three
  /// pixel smudge — which is why a divider appeared to do nothing.
  final double y2;
  final String? label;

  /// What this segment is (plan 5 #29): a shelf books rest on, or furniture
  /// that only draws.
  final ShelfKind kind;
}

/// Add/edit dialog for a shelf: left/right X, height Y (metres), and a label.
class ShelfDialog extends StatefulWidget {
  const ShelfDialog({
    super.key,
    required this.defaultY,
    this.title = 'Add shelf',
    this.initialLeft,
    this.initialRight,
    this.initialLabel,
    this.initialKind = ShelfKind.shelf,
    this.initialTopY,
    this.fill,
  });
  final double defaultY;
  final String title;
  final double? initialLeft;
  final double? initialRight;

  /// The upper end of an upright, when editing one.
  final double? initialTopY;
  final String? initialLabel;
  final ShelfKind initialKind;

  /// How full the shelf currently is (plan 5 #29). Shown when editing an
  /// existing one — it is the number you actually want while deciding whether
  /// to move a shelf or buy another bookcase.
  final ShelfFill? fill;

  @override
  State<ShelfDialog> createState() => _ShelfDialogState();
}

class _ShelfDialogState extends State<ShelfDialog> {
  late final _left =
      TextEditingController(text: (widget.initialLeft ?? 0.0).toString());
  late final _right =
      TextEditingController(text: (widget.initialRight ?? 1.0).toString());
  late final _height = TextEditingController(text: widget.defaultY.toString());
  late final _top = TextEditingController(
    text: (widget.initialTopY ?? widget.defaultY + 0.9).toString(),
  );
  late final _label = TextEditingController(text: widget.initialLabel ?? '');
  late ShelfKind _kind = widget.initialKind;

  /// An upright is authored as one X and two heights; a shelf as two X's and
  /// one height. Same row in the database either way — see [ShelfSpec.y2].
  bool get _isUpright => !_kind.holdsBooks && _kind != ShelfKind.marker;

  /// What Add would return, or null when the numbers don't describe a segment.
  /// A shelf needs width, an upright needs height; a label is a point and needs
  /// neither.
  ShelfSpec? get _spec {
    final label = _label.text.trim().isEmpty ? null : _label.text.trim();
    final y = double.tryParse(_height.text) ?? widget.defaultY;
    if (_isUpright) {
      final x = double.tryParse(_left.text) ?? 0;
      final top = double.tryParse(_top.text) ?? (y + 0.9);
      if ((top - y).abs() < 0.01) return null;
      return ShelfSpec(x, x, math.min(y, top), label, _kind,
          y2: math.max(y, top));
    }
    final left = double.tryParse(_left.text) ?? 0;
    final right = double.tryParse(_right.text) ?? 1;
    if (_kind != ShelfKind.marker && right - left < 0.01) return null;
    return ShelfSpec(left, right, y, label, _kind);
  }

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    _height.dispose();
    _top.dispose();
    _label.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    Widget field(String label, TextEditingController c) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: TextField(
            controller: c,
            onChanged: (_) => setState(() {}),
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        );
    return AlertDialog(
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isUpright
                  ? 'An upright runs between two heights at one X (metres).'
                  : 'A shelf is a flat line between two points (metres).',
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            // Furniture reuses this dialog because it *is* the same geometry —
            // the only difference is whether books rest on it (plan 5 #29).
            DropdownButtonFormField<ShelfKind>(
              initialValue: _kind,
              isDense: true,
              decoration: const InputDecoration(
                labelText: 'Kind',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final kind in ShelfKind.values)
                  DropdownMenuItem(
                    value: kind,
                    child: Text(kind.displayName),
                  ),
              ],
              onChanged: (value) =>
                  setState(() => _kind = value ?? ShelfKind.shelf),
            ),
            if (!_kind.holdsBooks)
              Padding(
                padding: const EdgeInsets.only(top: 6),
                child: Text(
                  _isUpright
                      ? 'Books never rest on this, and none can be slid '
                          'through it.'
                      : 'Books never rest on this — it only draws.',
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            if (_isUpright) ...[
              field('X (m)', _left),
              Row(
                children: [
                  Expanded(child: field('From Y (m)', _height)),
                  const SizedBox(width: 8),
                  Expanded(child: field('To Y (m)', _top)),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(child: field('Left X (m)', _left)),
                  const SizedBox(width: 8),
                  Expanded(child: field('Right X (m)', _right)),
                ],
              ),
              field('Height Y (m)', _height),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextField(
                controller: _label,
                decoration: const InputDecoration(
                  labelText: 'Label (optional)',
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            if (widget.fill != null) ...[
              const SizedBox(height: 14),
              _FillBar(fill: widget.fill!),
            ],
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          // Disabled rather than a no-op: pressing Add and having nothing
          // happen, with no reason given, is how a dialog looks broken.
          onPressed: _spec == null ? null : () => Navigator.pop(context, _spec),
          child: const Text('Add'),
        ),
      ],
    );
  }
}

/// How full a shelf is, as a bar and a sentence (plan 5 #29).
class _FillBar extends StatelessWidget {
  const _FillBar({required this.fill});

  final ShelfFill fill;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        LinearProgressIndicator(
          value: fill.fraction,
          // Overfull is a real state — books pushed past the end — and it wants
          // to look wrong rather than sit quietly at a full bar.
          color: fill.isOverfull ? theme.colorScheme.error : null,
        ),
        const SizedBox(height: 6),
        Text(
          '${fill.describe()} · ${fill.bookCount} book'
          '${fill.bookCount == 1 ? '' : 's'}',
          style: theme.textTheme.bodySmall,
        ),
      ],
    );
  }
}

/// What the size dialog returns: a format preset plus manual dimensions, or a
/// request to reset the placement back to the computed default.
class SizeSpec {
  SizeSpec({
    required this.formatKey,
    required this.thicknessCm,
    required this.heightCm,
    required this.reset,
  });
  final String? formatKey;
  final double thicknessCm;
  final double heightCm;
  final bool reset;
}

/// Resize dialog for a placed book: a format-preset dropdown plus manual
/// thickness/height overrides in centimetres.
class SizeDialog extends StatefulWidget {
  const SizeDialog({
    super.key,
    required this.book,
    required this.formatKey,
    required this.thicknessCm,
    required this.heightCm,
  });
  final Book book;
  final String? formatKey;
  final double thicknessCm;
  final double heightCm;

  @override
  State<SizeDialog> createState() => _SizeDialogState();
}

class _SizeDialogState extends State<SizeDialog> {
  late String? _formatKey = widget.formatKey;
  late final _thickness =
      TextEditingController(text: widget.thicknessCm.toStringAsFixed(1));
  late final _height =
      TextEditingController(text: widget.heightCm.toStringAsFixed(1));

  @override
  void dispose() {
    _thickness.dispose();
    _height.dispose();
    super.dispose();
  }

  // Picking a preset fills the fields with its size for this book's page count.
  void _applyFormat(String? key) {
    final format = BookFormat.byKey(key);
    setState(() {
      _formatKey = key;
      _thickness.text =
          (PhysicalMetrics.thickness(widget.book, format: format) * 100)
              .toStringAsFixed(1);
      _height.text =
          (PhysicalMetrics.height(widget.book, format: format) * 100)
              .toStringAsFixed(1);
    });
  }

  @override
  Widget build(BuildContext context) {
    Widget field(String label, TextEditingController c) => Padding(
          padding: const EdgeInsets.only(top: 10),
          child: TextField(
            controller: c,
            keyboardType: const TextInputType.numberWithOptions(decimal: true),
            decoration: InputDecoration(
              labelText: label,
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        );
    return AlertDialog(
      title: const Text('Book size'),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String?>(
              initialValue: _formatKey,
              isExpanded: true,
              decoration: const InputDecoration(
                labelText: 'Format preset',
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                const DropdownMenuItem(value: null, child: Text('Default')),
                for (final f in BookFormat.presets)
                  DropdownMenuItem(value: f.key, child: Text(f.label)),
              ],
              onChanged: _applyFormat,
            ),
            const Padding(
              padding: EdgeInsets.only(top: 8),
              child: Text(
                'A preset sizes the book from its page count; tweak the '
                'numbers below for a manual override.',
                style: TextStyle(fontSize: 12),
              ),
            ),
            field('Thickness (cm)', _thickness),
            field('Height (cm)', _height),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            SizeSpec(
              formatKey: null,
              thicknessCm: 0,
              heightCm: 0,
              reset: true,
            ),
          ),
          child: const Text('Reset'),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final t = double.tryParse(_thickness.text);
            final h = double.tryParse(_height.text);
            if (t == null || h == null || t <= 0 || h <= 0) return;
            Navigator.pop(
              context,
              SizeSpec(
                formatKey: _formatKey,
                thicknessCm: t,
                heightCm: h,
                reset: false,
              ),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
