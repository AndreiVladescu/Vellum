import 'package:flutter/material.dart';

import 'account/account_page.dart';
import 'account/user_profile.dart';
import 'data/library_repository.dart';
import 'dedupe/duplicates_page.dart';
import 'import/folder_import_page.dart';
import 'stats/insights_page.dart';
import 'loans/loans_page.dart';
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
        settings: settings,
      ),
    ));
  }

  void _openPreferences(BuildContext context) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context).push(
      MaterialPageRoute(
        builder: (_) =>
            PreferencesPage(
              settings: settings,
              repository: repository,
              connection: connection,
              sync: sync,
            ),
      ),
    );
  }

  void _openLoans(BuildContext context) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) =>
          LoansPage(repository: repository, connection: connection),
    ));
  }

  void _openFolderImport(BuildContext context) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => FolderImportPage(
        repository: repository,
        settings: settings,
      ),
    ));
  }

  void _openDuplicates(BuildContext context) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => DuplicatesPage(repository: repository),
    ));
  }

  void _openInsights(BuildContext context) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context).push(MaterialPageRoute(
      builder: (_) => InsightsPage(repository: repository),
    ));
  }

  void _openAccount(BuildContext context) {
    Navigator.of(context).pop(); // close the drawer first
    Navigator.of(context).push(
      MaterialPageRoute(builder: (_) => AccountPage(profile: profile)),
    );
  }

  @override
  Widget build(BuildContext context) {
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
          ListTile(
            leading: const Icon(Icons.swap_horiz),
            title: const Text('Loans'),
            onTap: () => _openLoans(context),
          ),
          ListTile(
            leading: const Icon(Icons.folder_open),
            title: const Text('Import a folder'),
            onTap: () => _openFolderImport(context),
          ),
          ListTile(
            leading: const Icon(Icons.content_copy_outlined),
            title: const Text('Find duplicates'),
            onTap: () => _openDuplicates(context),
          ),
          ListTile(
            leading: const Icon(Icons.insights_outlined),
            title: const Text('Reading insights'),
            onTap: () => _openInsights(context),
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
                applicationIcon:
                    Image.asset('assets/logo.png', width: 48, height: 48),
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
