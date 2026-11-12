import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../l10n/gen/app_localizations.dart';
import '../server/connection_store.dart';
import '../snack_bars.dart';
import '../settings/app_settings.dart';
import 'environment_editor_page.dart';
import 'publish_room.dart';
import '../server/server_client.dart';
import 'shared_room_page.dart';
import 'shelf_scan_page.dart';

/// The Physical tab body: lists physical environments ("libraries") and lets
/// you rename / delete them. Creation is driven by the host page's FAB via
/// [promptCreateLibrary]. Tapping one opens its shelf editor.
class PhysicalLibrariesTab extends StatelessWidget {
  const PhysicalLibrariesTab({
    super.key,
    required this.repository,
    required this.settings,
    this.connection,
  });

  final LibraryRepository repository;
  final AppSettingsStore settings;

  /// Needed only for publishing rooms (plan 5 #47); the actions are hidden
  /// without a connection, or against a server that doesn't advertise
  /// `layouts` — a Publish button that can only fail is worse than none.
  final ServerConnection? connection;

  Future<void> _rename(BuildContext context, PhysicalEnvironment env) async {
    final name = await _promptName(
      context,
      title: L10n.of(context).physicalLibsRenameTitle,
      initial: env.name,
    );
    if (name == null || name.trim().isEmpty) return;
    await repository.layout.renameEnvironment(env.id, name);
  }

  Future<void> _delete(BuildContext context, PhysicalEnvironment env) async {
    final l10n = L10n.of(context);
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.physicalLibsDeleteTitle(env.name)),
        content: Text(l10n.physicalLibsDeleteBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (ok == true) await repository.layout.deleteEnvironment(env.id);
  }

  /// The publisher, or null when this server can't take rooms.
  RoomPublisher? get _publisher {
    final c = connection;
    if (c == null) return null;
    final publisher = RoomPublisher(repository: repository, connection: c);
    return publisher.available ? publisher : null;
  }

  Future<void> _publish(BuildContext context, PhysicalEnvironment env) async {
    final publisher = _publisher;
    if (publisher == null) return;
    final l10n = L10n.of(context);

    // Asked, not assumed: publishing a room shares its *shape*; whether the
    // books in it become visible is a separate decision, and one people should
    // make deliberately.
    var shareBooks = false;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text(l10n.physicalLibsPublishTitle(env.name)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(l10n.physicalLibsPublishBody),
              CheckboxListTile(
                value: shareBooks,
                onChanged: (v) => setLocal(() => shareBooks = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: Text(l10n.physicalLibsCollectTitle),
                subtitle: Text(
                  // The tag's own name stays English: it is data on the
                  // server, matched by name on the next publish.
                  l10n.physicalLibsCollectNote('Room: ${env.name}'),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.physicalLibsPublish),
            ),
          ],
        ),
      ),
    );
    if (go != true || !context.mounted) return;

    final message = await publisher.publish(context, env, shareBooks: shareBooks);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _fetch(BuildContext context, PhysicalEnvironment env) async {
    final publisher = _publisher;
    if (publisher == null) return;
    final message =
        await publisher.fetch(L10n.of(context), env.id, name: env.name);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return StreamBuilder<List<PhysicalEnvironment>>(
      stream: repository.layout.watchEnvironments(),
      builder: (context, snapshot) {
        final envs = snapshot.data ?? const [];
        if (envs.isEmpty) {
          return ListView(children: [
            const SizedBox(height: 60),
            _emptyState(context, theme),
            _SharedRooms(
              connection: connection,
              repository: repository,
              localIds: const {},
            ),
          ]);
        }
        return ListView(
          padding: const EdgeInsets.only(top: 8, bottom: 88),
          children: [
            // Scanning a printed shelf label (plan 5 #28) belongs where the
            // rooms are listed, since what it does is open one of them.
            ListTile(
              leading: const Icon(Icons.qr_code_scanner),
              title: Text(l10n.physicalLibsScanTitle),
              subtitle: Text(l10n.physicalLibsScanNote),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) => ShelfScanPage(
                    repository: repository,
                    settings: settings,
                  ),
                ),
              ),
            ),
            for (final env in envs) ...[
              const Divider(height: 1),
              _roomTile(context, env),
            ],
            _SharedRooms(
              connection: connection,
              repository: repository,
              localIds: {for (final e in envs) e.id},
            ),
          ],
        );
      },
    );
  }

  Widget _emptyState(BuildContext context, ThemeData theme) {
    final l10n = L10n.of(context);
        {
          return Center(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(
                  Icons.chair_alt_outlined,
                  size: 56,
                  color: theme.colorScheme.primary.withValues(alpha: 0.7),
                ),
                const SizedBox(height: 16),
                Text(l10n.physicalLibsEmptyTitle,
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  l10n.physicalLibsEmptyBody,
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                // An empty state that only explains leaves the next step to be
                // hunted for; every one of them now offers it (plan 5 #41).
                FilledButton.icon(
                  onPressed: () =>
                      promptCreateLibrary(context, repository, settings),
                  icon: const Icon(Icons.add),
                  label: Text(l10n.physicalLibsCreateRoom),
                ),
              ],
            ),
          );
        }
  }

  Widget _roomTile(BuildContext context, PhysicalEnvironment env) {
    final l10n = L10n.of(context);
            return ListTile(
              leading: const Icon(Icons.grid_view_rounded),
              title: Text(env.name),
              onTap: () =>
                  openEnvironment(context, repository, settings, env.id, env.name),
              // The dirty badge (plan 5 #47): a room edited since its last
              // publish says so, rather than leaving you to remember.
              subtitle: _publisher == null
                  ? null
                  : Text(env.serverRevision == null
                      ? l10n.physicalLibsNotPublished
                      : env.needsPublish
                          ? l10n.physicalLibsChanged
                          : l10n.physicalLibsPublishedRevision(
                              env.serverRevision!)),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'rename' => _rename(context, env),
                  'delete' => _delete(context, env),
                  'publish' => _publish(context, env),
                  _ => _fetch(context, env),
                },
                itemBuilder: (context) => [
                  PopupMenuItem(
                      value: 'rename', child: Text(l10n.physicalLibsMenuRename)),
                  if (_publisher != null) ...[
                    PopupMenuItem(
                      value: 'publish',
                      child: Text(l10n.physicalLibsMenuPublish),
                    ),
                    PopupMenuItem(
                      value: 'fetch',
                      child: Text(l10n.physicalLibsMenuFetch),
                    ),
                  ],
                  PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
                ],
              ),
            );
  }
}

/// Rooms other people have shared with this account (next features #9).
///
/// Fetched rather than stored: a shared room is a mirror, so there is nothing
/// local to list. Absent entirely without a connection or against a server too
/// old to have `/api/layouts`, which is the same rule the publish actions
/// follow — a section that can only fail is worse than none.
/// Rooms this account published from another device that this one has never
/// seen.
///
/// A room is a *document* on the server, not a synced table (plan 5 #47), so
/// nothing pulls one down by itself. Without this they were invisible on a
/// second device — your own published rooms were filtered out of "shared with
/// you" for being yours, and "Update from server" only works on a room that is
/// already here. The effect was that rooms looked like the one thing that did
/// not sync.
List<ServerLayout> roomsPublishedElsewhere(
  List<ServerLayout> all,
  Set<String> localIds,
) =>
    [
      for (final layout in all)
        if (layout.mine && !localIds.contains(layout.id)) layout,
    ];

class _SharedRooms extends StatefulWidget {
  const _SharedRooms({
    required this.connection,
    required this.repository,
    required this.localIds,
  });

  /// The rooms this device already has, so a published room of your own is
  /// only offered when it is missing here.
  final Set<String> localIds;
  final LibraryRepository repository;

  final ServerConnection? connection;

  @override
  State<_SharedRooms> createState() => _SharedRoomsState();
}

class _SharedRoomsState extends State<_SharedRooms> {
  List<ServerLayout> _rooms = const [];

  /// Rooms this account published from another device and that this one has
  /// never seen. A room is a *document* on the server rather than a synced
  /// table, so nothing brings it down on its own — before this they were
  /// invisible here, which looked like rooms not syncing at all.
  List<ServerLayout> _mineElsewhere = const [];
  String? _busyId;

  @override
  void initState() {
    super.initState();
    _load();
  }

  @override
  void didUpdateWidget(_SharedRooms old) {
    super.didUpdateWidget(old);
    // A room brought down (or created, or deleted) changes what is missing.
    if (old.localIds.length != widget.localIds.length) _recompute(_all);
  }

  List<ServerLayout> _all = const [];

  Future<void> _load() async {
    final client = widget.connection?.client;
    if (client == null) return;
    try {
      final all = await client.listLayouts();
      if (!mounted) return;
      _recompute(all);
    } catch (_) {
      // Offline, or a server without rooms. Nothing to show, nothing to say.
    }
  }

  void _recompute(List<ServerLayout> all) {
    setState(() {
      _all = all;
      _rooms = [
        for (final l in all)
          if (!l.mine) l,
      ];
      _mineElsewhere = roomsPublishedElsewhere(all, widget.localIds);
    });
  }

  Future<void> _bringHere(ServerLayout room) async {
    final c = widget.connection;
    if (c == null) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    setState(() => _busyId = room.id);
    final message = await RoomPublisher(
      repository: widget.repository,
      connection: c,
    ).fetch(l10n, room.id, name: room.name);
    if (!mounted) return;
    setState(() => _busyId = null);
    messenger.showSnackBar(appSnackBar(content: Text(message)));
    // The stream of local rooms repaints the list above; this section learns
    // the room is here through didUpdateWidget.
  }

  @override
  Widget build(BuildContext context) {
    final client = widget.connection?.client;
    if (client == null) return const SizedBox.shrink();
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        if (_mineElsewhere.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 20, 16, 0),
            child: Text(l10n.physicalLibsElsewhereTitle,
                style: theme.textTheme.titleSmall),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 2, 16, 4),
            child: Text(
              l10n.physicalLibsElsewhereNote,
              style: theme.textTheme.bodySmall
                  ?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          for (final room in _mineElsewhere)
            ListTile(
              leading: const Icon(Icons.cloud_download_outlined),
              title: Text(room.name),
              subtitle: Text(l10n.physicalLibsRevision(room.revision)),
              trailing: _busyId == room.id
                  ? const SizedBox(
                      height: 20,
                      width: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : TextButton(
                      onPressed: () => _bringHere(room),
                      child: Text(l10n.physicalLibsBringHere),
                    ),
            ),
        ],
        SharedRoomsList(rooms: _rooms, client: client),
      ],
    );
  }
}

/// Opens the shelf editor for an environment.
void openEnvironment(
  BuildContext context,
  LibraryRepository repository,
  AppSettingsStore settings,
  String id,
  String name,
) {
  Navigator.of(context).push(
    MaterialPageRoute(
      builder: (_) => EnvironmentEditorPage(
        repository: repository,
        settings: settings,
        environmentId: id,
        environmentName: name,
      ),
    ),
  );
}

/// Prompts for a name, creates a library, and opens it. Driven by the FAB.
Future<void> promptCreateLibrary(
  BuildContext context,
  LibraryRepository repository,
  AppSettingsStore settings,
) async {
  final name = await _promptName(context,
      title: L10n.of(context).physicalLibsNewTitle);
  if (name == null || name.trim().isEmpty) return;
  final id = await repository.layout.createEnvironment(name);
  if (!context.mounted) return;
  openEnvironment(context, repository, settings, id, name.trim());
}

/// Small single-field name prompt shared by create and rename.
Future<String?> _promptName(
  BuildContext context, {
  required String title,
  String? initial,
}) {
  final l10n = L10n.of(context);
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: InputDecoration(hintText: l10n.physicalLibsNameHint),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: Text(l10n.save),
        ),
      ],
    ),
  );
}
