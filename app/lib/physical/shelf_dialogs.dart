import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'bookcase_template.dart';
import 'room_measure.dart';

import '../data/database.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/labels.dart';
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
    this.title,
    this.initialLeft,
    this.initialRight,
    this.initialLabel,
    this.initialKind = ShelfKind.shelf,
    this.initialTopY,
    this.fill,
  });
  final double defaultY;
  /// Defaults to "Add shelf".
  final String? title;
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
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(widget.title ?? l10n.roomShelfAddTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              _isUpright
                  ? l10n.roomUprightHint
                  : l10n.roomShelfHint,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            // Furniture reuses this dialog because it *is* the same geometry —
            // the only difference is whether books rest on it (plan 5 #29).
            DropdownButtonFormField<ShelfKind>(
              initialValue: _kind,
              isDense: true,
              decoration: InputDecoration(
                labelText: l10n.roomKindLabel,
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final kind in ShelfKind.values)
                  DropdownMenuItem(
                    value: kind,
                    child: Text(kind.labelOf(l10n)),
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
                      ? l10n.roomKindUprightNote
                      : l10n.roomKindMarkerNote,
                  style: const TextStyle(fontSize: 12),
                ),
              ),
            if (_isUpright) ...[
              field(l10n.roomFieldX, _left),
              Row(
                children: [
                  Expanded(child: field(l10n.roomFieldFromY, _height)),
                  const SizedBox(width: 8),
                  Expanded(child: field(l10n.roomFieldToY, _top)),
                ],
              ),
            ] else ...[
              Row(
                children: [
                  Expanded(child: field(l10n.roomFieldLeftX, _left)),
                  const SizedBox(width: 8),
                  Expanded(child: field(l10n.roomFieldRightX, _right)),
                ],
              ),
              field(l10n.roomFieldHeightY, _height),
            ],
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextField(
                controller: _label,
                decoration: InputDecoration(
                  labelText: l10n.roomFieldLabelOptional,
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
          child: Text(l10n.cancel),
        ),
        FilledButton(
          // Disabled rather than a no-op: pressing Add and having nothing
          // happen, with no reason given, is how a dialog looks broken.
          onPressed: _spec == null ? null : () => Navigator.pop(context, _spec),
          child: Text(l10n.roomAdd),
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
    final l10n = L10n.of(context);
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
          l10n.roomFillLine(fill.describe(l10n), fill.bookCount),
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

  /// What is wrong with what has been typed, or null when it is fine. Shown
  /// under the fields rather than silently trimmed on save: a number that
  /// quietly becomes a different number is how you end up not trusting the
  /// dialog.
  String? _problem;
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
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(l10n.roomSizeTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            DropdownButtonFormField<String?>(
              initialValue: _formatKey,
              isExpanded: true,
              decoration: InputDecoration(
                labelText: l10n.roomSizePreset,
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                DropdownMenuItem(value: null, child: Text(l10n.roomSizeDefault)),
                for (final f in BookFormat.presets)
                  DropdownMenuItem(value: f.key, child: Text(f.labelOf(l10n))),
              ],
              onChanged: _applyFormat,
            ),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                l10n.roomSizePresetNote,
                style: const TextStyle(fontSize: 12),
              ),
            ),
            field(l10n.roomSizeThickness, _thickness),
            field(l10n.roomSizeHeight, _height),
            Padding(
              padding: const EdgeInsets.only(top: 8),
              child: Text(
                _problem ??
                    l10n.roomSizeLimit(
                      (PhysicalMetrics.maxThickness * 100).toStringAsFixed(0),
                      (PhysicalMetrics.maxHeight * 100).toStringAsFixed(0),
                    ),
                style: TextStyle(
                  fontSize: 12,
                  color: _problem == null
                      ? null
                      : Theme.of(context).colorScheme.error,
                ),
              ),
            ),
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
          child: Text(l10n.roomSizeReset),
        ),
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () {
            final t = double.tryParse(_thickness.text);
            final h = double.tryParse(_height.text);
            if (t == null || h == null || t <= 0 || h <= 0) {
              setState(() => _problem = l10n.roomSizeNotNumbers);
              return;
            }
            // A3 is the ceiling; `PhysicalMetrics` enforces it regardless, so
            // this exists to say so rather than to be the only guard.
            if (t > PhysicalMetrics.maxThickness * 100 ||
                h > PhysicalMetrics.maxHeight * 100) {
              setState(() => _problem = l10n.roomSizeTooBig(
                    (PhysicalMetrics.maxThickness * 100).toStringAsFixed(0),
                    (PhysicalMetrics.maxHeight * 100).toStringAsFixed(0),
                  ));
              return;
            }
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
          child: Text(l10n.save),
        ),
      ],
    );
  }
}

/// What the bookcase dialog returns (next features #11).
class BookcaseSpec {
  BookcaseSpec({
    required this.style,
    required this.width,
    required this.height,
    required this.shelves,
    this.label,
  });

  final BookcaseStyle style;
  final double width;
  final double height;
  final int shelves;
  final String? label;
}

/// Add a whole bookcase at once, instead of drawing six shelves and two panels
/// by hand.
///
/// The style picker sets sensible real-world defaults and every one of them
/// stays editable — the styles are a starting point, not a constraint, because
/// the bookcase in your hallway is whatever size it is.
class BookcaseDialog extends StatefulWidget {
  const BookcaseDialog({
    super.key,
    this.initialWidth,
    this.initialHeight,
    this.initialShelves,
    this.initialLabel,
  });

  /// Set when re-shaping an existing bookcase, so the dialog opens on what is
  /// actually there rather than on a style's defaults.
  final double? initialWidth;
  final double? initialHeight;
  final int? initialShelves;
  final String? initialLabel;

  @override
  State<BookcaseDialog> createState() => _BookcaseDialogState();
}

class _BookcaseDialogState extends State<BookcaseDialog> {
  BookcaseStyle _style = BookcaseStyle.billy;
  late final _width = TextEditingController(
      text: '${widget.initialWidth ?? _style.width}');
  late final _height = TextEditingController(
      text: '${widget.initialHeight ?? _style.height}');
  late final _shelves = TextEditingController(
      text: '${widget.initialShelves ?? _style.shelves}');
  late final _label = TextEditingController(text: widget.initialLabel ?? '');

  @override
  void dispose() {
    _width.dispose();
    _height.dispose();
    _shelves.dispose();
    _label.dispose();
    super.dispose();
  }

  /// Switching style refills the numbers, because the numbers *are* the style.
  void _applyStyle(BookcaseStyle style) => setState(() {
        _style = style;
        _width.text = '${style.width}';
        _height.text = '${style.height}';
        _shelves.text = '${style.shelves}';
      });

  BookcaseSpec? get _spec {
    final w = double.tryParse(_width.text);
    final h = double.tryParse(_height.text);
    final n = int.tryParse(_shelves.text);
    if (w == null || h == null || n == null) return null;
    if (w < 0.1 || h < 0.1 || n < 1) return null;
    return BookcaseSpec(
      style: _style,
      width: w,
      height: h,
      shelves: n,
      label: _label.text.trim().isEmpty ? null : _label.text.trim(),
    );
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
    final spec = _spec;
    final l10n = L10n.of(context);
    return AlertDialog(
      title: Text(widget.initialWidth == null
          ? l10n.roomBookcaseAddTitle
          : l10n.roomBookcaseEditTitle),
      content: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              l10n.roomBookcaseNote,
              style: const TextStyle(fontSize: 12),
            ),
            const SizedBox(height: 8),
            DropdownButtonFormField<BookcaseStyle>(
              initialValue: _style,
              isDense: true,
              decoration: InputDecoration(
                labelText: l10n.roomStyleLabel,
                border: OutlineInputBorder(),
                isDense: true,
              ),
              items: [
                for (final style in BookcaseStyle.values)
                  DropdownMenuItem(
                      value: style, child: Text(style.labelOf(l10n))),
              ],
              onChanged: (value) => _applyStyle(value ?? BookcaseStyle.billy),
            ),
            Row(
              children: [
                Expanded(child: field(l10n.roomFieldWidth, _width)),
                const SizedBox(width: 8),
                Expanded(child: field(l10n.roomFieldHeight, _height)),
              ],
            ),
            field(l10n.roomFieldShelves, _shelves),
            Padding(
              padding: const EdgeInsets.only(top: 10),
              child: TextField(
                controller: _label,
                decoration: InputDecoration(
                  labelText: l10n.roomFieldNameOptional,
                  border: OutlineInputBorder(),
                  isDense: true,
                ),
              ),
            ),
            if (spec != null)
              Padding(
                padding: const EdgeInsets.only(top: 12),
                child: Text(
                  _style.hasSides
                      ? l10n.roomBookcaseSummarySides(spec.shelves,
                          formatDistance(spec.height / spec.shelves))
                      : l10n.roomBookcaseSummary(spec.shelves,
                          formatDistance(spec.height / spec.shelves)),
                  style: const TextStyle(fontSize: 12),
                ),
              ),
          ],
        ),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: spec == null ? null : () => Navigator.pop(context, spec),
          child: Text(widget.initialWidth == null ? l10n.roomAdd : l10n.save),
        ),
      ],
    );
  }
}
