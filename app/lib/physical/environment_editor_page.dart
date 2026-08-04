import 'dart:async';
import 'dart:io';
import 'dart:math' as math;
import 'dart:ui' as ui;

import 'package:drift/drift.dart' show Value;
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

import '../book_detail/book_detail_page.dart';
import '../data/database.dart';
import '../data/external_open.dart';
import '../data/library_repository.dart';
import '../settings/app_settings.dart';
import '../shelf/shelf_view.dart' show SpineFace;
import 'book_picker.dart';
import 'bookcase_template.dart';
import 'bulk_place.dart';
import 'labels.dart';
import 'locate.dart';
import 'physical_metrics.dart';
import 'placement_toolbar.dart';
import 'room_backdrop.dart';
import 'room_measure.dart';
import 'room_painter.dart';
import 'room_prop.dart';
import 'room_semantics.dart';
import 'settle.dart';
import 'shelf_snap.dart';
import 'stocktake_page.dart';
import 'shelf_dialogs.dart';

/// A book's footprint (width × height) in metres, after rotation.
typedef _Foot = ({double w, double h});

/// How thick an upright is treated as being when it comes to books bumping into
/// it (metres). A panel or divider is drawn from a single X, so without this it
/// would have no width to collide with — 18 mm is what a shelf board actually
/// measures.
const _barrierThickness = 0.018;

/// The shelf editor: a front-elevation, to-scale view of one physical
/// environment. Pan and pinch-zoom the room; drag books so they rest on the
/// nearest shelf or on top of another book (no overlaps); tap a book to rotate,
/// resize, or remove it. Everything is stored in metres.
class EnvironmentEditorPage extends StatefulWidget {
  const EnvironmentEditorPage({
    super.key,
    required this.repository,
    required this.settings,
    required this.environmentId,
    required this.environmentName,
    this.focusPlacementId,
  });

  final LibraryRepository repository;
  final AppSettingsStore settings;
  final String environmentId;
  final String environmentName;

  /// A placement to pan to and pulse once the room is on screen — how *Find my
  /// copy* (plan 5 #28) arrives here.
  final String? focusPlacementId;

  @override
  State<EnvironmentEditorPage> createState() => _EnvironmentEditorPageState();
}

class _EnvironmentEditorPageState extends State<EnvironmentEditorPage>
    with SingleTickerProviderStateMixin {
  // Camera: pixels-per-metre and the screen offset of world (0, 0). World Y is
  // up, so screen Y is flipped in the transforms below.
  double _scale = 300;
  Offset? _origin;
  static const _minScale = 40.0;
  static const _maxScale = 1600.0;

  // Latest stream data, so gesture callbacks can hit-test.
  List<PhysicalShelf> _shelves = const [];
  List<PlacedBook> _placed = const [];
  List<RoomProp> _props = const [];

  /// The prop being dragged, and where it currently is. Kept separate from the
  /// book drag: a prop has no placement, no copy and no rotation, and merging
  /// the two paths would mean a null check on every line of both.
  String? _dragPropId;
  Offset _propDragPos = Offset.zero;

  String? _selectedId;


  /// Segment ids picked while building a group by hand. Non-null means the
  /// "choose the parts" mode is on.
  Set<String>? _grouping;

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
  /// The segments moving with the one being dragged (its bookcase, or just it).
  List<PhysicalShelf> _dragGroup = const [];
  Offset _shelfGrabWorld = Offset.zero;
  Offset _shelfDelta = Offset.zero; // world offset applied while dragging
  // Placement ids of the books resting on the shelf being dragged, so they ride
  // along with it — live via [_shelfDeltaVN], then persisted on release.
  Set<String> _ridingIds = const {};
  /// Props standing on the shelf being dragged. They ride it exactly as the
  /// books do — an ornament that stayed put while the shelf slid out from
  /// under it would be the one thing in the room ignoring gravity.
  Set<String> _ridingPropIds = const {};

  // In-flight drag positions, published without a whole-canvas setState: the
  // dragged book's overlay listens to [_dragPosVN], and the room painter
  // repaints from [_shelfDeltaVN]. A single setState enters "drag mode" on the
  // first real movement; every frame after that only pokes a notifier.
  final ValueNotifier<Offset> _dragPosVN = ValueNotifier(Offset.zero);
  final ValueNotifier<Offset> _shelfDeltaVN = ValueNotifier(Offset.zero);

  // ---- find, search and snapshot (plan 5 #28) -----------------------------

  /// The in-room filter. Non-matching books are *dimmed*, never hidden: a room
  /// with holes in it stops being a picture of your shelves.
  final _search = TextEditingController();
  String _query = '';
  bool _searchOpen = false;

  /// Authors, for the filter — the field would be useless if typing a surname
  /// matched nothing. Watched rather than fetched so a rename shows up.
  Map<String, List<String>> _authorsByBook = const {};
  StreamSubscription<Map<String, List<String>>>? _authorsSub;

  /// The placement being pulsed after a *Find my copy*, and the animation that
  /// draws the ring. One-shot: it runs three times and stops, because a marker
  /// that pulses forever becomes part of the furniture.
  String? _pulseId;
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 700),
  );
  bool _didFocus = false;

  /// Wraps the canvas so it can be captured as a PNG.
  final GlobalKey _canvasKey = GlobalKey();

  // ---- room realism (plan 5 #29) ------------------------------------------

  /// The decoded backdrop photo, and the row it came from. Decoded once and
  /// held rather than re-read per frame: a wall photo is megabytes, and the
  /// painter runs on every pan.
  ui.Image? _backdrop;
  PhysicalEnvironment? _environment;

  /// The measure tool. Non-null `_measureFrom` means the tool is armed; the
  /// two points are world metres.
  bool _measuring = false;
  Offset? _measureFrom;
  Offset? _measureTo;

  @override
  void initState() {
    super.initState();
    _authorsSub = repo.watchAuthorsByBook().listen((byBook) {
      if (mounted) setState(() => _authorsByBook = byBook);
    });
    _loadEnvironment();
  }

  /// Reads the room row and decodes its backdrop, if any.
  Future<void> _loadEnvironment() async {
    final environment = await repo.layout.environment(widget.environmentId);
    if (!mounted) return;
    setState(() => _environment = environment);
    await _loadBackdrop(environment?.backdropPath);
  }

  Future<void> _loadBackdrop(String? relativePath) async {
    if (relativePath == null) {
      // Dispose the old one: an image held after its row is gone is a leak the
      // size of a photo.
      _backdrop?.dispose();
      if (mounted) setState(() => _backdrop = null);
      return;
    }
    try {
      final file = File(p.join(repo.dataDir.path, relativePath));
      final bytes = await file.readAsBytes();
      final decoded = await decodeImageFromList(bytes);
      if (!mounted) {
        decoded.dispose();
        return;
      }
      _backdrop?.dispose();
      setState(() => _backdrop = decoded);
    } catch (_) {
      // A missing or unreadable photo draws nothing rather than failing the
      // room — the geometry is the part that matters.
      if (mounted) setState(() => _backdrop = null);
    }
  }

  @override
  void dispose() {
    _backdrop?.dispose();
    _authorsSub?.cancel();
    _search.dispose();
    _pulse.dispose();
    _dragPosVN.dispose();
    _shelfDeltaVN.dispose();
    super.dispose();
  }

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
  /// A grab band around a segment, thin in whichever direction the segment is
  /// thin.
  ///
  /// This used to assume every segment was horizontal — it built a band across
  /// the top edge — so once uprights gained a real vertical extent, a side
  /// panel or divider was only clickable in a 12×22 box at its very top. In
  /// practice that meant they could not be selected or dragged at all.
  Rect _shelfHitRect(PhysicalShelf s) {
    final p1 = _worldToScreen(Offset(s.x1, s.y1));
    final p2 = _worldToScreen(Offset(s.x2, s.y2));
    final bounds = Rect.fromPoints(p1, p2);
    // Inflate to a comfortable target in both axes: a 1px line is not something
    // anyone can hit with a finger, and the bound is *at least* this thick
    // rather than exactly it, so a wide shelf stays wide.
    const grab = 11.0;
    return Rect.fromLTRB(
      bounds.left - grab,
      bounds.top - grab,
      bounds.right + grab,
      bounds.bottom + grab,
    );
  }

  /// The uprights books can be bracketed by — side panels and dividers with a
  /// real vertical extent. [exceptId] leaves out the segment being moved.
  List<Upright> _uprights({String? exceptId}) => [
        for (final s in _shelves)
          if (s.id != exceptId &&
              !ShelfKind.parse(s.kind).holdsBooks &&
              (s.y2 - s.y1).abs() > 1e-9)
            (
              x: (s.x1 + s.x2) / 2,
              bottom: math.min(s.y1, s.y2),
              top: math.max(s.y1, s.y2),
            ),
      ];

  /// Every segment that moves with [s] — its whole bookcase when it is part of
  /// one, otherwise just itself.
  List<PhysicalShelf> _groupOf(PhysicalShelf s) {
    final group = s.groupId;
    if (group == null) return [s];
    return [
      for (final other in _shelves)
        if (other.groupId == group) other,
    ];
  }

  /// The props resting on shelf [s], by the same test the books use.
  List<RoomProp> _propRidersOf(PhysicalShelf s) {
    final seg = SettleSegment(x1: s.x1, y1: s.y1, x2: s.x2, y2: s.y2);
    return [
      for (final prop in _props)
        if (restsOnShelf(
          SettleBox(x: prop.x, y: prop.y, w: prop.widthM, h: prop.heightM),
          seg,
        ))
          prop,
    ];
  }

  /// The placed books resting on shelf [s], so they can travel with it when it
  /// is moved (dragged or edited) instead of being stranded in mid-air.
  List<PlacedBook> _ridersOf(PhysicalShelf s) {
    final seg = SettleSegment(x1: s.x1, y1: s.y1, x2: s.x2, y2: s.y2);
    return [
      for (final pb in _placed)
        if (restsOnShelf(
          SettleBox(
            x: pb.placement.x,
            y: pb.placement.y,
            w: _footOf(pb).w,
            h: _footOf(pb).h,
          ),
          seg,
        ))
          pb,
    ];
  }

  /// Keep a shelf move on or above the floor (y = 0): a horizontal shelf can't
  /// be dragged below the ground. The room is open sideways, so x is free.
  Offset _clampShelfDelta(PhysicalShelf s, Offset delta) {
    final base = math.min(s.y1, s.y2);
    final dy = base + delta.dy < 0 ? -base : delta.dy;
    return Offset(delta.dx, dy);
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
    // The measure tool takes over the canvas while it is armed (plan 5 #29):
    // one drag, one distance. A modeless gesture would have to compete with
    // pan, zoom, drag-a-book and drag-a-shelf, and lose.
    if (_measuring) {
      setState(() {
        _measureFrom = _screenToWorld(focal);
        _measureTo = _measureFrom;
      });
      return;
    }
    // Topmost book under the finger, if any.
    final dragPropId = _dragPropId;
    _dragId = null;
    _dragShelfId = null;
    _dragPropId = null;
    _dragGroup = const [];
    _ridingIds = const {};
    _ridingPropIds = const {};

    // A released prop settles like a book: onto the highest surface beneath it,
    // nudged clear of whatever is already there. Dropped in mid-air it goes
    // back where it came from rather than floating, because unlike a book there
    // is no "not on a shelf any more" state for it to fall into.
    if (dragPropId != null) {
      final prop = _props.firstWhere((p) => p.id == dragPropId);
      if (_moved) {
        final settled = _settle(
          draggedId: prop.id,
          x: _propDragPos.dx,
          y: _propDragPos.dy,
          w: prop.widthM,
          h: prop.heightM,
        );
        if (settled.onSurface) {
          () async {
            await repo.layout.moveProp(
              prop.id,
              x: settled.pos.dx,
              y: settled.pos.dy,
            );
          }();
        }
      }
      setState(() {});
      return;
    }
    for (final pb in _placed.reversed) {
      if (_screenRectOf(pb).contains(focal)) {
        _dragId = pb.placement.id;
        _bookStart = Offset(pb.placement.x, pb.placement.y);
        _grabWorld = _screenToWorld(focal);
        _dragPos = _bookStart;
        break;
      }
    }
    // A prop, before the shelf it is standing on — it is drawn on top, so it
    // should be grabbed first.
    if (_dragId == null) {
      for (final prop in _props.reversed) {
        if (_propRect(prop).contains(focal)) {
          _dragPropId = prop.id;
          _propDragPos = Offset(prop.x, prop.y);
          _grabWorld = _screenToWorld(focal) - _propDragPos;
          break;
        }
      }
    }
    // Otherwise a shelf — any shelf can be dragged, and the books resting on it
    // ride along (captured here so they follow live and persist on release).
    if (_dragId == null && _dragPropId == null) {
      for (final s in _shelves.reversed) {
        if (_shelfHitRect(s).contains(focal)) {
          // Anchored is the default, so a left-click on a shelf pans the room
          // rather than dragging the furniture. Unanchor it from its menu
          // first — see `PhysicalShelves.anchored`.
          if (s.anchored) continue;
          _dragShelfId = s.id;
          _shelfStart = s;
          _shelfGrabWorld = _screenToWorld(focal);
          _shelfDelta = Offset.zero;
          // A bookcase moves as one, and everything standing on any of its
          // shelves rides along — dragging a side panel and leaving the shelves
          // behind would be a very surprising way to take a bookcase apart.
          _dragGroup = _groupOf(s);
          _ridingIds = {
            for (final part in _dragGroup)
              for (final pb in _ridersOf(part)) pb.placement.id,
          };
          _ridingPropIds = {
            for (final part in _dragGroup)
              for (final prop in _propRidersOf(part)) prop.id,
          };
          break;
        }
      }
    }
    _camStartScale = _scale;
    _camWorldFocal = _screenToWorld(focal);
  }

  void _onScaleUpdate(ScaleUpdateDetails d) {
    final focal = d.localFocalPoint;
    if (_measuring && _measureFrom != null) {
      setState(() => _measureTo = _screenToWorld(focal));
      return;
    }
    final draggingItem =
        _dragId != null || _dragShelfId != null || _dragPropId != null;
    if (d.scale != 1.0 || d.pointerCount >= 2 || !draggingItem) {
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
    if (_dragPropId != null) {
      // A prop is one widget with no riders, so a plain setState is cheap
      // enough — the book path needs a notifier because it also moves an
      // overlay and everything resting on the shelf.
      setState(() => _propDragPos = _screenToWorld(focal) - _grabWorld);
      _moved = true;
      return;
    }
    if (_dragId != null) {
      // Drag the grabbed book (camera fixed). Publish via the notifier so only
      // the dragged book's overlay repaints, not every other book and the room.
      final delta = _screenToWorld(focal) - _grabWorld;
      _dragPos = _bookStart + delta;
      _dragPosVN.value = _dragPos;
      if (delta.distance > 0.002 && !_moved) {
        // First real movement: one rebuild to enter drag mode (drop this book
        // from the static list and show the moving overlay). Later frames only
        // update the notifier above.
        _moved = true;
        setState(() {});
      }
      return;
    }
    // Drag the grabbed shelf — the painter and any riding books repaint from
    // _shelfDeltaVN. Clamp so the shelf can't be pushed below the floor.
    final delta = _clampShelfDelta(_shelfStart!, _screenToWorld(focal) - _shelfGrabWorld);
    _shelfDelta = delta;
    _shelfDeltaVN.value = delta;
    if (delta.distance > 0.002 && !_moved) {
      // One rebuild so the painter picks up draggingShelfId; then notifier-only.
      _moved = true;
      setState(() {});
    }
  }

  void _onScaleEnd(ScaleEndDetails d) {
    if (_measuring) {
      // The measurement stays on screen until the next drag or until the tool
      // is switched off — reading a number that vanished on lift-off is the
      // classic way to make a measure tool useless.
      return;
    }
    final dragId = _dragId;
    final dragShelfId = _dragShelfId;
    final propRiders = [
      for (final prop in _props)
        if (_ridingPropIds.contains(prop.id)) prop,
    ];
    final riders = [
      for (final pb in _placed)
        if (_ridingIds.contains(pb.placement.id)) pb,
    ];
    final dragPropId = _dragPropId;
    _dragId = null;
    _dragShelfId = null;
    _dragPropId = null;
    _dragGroup = const [];
    _ridingIds = const {};
    _ridingPropIds = const {};

    // A released prop settles like a book: onto the highest surface beneath it,
    // nudged clear of whatever is already there. Dropped in mid-air it goes
    // back where it came from rather than floating, because unlike a book there
    // is no "not on a shelf any more" state for it to fall into.
    if (dragPropId != null) {
      final prop = _props.firstWhere((p) => p.id == dragPropId);
      if (_moved) {
        final settled = _settle(
          draggedId: prop.id,
          x: _propDragPos.dx,
          y: _propDragPos.dy,
          w: prop.widthM,
          h: prop.heightM,
        );
        if (settled.onSurface) {
          () async {
            await repo.layout.moveProp(
              prop.id,
              x: settled.pos.dx,
              y: settled.pos.dy,
            );
          }();
        }
      }
      setState(() {});
      return;
    }

    // Finished dragging a shelf: persist the shifted endpoints and carry every
    // book that was resting on it by the same delta, then settle.
    if (dragShelfId != null) {
      final s = _shelfStart;
      final delta = _shelfDelta;
      if (_moved && s != null) {
        () async {
          final group = s.groupId;
          if (group != null) {
            await repo.layout.moveGroup(group, delta);
          } else {
            // A loose shelf dropped inside a bookcase snaps to span it, so it
            // lines up with the sides instead of stopping a few millimetres
            // short — which at this zoom is impossible to do by eye. The
            // arithmetic is pure and tested; see `dragSegment`.
            final moved = dragSegment(
              x1: s.x1,
              y1: s.y1,
              x2: s.x2,
              y2: s.y2,
              delta: delta,
              holdsBooks: ShelfKind.parse(s.kind).holdsBooks,
              uprights: _uprights(exceptId: s.id),
            );
            await repo.layout.updateShelf(
              s.id,
              x1: moved.x1,
              y1: moved.y1,
              x2: moved.x2,
              y2: moved.y2,
            );
          }

          for (final pb in riders) {
            await repo.layout.updatePlacement(
              pb.placement.id,
              x: pb.placement.x + delta.dx,
              y: pb.placement.y + delta.dy,
            );
          }
          // Ornaments travel with the shelf too, by the same delta.
          for (final prop in propRiders) {
            await repo.layout.moveProp(
              prop.id,
              x: prop.x + delta.dx,
              y: prop.y + delta.dy,
            );
          }
          await _applyGravity();
        }();
      }
      _shelfDeltaVN.value = Offset.zero;
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
    // Only surfaces books actually rest on (plan 5 #29): a side panel or a
    // divider is geometry, not a shelf, and landing a book on one would put it
    // in mid-air as far as anyone looking at the room is concerned.
    final shelves = [
      for (final s in _shelves)
        if (ShelfKind.parse(s.kind).holdsBooks)
          SettleSegment(x1: s.x1, y1: s.y1, x2: s.x2, y2: s.y2),
    ];
    // ...but furniture with a vertical extent is still in the way. A side panel
    // is the end of a bookcase and a divider splits a shelf into sections;
    // either way a book slid along the shelf has to stop at it rather than pass
    // through. Zero-height rows are skipped: those are the flat, pre-#29 ones
    // that never had an upright to speak of.
    final barriers = [
      for (final s in _shelves)
        if (!ShelfKind.parse(s.kind).holdsBooks && (s.y2 - s.y1).abs() > 1e-9)
          SettleBox(
            x: math.min(s.x1, s.x2),
            y: math.min(s.y1, s.y2),
            w: math.max((s.x2 - s.x1).abs(), _barrierThickness),
            h: (s.y2 - s.y1).abs(),
          ),
    ];
    // A prop standing on a shelf occupies shelf, so books nudge around it —
    // but as a *barrier*, not as a surface. Handed over as an ordinary
    // neighbour, `settle` would happily balance a paperback on a statuette's
    // head, since anything with a top is somewhere to stack.
    final propBoxes = [
      for (final prop in _props)
        if (prop.id != draggedId)
          // The *solid* part, not the drawn one. A plant's leaves overhang its
          // pot, and a book tucked under them is what a real shelf looks like;
          // colliding with the artwork left a gap that looked like a bug.
          () {
            final span = PropKind.parse(prop.kind).solidSpan(prop.x, prop.widthM);
            return SettleBox(
              x: span.x,
              y: prop.y,
              w: span.w,
              h: prop.heightM,
            );
          }(),
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
      barriers: [...barriers, ...propBoxes],
    );
    return (pos: Offset(r.x, r.y), onSurface: r.onSurface);
  }

  /// Gravity pass: after a book is removed or moved, drop any book now left
  /// unsupported onto the highest surface (shelf or book) beneath it, so stacks
  /// collapse. Vertical only — books keep their x. Reads fresh state so it's
  /// correct right after a mutation. Falls to the floor (y = 0) if nothing is
  /// below (non-destructive).
  Future<void> _applyGravity() async {
    final books = await repo.layout.watchPlacedBooks(widget.environmentId).first;
    final shelves = await repo.layout.watchShelves(widget.environmentId).first;
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
        // Same rule as `_settle`: furniture holds nothing up.
        if (!ShelfKind.parse(s.kind).holdsBooks) continue;
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
        await repo.layout.updatePlacement(pb.placement.id, y: surface);
      }
    }
  }

  Future<void> _removeAndSettle(BookPlacement p) async {
    await repo.layout.removePlacement(p);
    await _applyGravity();
  }

  Future<void> _moveAndSettle(String id, Offset pos) async {
    await repo.layout.updatePlacement(id, x: pos.dx, y: pos.dy);
    await _applyGravity();
  }

  // ---- actions ------------------------------------------------------------

  /// A whole bookcase in one gesture (next features #11): pick a style, adjust
  /// the numbers, and its shelves and side panels are written together.
  ///
  /// Dropped at the right-hand edge of what is already in the room, so a second
  /// bookcase stands beside the first rather than inside it.
  /// Stands a prop in the room, settled onto whatever is under the middle of
  /// the view — the same landing a book gets, so an ornament ends up *on* a
  /// shelf rather than hanging in the air.
  Future<void> _addProp() async {
    final kind = await showModalBottomSheet<PropKind>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => SafeArea(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(20, 0, 20, 8),
              child: Text('Put something on a shelf',
                  style: Theme.of(sheetContext).textTheme.titleMedium),
            ),
            for (final k in PropKind.values)
              ListTile(
                leading: SizedBox(
                  width: 34,
                  height: 34,
                  child: PropArt(
                    kind: k,
                    color: Theme.of(sheetContext).colorScheme.tertiary,
                  ),
                ),
                title: Text(k.label),
                subtitle: Text(
                  '${formatDistance(k.width)} × ${formatDistance(k.height)}',
                ),
                onTap: () => Navigator.pop(sheetContext, k),
              ),
          ],
        ),
      ),
    );
    if (kind == null || _origin == null || !mounted) return;

    final size = context.size ?? const Size(400, 600);
    final centre = _screenToWorld(Offset(size.width / 2, size.height / 2));
    final settled = _settle(
      draggedId: '',
      x: centre.dx - kind.width / 2,
      y: centre.dy,
      w: kind.width,
      h: kind.height,
    );
    await repo.layout.addProp(
      widget.environmentId,
      kind: kind,
      x: settled.pos.dx,
      y: settled.pos.dy,
    );
    if (mounted) _say('Added a ${kind.label.toLowerCase()}. Drag it to move it.');
  }

  Future<void> _addBookcase() async {
    final spec = await showDialog<BookcaseSpec>(
      context: context,
      builder: (_) => const BookcaseDialog(),
    );
    if (spec == null || !mounted) return;

    final rightEdge = _shelves.isEmpty
        ? 0.0
        : _shelves
                .map((s) => math.max(s.x1, s.x2))
                .reduce(math.max) +
            0.2;
    // Stood on the skirting rather than on the floor line: at y = 0 the bottom
    // shelf lands inside the skirting band and reads as a stripe across the
    // base of the case. Real bookcases have a plinth for the same reason.
    await repo.layout.addBookcase(
      widget.environmentId,
      bookcaseSegments(
        style: spec.style,
        x: rightEdge,
        y: skirtingMetres,
        width: spec.width,
        height: spec.height,
        shelves: spec.shelves,
        label: spec.label,
      ),
    );
    if (!mounted) return;
    _say('Added a bookcase. Drag any part to move it all.');
  }

  /// Re-shapes a bookcase in place: same corner, new numbers.
  ///
  /// The segments are rewritten rather than nudged, because changing the shelf
  /// count changes how many there are — there is nothing to nudge. The books
  /// stay where they are and the gravity pass catches whatever is left
  /// unsupported, which is the same thing that happens when a shelf is moved by
  /// hand.
  Future<void> _editBookcase(String groupId) async {
    final parts = _shelves.where((s) => s.groupId == groupId).toList();
    if (parts.isEmpty) return;
    final left = parts.map((s) => math.min(s.x1, s.x2)).reduce(math.min);
    final right = parts.map((s) => math.max(s.x1, s.x2)).reduce(math.max);
    final bottom = parts.map((s) => math.min(s.y1, s.y2)).reduce(math.min);
    final top = parts.map((s) => math.max(s.y1, s.y2)).reduce(math.max);
    final shelfCount =
        parts.where((s) => ShelfKind.parse(s.kind).holdsBooks).length;
    final label = parts.map((s) => s.label).firstWhere(
          (l) => l != null && l.isNotEmpty,
          orElse: () => null,
        );

    final spec = await showDialog<BookcaseSpec>(
      context: context,
      builder: (_) => BookcaseDialog(
        initialWidth: right - left,
        initialHeight: top - bottom,
        initialShelves: shelfCount,
        initialLabel: label,
      ),
    );
    if (spec == null || !mounted) return;

    await repo.layout.deleteGroup(groupId);
    await repo.layout.addBookcase(
      widget.environmentId,
      bookcaseSegments(
        style: spec.style,
        x: left,
        y: bottom,
        width: spec.width,
        height: spec.height,
        shelves: spec.shelves,
        label: spec.label,
      ),
      // The same id, so anything still pointing at this bookcase keeps doing so.
      groupId: groupId,
    );
    await _applyGravity();
    if (mounted) _say('Bookcase updated.');
  }

  Future<void> _finishGrouping() async {
    final picked = _grouping;
    if (picked == null || picked.length < 2) return;
    await repo.layout.groupShelves(widget.environmentId, picked.toList());
    if (!mounted) return;
    setState(() => _grouping = null);
    _say('Grouped ${picked.length} parts into one bookcase.');
  }

  Future<void> _deleteBookcase(String groupId) async {
    final parts = _shelves.where((s) => s.groupId == groupId).length;
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete the whole bookcase?'),
        content: Text(
          'Removes all $parts shelves and panels. Books standing on them drop '
          'to whatever is beneath — nothing leaves your library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await repo.layout.deleteGroup(groupId);
    await _applyGravity();
  }

  Future<void> _addShelf() async {
    // Default a new shelf a bit above whatever's already there.
    final topY = _shelves.isEmpty
        ? 0.3
        : _shelves.map((s) => math.max(s.y1, s.y2)).reduce(math.max) + 0.35;
    final result = await showDialog<ShelfSpec>(
      context: context,
      builder: (_) => ShelfDialog(defaultY: double.parse(topY.toStringAsFixed(2))),
    );
    if (result == null) return;
    await repo.layout.addShelf(
      widget.environmentId,
      x1: result.left,
      y1: result.y,
      x2: result.right,
      y2: result.y2,
      label: result.label,
      kind: result.kind,
    );
  }

  /// Bulk add: tick any number of books, choose a shelf, and they are packed
  /// onto it left to right.
  ///
  /// [shelf] pre-selects the target — how *Add books to this shelf…* arrives
  /// here. Otherwise the shelf is chosen after picking, from a list showing how
  /// much room each one has left, because "will they fit" is the question you
  /// actually have at that moment.
  Future<void> _addBooks({PhysicalShelf? shelf}) async {
    final placedIds = {for (final pb in _placed) pb.book.id};
    final books = await showModalBottomSheet<List<Book>>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => BookPicker(
        repository: repo,
        alreadyPlacedIds: placedIds,
        title: shelf == null
            ? 'Add books to ${widget.environmentName}'
            : 'Add books to ${shelfName(shelf, _shelves)}',
      ),
    );
    if (books == null || books.isEmpty || !mounted) return;

    final target = shelf ?? await _askWhichShelf(books.length);
    if (target == null || !mounted) return;
    await _placeOnShelf(target, books);
  }

  /// The shelves books can rest on, with how full each one is — furniture is
  /// left out, since nothing can be packed onto it.
  List<PhysicalShelf> get _bookShelves => [
        for (final s in _shelves)
          if (ShelfKind.parse(s.kind).holdsBooks) s,
      ];

  Future<PhysicalShelf?> _askWhichShelf(int count) async {
    final shelves = _bookShelves;
    if (shelves.isEmpty) {
      _say('This room has no shelves yet — add one first.');
      return null;
    }
    if (shelves.length == 1) return shelves.single;
    // Highest first: that is the order they appear on screen, and matching the
    // picture beats sorting by anything cleverer.
    final ordered = [...shelves]..sort(
        (a, b) => math.max(b.y1, b.y2).compareTo(math.max(a.y1, a.y2)),
      );
    if (!mounted) return null;
    return showDialog<PhysicalShelf>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: Text('Put $count ${count == 1 ? 'book' : 'books'} on…'),
        children: [
          for (final s in ordered)
            SimpleDialogOption(
              onPressed: () => Navigator.of(dialogContext).pop(s),
              child: ListTile(
                contentPadding: EdgeInsets.zero,
                title: Text(shelfName(s, _shelves)),
                subtitle: Text(fillOf(shelf: s, placed: _placed).describe()),
              ),
            ),
        ],
      ),
    );
  }

  /// Packs [books] into the free space on [shelf] and writes them in one go.
  Future<void> _placeOnShelf(PhysicalShelf shelf, List<Book> books) async {
    final surface = math.max(shelf.y1, shelf.y2);
    final left = math.min(shelf.x1, shelf.x2);
    final right = math.max(shelf.x1, shelf.x2);

    // What is in the way: books already resting here, plus any upright that
    // crosses this shelf — a divider sections the shelf, so a batch packs up to
    // it and continues on the far side rather than through it.
    final occupied = <({double start, double end})>[
      for (final pb in _placed)
        if ((pb.placement.y - surface).abs() <= 0.02)
          (start: pb.placement.x, end: pb.placement.x + _footOf(pb).w),
      for (final s in _shelves)
        if (!ShelfKind.parse(s.kind).holdsBooks &&
            math.min(s.y1, s.y2) <= surface + 0.02 &&
            math.max(s.y1, s.y2) > surface + 0.02)
          (
            start: math.min(s.x1, s.x2),
            end: math.min(s.x1, s.x2) +
                math.max((s.x2 - s.x1).abs(), _barrierThickness),
          ),
    ];

    final result = packOntoShelf(
      shelfLeft: left,
      shelfRight: right,
      widths: [for (final b in books) _foot(b, 0, null, null, null).w],
      occupied: occupied,
    );

    final placed = await repo.layout.placeBooks(
      widget.environmentId,
      [
        for (final p in result.placed)
          (bookId: books[p.index].id, x: p.x, y: surface),
      ],
    );
    if (!mounted) return;

    final where = shelfName(shelf, _shelves);
    if (result.unplaced.isEmpty) {
      _say('Added $placed ${placed == 1 ? 'book' : 'books'} to $where.');
    } else if (placed == 0) {
      _say('No room on $where — nothing was added.');
    } else {
      _say('Added $placed to $where; ${result.unplaced.length} did not fit.');
    }
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
    await repo.layout.updatePlacement(
      pb.placement.id,
      rotation: newRot,
      x: settled.pos.dx,
      y: settled.pos.dy,
    );
    await _applyGravity();
  }

  Future<void> _resizeSelected(PlacedBook pb) async {
    final format = BookFormat.byKey(pb.placement.format);
    final result = await showDialog<SizeSpec>(
      context: context,
      builder: (_) => SizeDialog(
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
    await repo.layout.updatePlacement(
      pb.placement.id,
      format: Value(result.formatKey),
      widthOverride: (t - defT).abs() < 0.0005 ? const Value(null) : Value(t),
      heightOverride: (h - defH).abs() < 0.0005 ? const Value(null) : Value(h),
    );
    await _applyGravity();
  }

  Future<void> _resetSize(PlacedBook pb) async {
    await repo.layout.updatePlacement(
      pb.placement.id,
      format: const Value(null),
      widthOverride: const Value(null),
      heightOverride: const Value(null),
    );
    await _applyGravity();
  }

  Future<void> _removeSelected(PlacedBook pb) async {
    await repo.layout.removePlacement(pb.placement);
    setState(() => _selectedId = null);
    await _applyGravity();
  }

  /// Open the book's detail page (from which it can be read), so the physical
  /// view isn't only for organising.
  void _openBook(PlacedBook pb) {
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) => BookDetailPage(
          book: pb.book,
          repository: repo,
          settings: widget.settings,
        ),
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
    for (final prop in _props.reversed) {
      if (_propRect(prop).contains(local)) {
        await _propMenu(prop, global);
        return;
      }
    }
    for (final s in _shelves.reversed) {
      if (_shelfHitRect(s).contains(local)) {
        final picking = _grouping;
        if (picking != null) {
          setState(() {
            if (!picking.remove(s.id)) picking.add(s.id);
          });
          return;
        }
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

  Future<void> _propMenu(RoomProp prop, Offset global) async {
    final kind = PropKind.parse(prop.kind);
    final choice = await showMenu<String>(
      context: context,
      position: _menuPosition(global),
      items: [
        PopupMenuItem(
          value: 'remove',
          child: Text('Remove the ${kind.label.toLowerCase()}'),
        ),
      ],
    );
    if (choice != 'remove') return;
    await repo.layout.deleteProp(prop.id);
    // Books that were pushed aside by it can spread back out.
    await _applyGravity();
  }

  Future<void> _shelfMenu(PhysicalShelf s, Offset global) async {
    final choice = await showMenu<String>(
      context: context,
      position: _menuPosition(global),
      items: [
        if (ShelfKind.parse(s.kind).holdsBooks)
          const PopupMenuItem(
            value: 'fill',
            child: Text('Add books to this shelf…'),
          ),
        // First, because it is the reason most people open this menu: nothing
        // in the room can be dragged until it is unanchored.
        PopupMenuItem(
          value: 'anchor',
          child: Text(
            s.anchored
                ? (s.groupId != null ? 'Unlock this bookcase' : 'Unlock')
                : (s.groupId != null ? 'Lock this bookcase' : 'Lock'),
          ),
        ),
        const PopupMenuDivider(),
        if (s.groupId != null) ...[
          const PopupMenuItem(
            value: 'edit-case',
            child: Text('Edit this bookcase…'),
          ),
          const PopupMenuItem(value: 'ungroup', child: Text('Ungroup')),
          const PopupMenuItem(
            value: 'delete-case',
            child: Text('Delete the whole bookcase'),
          ),
          const PopupMenuDivider(),
        ] else
          const PopupMenuItem(
            value: 'group',
            child: Text('Group into a bookcase…'),
          ),
        const PopupMenuItem(value: 'edit', child: Text('Edit this segment…')),
        if (ShelfKind.parse(s.kind).holdsBooks)
          const PopupMenuItem(value: 'tidy', child: Text('Tidy this shelf…')),
        const PopupMenuItem(value: 'delete', child: Text('Delete this segment')),
      ],
    );
    if (choice == null || !mounted) return;
    switch (choice) {
      case 'fill':
        await _addBooks(shelf: s);
      case 'anchor':
        final parts = _groupOf(s);
        await repo.layout.setAnchored(
          widget.environmentId,
          [for (final part in parts) part.id],
          anchored: !s.anchored,
        );
        if (mounted) {
          _say(s.anchored
              ? 'Unlocked — drag it to move it.'
              : 'Locked in place.');
        }
      case 'edit-case':
        await _editBookcase(s.groupId!);
      case 'ungroup':
        await repo.layout.ungroup(s.groupId!);
        if (mounted) _say('Ungrouped — the shelves stay where they are.');
      case 'delete-case':
        await _deleteBookcase(s.groupId!);
      case 'group':
        setState(() => _grouping = {s.id});
        _say('Tap the other shelves and panels, then press Done.');
      case 'delete':
        await repo.layout.deleteShelf(s.id);
        await _applyGravity();
      case 'tidy':
        final sort = await _askTidySort();
        if (sort != null && mounted) await _tidyShelf(s, sort);
      default:
        await _editShelf(s);
    }
  }

  Future<void> _editShelf(PhysicalShelf s) async {
    final result = await showDialog<ShelfSpec>(
      context: context,
      builder: (_) => ShelfDialog(
        title: 'Edit shelf',
        defaultY: math.min(s.y1, s.y2),
        initialLeft: math.min(s.x1, s.x2),
        initialRight: math.max(s.x1, s.x2),
        initialLabel: s.label,
        initialKind: ShelfKind.parse(s.kind),
        initialTopY: math.max(s.y1, s.y2),
        // "42 cm of 90 cm used" — the number you actually want while deciding
        // whether to move this shelf (plan 5 #29).
        fill: fillOf(shelf: s, placed: _placed),
      ),
    );
    if (result == null) return;

    // Books resting on the shelf should travel with it, so an edit doesn't
    // strand them in mid-air. Capture them (and the move delta) before the edit.
    final dx = result.left - math.min(s.x1, s.x2);
    final dy = result.y - math.max(s.y1, s.y2);
    final riders = _ridersOf(s);

    await repo.layout.updateShelf(
      s.id,
      x1: result.left,
      y1: result.y,
      x2: result.right,
      y2: result.y2,
      label: Value(result.label),
      kind: result.kind,
    );
    if (dx.abs() > 1e-9 || dy.abs() > 1e-9) {
      for (final pb in riders) {
        await repo.layout.updatePlacement(
          pb.placement.id,
          x: pb.placement.x + dx,
          y: pb.placement.y + dy,
        );
      }
    }
    await _applyGravity();
  }

  // ---- find, tidy, labels, snapshot (plan 5 #28) ---------------------------

  /// Centres the camera on [placement] and pulses it.
  ///
  /// Zooms *in* to at least 500 px/m but never zooms out: arriving from "find
  /// my copy" at a wall-sized view would technically show the book and tell you
  /// nothing. The camera is placed so the book sits slightly above centre,
  /// which is where the eye looks first.
  void _focusOn(BookPlacement placement, {double? width, double? height}) {
    final size = context.size ?? const Size(400, 600);
    final scale = math.max(_scale, 500.0).clamp(_minScale, _maxScale);
    final centreWorld = Offset(
      placement.x + (width ?? 0.03) / 2,
      placement.y + (height ?? PhysicalMetrics.defaultHeight) / 2,
    );
    setState(() {
      _scale = scale;
      _origin = Offset(
        size.width / 2 - centreWorld.dx * scale,
        size.height * 0.55 + centreWorld.dy * scale,
      );
      _pulseId = placement.id;
    });
    _pulse
      ..reset()
      ..repeat(reverse: true, count: 6);
  }

  /// Runs the pending *Find my copy* once the canvas has a size and the
  /// placement has actually arrived from the stream.
  void _maybeFocusInitial() {
    if (_didFocus || widget.focusPlacementId == null || _origin == null) return;
    for (final pb in _placed) {
      if (pb.placement.id == widget.focusPlacementId) {
        _didFocus = true;
        final f = _footOf(pb);
        // After this frame: we are inside a build, and focusing calls setState.
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) _focusOn(pb.placement, width: f.w, height: f.h);
        });
        return;
      }
    }
  }

  bool _matchesQuery(PlacedBook pb) => bookMatches(
        pb.book,
        _query,
        authors: _authorsByBook[pb.book.id] ?? const [],
      );

  /// Picks a photo of the wall and stores it beside the room's other blobs.
  ///
  /// Copied into the data dir rather than referenced: a photo picked from the
  /// camera roll can be deleted tomorrow, and the same reasoning as #51's
  /// condition photos applies — a backdrop that evaporates is worse than none.
  Future<void> _chooseBackdrop() async {
    final picked = await addRoomBackdrop(context, repo, widget.environmentId);
    if (picked == null || !mounted) return;
    await _loadEnvironment();
    if (mounted) {
      _say('Photo added. Calibrate it so the room is drawn to scale.');
    }
  }

  /// The two-point calibration: mark a length you know, say what it really is.
  ///
  /// Asked in pixels-on-the-photo terms rather than by dragging on the canvas,
  /// because the canvas is already carrying pan, zoom, drag-a-book and
  /// drag-a-shelf gestures — a fifth would need a mode nobody would find.
  Future<void> _calibrateBackdrop() async {
    final image = _backdrop;
    if (image == null) return;
    final result = await showDialog<BackdropCalibration>(
      context: context,
      builder: (_) => BackdropCalibrationDialog(
        imageWidth: image.width,
        imageHeight: image.height,
      ),
    );
    final metresPerPixel = result?.metresPerPixel;
    if (metresPerPixel == null) {
      if (result != null && mounted) {
        // Rejected rather than clamped: a wrong scale looks authoritative.
        _say("That doesn't give a usable scale — check both numbers.");
      }
      return;
    }
    await repo.layout.updateBackdrop(
      widget.environmentId,
      scale: Value(metresPerPixel),
    );
    await _loadEnvironment();
    if (mounted) {
      _say('Calibrated: the photo is now drawn to scale.');
    }
  }

  /// The room's own look (next features #10): a wall colour, a floor colour,
  /// and whether the floor line, skirting and shelf shadows are drawn.
  ///
  /// A short list of picked colours rather than a colour wheel — the aim is a
  /// room that looks like a room, and a free choice mostly produces one that
  /// fights the spines. "Use the theme" stays available and is the default.
  Future<void> _showRoomDecor() async {
    const walls = <(String, int?)>[
      ('Theme', null),
      ('Warm white', 0xFFF2EDE4),
      ('Clay', 0xFFD9C3B0),
      ('Sage', 0xFFBFC9BA),
      ('Ink', 0xFF2A2E33),
    ];
    const floors = <(String, int?)>[
      ('Theme', null),
      ('Oak', 0xFFC9A87C),
      ('Walnut', 0xFF7A5A42),
      ('Slate', 0xFF6E7278),
      ('Rug red', 0xFF8C4A3F),
    ];

    await showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      builder: (sheetContext) => StatefulBuilder(
        builder: (sheetContext, setSheet) {
          Widget swatches(
            String title,
            List<(String, int?)> options,
            int? current,
            Future<void> Function(int?) pick,
          ) =>
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: Theme.of(sheetContext).textTheme.titleSmall),
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 10,
                      runSpacing: 10,
                      children: [
                        for (final (name, value) in options)
                          InkWell(
                            onTap: () async {
                              await pick(value);
                              setSheet(() {});
                            },
                            child: Column(
                              children: [
                                Container(
                                  width: 44,
                                  height: 44,
                                  decoration: BoxDecoration(
                                    color: value == null
                                        ? Theme.of(sheetContext)
                                            .colorScheme
                                            .surfaceContainerHighest
                                        : Color(value),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                      color: current == value
                                          ? Theme.of(sheetContext)
                                              .colorScheme
                                              .primary
                                          : Theme.of(sheetContext)
                                              .colorScheme
                                              .outlineVariant,
                                      width: current == value ? 3 : 1,
                                    ),
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(name,
                                    style: Theme.of(sheetContext)
                                        .textTheme
                                        .labelSmall),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ],
                ),
              );

          return SafeArea(
            child: ListView(
              shrinkWrap: true,
              children: [
                swatches('Wall', walls, _environment?.wallColor, (v) async {
                  await repo.layout
                      .updateRoomLook(widget.environmentId, wallColor: Value(v));
                  await _loadEnvironment();
                }),
                const SizedBox(height: 12),
                swatches('Floor', floors, _environment?.floorColor, (v) async {
                  await repo.layout.updateRoomLook(widget.environmentId,
                      floorColor: Value(v));
                  await _loadEnvironment();
                }),
                SwitchListTile(
                  title: const Text('Floor line, skirting and shadows'),
                  subtitle: const Text(
                    'What stops an empty room looking like graph paper',
                  ),
                  value: _environment?.roomSurfaces ?? true,
                  onChanged: (v) async {
                    await repo.layout
                        .updateRoomLook(widget.environmentId, surfaces: v);
                    await _loadEnvironment();
                    setSheet(() {});
                  },
                ),
              ],
            ),
          );
        },
      ),
    );
  }

  Future<void> _showBackdropSettings() async {
    await showModalBottomSheet<void>(
      context: context,
      builder: (_) => BackdropSettingsSheet(
        repository: repo,
        environmentId: widget.environmentId,
        opacity: _environment?.backdropOpacity ?? 0.5,
        onChanged: _loadEnvironment,
      ),
    );
    await _loadEnvironment();
  }

  /// Re-packs the books resting on [s] in [sort] order, flush from its left end.
  Future<void> _tidyShelf(PhysicalShelf s, TidySort sort) async {
    final riders = _ridersOf(s);
    if (riders.isEmpty) {
      _say('Nothing is resting on that shelf.');
      return;
    }
    // Series *names* live in their own table; the book row only holds the id.
    final seriesById = {
      for (final row in await repo.db.select(repo.db.series).get())
        row.id: row.name,
    };
    if (!mounted) return;

    final books = [
      for (final pb in riders)
        TidyBook(
          placementId: pb.placement.id,
          width: _footOf(pb).w,
          title: pb.book.title,
          author: (_authorsByBook[pb.book.id] ?? const []).firstOrNull,
          seriesName: seriesById[pb.book.seriesId],
          seriesIndex: pb.book.seriesIndex,
        ),
    ];
    final moves = tidyPositions(
      tidyOrder(books, sort),
      shelfLeft: math.min(s.x1, s.x2),
      shelfRight: math.max(s.x1, s.x2),
      currentX: {for (final pb in riders) pb.placement.id: pb.placement.x},
    );
    if (moves.isEmpty) {
      _say('That shelf is already tidy.');
      return;
    }
    for (final move in moves) {
      await repo.layout.updatePlacement(move.placementId, x: move.x);
    }
    // Books that were stacked on top of the ones just moved are now floating.
    await _applyGravity();
    if (mounted) _say('Tidied ${moves.length} of ${riders.length} books.');
  }

  Future<TidySort?> _askTidySort() => showDialog<TidySort>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Tidy this shelf'),
          children: [
            for (final sort in TidySort.values)
              SimpleDialogOption(
                onPressed: () => Navigator.of(dialogContext).pop(sort),
                child: Text(sort.label),
              ),
          ],
        ),
      );

  /// Generates the printable label sheet and hands it to the system.
  Future<void> _printLabels() async {
    if (_shelves.isEmpty) {
      _say('This room has no shelves to label yet.');
      return;
    }
    final labels = [
      for (final s in _shelves)
        ShelfLabel(
          shelfId: s.id,
          environmentName: widget.environmentName,
          shelfName: s.label,
          bookCount: _ridersOf(s).length,
        ),
    ]..sort((a, b) => a.displayName.compareTo(b.displayName));

    final file = File(p.join(
      (await getTemporaryDirectory()).path,
      'vellum-labels-${DateTime.now().millisecondsSinceEpoch}.html',
    ));
    await file.writeAsString(buildLabelSheetHtml(
      labels: labels,
      title: '${widget.environmentName} — shelf labels',
    ));
    final opened = await openOrShare(file, mimeType: 'text/html');
    if (!mounted) return;
    _say(opened
        ? 'Labels opened — print them with Ctrl+P.'
        : 'Saved the labels to ${file.path}');
  }

  /// Saves the room as a PNG.
  ///
  /// Captures exactly what is on screen, deliberately: framing the picture is
  /// what the pan and zoom you already have are for, and re-deriving a "whole
  /// room" bounding box would produce a different image from the one you set up.
  Future<void> _saveSnapshot() async {
    final boundary =
        _canvasKey.currentContext?.findRenderObject() as RenderRepaintBoundary?;
    if (boundary == null) {
      _say('Nothing to capture yet.');
      return;
    }
    // 2× so the picture survives being looked at on a phone or printed small.
    final image = await boundary.toImage(pixelRatio: 2);
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();
    if (bytes == null) {
      if (mounted) _say("Couldn't render the picture.");
      return;
    }
    final safeName = widget.environmentName
        .replaceAll(RegExp(r'[^A-Za-z0-9]+'), '-')
        .toLowerCase();
    final file = File(p.join(
      (await getTemporaryDirectory()).path,
      'vellum-$safeName-${DateTime.now().millisecondsSinceEpoch}.png',
    ));
    await file.writeAsBytes(bytes.buffer.asUint8List());
    final opened = await openOrShare(file, mimeType: 'image/png');
    if (!mounted) return;
    _say(opened ? 'Picture saved and opened.' : 'Saved to ${file.path}');
  }

  void _say(String message) {
    ScaffoldMessenger.of(context)
        .showSnackBar(SnackBar(content: Text(message)));
  }

  // ---- build --------------------------------------------------------------

  /// Walks this room against its map (plan 5 #30).
  Future<void> _startStocktake() async {
    await Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => StocktakePage(
        repository: repo,
        environmentId: widget.environmentId,
        scopeLabel: widget.environmentName,
      ),
    ));
  }

  /// The room as a navigable list (plan 5 #42).
  ///
  /// The canvas carries the same information as one spoken summary, but a
  /// summary can only be heard start to finish. This sheet is the version you
  /// can move through item by item — and it turns out to be the fastest way to
  /// answer "what's on the middle shelf?" with a mouse, too, which is why it
  /// sits in the toolbar rather than behind an accessibility setting.
  void _showRoomContents() {
    final summaries = summarizeRoom(shelves: _shelves, placed: _placed);
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: summaries.isEmpty
            ? const Padding(
                padding: EdgeInsets.all(24),
                child: Text('This room is empty. Add a shelf, then drop in '
                    'books.'),
              )
            : ListView(
                shrinkWrap: true,
                children: [
                  for (final shelf in summaries)
                    ListTile(
                      leading: const Icon(Icons.shelves),
                      title: Text(shelf.name),
                      subtitle: Text(
                        shelf.titles.isEmpty
                            ? 'Empty'
                            : shelf.titles.join(', '),
                      ),
                      // One node per shelf reading exactly like the canvas
                      // summary, so both routes say the same thing.
                      onTap: () => Navigator.pop(sheetContext),
                    ),
                ],
              ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: _searchOpen
            ? TextField(
                controller: _search,
                autofocus: true,
                decoration: const InputDecoration(
                  hintText: 'Find a book in this room',
                  border: InputBorder.none,
                ),
                onChanged: (value) => setState(() => _query = value),
              )
            : Text(widget.environmentName),
        actions: [
          IconButton(
            tooltip: _searchOpen ? 'Close search' : 'Search this room',
            onPressed: () => setState(() {
              _searchOpen = !_searchOpen;
              if (!_searchOpen) {
                _search.clear();
                _query = '';
              }
            }),
            icon: Icon(_searchOpen ? Icons.close : Icons.search),
          ),
          IconButton(
            tooltip: 'Add bookcase',
            onPressed: _addBookcase,
            icon: const Icon(Icons.shelves),
          ),
          IconButton(
            tooltip: 'Add one shelf',
            onPressed: _addShelf,
            icon: const Icon(Icons.horizontal_rule),
          ),
          IconButton(
            tooltip: 'Put something on a shelf',
            onPressed: _addProp,
            icon: const Icon(Icons.emoji_objects_outlined),
          ),
          IconButton(
            tooltip: 'Room contents',
            onPressed: _showRoomContents,
            icon: const Icon(Icons.format_list_bulleted),
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
          PopupMenuButton<String>(
            tooltip: 'More',
            onSelected: (choice) async {
              switch (choice) {
                case 'labels':
                  await _printLabels();
                case 'snapshot':
                  await _saveSnapshot();
                case 'stocktake':
                  await _startStocktake();
                case 'backdrop':
                  await _chooseBackdrop();
                case 'calibrate':
                  await _calibrateBackdrop();
                case 'backdrop-opacity':
                  await _showBackdropSettings();
                case 'measure':
                  setState(() {
                    _measuring = !_measuring;
                    _measureFrom = null;
                    _measureTo = null;
                  });
                case 'decor':
                  await _showRoomDecor();
                case 'help':
                  _showHelp();
              }
            },
            itemBuilder: (context) => [
              PopupMenuItem(
                value: 'measure',
                child: Text(_measuring ? 'Stop measuring' : 'Measure…'),
              ),
              const PopupMenuItem(
                value: 'decor',
                child: Text('Wall and floor…'),
              ),
              PopupMenuItem(
                value: 'backdrop',
                child: Text(_environment?.backdropPath == null
                    ? 'Add a room photo…'
                    : 'Change the room photo…'),
              ),
              if (_environment?.backdropPath != null) ...[
                const PopupMenuItem(
                  value: 'calibrate',
                  child: Text('Calibrate the photo…'),
                ),
                const PopupMenuItem(
                  value: 'backdrop-opacity',
                  child: Text('Photo strength…'),
                ),
              ],
              const PopupMenuItem(
                value: 'labels',
                child: Text('Print shelf labels…'),
              ),
              const PopupMenuItem(
                value: 'snapshot',
                child: Text('Save a picture of this room'),
              ),
              const PopupMenuItem(
                value: 'stocktake',
                child: Text('Stocktake this room…'),
              ),
              const PopupMenuItem(value: 'help', child: Text('Help')),
            ],
          ),
        ],
      ),
      // Listen to settings so a spine-artwork preference change repaints the
      // books (they use widget.settings.spineArt in _bookVisual).
      body: ListenableBuilder(
        listenable: widget.settings,
        builder: (context, _) => StreamBuilder<List<PhysicalShelf>>(
          stream: repo.layout.watchShelves(widget.environmentId),
          builder: (context, shelfSnap) {
            _shelves = shelfSnap.data ?? const [];
            return StreamBuilder<List<PlacedBook>>(
              stream: repo.layout.watchPlacedBooks(widget.environmentId),
              builder: (context, bookSnap) {
                _placed = bookSnap.data ?? const [];
                return StreamBuilder<List<RoomProp>>(
                  stream: repo.layout.watchProps(widget.environmentId),
                  builder: (context, propSnap) {
                _props = propSnap.data ?? const [];
                return LayoutBuilder(
                  builder: (context, constraints) {
                    _origin ??= Offset(40, constraints.maxHeight - 90);
                    _maybeFocusInitial();
                    // The boundary is what `_saveSnapshot` captures, so it wraps
                    // the room and nothing else — no app bar, no snackbar.
                    //
                    // The Semantics wrapper is the canvas's accessible
                    // alternative (plan 5 #42): a drag-and-drop spatial view
                    // has no useful traversal order, so it reports as a single
                    // node describing the room shelf by shelf, and
                    // ExcludeSemantics stops the individual spines underneath
                    // from also announcing themselves out of any order.
                    return Semantics(
                      container: true,
                      label: roomSemanticLabel(
                        summarizeRoom(shelves: _shelves, placed: _placed),
                      ),
                      hint: 'Use Room contents for a navigable list',
                      child: ExcludeSemantics(
                        child: RepaintBoundary(
                          key: _canvasKey,
                          child: _buildCanvas(constraints),
                        ),
                      ),
                    );
                  },
                );
                  },
                );
              },
            );
          },
        ),
      ),
      // Hidden while a book is selected, so it doesn't overlap the toolbar.
      floatingActionButton: _selectedId != null
          ? null
          : FloatingActionButton.extended(
              onPressed: _addBooks,
              icon: const Icon(Icons.add),
              label: const Text('Add books'),
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
          '• Drag a shelf to move it — the books on it ride along.\n'
          '• A shelf can be furniture instead: a side panel, divider or label '
          'draws but holds nothing.\n'
          '• “Measure” turns the canvas into a ruler; “Add a room photo” lets '
          'you trace your actual wall once you calibrate it.\n'
          '• Right-click a shelf to tidy it by author, title or series.\n'
          '• The search icon dims everything that doesn’t match.\n'
          '• “Print shelf labels” makes a sheet you can cut up and stick on; '
          'scanning one opens this room.',
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
                painter: RoomPainter(
                  shelves: _shelves,
                  origin: _origin!,
                  scale: _scale,
                  line: theme.colorScheme.outlineVariant,
                  plank: theme.colorScheme.primary,
                  label: theme.colorScheme.onSurfaceVariant,
                  draggingIds: {for (final part in _dragGroup) part.id},
                  shelfDelta: _shelfDeltaVN,
                  backdrop: _backdrop,
                  backdropOpacity: _environment?.backdropOpacity ?? 0.5,
                  backdropScale: _environment?.backdropScale,
                  backdropOffset: Offset(
                    _environment?.backdropOffsetX ?? 0,
                    _environment?.backdropOffsetY ?? 0,
                  ),
                  measureFrom: _measureFrom,
                  measureTo: _measureTo,
                  measureColor: theme.colorScheme.tertiary,
                  // The room's own look (next features #10). Null falls back to
                  // the theme, which is what a room made before this had.
                  wallColor: _environment?.wallColor == null
                      ? null
                      : Color(_environment!.wallColor!),
                  floorColor: _environment?.floorColor == null
                      ? null
                      : Color(_environment!.floorColor!),
                  surfaces: _environment?.roomSurfaces ?? true,
                  // Ticks are only for picking the parts of a new group. A
                  // *selected* bookcase gets one box round the whole thing.
                  highlightIds: _grouping ?? const {},
                  outlines: unlockedBoxes(_shelves),
                ),
                size: Size.infinite,
              ),
            ),
          ),
        ),
        // Props sit behind the books: an ornament pushed to the back of a
        // shelf is the ordinary case, and a statuette in front of a spine you
        // are trying to read is not.
        for (final prop in _props)
          _ridingPropIds.contains(prop.id)
              ? _ridingPropWidget(prop)
              : _propWidget(prop),
        // Books (each in its own RepaintBoundary; the one being dragged is
        // drawn as a live overlay instead of in this static list).
        for (final pb in _placed)
          if (pb.placement.id != _dragId)
            (_dragShelfId != null && _ridingIds.contains(pb.placement.id))
                ? _ridingBookWidget(pb)
                : _bookWidget(pb),
        if (_dragId != null) _draggedBookOverlay(),
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
          child: ScaleBar(scale: _scale),
        ),
        if (_grouping != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: Card(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(12, 6, 6, 6),
                child: Row(
                  children: [
                    Expanded(
                      child: Text(
                        '${_grouping!.length} selected — tap the shelves and '
                        'panels that make up this bookcase',
                        style: theme.textTheme.bodySmall,
                      ),
                    ),
                    TextButton(
                      onPressed: () => setState(() => _grouping = null),
                      child: const Text('Cancel'),
                    ),
                    FilledButton(
                      onPressed: _grouping!.length < 2 ? null : _finishGrouping,
                      child: const Text('Group'),
                    ),
                  ],
                ),
              ),
            ),
          ),
        // Selected-book toolbar.
        if (selected != null)
          Positioned(
            left: 12,
            right: 12,
            bottom: 12,
            child: SelectionBar(
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

  /// A book resting at its stored placement. In its own RepaintBoundary so a
  /// neighbour being dragged doesn't force it to re-raster.
  Widget _bookWidget(PlacedBook pb) {
    final f = _footOf(pb);
    final topLeft = _worldToScreen(Offset(pb.placement.x, pb.placement.y + f.h));
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: f.w * _scale,
      height: f.h * _scale,
      child: RepaintBoundary(child: _bookVisual(pb, dragging: false)),
    );
  }

  /// A book riding a shelf that's being dragged: positioned live from
  /// [_shelfDeltaVN] so it follows the plank frame-for-frame, mirroring the
  /// dragged-book overlay. On release its new position is persisted.
  Widget _ridingBookWidget(PlacedBook pb) {
    final f = _footOf(pb);
    final w = f.w * _scale;
    final h = f.h * _scale;
    return Positioned.fill(
      child: ValueListenableBuilder<Offset>(
        valueListenable: _shelfDeltaVN,
        child: RepaintBoundary(child: _bookVisual(pb, dragging: false)),
        builder: (context, delta, child) {
          final topLeft = _worldToScreen(
            Offset(pb.placement.x + delta.dx, pb.placement.y + delta.dy + f.h),
          );
          return Stack(
            children: [
              Positioned(
                left: topLeft.dx,
                top: topLeft.dy,
                width: w,
                height: h,
                child: child!,
              ),
            ],
          );
        },
      ),
    );
  }

  /// The book currently under the finger, positioned live from [_dragPosVN] so
  /// dragging repaints only this overlay — the rest of the canvas is untouched.
  Widget _draggedBookOverlay() {
    PlacedBook? dragged;
    for (final pb in _placed) {
      if (pb.placement.id == _dragId) {
        dragged = pb;
        break;
      }
    }
    if (dragged == null) return const SizedBox.shrink();
    final pb = dragged;
    final f = _footOf(pb);
    final w = f.w * _scale;
    final h = f.h * _scale;
    return Positioned.fill(
      child: ValueListenableBuilder<Offset>(
        valueListenable: _dragPosVN,
        // `child` (the spine artwork) is built once and reused every frame; only
        // the surrounding Positioned is recomputed from the drag position.
        child: _bookVisual(pb, dragging: true),
        builder: (context, dragPos, child) {
          final topLeft = _worldToScreen(Offset(dragPos.dx, dragPos.dy + f.h));
          return Stack(
            children: [
              Positioned(
                left: topLeft.dx,
                top: topLeft.dy,
                width: w,
                height: h,
                child: child!,
              ),
            ],
          );
        },
      ),
    );
  }

  /// One prop, positioned and drawn. Dragging moves it; a long-press or a
  /// right-click offers to take it away.
  Widget _propWidget(RoomProp prop) {
    final kind = PropKind.parse(prop.kind);
    final dragging = _dragPropId == prop.id;
    final at = dragging ? _propDragPos : Offset(prop.x, prop.y);
    final topLeft = _worldToScreen(Offset(at.dx, at.dy + prop.heightM));
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: prop.widthM * _scale,
      height: prop.heightM * _scale,
      child: IgnorePointer(
        child: Opacity(
          opacity: dragging ? 0.75 : 1,
          child: PropArt(
            kind: kind,
            // The room's own colour rather than one of its own, so a shelf of
            // ornaments reads as one scene instead of a collection of stickers.
            color: Theme.of(context).colorScheme.tertiary,
          ),
        ),
      ),
    );
  }

  /// A prop standing on the shelf being dragged: follows [_shelfDeltaVN] live,
  /// so it moves *with* the plank rather than catching up on release.
  Widget _ridingPropWidget(RoomProp prop) {
    final kind = PropKind.parse(prop.kind);
    return Positioned.fill(
      child: ValueListenableBuilder<Offset>(
        valueListenable: _shelfDeltaVN,
        child: PropArt(
          kind: kind,
          color: Theme.of(context).colorScheme.tertiary,
        ),
        builder: (context, delta, child) {
          final topLeft = _worldToScreen(
            Offset(prop.x + delta.dx, prop.y + delta.dy + prop.heightM),
          );
          return Stack(
            children: [
              Positioned(
                left: topLeft.dx,
                top: topLeft.dy,
                width: prop.widthM * _scale,
                height: prop.heightM * _scale,
                child: IgnorePointer(child: child!),
              ),
            ],
          );
        },
      ),
    );
  }

  /// The screen box a prop occupies, for hit-testing.
  Rect _propRect(RoomProp prop) {
    final topLeft = _worldToScreen(Offset(prop.x, prop.y + prop.heightM));
    return topLeft & Size(prop.widthM * _scale, prop.heightM * _scale);
  }

  /// The visual for a placed book: the same spine artwork as the digital shelf
  /// (cover slice or generated), a quarter-turn for a flat book so its title
  /// still reads left-to-right, and a selection outline. Purely visual —
  /// gestures are handled by the canvas.
  Widget _bookVisual(PlacedBook pb, {required bool dragging}) {
    final selected = _selectedId == pb.placement.id;
    final flat = pb.placement.rotation == 90;
    // Dimmed, not hidden, when a search is running and this book doesn't match:
    // the room stays a room, and the matches stand out because everything else
    // recedes.
    final dimmed = _query.trim().isNotEmpty && !_matchesQuery(pb);
    Widget spine = SpineFace(
      book: pb.book,
      coverFile: repo.coverFileOf(pb.book),
      spineArt: widget.settings.spineArt,
    );
    if (flat) spine = RotatedBox(quarterTurns: 3, child: spine);
    return IgnorePointer(
      child: Opacity(
        opacity: dimmed ? 0.22 : (dragging ? 0.85 : 1),
        child: Stack(
          fit: StackFit.expand,
          children: [
            spine,
            if (_pulseId == pb.placement.id) _pulseRing(),
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
    );
  }

  /// The "here it is" marker: a ring that breathes a few times and stops.
  Widget _pulseRing() {
    final colour = Theme.of(context).colorScheme.tertiary;
    return AnimatedBuilder(
      animation: _pulse,
      builder: (context, _) => DecoratedBox(
        decoration: BoxDecoration(
          border: Border.all(color: colour, width: 2 + _pulse.value * 3),
          borderRadius: BorderRadius.circular(3),
          boxShadow: [
            BoxShadow(
              color: colour.withValues(alpha: 0.55 * (1 - _pulse.value)),
              blurRadius: 14 * _pulse.value + 4,
              spreadRadius: 3 * _pulse.value,
            ),
          ],
        ),
      ),
    );
  }
}
