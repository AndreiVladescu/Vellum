import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup_service.dart';
import '../data/library_repository.dart';
import '../server/connection_store.dart';
import '../server/sync_service.dart';
import 'app_settings.dart';
import 'book_face.dart';
import 'spine_art.dart';
import 'wallpaper.dart';

/// Appearance preferences (how books are shown on the shelf, the shelf
/// wallpaper — on the local [AppSettingsStore], applied instantly) plus the
/// library backup/restore actions.
class PreferencesPage extends StatelessWidget {
  const PreferencesPage({
    super.key,
    required this.settings,
    required this.repository,
    required this.connection,
    required this.sync,
  });

  final AppSettingsStore settings;
  final LibraryRepository repository;
  final ServerConnection connection;
  final SyncService sync;

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
            // Spine artwork only matters spine-out; face-out always shows the
            // cover itself.
            if (settings.bookFace == BookFace.spine) ...[
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text('Spine artwork for books with a cover'),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SegmentedButton<SpineArt>(
                  segments: [
                    for (final art in SpineArt.values)
                      ButtonSegment(
                        value: art,
                        label: Text(art.label),
                        icon: Icon(art == SpineArt.coverSlice
                            ? Icons.image_outlined
                            : Icons.palette_outlined),
                      ),
                  ],
                  selected: {settings.spineArt},
                  onSelectionChanged: (selection) =>
                      settings.setSpineArt(selection.first),
                ),
              ),
            ],
            const Divider(height: 24),
            _SectionHeader('Wallpaper'),
            for (final wallpaper in Wallpaper.values)
              _WallpaperTile(
                wallpaper: wallpaper,
                selected: settings.wallpaper == wallpaper,
                onTap: () => settings.setWallpaper(wallpaper),
              ),
            const Divider(height: 24),
            _SectionHeader('Genres'),
            SwitchListTile(
              secondary: const Icon(Icons.sell_outlined),
              title: const Text('Import genres from Open Library'),
              subtitle: const Text(
                  'Auto-tag new books with Open Library’s subjects. Off by '
                  'default — those are noisy; assign your own genres instead'),
              value: settings.importOpenLibraryGenres,
              onChanged: settings.setImportOpenLibraryGenres,
            ),
            const Divider(height: 24),
            _SectionHeader('Sync'),
            SwitchListTile(
              secondary: const Icon(Icons.cloud_sync_outlined),
              title: const Text('Push changes automatically'),
              subtitle: const Text(
                  'Send edits to the server in the background while connected'),
              value: settings.autoPush,
              onChanged: settings.setAutoPush,
            ),
            _ReadingPositionSwitch(
              settings: settings,
              repository: repository,
              connection: connection,
            ),
            const Divider(height: 24),
            _SectionHeader('Backup'),
            _BackupSection(
              repository: repository,
              connection: connection,
              sync: sync,
            ),
          ],
        ),
      ),
    );
  }
}

/// The opt-in for publishing this device's reading position (plan 5 #5).
///
/// A switch with side effects in both directions, which is why it isn't a plain
/// [SwitchListTile] on the settings object:
/// - **On** marks every already-read book for publishing, so the first sync
///   after opting in carries the positions you already have rather than only
///   books you open from now on.
/// - **Off** deletes this device's rows on the server (best-effort — offline
///   must not block the toggle) and clears the local cache, so the opt-in is
///   reversible rather than a one-way door.
class _ReadingPositionSwitch extends StatefulWidget {
  const _ReadingPositionSwitch({
    required this.settings,
    required this.repository,
    required this.connection,
  });

  final AppSettingsStore settings;
  final LibraryRepository repository;
  final ServerConnection connection;

  @override
  State<_ReadingPositionSwitch> createState() => _ReadingPositionSwitchState();
}

class _ReadingPositionSwitchState extends State<_ReadingPositionSwitch> {
  bool _busy = false;

  Future<void> _toggle(bool value) async {
    setState(() => _busy = true);
    final positions = widget.repository.readingPositions;
    var serverUnreachable = false;
    try {
      if (value) {
        await positions.markReadBooksForProgressPush();
      } else {
        final client = widget.connection.client;
        if (client != null) {
          try {
            await client.forgetReadingPositions(widget.settings.deviceId);
          } catch (_) {
            // Offline, or the server predates the endpoint. The switch still
            // goes off locally; the rows stay until a later opt-out succeeds.
            serverUnreachable = true;
          }
        }
        await positions.forgetLocally();
      }
      await widget.settings.setSyncReadingPosition(value);
    } finally {
      if (mounted) setState(() => _busy = false);
    }
    if (!mounted || !serverUnreachable) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          "Turned off here, but the server couldn't be reached to remove "
          'the positions it already has. Turn it off again while connected.',
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.auto_stories_outlined),
      title: const Text('Sync reading position'),
      subtitle: Text(
        'Let your other devices offer to resume where you left off. Off by '
        'default: unlike your catalogue, this tells the server what you read '
        'and how far. This device appears as “${widget.settings.deviceLabel}”.',
      ),
      value: widget.settings.syncReadingPosition,
      onChanged: _busy ? null : _toggle,
    );
  }
}

/// Export the library to a single archive, or restore one. Restore replaces
/// everything and requires an app restart, so it double-confirms.
class _BackupSection extends StatefulWidget {
  const _BackupSection({
    required this.repository,
    required this.connection,
    required this.sync,
  });

  final LibraryRepository repository;
  final ServerConnection connection;
  final SyncService sync;

  @override
  State<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<_BackupSection> {
  bool _busy = false;

  static String _suggestedName() {
    final now = DateTime.now();
    final d = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    return 'vellum-backup-$d.zip';
  }

  Future<void> _export() async {
    // file_selector can't offer a save location on Android/iOS, so on mobile we
    // write the archive to a temp file and hand it to the system share sheet
    // (save to Downloads/Drive/…). Desktop keeps the native save dialog.
    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (isMobile) {
      await _exportViaShare();
      return;
    }
    final location = await getSaveLocation(
      suggestedName: _suggestedName(),
      acceptedTypeGroups: const [
        XTypeGroup(label: 'Zip archive', extensions: ['zip']),
      ],
    );
    if (location == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await BackupService(widget.repository).exportTo(File(location.path));
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('Backup saved to ${location.path}')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Backup failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportViaShare() async {
    setState(() => _busy = true);
    try {
      final tmp = File(
          p.join((await getTemporaryDirectory()).path, _suggestedName()));
      await BackupService(widget.repository).exportTo(tmp);
      await SharePlus.instance.share(ShareParams(
        files: [XFile(tmp.path, mimeType: 'application/zip')],
        subject: 'Vellum backup',
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text('Backup failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    // A restore closes the database; doing that under a live launch/manual sync
    // would throw mid-transaction. Export is safe (VACUUM INTO is a snapshot).
    if (widget.sync.isRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Wait for the sync to finish, then try again.')),
      );
      return;
    }
    const group = XTypeGroup(label: 'Vellum backup', extensions: ['zip']);
    final picked = await openFile(acceptedTypeGroups: const [group]);
    if (picked == null || !mounted) return;
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Restore from backup?'),
        content: const Text(
          'This replaces your whole library — every book, cover, file, and '
          'reading position — with the backup\'s contents. Vellum will close '
          'when the restore finishes; open it again to see the restored '
          'library.\n\nThere is no undo.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Replace & restart'),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return;
    setState(() => _busy = true);
    try {
      final ok =
          await BackupService(widget.repository).restoreFrom(File(picked.path));
      if (!ok) {
        if (mounted) {
          setState(() => _busy = false);
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text("That file doesn't look like a Vellum backup.")),
          );
        }
        return;
      }
      // The restored database may predate the delta-pull cursor; clear all
      // cursors so the next launch does a full pull and converges. Prefs survive
      // the process swap, so this must happen before exit.
      await widget.connection.clearAllSyncCursors();
      // The database connection is closed and the files are swapped; the only
      // safe next step is a fresh process.
      exit(0);
    } catch (e) {
      // The library may be half-swapped and the DB closed — restarting is the
      // only way back to a consistent state, so don't pretend to recover.
      if (mounted) {
        await showDialog<void>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Restore failed'),
            content: Text(
                'The restore did not complete: $e\n\nVellum will close now; '
                'open it again and check your library (your previous backup '
                'file is untouched).'),
            actions: [
              FilledButton(
                onPressed: () => exit(0),
                child: const Text('Close Vellum'),
              ),
            ],
          ),
        );
      }
      exit(0);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: const Text('Export library…'),
          subtitle: const Text(
              'Everything — database, covers, and book files — in one .zip'),
          enabled: !_busy,
          onTap: _export,
          trailing: _busy
              ? const SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2))
              : null,
        ),
        ListTile(
          leading: const Icon(Icons.unarchive_outlined),
          title: const Text('Restore from backup…'),
          subtitle: const Text('Replaces the current library, then restarts'),
          enabled: !_busy,
          onTap: _restore,
        ),
      ],
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
