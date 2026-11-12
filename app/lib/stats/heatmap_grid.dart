import 'package:flutter/material.dart';
import 'package:flutter/semantics.dart';
import 'package:flutter/services.dart';

/// One day on a heat map.
class HeatmapCell {
  const HeatmapCell({
    required this.day,
    required this.value,
    required this.label,
  });

  final DateTime day;

  /// What the shade shows (minutes read). Zero is drawn as an empty cell.
  final int value;

  /// What a screen reader says for this day, already localised, e.g.
  /// "Tuesday, March 4: 35 minutes, 12 pages".
  final String label;
}

/// Where cells sit in the grid, apart from any drawing, so the geometry that
/// hit-testing and the arrow keys rely on is testable without a widget.
///
/// Slots are filled in reading order of the data: [rowMajor] false fills
/// column by column ([rows] per column, the 12-week map where each column is a
/// week), true fills row by row ([columns] per row, the calendar month where
/// each row is a week).
class HeatmapLayout {
  const HeatmapLayout({
    required this.count,
    required this.rows,
    required this.columns,
    required this.rowMajor,
  });

  final int count;
  final int rows;
  final int columns;
  final bool rowMajor;

  ({int col, int row}) position(int index) => rowMajor
      ? (col: index % columns, row: index ~/ columns)
      : (col: index ~/ rows, row: index % rows);

  /// The slot at a grid position, or -1 outside the grid or past the data.
  int indexAt(int col, int row) {
    if (col < 0 || row < 0 || col >= columns || row >= rows) return -1;
    final index = rowMajor ? row * columns + col : col * rows + row;
    return index < count ? index : -1;
  }

  /// The slot under a point, [cell] pixels per square, or -1 if none.
  int indexAtPoint(Offset point, double cell) {
    if (cell <= 0 || point.dx < 0 || point.dy < 0) return -1;
    return indexAt((point.dx / cell).floor(), (point.dy / cell).floor());
  }

  /// The slot reached by stepping [dCol]/[dRow] from [index], or [index]
  /// itself when that lands outside the grid or on a slot [isFilled] rejects
  /// (the blanks before the 1st of a month).
  int move(int index, int dCol, int dRow, bool Function(int) isFilled) {
    final p = position(index);
    final target = indexAt(p.col + dCol, p.row + dRow);
    return target >= 0 && isFilled(target) ? target : index;
  }
}

/// A grid of days shaded by how much was read, drawn with `CustomPaint` but
/// reachable the way a list of buttons would be (docs/ACCESSIBILITY.md, rule
/// 4: anything painted needs a parallel representation).
///
/// - **Pointer and touch:** a tap resolves to the square under it; squares are
///   as large as the width allows (up to [maxCell]), and the whole square,
///   gap included, is the target.
/// - **Keyboard:** the grid takes one tab stop; the arrow keys move a visible
///   focus ring between days and Enter or Space activates the one it is on.
/// - **Screen reader:** every day is its own semantics node with the label it
///   was given, and a tap action when [onDayTap] is set.
class HeatmapGrid extends StatefulWidget {
  const HeatmapGrid({
    super.key,
    required this.cells,
    required this.rows,
    required this.columns,
    required this.rowMajor,
    required this.color,
    required this.empty,
    required this.onColor,
    required this.textColor,
    required this.focusColor,
    this.maxCell = 32,
    this.showDayNumbers = false,
    this.startAtEnd = false,
    this.onDayTap,
    this.semanticsLabel,
  });

  /// One entry per slot, in the order [rowMajor] describes; null is a blank.
  final List<HeatmapCell?> cells;
  final int rows;
  final int columns;
  final bool rowMajor;
  final Color color;
  final Color empty;

  /// Text on a strongly shaded square, and on a pale or empty one.
  final Color onColor;
  final Color textColor;
  final Color focusColor;
  final double maxCell;
  final bool showDayNumbers;

  /// Whether keyboard focus starts on the last day (the most recent) rather
  /// than the first.
  final bool startAtEnd;

  final void Function(DateTime day)? onDayTap;
  final String? semanticsLabel;

  @override
  State<HeatmapGrid> createState() => _HeatmapGridState();
}

class _HeatmapGridState extends State<HeatmapGrid> {
  final _focus = FocusNode(debugLabel: 'HeatmapGrid');
  int? _focused;

  HeatmapLayout get _layout => HeatmapLayout(
        count: widget.cells.length,
        rows: widget.rows,
        columns: widget.columns,
        rowMajor: widget.rowMajor,
      );

  bool _filled(int i) => i >= 0 && i < widget.cells.length && widget.cells[i] != null;

  @override
  void dispose() {
    _focus.dispose();
    super.dispose();
  }

  int _initialIndex() {
    final indexes = [for (var i = 0; i < widget.cells.length; i++) if (_filled(i)) i];
    if (indexes.isEmpty) return -1;
    return widget.startAtEnd ? indexes.last : indexes.first;
  }

  void _activate(int index) {
    final cell = _filled(index) ? widget.cells[index] : null;
    if (cell != null) widget.onDayTap?.call(cell.day);
  }

  KeyEventResult _onKey(FocusNode node, KeyEvent event) {
    if (event is KeyUpEvent) return KeyEventResult.ignored;
    final current = _focused ?? _initialIndex();
    if (current < 0) return KeyEventResult.ignored;
    final key = event.logicalKey;
    int? next;
    if (key == LogicalKeyboardKey.arrowLeft) {
      next = _layout.move(current, -1, 0, _filled);
    } else if (key == LogicalKeyboardKey.arrowRight) {
      next = _layout.move(current, 1, 0, _filled);
    } else if (key == LogicalKeyboardKey.arrowUp) {
      next = _layout.move(current, 0, -1, _filled);
    } else if (key == LogicalKeyboardKey.arrowDown) {
      next = _layout.move(current, 0, 1, _filled);
    } else if (event is KeyDownEvent &&
        (key == LogicalKeyboardKey.enter ||
            key == LogicalKeyboardKey.numpadEnter ||
            key == LogicalKeyboardKey.space)) {
      _activate(current);
      return KeyEventResult.handled;
    }
    if (next == null) return KeyEventResult.ignored;
    setState(() => _focused = next);
    return KeyEventResult.handled;
  }

  @override
  Widget build(BuildContext context) {
    final onTap = widget.onDayTap;
    return LayoutBuilder(builder: (context, constraints) {
      final available = constraints.maxWidth.isFinite ? constraints.maxWidth : 320.0;
      final cell = (available / widget.columns).clamp(4.0, widget.maxCell);
      final size = Size(cell * widget.columns, cell * widget.rows);
      final hasFocus = _focus.hasFocus;
      final ring = hasFocus ? (_focused ?? _initialIndex()) : -1;
      return Align(
        alignment: AlignmentDirectional.topStart,
        child: Semantics(
          container: true,
          label: widget.semanticsLabel,
          child: Focus(
            focusNode: _focus,
            onKeyEvent: _onKey,
            onFocusChange: (_) => setState(() {}),
            child: MouseRegion(
              cursor: onTap == null
                  ? MouseCursor.defer
                  : SystemMouseCursors.click,
              child: GestureDetector(
                behavior: HitTestBehavior.opaque,
                onTapUp: onTap == null
                    ? null
                    : (details) {
                        final i = _layout.indexAtPoint(details.localPosition, cell);
                        if (!_filled(i)) return;
                        _focus.requestFocus();
                        setState(() => _focused = i);
                        _activate(i);
                      },
                child: SizedBox(
                  width: size.width,
                  height: size.height,
                  child: CustomPaint(
                    painter: _GridPainter(
                      cells: widget.cells,
                      layout: _layout,
                      cell: cell,
                      color: widget.color,
                      empty: widget.empty,
                      onColor: widget.onColor,
                      textColor: widget.textColor,
                      focusColor: widget.focusColor,
                      showDayNumbers: widget.showDayNumbers,
                      focusedIndex: ring,
                      tappable: onTap != null,
                      onActivate: _activate,
                      textDirection: Directionality.of(context),
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
            ),
          ),
        ),
      );
    });
  }
}

class _GridPainter extends CustomPainter {
  _GridPainter({
    required this.cells,
    required this.layout,
    required this.cell,
    required this.color,
    required this.empty,
    required this.onColor,
    required this.textColor,
    required this.focusColor,
    required this.showDayNumbers,
    required this.focusedIndex,
    required this.tappable,
    required this.onActivate,
    required this.textDirection,
  });

  final List<HeatmapCell?> cells;
  final HeatmapLayout layout;
  final double cell;
  final Color color;
  final Color empty;
  final Color onColor;
  final Color textColor;
  final Color focusColor;
  final bool showDayNumbers;
  final int focusedIndex;
  final bool tappable;
  final void Function(int index) onActivate;
  final TextDirection textDirection;

  Rect _rect(int i) {
    final p = layout.position(i);
    return Rect.fromLTWH(p.col * cell, p.row * cell, cell, cell);
  }

  @override
  void paint(Canvas canvas, Size size) {
    var max = 0;
    for (final c in cells) {
      if (c != null && c.value > max) max = c.value;
    }
    final gap = cell * 0.15;
    for (var i = 0; i < cells.length; i++) {
      final c = cells[i];
      if (c == null) continue;
      final intensity = max == 0 ? 0.0 : (c.value / max).clamp(0.0, 1.0);
      final box = _rect(i).deflate(gap / 2);
      final rrect = RRect.fromRectAndRadius(box, const Radius.circular(2));
      canvas.drawRRect(
        rrect,
        Paint()
          ..color = c.value == 0
              ? empty
              : color.withValues(alpha: 0.25 + 0.75 * intensity),
      );
      if (showDayNumbers && cell >= 24) {
        final painter = TextPainter(
          text: TextSpan(
            text: '${c.day.day}', // i18n-ignore
            style: TextStyle(
              fontSize: (cell * 0.32).clamp(9.0, 13.0),
              color: intensity > 0.55 && c.value > 0 ? onColor : textColor,
            ),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        painter.paint(
          canvas,
          box.topLeft + const Offset(3, 2),
        );
      }
      if (i == focusedIndex) {
        canvas.drawRRect(
          rrect.inflate(1),
          Paint()
            ..style = PaintingStyle.stroke
            ..strokeWidth = 2
            ..color = focusColor,
        );
      }
    }
  }

  @override
  SemanticsBuilderCallback get semanticsBuilder => (size) => [
        for (var i = 0; i < cells.length; i++)
          if (cells[i] != null)
            CustomPainterSemantics(
              key: ValueKey(i),
              rect: _rect(i),
              properties: SemanticsProperties(
                label: cells[i]!.label,
                textDirection: textDirection,
                button: tappable,
                onTap: tappable ? () => onActivate(i) : null,
              ),
            ),
      ];

  @override
  bool shouldRepaint(_GridPainter old) => true;

  @override
  bool shouldRebuildSemantics(_GridPainter old) => true;
}
