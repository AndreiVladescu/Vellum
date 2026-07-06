import 'package:flutter/material.dart';

import 'account/account_page.dart';
import 'account/user_profile.dart';
import 'settings/app_settings.dart';
import 'settings/wallpaper.dart';

class AppDrawer extends StatelessWidget {
  const AppDrawer(
      {super.key, required this.profile, required this.settings});

  final UserProfileStore profile;
  final AppSettingsStore settings;

  Future<void> _pickWallpaper(BuildContext context) async {
    Navigator.of(context).pop(); // close the drawer
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => SimpleDialog(
        title: const Text('Wallpaper'),
        children: [
          for (final wallpaper in Wallpaper.values)
            SimpleDialogOption(
              onPressed: () {
                settings.setWallpaper(wallpaper);
                Navigator.of(dialogContext).pop();
              },
              child: Row(
                children: [
                  ClipRRect(
                    borderRadius: BorderRadius.circular(6),
                    child: SizedBox(
                      width: 72,
                      height: 44,
                      child: WallpaperBackground(
                        wallpaper: wallpaper,
                        child: const SizedBox.expand(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 14),
                  Expanded(child: Text(wallpaper.label)),
                  if (settings.wallpaper == wallpaper)
                    Icon(Icons.check,
                        color: Theme.of(dialogContext).colorScheme.primary),
                ],
              ),
            ),
        ],
      ),
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
          const ListTile(
            leading: Icon(Icons.cloud_outlined),
            title: Text('Library server'),
            subtitle: Text('Coming soon'),
            enabled: false,
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.wallpaper),
            title: const Text('Wallpaper'),
            onTap: () => _pickWallpaper(context),
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
