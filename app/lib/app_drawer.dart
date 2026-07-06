import 'package:flutter/material.dart';

import 'account/account_page.dart';
import 'account/user_profile.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer({super.key, required this.profile});

  final UserProfileStore profile;

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
          const ListTile(
            leading: Icon(Icons.cloud_outlined),
            title: Text('Library server'),
            subtitle: Text('Coming soon'),
            enabled: false,
          ),
          const Divider(),
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
