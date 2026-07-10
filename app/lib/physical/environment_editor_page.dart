import 'dart:math' as math;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../book_detail/book_detail_page.dart';
import '../data/database.dart';
import '../data/library_repository.dart';
import '../shelf/shelf_view.dart' show SpineFace;
import 'physical_metrics.dart';
import 'settle.dart';

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
  // Shelf dragging.
  String? _dragShelfId;
  PhysicalShelf? _shelfStart;
  Offset _shelfGrabWorld = Offset.zero;
  Offset _shelfDelta = Offset.zero; // world offset applied while dragging
  // A shelf holding books was grabbed: it's pinned, so the gesture is swallowed
  // and the user is told to clear the books first.
  bool _lockedShelfGrab = false;

  LibraryRepository get repo => widget.repository;

  Offset _worldToScreen(Offset w) =>
      Offset(_origin!.dx + w.dx * _scale, _origin!.dy - w.dy * _scale);

  Offset _screenToWorld(Offset s) =>
      Offset((s.dx - _origin!.dx) / _scale, (_origin!.dy - s.dy) / _scale);

  _Foot _foot(Book b, int rot, String? fmt, double? wo, double? ho) {
    final format = BookFormat.byKey(fmt);
    final t = PhysicalMetrics.thickness(b, format: format, override: wo);
    final h = PhysicalMetrics.height(b, format: format, override: ho);
    return rot == 0 ? (w: t, h: h) : (w: h, h: t);
  }

  _Foot _footOf(PlacedBook pb) => _foot(
        pb.book,
        pb.placement.rotation,
        pb.placement.format,
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

  // A grab band around a shelf's plank, so the thin line is easy to hit.
  Rect _shelfHitRect(PhysicalShelf s) {
    final p1 = _worldToScreen(Offset(s.x1, s.y1));
    final p2 = _worldToScreen(Offset(s.x2, s.y2));
    final left = math.min(p1.dx, p2.dx);
    final right = math.max(p1.dx, p2.dx);
    final top = math.min(p1.dy, p2.dy);
    return Rect.fromLTRB(left - 6, top - 10, right + 6, top + 12);
  }

  /// True when a placed book is resting on [s] (see [shelfHasBooks]). Such a
  /// shelf is pinned: moving it would strand its books.
  bool _shelfHasBooks(PhysicalShelf s) {
    final others = _placed.map((pb) {
      final f = _footOf(pb);
      return SettleBox(x: pb.placement.x, y: pb.placement.y, w: f.w, h: f.h);
    }).toList();
    return shelfHasBooks(
      SettleSegment(x1: s.x1, y1: s.y1, x2: s.x2, y2: s.y2),
      others,
    );
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
    _dragShelfId = null;
    _lockedShelfGrab = false;
    for (final pb in _placed.reversed) {
      if (_screenRectOf(pb).contains(focal)) {
        _dragId = pb.placement.id;
        _bookStart = Offset(pb.placement.x, pb.placement.y);
        _grabWorld = _screenToWorld(focal);
        _dragPos = _bookStart;
        break;
      }
    }
    // Otherwise a shelf, so empty shelves can be dragged too. A shelf holding
    // books is pinned — grabbing it locks the gesture instead of moving it.
    if (_dragId == null) {
      for (final s in _shelves.reversed) {
        if (_shelfHitRect(s).contains(focal)) {
          if (_shelfHasBooks(s)) {
            _lockedShelfGrab = true;
          } else {
            _dragShelfId = s.id;
            _shelfStart = s;
            _shelfGrabWorld = _screenToWorld(focal);
            _shelfDelta = Offset.zero;
          }
          break;
        }
      }
    }
    _camStartScale = _scale;
    _camWorldFocal = _screenToWorld(focal);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final focal = d.localFocalPoint;
    // A pinned (occupied) shelf was grabbed with one finger: swallow the pan so
    // the shelf stays put and the view doesn't slide. A pinch still zooms.
    if (_lockedShelfGrab && d.scale == 1.0 && d.pointerCount < 2) {
      if ((_screenToWorld(focal) - _camWorldFocal).distance > 0.002) {
        _moved = true;
      }
      return;
    }
    final draggingItem = _dragId != null || _dragShelfId != null;
    if (d.scale != 1.0 || d.pointerCount >= 2 || !draggingItem) {
      // A pinch that began on a pinned shelf is a zoom, not a move attempt —
      // release the lock so no "shelf is pinned" hint fires on release.
      _lockedShelfGrab = false;
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
    if (_dragId != null) {
      // Drag the grabbed book (camera fixed).
      final delta = _screenToWorld(focal) - _grabWorld;
      if (delta.distance > 0.002) _moved = true;
      setState(() => _dragPos = _bookStart + delta);
      return;
    }
    // Drag the grabbed shelf.
    final delta = _screenToWorld(focal) - _shelfGrabWorld;
    if (delta.distance > 0.002) _moved = true;
    setState(() => _shelfDelta = delta);
  }

  void _onScaleEnd(ScaleEndDetails d) {
    final dragId = _dragId;
    final dragShelfId = _dragShelfId;
    final lockedShelfGrab = _lockedShelfGrab;
    _dragId = null;
    _dragShelfId = null;
    _lockedShelfGrab = false;

    // Tried to drag a shelf that holds books: it stayed put — explain why.
    if (lockedShelfGrab) {
      if (_moved) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('This shelf holds books — move them off to reposition it.'),
            duration: Duration(seconds: 2),
          ),
        );
      } else {
        setState(() => _selectedId = null);
      }
      return;
    }

    // Finished dragging a shelf: persist the shifted endpoints, then settle.
    if (dragShelfId != null) {
      final s = _shelfStart;
      if (_moved && s != null) {
        () async {
          await repo.updateShelf(
            s.id,
            x1: s.x1 + _shelfDelta.dx,
            y1: s.y1 + _shelfDelta.dy,
            x2: s.x2 + _shelfDelta.dx,
            y2: s.y2 + _shelfDelta.dy,
          );
          await _applyGravity();
        }();
      }
      setState(() => _shelfDelta = Offset.zero);
      return;
    }

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
    if (!settled.onSurface) {
      // Dropped into empty space with no shelf beneath — take it off the shelf,
      // then let anything that was on top of it fall.
      _removeAndSettle(pb.placement);
      setState(() => _selectedId = null);
      return;
    }
    // Move it, then settle anything left unsupported at its old spot.
    _moveAndSettle(dragId, settled.pos);
    setState(() => _selectedId = dragId);
  }

  /// Resolve where a dragged book comes to rest: drop onto the highest shelf or
  /// book-top beneath it (within its horizontal span), then nudge sideways out
  /// of any overlaps. A plain packing heuristic — no physics. `onSurface` is
  /// false when nothing (no shelf or book) was under it — the caller treats that
  /// as "dropped into empty space".
  ({Offset pos, bool onSurface}) _settle({
    required String draggedId,
    required double x,
    required double y,
    required double w,
    required double h,
  }) {
    final shelves = [
      for (final s in _shelves)
        SettleSegment(x1: s.x1, y1: s.y1, x2: s.x2, y2: s.y2),
    ];
    final others = _placed
        .where((p) => p.placement.id != draggedId)
        .map((p) {
          final of = _footOf(p);
          return SettleBox(
            x: p.placement.x,
            y: p.placement.y,
            w: of.w,
            h: of.h,
          );
        })
        .toList();
    final r = settle(
      x: x,
      y: y,
      w: w,
      h: h,
      shelves: shelves,
      others: others,
    );
    return (pos: Offset(r.x, r.y), onSurface: r.onSurface);
  }

  /// Gravity pass: after a book is removed or moved, drop any book now left
  /// unsupported onto the highest surface (shelf or book) beneath it, so stacks
  /// collapse. Vertical only — books keep their x. Reads fresh state so it's
  /// correct right after a mutation. Falls to the floor (y = 0) if nothing is
  /// below (non-destructive).
  Future<void> _applyGravity() async {
    final books = await repo.watchPlacedBooks(widget.environmentId).first;
    final shelves = await repo.watchShelves(widget.environmentId).first;
    if (!mounted) return;
    books.sort((a, b) => a.placement.y.compareTo(b.placement.y));
    const tol = 0.02;
    final tops = <({double x, double w, double topY})>[];
    for (final pb in books) {
      final f = _footOf(pb);
      final x = pb.placement.x;
      final bottom = pb.placement.y;
      double surface = 0; // floor
      for (final s in shelves) {
        final left = math.min(s.x1, s.x2);
        final right = math.max(s.x1, s.x2);
        final top = math.max(s.y1, s.y2);
        if (x + f.w > left && x < right && top <= bottom + tol && top > surface) {
          surface = top;
        }
      }
      for (final t in tops) {
        if (x + f.w > t.x &&
            x < t.x + t.w &&
            t.topY <= bottom + tol &&
            t.topY > surface) {
          surface = t.topY;
        }
      }
      tops.add((x: x, w: f.w, topY: surface + f.h));
      if ((surface - bottom).abs() > 0.001) {
        await repo.updatePlacement(pb.placement.id, y: surface);
      }
    }
  }

  Future<void> _removeAndSettle(BookPlacement p) async {
    await repo.removePlacement(p);
    await _applyGravity();
  }

  Future<void> _moveAndSettle(String id, Offset pos) async {
    await repo.updatePlacement(id, x: pos.dx, y: pos.dy);
    await _applyGravity();
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
    final f = _foot(book, 0, null, null, null);
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
      x: settled.pos.dx,
      y: settled.pos.dy,
    );
  }

  Future<void> _rotateSelected(PlacedBook pb) async {
    final newRot = pb.placement.rotation == 0 ? 90 : 0;
    final f = _foot(
      pb.book,
      newRot,
      pb.placement.format,
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
      x: settled.pos.dx,
      y: settled.pos.dy,
    );
    await _applyGravity();
  }

  Future<void> _resizeSelected(PlacedBook pb) async {
    final format = BookFormat.byKey(pb.placement.format);
    final result = await showDialog<_SizeSpec>(
      context: context,
      builder: (_) => _SizeDialog(
        book: pb.book,
        formatKey: pb.placement.format,
        thicknessCm: PhysicalMetrics.thickness(
              pb.book,
              format: format,
              override: pb.placement.widthOverride,
            ) *
            100,
        heightCm: PhysicalMetrics.height(
              pb.book,
              format: format,
              override: pb.placement.heightOverride,
            ) *
            100,
      ),
    );
    if (result == null) return;
    if (result.reset) {
      await _resetSize(pb);
      return;
    }
    // Store the preset, and keep a dimension override only when it differs from
    // what the preset would compute (so a plain preset recomputes from pages).
    final fmt = BookFormat.byKey(result.formatKey);
    final defT = PhysicalMetrics.thickness(pb.book, format: fmt);
    final defH = PhysicalMetrics.height(pb.book, format: fmt);
    final t = result.thicknessCm / 100;
    final h = result.heightCm / 100;
    await repo.updatePlacement(
      pb.placement.id,
      format: Value(result.formatKey),
      widthOverride: (t - defT).abs() < 0.0005 ? const Value(null) : Value(t),
      heightOverride: (h - defH).abs() < 0.0005 ? const Value(null) : Value(h),
    );
    await _applyGravity();
  }

  Future<void> _resetSize(PlacedBook pb) async {
    await repo.updatePlacement(
      pb.placement.id,
      format: const Value(null),
      widthOverride: const Value(null),
      heightOverride: const Value(null),
    );
    await _applyGravity();
  }

  Future<void> _removeSelected(PlacedBook pb) async {
    await repo.removePlacement(pb.placement);
    setState(() => _selectedId = null);
    await _applyGravity();
  }

  /// Open the book's detail page (from which it can be read), so the physical
  /// view isn't only for organising.
  void _openBook(PlacedBook pb) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookDetailPage(book: pb.book, repository: repo),
      ),
    );
  }

  RelativeRect _menuPosition(Offset global) {
    final overlay =
        Overlay.of(context).context.findRenderObject() as RenderBox;
    return RelativeRect.fromRect(
      Rect.fromLTWH(global.dx, global.dy, 0, 0),
      Offset.zero & overlay.size,
    );
  }

  /// Long-press (touch) or right-click (desktop) a book — or, failing that, a
  /// shelf — for a quick menu.
  Future<void> _contextMenuAt(Offset local, Offset global) async {
    for (final pb in _placed.reversed) {
      if (_screenRectOf(pb).contains(local)) {
        await _bookMenu(pb, global);
        return;
      }
    }
    for (final s in _shelves.reversed) {
      if (_shelfHitRect(s).contains(local)) {
        await _shelfMenu(s, global);
        return;
      }
    }
  }

  Future<void> _bookMenu(PlacedBook pb, Offset global) async {
    setState(() => _selectedId = pb.placement.id);
    final choice = await showMenu<String>(
      context: context,
      position: _menuPosition(global),
      items: [
        const PopupMenuItem(value: 'open', child: Text('Open book')),
        PopupMenuItem(
          value: 'rotate',
          child: Text(pb.placement.rotation == 0 ? 'Lay flat' : 'Stand up'),
        ),
        const PopupMenuItem(value: 'resize', child: Text('Resize…')),
        const PopupMenuItem(
            value: 'reset', child: Text('Reset size to default')),
        const PopupMenuItem(value: 'remove', child: Text('Remove from room')),
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'open':
        _openBook(pb);
      case 'rotate':
        await _rotateSelected(pb);
      case 'resize':
        await _resizeSelected(pb);
      case 'reset':
        await _resetSize(pb);
      case 'remove':
        await _removeSelected(pb);
    }
  }

  Future<void> _shelfMenu(PhysicalShelf s, Offset global) async {
    final choice = await showMenu<String>(
      context: context,
      position: _menuPosition(global),
      items: const [
        PopupMenuItem(value: 'edit', child: Text('Edit shelf…')),
        PopupMenuItem(value: 'delete', child: Text('Delete shelf')),
      ],
    );
    if (choice == null || !mounted) return;
    if (choice == 'delete') {
      await repo.deleteShelf(s.id);
      await _applyGravity();
    } else {
      await _editShelf(s);
    }
  }

  Future<void> _editShelf(PhysicalShelf s) async {
    final result = await showDialog<_ShelfSpec>(
      context: context,
      builder: (_) => _ShelfDialog(
        title: 'Edit shelf',
        defaultY: s.y1,
        initialLeft: math.min(s.x1, s.x2),
        initialRight: math.max(s.x1, s.x2),
        initialLabel: s.label,
      ),
    );
    if (result == null) return;
    await repo.updateShelf(
      s.id,
      x1: result.left,
      y1: result.y,
      x2: result.right,
      y2: result.y,
      label: Value(result.label),
    );
    await _applyGravity();
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
          IconButton(
            tooltip: 'Help',
            onPressed: _showHelp,
            icon: const Icon(Icons.help_outline),
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
      // Hidden while a book is selected, so it doesn't overlap the toolbar.
      floatingActionButton: _selectedId != null
          ? null
          : FloatingActionButton.extended(
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

  void _showHelp() {
    showDialog<void>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Arranging the room'),
        content: const Text(
          '• Pinch or scroll to zoom; drag empty space to pan.\n'
          '• “Add book” drops a book in; drag it so it rests on a shelf or '
          'on top of another book.\n'
          '• Tap a book to select it (rotate / resize / remove).\n'
          '• Right-click or long-press a book or shelf to edit it.\n'
          '• Drag an empty shelf to move it — a shelf with books on it is '
          'pinned until you clear them.',
        ),
        actions: [
          FilledButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Got it'),
          ),
        ],
      ),
    );
  }

  Widget _buildCanvas(BoxConstraints constraints) {
    final theme = Theme.of(context);
    final selected = _selectedId == null
        ? null
        : _placed
            .where((p) => p.placement.id == _selectedId)
            .cast<PlacedBook?>()
            .firstWhere((p) => true, orElse: () => null);

    return Focus(
      autofocus: true,
      onKeyEvent: (node, event) {
        // Esc clears the current selection.
        if (event is KeyDownEvent &&
            event.logicalKey == LogicalKeyboardKey.escape &&
            _selectedId != null) {
          setState(() => _selectedId = null);
          return KeyEventResult.handled;
        }
        return KeyEventResult.ignored;
      },
      child: Stack(
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
              onLongPressStart: (d) =>
                  _contextMenuAt(d.localPosition, d.globalPosition),
              onSecondaryTapDown: (d) =>
                  _contextMenuAt(d.localPosition, d.globalPosition),
              child: CustomPaint(
                painter: _RoomPainter(
                  shelves: _shelves,
                  origin: _origin!,
                  scale: _scale,
                  line: theme.colorScheme.outlineVariant,
                  plank: theme.colorScheme.primary,
                  label: theme.colorScheme.onSurfaceVariant,
                  draggingShelfId: _dragShelfId,
                  shelfDelta: _shelfDelta,
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
              'Add a shelf, then drop in books.\n'
              'Pinch or scroll to zoom, drag to pan.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
        // Persistent tip on how to edit — a small box top-right, under the
        // zoom icons.
        if (_placed.isNotEmpty || _shelves.isNotEmpty)
          Positioned(
            top: 8,
            right: 8,
            child: Container(
              width: 150,
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              decoration: BoxDecoration(
                color: theme.colorScheme.surface.withValues(alpha: 0.88),
                borderRadius: BorderRadius.circular(10),
                border: Border.all(color: theme.colorScheme.outlineVariant),
              ),
              child: Text(
                'Right-click or long-press a book or shelf to edit',
                style: theme.textTheme.bodySmall,
              ),
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
              onOpen: () => _openBook(selected),
              onRotate: () => _rotateSelected(selected),
              onResize: () => _resizeSelected(selected),
              onRemove: () => _removeSelected(selected),
              onClose: () => setState(() => _selectedId = null),
            ),
          ),
        ],
      ),
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
    final selected = _selectedId == pb.placement.id;
    final flat = pb.placement.rotation == 90;

    // The same spine artwork as the digital shelf (cover slice or generated).
    // For a flat book, the standing spine is turned a quarter-turn anticlockwise
    // so the title still reads left-to-right.
    Widget spine = SpineFace(book: pb.book, coverFile: repo.coverFileOf(pb.book));
    if (flat) spine = RotatedBox(quarterTurns: 3, child: spine);

    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: w,
      height: h,
      child: IgnorePointer(
        // Gestures are handled by the canvas; this is purely visual.
        child: Opacity(
          opacity: isDragging ? 0.85 : 1,
          child: Stack(
            fit: StackFit.expand,
            children: [
              spine,
              if (selected)
                DecoratedBox(
                  decoration: BoxDecoration(
                    border: Border.all(
                      color: Theme.of(context).colorScheme.secondary,
                      width: 2.5,
                    ),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
            ],
          ),
        ),
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
    this.draggingShelfId,
    this.shelfDelta = Offset.zero,
  });

  final List<PhysicalShelf> shelves;
  final Offset origin;
  final double scale;
  final Color line;
  final Color plank;
  final Color label;
  final String? draggingShelfId;
  final Offset shelfDelta;

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

    // Shelves as planks (the one being dragged is shifted live).
    final plankPaint = Paint()..color = plank.withValues(alpha: 0.85);
    for (final s in shelves) {
      final d = s.id == draggingShelfId ? shelfDelta : Offset.zero;
      final p1 = _w2s(Offset(s.x1 + d.dx, s.y1 + d.dy));
      final p2 = _w2s(Offset(s.x2 + d.dx, s.y2 + d.dy));
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
      old.scale != scale ||
      old.draggingShelfId != draggingShelfId ||
      old.shelfDelta != shelfDelta;
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
  const _ShelfDialog({
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
  State<_ShelfDialog> createState() => _ShelfDialogState();
}

class _ShelfDialogState extends State<_ShelfDialog> {
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
  _SizeSpec({
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

class _SizeDialog extends StatefulWidget {
  const _SizeDialog({
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
  State<_SizeDialog> createState() => _SizeDialogState();
}

class _SizeDialogState extends State<_SizeDialog> {
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
            _SizeSpec(
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
              _SizeSpec(
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
