import 'package:flutter/material.dart';

import 'app_settings.dart';
import 'book_face.dart';
import 'wallpaper.dart';

/// Appearance preferences: how books are shown on the shelf, and the shelf
/// wallpaper. Both live on the local [AppSettingsStore] and apply instantly.
class PreferencesPage extends StatelessWidget {
  const PreferencesPage({super.key, required this.settings});

  final AppSettingsStore settings;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Preferences')),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) => ListView(
          padding: const EdgeInsets.symmetric(vertical: 8),
          children: [
            _SectionHeader('Books on the shelf'),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SegmentedButton<BookFace>(
                segments: [
                  for (final face in BookFace.values)
                    ButtonSegment(
                      value: face,
                      label: Text(face.label),
                      icon: Icon(face == BookFace.cover
                          ? Icons.image_outlined
                          : Icons.menu_book_outlined),
                    ),
                ],
                selected: {settings.bookFace},
                onSelectionChanged: (selection) =>
                    settings.setBookFace(selection.first),
              ),
            ),
            const Divider(height: 24),
            _SectionHeader('Wallpaper'),
            for (final wallpaper in Wallpaper.values)
              _WallpaperTile(
                wallpaper: wallpaper,
                selected: settings.wallpaper == wallpaper,
                onTap: () => settings.setWallpaper(wallpaper),
              ),
          ],
        ),
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.text);

  final String text;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
      child: Text(
        text,
        style: theme.textTheme.titleSmall
            ?.copyWith(color: theme.colorScheme.primary),
      ),
    );
  }
}

class _WallpaperTile extends StatelessWidget {
  const _WallpaperTile({
    required this.wallpaper,
    required this.selected,
    required this.onTap,
  });

  final Wallpaper wallpaper;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    return ListTile(
      onTap: onTap,
      leading: ClipRRect(
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
      title: Text(wallpaper.label),
      trailing: selected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
    );
  }
}
