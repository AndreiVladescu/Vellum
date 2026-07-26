import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../settings/app_settings.dart';
import 'environment_editor_page.dart';

/// The Physical tab body: lists physical environments ("libraries") and lets
/// you rename / delete them. Creation is driven by the host page's FAB via
/// [promptCreateLibrary]. Tapping one opens its shelf editor.
class PhysicalLibrariesTab extends StatelessWidget {
  const PhysicalLibrariesTab({
    super.key,
    required this.repository,
    required this.settings,
  });

  final LibraryRepository repository;
  final AppSettingsStore settings;

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
          itemCount: envs.length,
          separatorBuilder: (_, _) => const Divider(height: 1),
          itemBuilder: (context, i) {
            final env = envs[i];
            return ListTile(
              leading: const Icon(Icons.grid_view_rounded),
              title: Text(env.name),
              onTap: () =>
                  openEnvironment(context, repository, settings, env.id, env.name),
              trailing: PopupMenuButton<String>(
                onSelected: (v) => v == 'rename'
                    ? _rename(context, env)
                    : _delete(context, env),
                itemBuilder: (context) => const [
                  PopupMenuItem(value: 'rename', child: Text('Rename')),
                  PopupMenuItem(value: 'delete', child: Text('Delete')),
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
