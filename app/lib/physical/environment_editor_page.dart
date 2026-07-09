import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import 'physical_metrics.dart';

/// A book's footprint (width × height) in metres, after rotation.
typedef _Foot = ({double w, double h});

/// The shelf editor: a front-elevation, to-scale view of one physical
/// environment. Pan and pinch-zoom the room; drag books so they rest on the
/// nearest shelf or on top of another book (no overlaps); tap a book to rotate,
/// resize, or remove it. Everything is stored in metres.
class EnvironmentEditorPage extends StatefulWidget {
  const EnvironmentEditorPage({
    super.key,
    required this.repository,
    required this.environmentId,
    required this.environmentName,
  });

  final LibraryRepository repository;
  final String environmentId;
  final String environmentName;

  @override
  State<EnvironmentEditorPage> createState() => _EnvironmentEditorPageState();
}

class _EnvironmentEditorPageState extends State<EnvironmentEditorPage> {
  // Camera: pixels-per-metre and the screen offset of world (0, 0). World Y is
  // up, so screen Y is flipped in the transforms below.
  double _scale = 300;
  Offset? _origin;
  static const _minScale = 40.0;
  static const _maxScale = 1600.0;

  // Latest stream data, so gesture callbacks can hit-test.
  List<PhysicalShelf> _shelves = const [];
  List<PlacedBook> _placed = const [];

  String? _selectedId;

  // Gesture bookkeeping.
  String? _dragId; // placement being dragged (null = panning/zooming)
  Offset _dragPos = Offset.zero; // dragged book's world bottom-left
  Offset _grabWorld = Offset.zero;
  Offset _bookStart = Offset.zero;
  bool _moved = false;
  double _camStartScale = 1;
  Offset _camWorldFocal = Offset.zero;

  LibraryRepository get repo => widget.repository;

  Offset _worldToScreen(Offset w) =>
      Offset(_origin!.dx + w.dx * _scale, _origin!.dy - w.dy * _scale);

  Offset _screenToWorld(Offset s) =>
      Offset((s.dx - _origin!.dx) / _scale, (_origin!.dy - s.dy) / _scale);

  _Foot _foot(Book b, int rot, double? wo, double? ho) {
    final t = PhysicalMetrics.thickness(b, override: wo);
    final h = PhysicalMetrics.height(b, override: ho);
    return rot == 0 ? (w: t, h: h) : (w: h, h: t);
  }

  _Foot _footOf(PlacedBook pb) => _foot(
        pb.book,
        pb.placement.rotation,
        pb.placement.widthOverride,
        pb.placement.heightOverride,
      );

  Rect _screenRectOf(PlacedBook pb) {
    final f = _footOf(pb);
    final topLeft = _worldToScreen(
      Offset(pb.placement.x, pb.placement.y + f.h),
    );
    return topLeft & Size(f.w * _scale, f.h * _scale);
  }

  // ---- camera -------------------------------------------------------------

  void _zoomAt(Offset focal, double factor) {
    final newScale = (_scale * factor).clamp(_minScale, _maxScale);
    final worldFocal = _screenToWorld(focal);
    setState(() {
      _scale = newScale;
      _origin = Offset(
        focal.dx - worldFocal.dx * newScale,
        focal.dy + worldFocal.dy * newScale,
      );
    });
  }

  void _onScaleStart(ScaleStartDetails d) {
    _moved = false;
    final focal = d.localFocalPoint;
    // Topmost book under the finger, if any.
    _dragId = null;
    for (final pb in _placed.reversed) {
      if (_screenRectOf(pb).contains(focal)) {
        _dragId = pb.placement.id;
        _bookStart = Offset(pb.placement.x, pb.placement.y);
        _grabWorld = _screenToWorld(focal);
        _dragPos = _bookStart;
        break;
      }
    }
    _camStartScale = _scale;
    _camWorldFocal = _screenToWorld(focal);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final focal = d.localFocalPoint;
    if (d.scale != 1.0 || d.pointerCount >= 2 || _dragId == null) {
      // Pan + zoom the camera, anchoring the world point grabbed at start.
      final newScale = (_camStartScale * d.scale).clamp(_minScale, _maxScale);
      setState(() {
        _scale = newScale;
        _origin = Offset(
          focal.dx - _camWorldFocal.dx * newScale,
          focal.dy + _camWorldFocal.dy * newScale,
        );
      });
      _moved = true;
      return;
    }
    // Drag the grabbed book (camera fixed).
    final delta = _screenToWorld(focal) - _grabWorld;
    if (delta.distance > 0.002) _moved = true;
    setState(() => _dragPos = _bookStart + delta);
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final dragId = _dragId;
    _dragId = null;
    if (dragId == null) {
      if (!_moved) setState(() => _selectedId = null);
      return;
    }
    if (!_moved) {
      setState(() => _selectedId = dragId);
      return;
    }
    final pb = _placed.firstWhere((p) => p.placement.id == dragId);
    final f = _footOf(pb);
    final settled = _settle(
      draggedId: dragId,
      x: _dragPos.dx,
      y: _dragPos.dy,
      w: f.w,
      h: f.h,
    );
    repo.updatePlacement(dragId, x: settled.dx, y: settled.dy);
    setState(() => _selectedId = dragId);
  }

  /// Resolve where a dragged book comes to rest: drop onto the highest shelf or
  /// book-top beneath it (within its horizontal span), then nudge sideways out
  /// of any overlaps. A plain packing heuristic — no physics.
  Offset _settle({
    required String draggedId,
    required double x,
    required double y,
    required double w,
    required double h,
  }) {
    var bx = x;
    var by = y;
    const tol = 0.02; // 2 cm snap tolerance
    final others =
        _placed.where((p) => p.placement.id != draggedId).toList();

    // Vertical: highest surface at or just below the bottom, overlapping in X.
    double best = 0; // floor
    for (final s in _shelves) {
      final left = math.min(s.x1, s.x2);
      final right = math.max(s.x1, s.x2);
      final surface = math.max(s.y1, s.y2);
      if (bx + w > left && bx < right && surface <= by + tol && surface > best) {
        best = surface;
      }
    }
    for (final o in others) {
      final of = _footOf(o);
      final top = o.placement.y + of.h;
      if (bx + w > o.placement.x &&
          bx < o.placement.x + of.w &&
          top <= by + tol &&
          top > best) {
        best = top;
      }
    }
    by = best;

    // Horizontal: shove out of overlaps with books at the same height.
    for (var pass = 0; pass < 16; pass++) {
      var moved = false;
      for (final o in others) {
        final of = _footOf(o);
        final ox = o.placement.x, oy = o.placement.y;
        final vOverlap = by < oy + of.h - 1e-6 && by + h > oy + 1e-6;
        final hOverlap = bx < ox + of.w - 1e-6 && bx + w > ox + 1e-6;
        if (vOverlap && hOverlap) {
          final pushRight = (ox + of.w) - bx;
          final pushLeft = (bx + w) - ox;
          bx = pushRight <= pushLeft ? ox + of.w : ox - w;
          moved = true;
        }
      }
      if (!moved) break;
    }
    return Offset(bx, by);
  }

  // ---- actions ------------------------------------------------------------

  Future<void> _addShelf() async {
    // Default a new shelf a bit above whatever's already there.
    final topY = _shelves.isEmpty
        ? 0.3
        : _shelves.map((s) => math.max(s.y1, s.y2)).reduce(math.max) + 0.35;
    final result = await showDialog<_ShelfSpec>(
      context: context,
      builder: (_) => _ShelfDialog(defaultY: double.parse(topY.toStringAsFixed(2))),
    );
    if (result == null) return;
    await repo.addShelf(
      widget.environmentId,
      x1: result.left,
      y1: result.y,
      x2: result.right,
      y2: result.y,
      label: result.label,
    );
  }

  Future<void> _addBook() async {
    final book = await showModalBottomSheet<Book>(
      context: context,
      showDragHandle: true,
      builder: (_) => _BookPicker(repository: repo),
    );
    if (book == null || _origin == null || !mounted) return;
    // Drop at the centre of the view, then let it settle onto a surface.
    final size = context.size ?? const Size(400, 600);
    final centre = _screenToWorld(Offset(size.width / 2, size.height / 2));
    final f = _foot(book, 0, null, null);
    final settled = _settle(
      draggedId: '',
      x: centre.dx - f.w / 2,
      y: centre.dy,
      w: f.w,
      h: f.h,
    );
    await repo.placeBook(
      widget.environmentId,
      book.id,
      x: settled.dx,
      y: settled.dy,
    );
  }

  Future<void> _rotateSelected(PlacedBook pb) async {
    final newRot = pb.placement.rotation == 0 ? 90 : 0;
    final f = _foot(
      pb.book,
      newRot,
      pb.placement.widthOverride,
      pb.placement.heightOverride,
    );
    final settled = _settle(
      draggedId: pb.placement.id,
      x: pb.placement.x,
      y: pb.placement.y,
      w: f.w,
      h: f.h,
    );
    await repo.updatePlacement(
      pb.placement.id,
      rotation: newRot,
      x: settled.dx,
      y: settled.dy,
    );
  }

  Future<void> _resizeSelected(PlacedBook pb) async {
    final result = await showDialog<_SizeSpec>(
      context: context,
      builder: (_) => _SizeDialog(
        thicknessCm:
            PhysicalMetrics.thickness(pb.book, override: pb.placement.widthOverride) *
                100,
        heightCm:
            PhysicalMetrics.height(pb.book, override: pb.placement.heightOverride) *
                100,
      ),
    );
    if (result == null) return;
    await repo.updatePlacement(
      pb.placement.id,
      widthOverride: Value(result.reset ? null : result.thicknessCm / 100),
      heightOverride: Value(result.reset ? null : result.heightCm / 100),
    );
  }

  Future<void> _removeSelected(PlacedBook pb) async {
    await repo.removePlacement(pb.placement);
    setState(() => _selectedId = null);
  }

  // ---- build --------------------------------------------------------------

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.environmentName),
        actions: [
          IconButton(
            tooltip: 'Add shelf',
            onPressed: _addShelf,
            icon: const Icon(Icons.shelves),
          ),
          IconButton(
            tooltip: 'Zoom in',
            onPressed: () => _zoomAt(_viewCentre(), 1.25),
            icon: const Icon(Icons.zoom_in),
          ),
          IconButton(
            tooltip: 'Zoom out',
            onPressed: () => _zoomAt(_viewCentre(), 0.8),
            icon: const Icon(Icons.zoom_out),
          ),
        ],
      ),
      body: StreamBuilder<List<PhysicalShelf>>(
        stream: repo.watchShelves(widget.environmentId),
        builder: (context, shelfSnap) {
          _shelves = shelfSnap.data ?? const [];
          return StreamBuilder<List<PlacedBook>>(
            stream: repo.watchPlacedBooks(widget.environmentId),
            builder: (context, bookSnap) {
              _placed = bookSnap.data ?? const [];
              return LayoutBuilder(
                builder: (context, constraints) {
                  _origin ??= Offset(40, constraints.maxHeight - 90);
                  return _buildCanvas(constraints);
                },
              );
            },
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _addBook,
        icon: const Icon(Icons.add),
        label: const Text('Add book'),
      ),
    );
  }

  Offset _viewCentre() {
    final size = context.size ?? const Size(400, 600);
    return Offset(size.width / 2, size.height / 2);
  }

  Widget _buildCanvas(BoxConstraints constraints) {
    final theme = Theme.of(context);
    final selected = _selectedId == null
        ? null
        : _placed
            .where((p) => p.placement.id == _selectedId)
            .cast<PlacedBook?>()
            .firstWhere((p) => true, orElse: () => null);

    return Stack(
      children: [
        Positioned.fill(
          child: Listener(
            onPointerSignal: (event) {
              if (event is PointerScrollEvent) {
                _zoomAt(event.localPosition, event.scrollDelta.dy < 0 ? 1.1 : 0.9);
              }
            },
            child: GestureDetector(
              onScaleStart: _onScaleStart,
              onScaleUpdate: _onScaleUpdate,
              onScaleEnd: _onScaleEnd,
              child: CustomPaint(
                painter: _RoomPainter(
                  shelves: _shelves,
                  origin: _origin!,
                  scale: _scale,
                  line: theme.colorScheme.outlineVariant,
                  plank: theme.colorScheme.primary,
                  label: theme.colorScheme.onSurfaceVariant,
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        // Books.
        for (final pb in _placed) _bookWidget(pb),
        // Empty-state hint.
        if (_placed.isEmpty && _shelves.isEmpty)
          Center(
            child: Text(
              'Add a shelf, then drop in books.\nPinch or scroll to zoom, drag to pan.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        // Scale readout.
        Positioned(
          left: 12,
          bottom: 12,
          child: _ScaleBar(scale: _scale),
        ),
        // Selected-book toolbar.
        if (selected != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: _SelectionBar(
              title: selected.book.title,
              onRotate: () => _rotateSelected(selected),
              onResize: () => _resizeSelected(selected),
              onRemove: () => _removeSelected(selected),
              onClose: () => setState(() => _selectedId = null),
            ),
          ),
      ],
    );
  }

  Widget _bookWidget(PlacedBook pb) {
    final isDragging = _dragId == pb.placement.id;
    final f = _footOf(pb);
    // While dragging, follow the finger from local drag state.
    final bx = isDragging ? _dragPos.dx : pb.placement.x;
    final by = isDragging ? _dragPos.dy : pb.placement.y;
    final topLeft = _worldToScreen(Offset(bx, by + f.h));
    final w = f.w * _scale;
    final h = f.h * _scale;
    final color = PhysicalMetrics.color(pb.book);
    final selected = _selectedId == pb.placement.id;
    final flat = pb.placement.rotation == 90;

    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: w,
      height: h,
      child: IgnorePointer(
        // Gestures are handled by the canvas; this is purely visual.
        child: Opacity(
          opacity: isDragging ? 0.85 : 1,
          child: Container(
            decoration: BoxDecoration(
              color: color,
              border: Border.all(
                color: selected
                    ? Theme.of(context).colorScheme.secondary
                    : Colors.black.withValues(alpha: 0.35),
                width: selected ? 2.5 : 0.6,
              ),
              borderRadius: BorderRadius.circular(2),
            ),
            clipBehavior: Clip.antiAlias,
            alignment: Alignment.center,
            child: _spineLabel(pb.book, w, h, flat),
          ),
        ),
      ),
    );
  }

  Widget _spineLabel(Book book, double w, double h, bool flat) {
    // Only draw the title when the spine is big enough to read.
    final smallest = math.min(w, h);
    if (smallest < 16) return const SizedBox.shrink();
    final text = Text(
      book.title,
      maxLines: 1,
      overflow: TextOverflow.ellipsis,
      style: TextStyle(
        color: PhysicalMetrics.textColor(book),
        fontSize: (smallest * 0.42).clamp(7, 13),
        fontWeight: FontWeight.w600,
      ),
    );
    if (flat) return Padding(padding: const EdgeInsets.all(2), child: text);
    // Standing spine: read bottom-to-top.
    return RotatedBox(
      quarterTurns: 3,
      child: SizedBox(
        width: h - 6,
        child: Padding(padding: const EdgeInsets.all(2), child: text),
      ),
    );
  }
}

// ---- painter --------------------------------------------------------------

class _RoomPainter extends CustomPainter {
  _RoomPainter({
    required this.shelves,
    required this.origin,
    required this.scale,
    required this.line,
    required this.plank,
    required this.label,
  });

  final List<PhysicalShelf> shelves;
  final Offset origin;
  final double scale;
  final Color line;
  final Color plank;
  final Color label;

  Offset _w2s(Offset w) =>
      Offset(origin.dx + w.dx * scale, origin.dy - w.dy * scale);

  @override
  void paint(Canvas canvas, Size size) {
    // Faint metre grid.
    final grid = Paint()
      ..color = line.withValues(alpha: 0.25)
      ..strokeWidth = 1;
    final leftWorld = (0 - origin.dx) / scale;
    final rightWorld = (size.width - origin.dx) / scale;
    for (var x = leftWorld.floorToDouble(); x <= rightWorld; x += 1) {
      final sx = origin.dx + x * scale;
      canvas.drawLine(Offset(sx, 0), Offset(sx, size.height), grid);
    }
    final bottomWorld = (origin.dy - size.height) / scale;
    final topWorld = origin.dy / scale;
    for (var y = bottomWorld.floorToDouble(); y <= topWorld; y += 1) {
      final sy = origin.dy - y * scale;
      canvas.drawLine(Offset(0, sy), Offset(size.width, sy), grid);
    }

    // Floor (world y = 0).
    final floor = Paint()
      ..color = line
      ..strokeWidth = 2;
    canvas.drawLine(Offset(0, origin.dy), Offset(size.width, origin.dy), floor);

    // Shelves as planks.
    final plankPaint = Paint()..color = plank.withValues(alpha: 0.85);
    for (final s in shelves) {
      final p1 = _w2s(Offset(s.x1, s.y1));
      final p2 = _w2s(Offset(s.x2, s.y2));
      final left = math.min(p1.dx, p2.dx);
      final right = math.max(p1.dx, p2.dx);
      final top = math.min(p1.dy, p2.dy);
      canvas.drawRect(Rect.fromLTWH(left, top, right - left, 5), plankPaint);
      final name = s.label;
      if (name != null && name.isNotEmpty) {
        final tp = TextPainter(
          text: TextSpan(
            text: name,
            style: TextStyle(color: label, fontSize: 11),
          ),
          textDirection: TextDirection.ltr,
        )..layout();
        tp.paint(canvas, Offset(left + 2, top + 7));
      }
    }
  }

  @override
  bool shouldRepaint(covariant _RoomPainter old) =>
      old.shelves != shelves ||
      old.origin != origin ||
      old.scale != scale;
}

// ---- scale bar ------------------------------------------------------------

class _ScaleBar extends StatelessWidget {
  const _ScaleBar({required this.scale});
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

// ---- selection toolbar ----------------------------------------------------

class _SelectionBar extends StatelessWidget {
  const _SelectionBar({
    required this.title,
    required this.onRotate,
    required this.onResize,
    required this.onRemove,
    required this.onClose,
  });

  final String title;
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
              tooltip: 'Rotate 90°',
              onPressed: onRotate,
              icon: const Icon(Icons.rotate_90_degrees_cw),
            ),
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

// ---- book picker ----------------------------------------------------------

class _BookPicker extends StatefulWidget {
  const _BookPicker({required this.repository});
  final LibraryRepository repository;

  @override
  State<_BookPicker> createState() => _BookPickerState();
}

class _BookPickerState extends State<_BookPicker> {
  String _query = '';

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Book>>(
      stream: widget.repository.watchAllBooks(),
      builder: (context, snap) {
        final q = _query.trim().toLowerCase();
        final books = [
          for (final b in snap.data ?? const <Book>[])
            if (q.isEmpty || b.title.toLowerCase().contains(q)) b,
        ];
        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: TextField(
                  autofocus: false,
                  onChanged: (v) => setState(() => _query = v),
                  decoration: const InputDecoration(
                    prefixIcon: Icon(Icons.search),
                    hintText: 'Find a book to place…',
                    border: OutlineInputBorder(),
                    isDense: true,
                  ),
                ),
              ),
              Expanded(
                child: books.isEmpty
                    ? const Center(child: Text('No books.'))
                    : ListView.builder(
                        itemCount: books.length,
                        itemBuilder: (context, i) {
                          final b = books[i];
                          return ListTile(
                            leading: Container(
                              width: 12,
                              height: 34,
                              decoration: BoxDecoration(
                                color: PhysicalMetrics.color(b),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            title: Text(b.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: b.pageCount == null
                                ? null
                                : Text('${b.pageCount} pages'),
                            onTap: () => Navigator.pop(context, b),
                          );
                        },
                      ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// ---- shelf dialog ---------------------------------------------------------

class _ShelfSpec {
  _ShelfSpec(this.left, this.right, this.y, this.label);
  final double left;
  final double right;
  final double y;
  final String? label;
}

class _ShelfDialog extends StatefulWidget {
  const _ShelfDialog({required this.defaultY});
  final double defaultY;

  @override
  State<_ShelfDialog> createState() => _ShelfDialogState();
}

class _ShelfDialogState extends State<_ShelfDialog> {
  late final _left = TextEditingController(text: '0.0');
  late final _right = TextEditingController(text: '1.0');
  late final _height = TextEditingController(text: widget.defaultY.toString());
  final _label = TextEditingController();

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
      title: const Text('Add shelf'),
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
              _ShelfSpec(
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

// ---- size dialog ----------------------------------------------------------

class _SizeSpec {
  _SizeSpec({required this.thicknessCm, required this.heightCm, required this.reset});
  final double thicknessCm;
  final double heightCm;
  final bool reset;
}

class _SizeDialog extends StatefulWidget {
  const _SizeDialog({required this.thicknessCm, required this.heightCm});
  final double thicknessCm;
  final double heightCm;

  @override
  State<_SizeDialog> createState() => _SizeDialogState();
}

class _SizeDialogState extends State<_SizeDialog> {
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
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          field('Thickness (cm)', _thickness),
          field('Height (cm)', _height),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(
            context,
            _SizeSpec(thicknessCm: 0, heightCm: 0, reset: true),
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
              _SizeSpec(thicknessCm: t, heightCm: h, reset: false),
            );
          },
          child: const Text('Save'),
        ),
      ],
    );
  }
}
