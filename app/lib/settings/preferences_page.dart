import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup_crypto.dart';
import '../data/backup_schedule.dart';
import '../data/backup_service.dart';
import '../data/library_doctor.dart';
import '../data/library_repository.dart';
import '../server/connection_store.dart';
import '../server/sync_service.dart';
import 'app_settings.dart';
import 'book_face.dart';
import 'spine_art.dart';
import 'trash_page.dart';
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
            _SectionHeader('Trash'),
            _TrashTile(repository: repository),
            const Divider(height: 24),
            _SectionHeader('Library health'),
            _HealthSection(repository: repository, connection: connection),
            const Divider(height: 24),
            _SectionHeader('Backup'),
            _BackupSection(
              repository: repository,
              connection: connection,
              sync: sync,
              settings: settings,
            ),
          ],
        ),
      ),
    );
  }
}

/// The library health check (plan 5 #11).
///
/// Read-only until asked: the scan reports, and each category is repaired only on
/// an explicit tap — with a confirmation for the destructive ones, since deleting
/// blobs and collapsing duplicate rows cannot be undone.
class _HealthSection extends StatefulWidget {
  const _HealthSection({required this.repository, required this.connection});

  final LibraryRepository repository;
  final ServerConnection connection;

  @override
  State<_HealthSection> createState() => _HealthSectionState();
}

class _HealthSectionState extends State<_HealthSection> {
  DoctorReport? _report;
  bool _busy = false;
  bool _cancelRequested = false;

  Future<void> _scan() async {
    setState(() {
      _busy = true;
      _cancelRequested = false;
    });
    final report = await LibraryDoctor(widget.repository).scan(
      hasServer: widget.connection.baseUrl.isNotEmpty,
      isCancelled: () async => _cancelRequested,
    );
    if (!mounted) return;
    setState(() {
      _report = report;
      _busy = false;
    });
  }

  Future<void> _repair(DefectKind kind, List<Defect> defects) async {
    if (kind.isDestructive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(kind.label),
          content: Text('${kind.repairLabel} for ${defects.length} item'
              '${defects.length == 1 ? '' : 's'}. This can’t be undone.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('Continue'),
            ),
          ],
        ),
      );
      if (confirmed != true) return;
    }
    setState(() => _busy = true);
    final fixed = await LibraryDoctor(widget.repository).repairAll(defects);
    if (!mounted) return;
    await _scan();
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text('Repaired $fixed item${fixed == 1 ? '' : 's'}')),
    );
  }

  String _bytes(int value) {
    if (value < 1024) return '$value B';
    if (value < 1024 * 1024) return '${(value / 1024).round()} KB';
    if (value < 1024 * 1024 * 1024) {
      return '${(value / (1024 * 1024)).toStringAsFixed(1)} MB';
    }
    return '${(value / (1024 * 1024 * 1024)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final report = _report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            'Checks that every book still has its file and cover, and that no '
            'stray data is left behind. Nothing is changed until you ask.',
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Row(
            children: [
              FilledButton.tonalIcon(
                onPressed: _busy ? null : _scan,
                icon: const Icon(Icons.health_and_safety_outlined),
                label: Text(_busy ? 'Checking…' : 'Check library'),
              ),
              if (_busy)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: TextButton(
                    onPressed: () => setState(() => _cancelRequested = true),
                    child: const Text('Stop'),
                  ),
                ),
            ],
          ),
        ),
        if (report != null && report.isHealthy)
          const Padding(
            padding: EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                Icon(Icons.check_circle_outline, size: 18),
                SizedBox(width: 8),
                Text('Everything checks out.'),
              ],
            ),
          ),
        if (report != null && !report.isHealthy)
          for (final entry in report.counts.entries)
            ListTile(
              dense: true,
              title: Text(entry.key.label),
              subtitle: Text(entry.key == DefectKind.orphanBlob
                  ? '${entry.value} · ${_bytes(report.reclaimableBytes)} to reclaim'
                  : '${entry.value} found · ${entry.key.repairLabel}'),
              trailing: TextButton(
                onPressed: _busy
                    ? null
                    : () => _repair(entry.key, report.of(entry.key)),
                child: const Text('Repair'),
              ),
            ),
      ],
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
    required this.settings,
  });

  final LibraryRepository repository;
  final ServerConnection connection;
  final SyncService sync;
  final AppSettingsStore settings;

  @override
  State<_BackupSection> createState() => _BackupSectionState();
}

class _BackupSectionState extends State<_BackupSection> {
  bool _busy = false;

  static String _suggestedName({bool encrypted = false}) {
    final now = DateTime.now();
    final d = '${now.year}'
        '${now.month.toString().padLeft(2, '0')}'
        '${now.day.toString().padLeft(2, '0')}';
    return 'vellum-backup-$d.${encrypted ? 'vbk' : 'zip'}';
  }

  /// Asks for a passphrase, twice, or returns null if the user opts out.
  ///
  /// Two fields and a blunt warning, because there is no recovery path: nothing
  /// about the passphrase is stored, so a typo in the only copy of it turns the
  /// backup into noise. Returning an empty string means "no encryption".
  Future<String?> _askPassphrase() async {
    final first = TextEditingController();
    final second = TextEditingController();
    String? error;
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: const Text('Encrypt this backup?'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'A backup holds your whole library, including your private '
                  'reader notes. Encrypting it means only someone with the '
                  'passphrase can read it.\n\n'
                  'Vellum does not store the passphrase anywhere. If you lose '
                  'it, the backup is gone — there is no recovery.\n\n'
                  'Encrypting is real work for the processor, so a large '
                  'library takes noticeably longer to export than a plain zip.',
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: first,
                  autofocus: true,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Passphrase'),
                ),
                TextField(
                  controller: second,
                  obscureText: true,
                  decoration: const InputDecoration(labelText: 'Repeat it'),
                ),
                if (error != null) ...[
                  const SizedBox(height: 8),
                  Text(error!,
                      style: TextStyle(
                          color: Theme.of(dialogContext).colorScheme.error)),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(''),
              child: const Text('No, plain .zip'),
            ),
            FilledButton(
              onPressed: () {
                if (first.text.isEmpty) {
                  setLocal(() => error = 'Enter a passphrase, or choose plain.');
                  return;
                }
                if (first.text != second.text) {
                  setLocal(() => error = 'Those two do not match.');
                  return;
                }
                Navigator.of(dialogContext).pop(first.text);
              },
              child: const Text('Encrypt'),
            ),
          ],
        ),
      ),
    );
    first.dispose();
    second.dispose();
    return result;
  }

  /// Asks for the passphrase of an existing archive.
  Future<String?> _promptExistingPassphrase() async {
    final controller = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('This backup is encrypted'),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: const InputDecoration(labelText: 'Passphrase'),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: const Text('Open'),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  /// Checks an archive without restoring it (plan 5 #13).
  Future<void> _verify() async {
    const group = XTypeGroup(
      label: 'Vellum backup',
      extensions: ['zip', 'vbk'],
    );
    final picked = await openFile(acceptedTypeGroups: const [group]);
    if (picked == null || !mounted) return;
    final file = File(picked.path);
    String? passphrase;
    if (await BackupCrypto.isEncrypted(file)) {
      if (!mounted) return;
      passphrase = await _promptExistingPassphrase();
      if (passphrase == null || !mounted) return;
    }
    setState(() => _busy = true);
    try {
      final check =
          await BackupService(widget.repository).verify(file, passphrase: passphrase);
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(check.ok ? 'Backup checks out' : 'Backup has problems'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.describe()),
                if (check.created != null) ...[
                  const SizedBox(height: 8),
                  Text('Written ${check.created!.toLocal()}'),
                ],
                for (final name in [...check.corrupt, ...check.missing].take(10))
                  Text('• $name'),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Close'),
            ),
          ],
        ),
      );
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _export() async {
    // file_selector can't offer a save location on Android/iOS, so on mobile we
    // write the archive to a temp file and hand it to the system share sheet
    // (save to Downloads/Drive/…). Desktop keeps the native save dialog.
    final passphrase = await _askPassphrase();
    if (passphrase == null || !mounted) return; // cancelled
    final encrypted = passphrase.isNotEmpty;

    final isMobile = defaultTargetPlatform == TargetPlatform.android ||
        defaultTargetPlatform == TargetPlatform.iOS;
    if (isMobile) {
      await _exportViaShare(passphrase);
      return;
    }
    final location = await getSaveLocation(
      suggestedName: _suggestedName(encrypted: encrypted),
      acceptedTypeGroups: [
        XTypeGroup(
          label: encrypted ? 'Encrypted Vellum backup' : 'Zip archive',
          extensions: [encrypted ? 'vbk' : 'zip'],
        ),
      ],
    );
    if (location == null || !mounted) return;
    setState(() => _busy = true);
    try {
      await BackupService(widget.repository)
          .exportTo(File(location.path), passphrase: passphrase);
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

  Future<void> _exportViaShare(String passphrase) async {
    setState(() => _busy = true);
    try {
      final encrypted = passphrase.isNotEmpty;
      final tmp = File(p.join((await getTemporaryDirectory()).path,
          _suggestedName(encrypted: encrypted)));
      await BackupService(widget.repository)
          .exportTo(tmp, passphrase: passphrase);
      await SharePlus.instance.share(ShareParams(
        files: [
          XFile(tmp.path,
              mimeType:
                  encrypted ? 'application/octet-stream' : 'application/zip'),
        ],
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
    const group =
        XTypeGroup(label: 'Vellum backup', extensions: ['zip', 'vbk']);
    final picked = await openFile(acceptedTypeGroups: const [group]);
    if (picked == null || !mounted) return;
    String? passphrase;
    if (await BackupCrypto.isEncrypted(File(picked.path))) {
      if (!mounted) return;
      passphrase = await _promptExistingPassphrase();
      // An empty passphrase would fail below anyway; treat it as a cancel so
      // the confirm dialog isn't shown for a restore that cannot happen.
      if (passphrase == null || passphrase.isEmpty) return;
    }
    if (!mounted) return;
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
      final ok = await BackupService(widget.repository)
          .restoreFrom(File(picked.path), passphrase: passphrase);
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
          leading: const Icon(Icons.fact_check_outlined),
          title: const Text('Verify a backup…'),
          subtitle: const Text(
              'Re-checks every file against its checksum, without restoring'),
          enabled: !_busy,
          onTap: _verify,
        ),
        ListTile(
          leading: const Icon(Icons.unarchive_outlined),
          title: const Text('Restore from backup…'),
          subtitle: const Text('Replaces the current library, then restarts'),
          enabled: !_busy,
          onTap: _restore,
        ),
        _ScheduledBackupTile(settings: widget.settings),
      ],
    );
  }
}

/// Unattended backups (plan 5 #13): how often, where, and how many to keep.
///
/// Desktop only, and shown as unavailable elsewhere rather than hidden: on
/// Android there is no folder to write to without a picker and no moment to run
/// in, so promising a schedule there would be promising something that doesn't
/// happen.
class _ScheduledBackupTile extends StatefulWidget {
  const _ScheduledBackupTile({required this.settings});

  final AppSettingsStore settings;

  @override
  State<_ScheduledBackupTile> createState() => _ScheduledBackupTileState();
}

class _ScheduledBackupTileState extends State<_ScheduledBackupTile> {
  bool get _supported =>
      defaultTargetPlatform != TargetPlatform.android &&
      defaultTargetPlatform != TargetPlatform.iOS;

  Future<void> _pickFolder() async {
    final path = await getDirectoryPath();
    if (path == null) return;
    await widget.settings.setBackupFolder(path);
  }

  @override
  Widget build(BuildContext context) {
    final settings = widget.settings;
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final frequency = BackupFrequency.parse(settings.backupFrequency);
        final last = settings.lastBackupAt;
        return ExpansionTile(
          leading: const Icon(Icons.schedule),
          title: const Text('Scheduled backups'),
          subtitle: Text(
            !_supported
                ? 'Desktop only'
                : frequency == BackupFrequency.off
                    ? 'Off'
                    : '${frequency.label}, keeping ${settings.backupKeep}'
                        '${last == null ? '' : ' · last ${last.toLocal()}'}',
          ),
          children: [
            if (!_supported)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(
                  'A phone has no folder to write to unattended and no moment '
                  'to run in. Use “Export library…” and save it wherever you '
                  'keep things.',
                ),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  'Runs when Vellum starts, if the last backup is older than '
                  'the interval — no background service. Scheduled archives '
                  'are plain .zip: encrypting them would mean storing the '
                  'passphrase, which is the same as not encrypting them.',
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    const Text('How often'),
                    const Spacer(),
                    DropdownButton<BackupFrequency>(
                      value: frequency,
                      onChanged: (value) => value == null
                          ? null
                          : settings.setBackupFrequency(value.key),
                      items: [
                        for (final option in BackupFrequency.values)
                          DropdownMenuItem(
                            value: option,
                            child: Text(option.label),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              ListTile(
                title: const Text('Folder'),
                subtitle: Text(settings.backupFolder ?? 'Not chosen yet'),
                trailing: const Icon(Icons.folder_open),
                onTap: _pickFolder,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    const Text('Keep'),
                    const Spacer(),
                    DropdownButton<int>(
                      value: settings.backupKeep,
                      onChanged: (value) =>
                          value == null ? null : settings.setBackupKeep(value),
                      items: [
                        for (final n in [1, 3, 5, 10, 20])
                          DropdownMenuItem(value: n, child: Text('$n')),
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ],
        );
      },
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

/// The way into the trash (plan 5 #52), with a live count so a library with
/// nothing waiting says so rather than making you open an empty page.
class _TrashTile extends StatelessWidget {
  const _TrashTile({required this.repository});

  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: repository.trash.watchTrashCount(),
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        return ListTile(
          leading: const Icon(Icons.delete_outline),
          title: const Text('Trash'),
          subtitle: Text(count == 0
              ? 'Nothing waiting to be deleted'
              : '$count book${count == 1 ? '' : 's'}, deleted for good after '
                  '${TrashService.graceperiod.inDays} days'),
          trailing: const Icon(Icons.chevron_right),
          onTap: () => Navigator.of(context).push(
            MaterialPageRoute(
              builder: (_) => TrashPage(repository: repository),
            ),
          ),
        );
      },
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
