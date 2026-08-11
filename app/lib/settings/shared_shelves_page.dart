import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../data/shelf_service.dart';
import '../server/connection_store.dart';
import '../widgets/page_insets.dart';
import 'app_settings.dart';

/// Which of other people's shelves this device shows.
///
/// On a shared library a shelf arrives uninvited: it is somebody else's opinion
/// about how books group together, and there is no reason yours should be
/// crowded out by it. But refusing them all is too blunt — the shelf a family
/// keeps for the children's books is exactly the sort of thing sharing is for.
///
/// So there are two controls and they answer different questions. The switch at
/// the top decides what happens to shelves you have *not* ruled on, including
/// ones that have not arrived yet. The list below is your ruling on a
/// particular shelf, and it outlives changes to the switch — otherwise turning
/// the default back on would quietly undo every individual no.
///
/// Nothing here touches the server. Declining a shelf hides it on this device;
/// the person who made it is not told, and the shelf is not deleted.
class SharedShelvesPage extends StatelessWidget {
  const SharedShelvesPage({
    super.key,
    required this.repository,
    required this.settings,
    required this.connection,
  });

  final LibraryRepository repository;
  final AppSettingsStore settings;
  final ServerConnection connection;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Shelves from others')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => StreamBuilder<List<Shelf>>(
          stream: repository.watchShelves(),
          builder: (context, snapshot) {
            final all = snapshot.data ?? const <Shelf>[];
            final theirs = [
              for (final s in all)
                if (shelfMadeByAnother(s, connection.userId)) s,
            ];
            return ListView(
              padding: pageInsets(context, const EdgeInsets.only(bottom: 12)),
              children: [
                SwitchListTile(
                  value: settings.acceptSharedShelves,
                  onChanged: settings.setAcceptSharedShelves,
                  title: const Text('Show new shelves from others'),
                  subtitle: const Text(
                    'What happens to a shelf you have not ruled on, including '
                    'ones that arrive later. Your answers below are kept '
                    'either way.',
                  ),
                ),
                const Divider(),
                if (theirs.isEmpty)
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 24, 16, 0),
                    child: Text(
                      'Nobody else has shared a shelf with this library yet.',
                      textAlign: TextAlign.center,
                    ),
                  )
                else ...[
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
                    child: Row(
                      children: [
                        Expanded(
                          child: Text(
                            '${theirs.length} shelf'
                            '${theirs.length == 1 ? '' : 'ves'} from others',
                            style: Theme.of(context).textTheme.titleSmall,
                          ),
                        ),
                        // The bulk pair. They write an explicit answer to every
                        // shelf rather than clearing them back to "undecided",
                        // because "show all of these" is a decision too.
                        TextButton(
                          onPressed: () => repository.setAllShelvesAccepted(
                            [for (final s in theirs) s.id],
                            false,
                          ),
                          child: const Text('Hide all'),
                        ),
                        TextButton(
                          onPressed: () => repository.setAllShelvesAccepted(
                            [for (final s in theirs) s.id],
                            true,
                          ),
                          child: const Text('Show all'),
                        ),
                      ],
                    ),
                  ),
                  for (final shelf in theirs)
                    SwitchListTile(
                      value: shelf.accepted ?? settings.acceptSharedShelves,
                      onChanged: (v) =>
                          repository.setShelfAccepted(shelf.id, v),
                      title: Text(shelf.name),
                      subtitle: Text(
                        shelf.accepted == null
                            ? 'Following the setting above'
                            : (shelf.accepted!
                                ? 'Shown in your library'
                                : 'Hidden on this device'),
                      ),
                      secondary: shelf.accepted == null
                          ? null
                          // Only offered once there is something to undo: the
                          // way back to "just follow the setting".
                          : IconButton(
                              icon: const Icon(Icons.settings_backup_restore),
                              tooltip: 'Follow the setting above',
                              onPressed: () =>
                                  repository.setShelfAccepted(shelf.id, null),
                            ),
                    ),
                ],
              ],
            );
          },
        ),
      ),
    );
  }
}
