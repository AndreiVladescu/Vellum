import 'package:flutter/material.dart';

import 'account/account_page.dart';
import 'account/user_profile.dart';
import 'data/library_repository.dart';
import 'server/connection_store.dart';
import 'server/server_page.dart';
import 'server/sync_service.dart';
import 'settings/app_settings.dart';
import 'settings/preferences_page.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({
    super.key,
    required this.profile,
    required this.settings,
    required this.connection,
    required this.repository,
    required this.sync,
  });

  final UserProfileStore profile;
  final AppSettingsStore settings;
  final ServerConnection connection;
  final LibraryRepository repository;
  final SyncService sync;

  void _openServer(BuildContext context) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => ServerPage(
        connection: connection,
        repository: repository,
        sync: sync,
      ),
    ));
  }

  void _openPreferences(BuildContext context) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => PreferencesPage(settings: settings)),
    );
  }

  void _openAccount(BuildContext context) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AccountPage(profile: profile)),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Drawer(
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          ListenableBuilder(
            listenable: profile,
            builder: (context, _) => UserAccountsDrawerHeader(
              currentAccountPicture: CircleAvatar(
                child: Text(profile.initial,
                    style: const TextStyle(fontSize: 24)),
              ),
              accountName:
                  Text(profile.isSet ? profile.name : 'Set up your profile'),
              accountEmail: Text(
                  profile.email.isEmpty ? 'Local library' : profile.email),
              onDetailsPressed: () => _openAccount(context),
            ),
          ),
          ListTile(
            leading: const Icon(Icons.shelves),
            title: const Text('My shelf'),
            selected: true,
            onTap: () => Navigator.of(context).pop(),
          ),
          const ListTile(
            leading: Icon(Icons.auto_stories_outlined),
            title: Text('Physical books'),
            subtitle: Text('Coming soon'),
            enabled: false,
          ),
          const ListTile(
            leading: Icon(Icons.swap_horiz),
            title: Text('Loans'),
            subtitle: Text('Coming soon'),
            enabled: false,
          ),
          ListenableBuilder(
            listenable: connection,
            builder: (context, _) => ListTile(
              leading: Icon(connection.isConnected
                  ? Icons.cloud_done_outlined
                  : Icons.cloud_outlined),
              title: const Text('Library server'),
              subtitle: Text(connection.isConnected
                  ? 'Connected · ${connection.email}'
                  : 'Not connected'),
              onTap: () => _openServer(context),
            ),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.tune),
            title: const Text('Preferences'),
            onTap: () => _openPreferences(context),
          ),
          ListTile(
            leading: const Icon(Icons.person_outline),
            title: const Text('Account'),
            onTap: () => _openAccount(context),
          ),
          ListTile(
            leading: const Icon(Icons.info_outline),
            title: const Text('About Vellum'),
            onTap: () {
              Navigator.of(context).pop();
              showAboutDialog(
                context: context,
                applicationName: 'Vellum',
                applicationVersion: '0.1.0',
                applicationIcon: Icon(Icons.menu_book,
                    color: theme.colorScheme.primary, size: 40),
                children: const [
                  Text('A personal library for your digital and physical '
                      'books, shown the way books actually look: '
                      'spine-out on a shelf.'),
                ],
              );
            },
          ),
        ],
      ),
    );
  }
}
