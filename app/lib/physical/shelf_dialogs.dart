import 'package:flutter/material.dart';

import '../data/database.dart';
import 'physical_metrics.dart';

/// What the shelf dialog returns: endpoints, height, and an optional label.
class ShelfSpec {
  ShelfSpec(this.left, this.right, this.y, this.label);
  final double left;
  final double right;
  final double y;
  final String? label;
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
  });
  final double defaultY;
  final String title;
  final double? initialLeft;
  final double? initialRight;
  final String? initialLabel;

  @override
  State<ShelfDialog> createState() => _ShelfDialogState();
}

class _ShelfDialogState extends State<ShelfDialog> {
  late final _left =
      TextEditingController(text: (widget.initialLeft ?? 0.0).toString());
  late final _right =
      TextEditingController(text: (widget.initialRight ?? 1.0).toString());
  late final _height = TextEditingController(text: widget.defaultY.toString());
  late final _label = TextEditingController(text: widget.initialLabel ?? '');

  @override
  void dispose() {
    _left.dispose();
    _right.dispose();
    _height.dispose();
    _label.dispose();
    super.dispose();
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
      title: Text(widget.title),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            const Text(
              'A shelf is a flat line between two points (metres).',
              style: TextStyle(fontSize: 12),
            ),
            Row(
              children: [
                Expanded(child: field('Left X (m)', _left)),
                const SizedBox(width: 8),
                Expanded(child: field('Right X (m)', _right)),
              ],
            ),
            field('Height Y (m)', _height),
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
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () {
            final left = double.tryParse(_left.text) ?? 0;
            final right = double.tryParse(_right.text) ?? 1;
            final y = double.tryParse(_height.text) ?? widget.defaultY;
            if (right <= left) return;
            Navigator.pop(
              context,
              ShelfSpec(
                left,
                right,
                y,
                _label.text.trim().isEmpty ? null : _label.text.trim(),
              ),
            );
          },
          child: const Text('Add'),
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
