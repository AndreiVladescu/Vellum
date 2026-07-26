import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../server/connection_store.dart';
import '../settings/app_settings.dart';
import 'environment_editor_page.dart';
import 'publish_room.dart';
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
      title: 'Rename library',
      initial: env.name,
    );
    if (name == null || name.trim().isEmpty) return;
    await repository.layout.renameEnvironment(env.id, name);
  }

  Future<void> _delete(BuildContext context, PhysicalEnvironment env) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text('Delete “${env.name}”?'),
        content: const Text(
          'This removes the room and everything arranged in it. '
          'The books themselves stay in your library.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: const Text('Delete'),
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

    // Asked, not assumed: publishing a room shares its *shape*; whether the
    // books in it become visible is a separate decision, and one people should
    // make deliberately.
    var shareBooks = false;
    final go = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text('Publish “${env.name}”?'),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Your other devices — and anyone you share the room with — '
                'will see this arrangement. The room itself carries only '
                'shelf and book positions, never titles or covers.',
              ),
              CheckboxListTile(
                value: shareBooks,
                onChanged: (v) => setLocal(() => shareBooks = v ?? false),
                contentPadding: EdgeInsets.zero,
                controlAffinity: ListTileControlAffinity.leading,
                dense: true,
                title: const Text('Also collect its books under a tag'),
                subtitle: Text(
                  'Makes a “Room: ${env.name}” tag you can share, so viewers '
                  'see titles instead of blank spines',
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: const Text('Publish'),
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
    final message = await publisher.fetch(env.id, name: env.name);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text(message)));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<PhysicalEnvironment>>(
      stream: repository.layout.watchEnvironments(),
      builder: (context, snapshot) {
        final envs = snapshot.data ?? const [];
        if (envs.isEmpty) {
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
                Text('No physical libraries yet',
                    style: theme.textTheme.titleMedium),
                const SizedBox(height: 6),
                Text(
                  'Create a room, add shelves, and arrange your books.',
                  style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                ),
                const SizedBox(height: 16),
                // An empty state that only explains leaves the next step to be
                // hunted for; every one of them now offers it (plan 5 #41).
                FilledButton.icon(
                  onPressed: () =>
                      promptCreateLibrary(context, repository, settings),
                  icon: const Icon(Icons.add),
                  label: const Text('Create a room'),
                ),
              ],
            ),
          );
        }
        return ListView.separated(
          padding: const EdgeInsets.only(top: 8, bottom: 88),
          // One extra row at the top: scanning a printed shelf label
          // (plan 5 #28) belongs where the rooms are listed, since what it does
          // is open one of them.
          itemCount: envs.length + 1,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            if (i == 0) {
              return ListTile(
                leading: const Icon(Icons.qr_code_scanner),
                title: const Text('Scan a shelf label'),
                subtitle: const Text('Opens the room that shelf is in'),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => ShelfScanPage(
                      repository: repository,
                      settings: settings,
                    ),
                  ),
                ),
              );
            }
            final env = envs[i - 1];
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
                      ? 'Not published'
                      : env.needsPublish
                          ? 'Changed since publishing'
                          : 'Published · revision ${env.serverRevision}'),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => switch (v) {
                  'rename' => _rename(context, env),
                  'delete' => _delete(context, env),
                  'publish' => _publish(context, env),
                  _ => _fetch(context, env),
                },
                itemBuilder: (context) => [
                  const PopupMenuItem(value: 'rename', child: Text('Rename')),
                  if (_publisher != null) ...[
                    const PopupMenuItem(
                      value: 'publish',
                      child: Text('Publish to server'),
                    ),
                    const PopupMenuItem(
                      value: 'fetch',
                      child: Text('Update from server'),
                    ),
                  ],
                  const PopupMenuItem(value: 'delete', child: Text('Delete')),
                ],
              ),
            );
          },
        );
      },
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
  final name = await _promptName(context, title: 'New library');
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
  final controller = TextEditingController(text: initial);
  return showDialog<String>(
    context: context,
    builder: (context) => AlertDialog(
      title: Text(title),
      content: TextField(
        controller: controller,
        autofocus: true,
        decoration: const InputDecoration(hintText: 'e.g. Living room'),
        onSubmitted: (v) => Navigator.pop(context, v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(context, controller.text),
          child: const Text('Save'),
        ),
      ],
    ),
  );
}
