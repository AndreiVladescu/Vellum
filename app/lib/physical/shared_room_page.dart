import 'package:flutter/material.dart';

import '../data/database.dart';
import '../server/server_client.dart';
import 'layout_doc.dart';
import 'physical_metrics.dart';
import 'room_painter.dart';

/// Someone else's room, drawn read-only (next features #9).
///
/// **A mirror, not a copy.** The document is fetched, parsed and drawn; nothing
/// is written to the local tables. That is the smaller and more honest of the
/// two options — it is always current, it cannot be edited by mistake, and it
/// matches what viewer-only sharing already means everywhere else in Vellum.
/// The trade is that it needs the server, which is why the page says so when
/// the fetch fails rather than showing an empty room.
///
/// Before this existed the console could list and draw a room shared with you
/// and the app could not, so the browser showed more of your own library than
/// the app did.
class SharedRoomPage extends StatefulWidget {
  const SharedRoomPage({
    super.key,
    required this.client,
    required this.layoutId,
    required this.name,
  });

  final VellumServerClient client;
  final String layoutId;
  final String name;

  @override
  State<SharedRoomPage> createState() => _SharedRoomPageState();
}

class _SharedRoomPageState extends State<SharedRoomPage> {
  ParsedLayout? _room;
  Map<String, String> _titles = const {};
  String? _error;
  bool _loading = true;

  // Camera, same conventions as the editor: pixels per metre, and the screen
  // offset of world (0, 0). No dragging of anything but the view.
  double _scale = 200;
  Offset? _origin;
  double _startScale = 1;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    try {
      final layout = await widget.client.fetchLayout(widget.layoutId);
      final doc = layout.doc;
      if (doc == null) throw const LayoutDocException('The room is empty.');
      final parsed = parseLayoutDoc(doc);
      // Titles are a separate request because the document is geometry only.
      // A failure here is not a failure of the room: it draws unnamed.
      var titles = <String, String>{};
      try {
        titles = await widget.client.fetchLayoutBookTitles(widget.layoutId);
      } catch (_) {}
      if (!mounted) return;
      setState(() {
        _room = parsed;
        _titles = titles;
        _loading = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _error = '$e';
        _loading = false;
      });
    }
  }

  /// Frames the whole room on first paint, so opening a shared room shows the
  /// room rather than a corner of it.
  void _fitTo(Size size, ParsedLayout room) {
    var maxX = 1.0;
    var maxY = 1.0;
    for (final s in room.shelves) {
      maxX = [maxX, s.x1, s.x2].reduce((a, b) => a > b ? a : b);
      maxY = [maxY, s.y1, s.y2].reduce((a, b) => a > b ? a : b);
    }
    for (final p in room.placements) {
      maxX = [maxX, p.x + p.widthM].reduce((a, b) => a > b ? a : b);
      maxY = [maxY, p.y + p.heightM].reduce((a, b) => a > b ? a : b);
    }
    const margin = 0.4;
    final fit = [
      size.width / (maxX + margin),
      size.height / (maxY + margin),
    ].reduce((a, b) => a < b ? a : b);
    _scale = fit.clamp(20.0, 600.0);
    _origin = Offset(20, size.height - 20);
  }

  Offset _worldToScreen(Offset w) =>
      Offset(_origin!.dx + w.dx * _scale, _origin!.dy - w.dy * _scale);

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(widget.name),
        // Said in the bar rather than in a tooltip: the one thing to know about
        // this screen is that it is not yours to change.
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(28),
          child: Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Text(
              'Shared with you · view only',
              style: theme.textTheme.labelMedium,
            ),
          ),
        ),
      ),
      body: _body(theme),
    );
  }

  Widget _body(ThemeData theme) {
    if (_loading) return const Center(child: CircularProgressIndicator());
    final error = _error;
    if (error != null) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.cloud_off, color: theme.colorScheme.outline),
              const SizedBox(height: 12),
              const Text(
                'This room is kept on the server, so it needs a connection to '
                'open.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 8),
              Text(error,
                  style: theme.textTheme.bodySmall, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              FilledButton(
                onPressed: () {
                  setState(() {
                    _loading = true;
                    _error = null;
                  });
                  _load();
                },
                child: const Text('Try again'),
              ),
            ],
          ),
        ),
      );
    }

    final room = _room!;
    return LayoutBuilder(
      builder: (context, constraints) {
        _origin ??= () {
          _fitTo(constraints.biggest, room);
          return _origin;
        }();
        return GestureDetector(
          onScaleStart: (d) => _startScale = _scale,
          onScaleUpdate: (d) => setState(() {
            _scale = (_startScale * d.scale).clamp(20.0, 1600.0);
            _origin = _origin! + d.focalPointDelta;
          }),
          child: ClipRect(
            child: Stack(
              children: [
                Positioned.fill(
                  child: CustomPaint(
                    painter: RoomPainter(
                      shelves: [
                        for (final s in room.shelves)
                          PhysicalShelf(
                            id: s.id,
                            environmentId: room.environmentId,
                            x1: s.x1,
                            y1: s.y1,
                            x2: s.x2,
                            y2: s.y2,
                            label: s.label,
                            kind: s.kind,
                            createdAt: DateTime.now(),
                          ),
                      ],
                      origin: _origin!,
                      scale: _scale,
                      line: theme.colorScheme.outlineVariant,
                      plank: theme.colorScheme.onSurfaceVariant,
                      label: theme.colorScheme.onSurface,
                      shelfDelta: const AlwaysStoppedAnimation(Offset.zero),
                    ),
                  ),
                ),
                for (final p in room.placements) _book(p, theme),
              ],
            ),
          ),
        );
      },
    );
  }

  /// One book, as a plain coloured block. No cover art: the document carries
  /// geometry only, and the images belong to whoever published the room.
  Widget _book(ParsedPlacement p, ThemeData theme) {
    final flat = p.rotation == 90;
    final w = (flat ? p.heightM : p.widthM) * _scale;
    final h = (flat ? p.widthM : p.heightM) * _scale;
    final topLeft = _worldToScreen(Offset(p.x, p.y + (flat ? p.widthM : p.heightM)));
    final title = _titles[p.bookId];
    return Positioned(
      left: topLeft.dx,
      top: topLeft.dy,
      width: w,
      height: h,
      child: Tooltip(
        message: title ?? 'A book you cannot see',
        child: DecoratedBox(
          decoration: BoxDecoration(
            color: title == null
                // A book in someone else's room that isn't shared with you:
                // drawn, because leaving a hole would misrepresent the shelf,
                // but plainly anonymous.
                ? theme.colorScheme.surfaceContainerHighest
                : PhysicalMetrics.colorForTitle(title),
            borderRadius: BorderRadius.circular(2),
            border: Border.all(color: theme.colorScheme.outlineVariant),
          ),
        ),
      ),
    );
  }
}

/// The list of rooms other people have shared with this account.
class SharedRoomsList extends StatelessWidget {
  const SharedRoomsList({
    super.key,
    required this.rooms,
    required this.client,
  });

  final List<ServerLayout> rooms;
  final VellumServerClient client;

  @override
  Widget build(BuildContext context) {
    if (rooms.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
          child: Text('Shared with you', style: theme.textTheme.titleSmall),
        ),
        for (final room in rooms)
          ListTile(
            leading: const Icon(Icons.visibility_outlined),
            title: Text(room.name),
            subtitle: const Text('View only — kept on the server'),
            onTap: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => SharedRoomPage(
                  client: client,
                  layoutId: room.id,
                  name: room.name,
                ),
              ),
            ),
          ),
      ],
    );
  }
}
