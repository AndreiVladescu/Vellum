import 'dart:io';
import '../widgets/page_insets.dart';
import '../snack_bars.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/backup_crypto.dart';
import '../diagnostics/diagnostics_collector.dart';
import '../diagnostics/diagnostics_report.dart';
import '../data/backup_schedule.dart';
import '../data/backup_service.dart';
import '../data/library_doctor.dart';
import '../data/library_repository.dart';
import '../data/local_text_index.dart';
import '../server/background_sync.dart';
import '../server/connection_store.dart';
import '../server/sync_service.dart';
import 'app_settings.dart';
import 'appearance.dart';
import 'book_face.dart';
import 'spine_art.dart';
import '../loans/loan_reminders.dart';
import '../notifications/tray.dart';
import 'shared_shelves_page.dart';
import 'trash_page.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/labels.dart';
import '../onboarding/sample_library.dart';
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
      appBar: AppBar(title: Text(L10n.of(context).prefsTitle)),
      body: ListenableBuilder(
        listenable: settings,
        builder: (context, _) {
          final l10n = L10n.of(context);
          return ListView(
          padding: pageInsets(context, EdgeInsets.symmetric(vertical: 8)),
          children: [
            _SectionHeader(l10n.prefsSectionAppearance),
            _AppearanceSection(settings: settings),
            const Divider(height: 24),
            _SectionHeader(l10n.prefsSectionBooks),
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
              child: SegmentedButton<BookFace>(
                segments: [
                  for (final face in BookFace.values)
                    ButtonSegment(
                      value: face,
                      label: Text(face.labelOf(l10n)),
                      icon: Icon(face.icon),
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
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
                child: Text(l10n.prefsSpineArtLabel),
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
                child: SegmentedButton<SpineArt>(
                  segments: [
                    for (final art in SpineArt.values)
                      ButtonSegment(
                        value: art,
                        label: Text(art.labelOf(l10n)),
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
            _SectionHeader(l10n.prefsSectionWallpaper),
            for (final wallpaper in Wallpaper.values)
              _WallpaperTile(
                wallpaper: wallpaper,
                selected: settings.wallpaper == wallpaper,
                onTap: () => settings.setWallpaper(wallpaper),
              ),
            const Divider(height: 24),
            _SectionHeader(l10n.prefsSectionGenres),
            SwitchListTile(
              secondary: const Icon(Icons.sell_outlined),
              title: Text(l10n.prefsGenresImportTitle),
              subtitle: Text(l10n.prefsGenresImportSubtitle),
              value: settings.importOpenLibraryGenres,
              onChanged: settings.setImportOpenLibraryGenres,
            ),
            if (textIndexSupportedHere) ...[
              const Divider(height: 24),
              _SectionHeader(l10n.prefsSectionSearch),
              _ContentIndexSection(
                repository: repository,
                settings: settings,
              ),
            ],
            const Divider(height: 24),
            _SectionHeader(l10n.prefsSectionSync),
            SwitchListTile(
              secondary: const Icon(Icons.cloud_sync_outlined),
              title: Text(l10n.prefsAutoPushTitle),
              subtitle: Text(l10n.prefsAutoPushSubtitle),
              value: settings.autoPush,
              onChanged: settings.setAutoPush,
            ),
            _ReadingPositionSwitch(
              settings: settings,
              repository: repository,
              connection: connection,
            ),
            _BackgroundSyncTile(settings: settings),
            _TrayNotificationsTile(settings: settings),
            _LoanRemindersTile(settings: settings),
            // Only meaningful on a shared library: with no server there is
            // nobody else whose shelves could arrive.
            if (connection.isConnected)
              ListTile(
                leading: const Icon(Icons.shelves),
                title: Text(l10n.prefsSharedShelvesTitle),
                subtitle: Text(l10n.prefsSharedShelvesSubtitle),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => Navigator.of(context).push(
                  MaterialPageRoute<void>(
                    builder: (_) => SharedShelvesPage(
                      repository: repository,
                      settings: settings,
                      connection: connection,
                    ),
                  ),
                ),
              ),
            const Divider(height: 24),
            _SectionHeader(l10n.prefsSectionSamples),
            _SamplesTile(repository: repository),
            const Divider(height: 24),
            _SectionHeader(l10n.prefsSectionTrash),
            _TrashTile(repository: repository),
            const Divider(height: 24),
            _SectionHeader(l10n.prefsSectionHealth),
            _HealthSection(repository: repository, connection: connection),
            _DiagnosticsTile(repository: repository, connection: connection),
            const Divider(height: 24),
            _SectionHeader(l10n.prefsSectionBackup),
            _BackupSection(
              repository: repository,
              connection: connection,
              sync: sync,
              settings: settings,
            ),
            const Divider(height: 24),
            _SectionHeader(l10n.prefsSectionDanger),
            _ClearLibraryTile(repository: repository),
          ],
          );
        },
      ),
    );
  }
}

/// The on-device index of book *text*, so search can look inside books and not
/// only at their catalogue entry.
///
/// Opt-in, and shown only where it can run — see `local_text_index.dart`. The
/// counts are the honest state of the queue rather than a progress bar: some
/// files legitimately never index (a scanned PDF has no text), and a bar that
/// never reaches the end would misrepresent that as a stall.
class _ContentIndexSection extends StatefulWidget {
  const _ContentIndexSection({
    required this.repository,
    required this.settings,
  });

  final LibraryRepository repository;
  final AppSettingsStore settings;

  @override
  State<_ContentIndexSection> createState() => _ContentIndexSectionState();
}

class _ContentIndexSectionState extends State<_ContentIndexSection> {
  Map<String, int> _counts = const {};
  bool _busy = false;

  LocalTextIndex get _index => LocalTextIndex(
        widget.repository.db,
        dataDir: widget.repository.dataDir,
      );

  @override
  void initState() {
    super.initState();
    _refresh();
  }

  Future<void> _refresh() async {
    final counts = await _index.statusCounts();
    if (mounted) setState(() => _counts = counts);
  }

  /// Works through the queue in bounded batches, reporting after each, so a
  /// library that takes minutes shows progress instead of freezing.
  Future<void> _indexNow() async {
    setState(() => _busy = true);
    final index = _index;
    await index.enqueueMissing();
    while (mounted) {
      final done = await index.processPending(limit: 5);
      await _refresh();
      if (done == 0) break;
    }
    if (mounted) setState(() => _busy = false);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final pending = _counts['pending'] ?? 0;
    final ok = _counts['ok'] ?? 0;
    final noText = _counts['no_text'] ?? 0;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        SwitchListTile(
          secondary: const Icon(Icons.manage_search_outlined),
          title: Text(l10n.prefsIndexTitle),
          subtitle: Text(l10n.prefsIndexSubtitle),
          value: widget.settings.indexBookText,
          onChanged: (on) async {
            await widget.settings.setIndexBookText(on);
            if (on) await _indexNow();
            if (mounted) setState(() {});
          },
        ),
        if (widget.settings.indexBookText)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  // Named rather than hidden: a scanned book is not a failure,
                  // and someone wondering why it never turns up in results
                  // deserves to see that it has no text to search.
                  [
                    l10n.prefsIndexedCount(ok),
                    if (pending > 0) l10n.prefsIndexWaitingCount(pending),
                    if (noText > 0) l10n.prefsIndexNoTextCount(noText),
                  ].join(', '),
                  style: theme.textTheme.bodySmall,
                ),
                const SizedBox(height: 8),
                Wrap(
                  spacing: 8,
                  children: [
                    FilledButton.tonal(
                      onPressed: _busy ? null : _indexNow,
                      child: Text(_busy ? l10n.prefsIndexing : l10n.prefsIndexNow),
                    ),
                    TextButton(
                      onPressed: _busy
                          ? null
                          : () async {
                              await _index.reindexAll();
                              await _indexNow();
                            },
                      child: Text(l10n.prefsIndexRebuild),
                    ),
                  ],
                ),
              ],
            ),
          ),
      ],
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
    final l10n = L10n.of(context);
    if (kind.isDestructive) {
      final confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          title: Text(kind.labelOf(l10n)),
          content: Text(
              l10n.prefsRepairConfirmBody(kind.repairLabelOf(l10n), defects.length)),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: Text(l10n.prefsContinue),
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
      SnackBar(content: Text(l10n.prefsRepaired(fixed))),
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
    final l10n = L10n.of(context);
    final report = _report;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16),
          child: Text(
            l10n.prefsHealthIntro,
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
                label: Text(_busy ? l10n.prefsHealthChecking : l10n.prefsHealthCheck),
              ),
              if (_busy)
                Padding(
                  padding: const EdgeInsets.only(left: 8),
                  child: TextButton(
                    onPressed: () => setState(() => _cancelRequested = true),
                    child: Text(l10n.prefsHealthStop),
                  ),
                ),
            ],
          ),
        ),
        if (report != null && report.isHealthy)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
            child: Row(
              children: [
                const Icon(Icons.check_circle_outline, size: 18),
                const SizedBox(width: 8),
                Text(l10n.prefsHealthAllGood),
              ],
            ),
          ),
        if (report != null)
          for (final entry in report.repairableCounts.entries)
            ListTile(
              dense: true,
              title: Text(entry.key.labelOf(l10n)),
              subtitle: Text(entry.key == DefectKind.orphanBlob
                  ? l10n.prefsHealthReclaim(
                      entry.value, _bytes(report.reclaimableBytes))
                  : l10n.prefsHealthFound(
                      entry.value, entry.key.repairLabelOf(l10n))),
              trailing: TextButton(
                onPressed: _busy
                    ? null
                    : () => _repair(entry.key, report.of(entry.key)),
                child: Text(l10n.prefsHealthRepair),
              ),
            ),
        // Kept below, and under its own heading, because these are not damage:
        // a book with no year is untidy, not broken, and mixing the two would
        // make a perfectly sound library look faulty every time it is scanned.
        if (report != null && report.adviceCounts.isNotEmpty) ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 0),
            child: Text(l10n.prefsHealthAdviceHeader),
          ),
          for (final entry in report.adviceCounts.entries)
            ListTile(
              dense: true,
              title: Text(entry.key.labelOf(l10n)),
              // No button: which of two near-identical books to keep, or what
              // the missing author is called, is not something the app can
              // answer, and an inert "Repair" is worse than none.
              subtitle: Text(
                  l10n.prefsHealthAdviceRow(entry.value, entry.key.repairLabelOf(l10n))),
            ),
        ],
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
/// "Copy diagnostics": a short report for a bug report — versions, counts and
/// recent errors, never titles, paths or the server address. The text is built
/// by [buildDiagnosticsReport]; this only collects, shows and copies it.
class _DiagnosticsTile extends StatelessWidget {
  const _DiagnosticsTile({required this.repository, required this.connection});

  final LibraryRepository repository;
  final ServerConnection connection;

  // The context is only read for screen size and text scale, which the
  // collector does before its first await.
  Future<String> _build(BuildContext context) async => buildDiagnosticsReport(
    await collectDiagnostics(
      context,
      repository: repository,
      connection: connection,
    ),
  );

  Future<void> _copy(BuildContext context, String text) async {
    await Clipboard.setData(ClipboardData(text: text));
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      appSnackBar(content: Text(L10n.of(context).prefsDiagCopied)),
    );
  }

  Future<void> _copyNow(BuildContext context) async {
    final text = await _build(context);
    if (!context.mounted) return;
    await _copy(context, text);
  }

  Future<void> _preview(BuildContext context) async {
    final text = await _build(context);
    if (!context.mounted) return;
    await showDialog<void>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.of(context).prefsDiagTitle),
        content: SizedBox(
          width: 560,
          child: SingleChildScrollView(
            child: SelectableText(
              text,
              style: const TextStyle(fontFamily: 'monospace', fontSize: 12),
            ),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(L10n.of(context).prefsClose),
          ),
          FilledButton(
            onPressed: () async {
              Navigator.pop(dialogContext);
              await _copy(context, text);
            },
            child: Text(L10n.of(context).prefsCopy),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Text(
            l10n.prefsDiagIntro,
            style: Theme.of(context).textTheme.bodySmall,
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 0),
          child: Wrap(
            spacing: 8,
            children: [
              FilledButton.tonalIcon(
                onPressed: () => _copyNow(context),
                icon: const Icon(Icons.copy_outlined),
                label: Text(l10n.prefsDiagCopyButton),
              ),
              TextButton(
                onPressed: () => _preview(context),
                child: Text(l10n.prefsDiagShow),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

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
      SnackBar(
        content: Text(L10n.of(context).prefsReadingPositionOffFailed),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: const Icon(Icons.auto_stories_outlined),
      title: Text(L10n.of(context).prefsReadingPositionTitle),
      subtitle: Text(
        L10n.of(context)
            .prefsReadingPositionSubtitle(widget.settings.deviceLabel),
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
    final l10n = L10n.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (dialogContext, setLocal) => AlertDialog(
          title: Text(l10n.prefsEncryptTitle),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(l10n.prefsEncryptBody),
                const SizedBox(height: 12),
                TextField(
                  controller: first,
                  autofocus: true,
                  obscureText: true,
                  decoration:
                      InputDecoration(labelText: l10n.prefsPassphraseLabel),
                ),
                TextField(
                  controller: second,
                  obscureText: true,
                  decoration:
                      InputDecoration(labelText: l10n.prefsPassphraseRepeatLabel),
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
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(''),
              child: Text(l10n.prefsEncryptPlain),
            ),
            FilledButton(
              onPressed: () {
                if (first.text.isEmpty) {
                  setLocal(() => error = l10n.prefsPassphraseMissing);
                  return;
                }
                if (first.text != second.text) {
                  setLocal(() => error = l10n.prefsPassphraseMismatch);
                  return;
                }
                Navigator.of(dialogContext).pop(first.text);
              },
              child: Text(l10n.prefsEncryptAction),
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
    final l10n = L10n.of(context);
    final result = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.prefsBackupEncryptedTitle),
        content: TextField(
          controller: controller,
          autofocus: true,
          obscureText: true,
          decoration: InputDecoration(labelText: l10n.prefsPassphraseLabel),
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(controller.text),
            child: Text(l10n.prefsOpen),
          ),
        ],
      ),
    );
    controller.dispose();
    return result;
  }

  /// Checks an archive without restoring it (plan 5 #13).
  Future<void> _verify() async {
    final l10n = L10n.of(context);
    final group = XTypeGroup(
      label: l10n.prefsBackupTypeGroup,
      extensions: const ['zip', 'vbk'],
    );
    final picked = await openFile(acceptedTypeGroups: [group]);
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
          title: Text(check.ok ? l10n.prefsVerifyOk : l10n.prefsVerifyProblems),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(check.describeOf(l10n)),
                if (check.created != null) ...[
                  const SizedBox(height: 8),
                  Text(l10n.prefsVerifyWritten('${check.created!.toLocal()}')),
                ],
                for (final name in [...check.corrupt, ...check.missing].take(10))
                  Text('• $name'), // i18n-ignore
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: Text(l10n.prefsClose),
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
    final l10n = L10n.of(context);
    final location = await getSaveLocation(
      suggestedName: _suggestedName(encrypted: encrypted),
      acceptedTypeGroups: [
        XTypeGroup(
          label: encrypted
              ? l10n.prefsBackupTypeEncrypted
              : l10n.prefsBackupTypeZip,
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
          SnackBar(content: Text(l10n.prefsBackupSaved(location.path))),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.prefsBackupFailed('$e'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _exportViaShare(String passphrase) async {
    final l10n = L10n.of(context);
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
        subject: l10n.prefsBackupTypeGroup,
      ));
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(l10n.prefsBackupFailed('$e'))));
      }
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _restore() async {
    final l10n = L10n.of(context);
    // A restore closes the database; doing that under a live launch/manual sync
    // would throw mid-transaction. Export is safe (VACUUM INTO is a snapshot).
    if (widget.sync.isRunning) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text(l10n.prefsRestoreWaitSync)),
      );
      return;
    }
    final group = XTypeGroup(
        label: l10n.prefsBackupTypeGroup, extensions: const ['zip', 'vbk']);
    final picked = await openFile(acceptedTypeGroups: [group]);
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
        title: Text(l10n.prefsRestoreTitle),
        content: Text(l10n.prefsRestoreBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: Text(l10n.prefsRestoreReplace),
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
            SnackBar(content: Text(l10n.prefsRestoreNotBackup)),
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
            title: Text(l10n.prefsRestoreFailedTitle),
            content: Text(l10n.prefsRestoreFailedBody('$e')),
            actions: [
              FilledButton(
                onPressed: () => exit(0),
                child: Text(l10n.prefsRestoreCloseApp),
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
    final l10n = L10n.of(context);
    return Column(
      children: [
        ListTile(
          leading: const Icon(Icons.archive_outlined),
          title: Text(l10n.prefsExportTitle),
          subtitle: Text(l10n.prefsExportSubtitle),
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
          title: Text(l10n.prefsVerifyTitle),
          subtitle: Text(l10n.prefsVerifySubtitle),
          enabled: !_busy,
          onTap: _verify,
        ),
        ListTile(
          leading: const Icon(Icons.unarchive_outlined),
          title: Text(l10n.prefsRestoreTile),
          subtitle: Text(l10n.prefsRestoreTileSubtitle),
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
/// Borrowing news in the Android status bar.
///
/// Off by default and shown as unavailable elsewhere, same as background sync
/// and for the same reason: a switch that silently does nothing on your
/// platform is worse than one that says so.
///
/// **Turning it on asks Android for permission, and stays off if refused.** A
/// switch that reads "on" while the system is dropping every notification is a
/// lie the app tells itself; and the check rides the background sync, so
/// enabling it without a schedule sets a daily one rather than quietly never
/// running.
class _TrayNotificationsTile extends StatefulWidget {
  const _TrayNotificationsTile({required this.settings});

  final AppSettingsStore settings;

  @override
  State<_TrayNotificationsTile> createState() => _TrayNotificationsTileState();
}

class _TrayNotificationsTileState extends State<_TrayNotificationsTile> {
  bool _busy = false;

  bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  Future<void> _toggle(bool wanted) async {
    if (!wanted) {
      await widget.settings.setTrayNotifications(false);
      await NotificationTray().clear();
      return;
    }
    setState(() => _busy = true);
    final granted = await NotificationTray().requestPermission();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L10n.of(context).prefsTrayDenied),
      ));
      return;
    }
    await widget.settings.setTrayNotifications(true);

    // The check runs inside the background sync, so without a schedule there
    // would be nothing to run it. Daily is the gentlest one on offer.
    if (BackgroundSyncInterval.parse(widget.settings.backgroundSyncInterval) ==
        BackgroundSyncInterval.off) {
      await widget.settings
          .setBackgroundSyncInterval(BackgroundSyncInterval.daily.key);
      await applySchedule(BackgroundSyncPolicy(
        interval: BackgroundSyncInterval.daily,
        hasServer: true,
        isAndroid: true,
      ));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L10n.of(context).prefsTrayDailySet),
      ));
    }
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: _busy
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.notifications_active_outlined),
      title: Text(L10n.of(context).prefsTrayTitle),
      subtitle: Text(_supported
          ? L10n.of(context).prefsTraySubtitle
          : L10n.of(context).prefsTrayUnavailable),
      value: _supported && widget.settings.trayNotifications,
      onChanged: _supported && !_busy ? _toggle : null,
    );
  }
}

/// System notifications for loan due dates (roadmap v1.4.2).
///
/// Off by default; turning it on asks for the Android notification permission
/// and stays off if refused, for the same reason as the tile above. The
/// scheduling itself is `LoanReminderService`, which reacts to this setting.
class _LoanRemindersTile extends StatefulWidget {
  const _LoanRemindersTile({required this.settings});

  final AppSettingsStore settings;

  @override
  State<_LoanRemindersTile> createState() => _LoanRemindersTileState();
}

class _LoanRemindersTileState extends State<_LoanRemindersTile> {
  bool _busy = false;

  bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  Future<void> _toggle(bool wanted) async {
    if (!wanted) {
      await widget.settings.setLoanReminders(false);
      return;
    }
    setState(() => _busy = true);
    final granted = await LocalReminderNotifier().requestPermission();
    if (!mounted) return;
    setState(() => _busy = false);
    if (!granted) {
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text(L10n.of(context).prefsLoanRemindDenied),
      ));
      return;
    }
    await widget.settings.setLoanReminders(true);
  }

  @override
  Widget build(BuildContext context) {
    return SwitchListTile(
      secondary: _busy
          ? const SizedBox(
              width: 18, height: 18,
              child: CircularProgressIndicator(strokeWidth: 2))
          : const Icon(Icons.event_available_outlined),
      title: Text(L10n.of(context).prefsLoanRemindTitle),
      subtitle: Text(_supported
          ? L10n.of(context).prefsLoanRemindSubtitle
          : L10n.of(context).prefsLoanRemindUnavailable),
      value: _supported && widget.settings.loanReminders,
      onChanged: _supported && !_busy ? _toggle : null,
    );
  }
}

/// Background sync on Android (plan 5 #40).
///
/// Off by default, Wi-Fi and charging only, and shown as unavailable elsewhere
/// rather than hidden — a setting that silently does nothing on your platform is
/// worse than one that says so.
class _BackgroundSyncTile extends StatelessWidget {
  const _BackgroundSyncTile({required this.settings});

  final AppSettingsStore settings;

  bool get _supported => defaultTargetPlatform == TargetPlatform.android;

  @override
  Widget build(BuildContext context) {
    final interval =
        BackgroundSyncInterval.parse(settings.backgroundSyncInterval);
    final last = settings.lastBackgroundSyncAt;
    final l10n = L10n.of(context);
    return ExpansionTile(
      leading: const Icon(Icons.schedule_send_outlined),
      title: Text(l10n.prefsBgTitle),
      subtitle: Text(
        !_supported
            ? l10n.prefsAndroidOnly
            : interval == BackgroundSyncInterval.off
                ? l10n.prefsOff
                : last == null
                    ? interval.labelOf(l10n)
                    : l10n.prefsIntervalLast(
                        interval.labelOf(l10n), '${last.toLocal()}'),
      ),
      children: [
        if (!_supported)
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
            child: Text(l10n.prefsBgDesktopNote),
          )
        else ...[
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
            child: Text(
              l10n.prefsBgConditions,
              style: Theme.of(context).textTheme.bodySmall,
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                Text(l10n.prefsHowOften),
                const Spacer(),
                DropdownButton<BackgroundSyncInterval>(
                  value: interval,
                  onChanged: (value) async {
                    if (value == null) return;
                    await settings.setBackgroundSyncInterval(value.key);
                    // Applied immediately rather than at the next launch: a
                    // setting that takes effect "sometime later" is one people
                    // stop trusting.
                    await applySchedule(policyFrom(
                      settings,
                      hasServer: true,
                      isAndroid: true,
                    ));
                  },
                  items: [
                    for (final option in BackgroundSyncInterval.values)
                      DropdownMenuItem(
                        value: option,
                        child: Text(option.labelOf(l10n)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 8),
        ],
      ],
    );
  }
}

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
        final l10n = L10n.of(context);
        return ExpansionTile(
          leading: const Icon(Icons.schedule),
          title: Text(l10n.prefsSchedTitle),
          subtitle: Text(
            !_supported
                ? l10n.prefsDesktopOnly
                : frequency == BackupFrequency.off
                    ? l10n.prefsOff
                    : last == null
                        ? l10n.prefsSchedSummary(
                            frequency.labelOf(l10n), settings.backupKeep)
                        : l10n.prefsSchedSummaryLast(frequency.labelOf(l10n),
                            settings.backupKeep, '${last.toLocal()}'),
          ),
          children: [
            if (!_supported)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Text(l10n.prefsSchedPhoneNote),
              )
            else ...[
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Text(
                  l10n.prefsSchedHow,
                  style: Theme.of(context).textTheme.bodySmall,
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    Text(l10n.prefsHowOften),
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
                            child: Text(option.labelOf(l10n)),
                          ),
                      ],
                    ),
                  ],
                ),
              ),
              ListTile(
                title: Text(l10n.prefsFolder),
                subtitle: Text(settings.backupFolder ?? l10n.prefsFolderNone),
                trailing: const Icon(Icons.folder_open),
                onTap: _pickFolder,
              ),
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 12),
                child: Row(
                  children: [
                    Text(l10n.prefsKeep),
                    const Spacer(),
                    DropdownButton<int>(
                      value: settings.backupKeep,
                      onChanged: (value) =>
                          value == null ? null : settings.setBackupKeep(value),
                      items: [
                        for (final n in [1, 3, 5, 10, 20])
                          DropdownMenuItem(value: n, child: Text('$n')), // i18n-ignore
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

/// Theme mode, seed colour, shelf material and spine size (plan 5 #39).
///
/// Grouped into one section because they are one decision — "what does my
/// library look like" — taken in four parts, and splitting them across the page
/// would make each feel like an unrelated switch.
class _AppearanceSection extends StatelessWidget {
  const _AppearanceSection({required this.settings});

  final AppSettingsStore settings;

  Future<void> _pickCustomSeed(BuildContext context) async {
    // A grid of usable colours rather than a colour wheel: an arbitrary hue at
    // arbitrary saturation makes a poor Material scheme, and every swatch here
    // is one we know seeds cleanly.
    const swatches = [
      Color(0xFF7A5C3E), Color(0xFF9C5B3A), Color(0xFFA8482C),
      Color(0xFF8C3A4E), Color(0xFF7A3E63), Color(0xFF5A4A8C),
      Color(0xFF3B4C8F), Color(0xFF2E6E8E), Color(0xFF2E7D7B),
      Color(0xFF3C6B4B), Color(0xFF5E7A3C), Color(0xFF56626D),
    ];
    final picked = await showDialog<Color>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(L10n.of(context).prefsCustomColourTitle),
        content: SizedBox(
          width: 280,
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final colour in swatches)
                InkWell(
                  onTap: () => Navigator.pop(dialogContext, colour),
                  customBorder: const CircleBorder(),
                  child: Semantics(
                    label: L10n.of(context).prefsSeedSwatch,
                    button: true,
                    child: Container(
                      width: 48,
                      height: 48,
                      decoration: BoxDecoration(
                        color: colour,
                        shape: BoxShape.circle,
                        border: Border.all(
                          color: Theme.of(dialogContext).colorScheme.outline,
                        ),
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(L10n.of(context).cancel),
          ),
        ],
      ),
    );
    if (picked != null) await settings.setCustomSeed(picked);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final typography = settings.spineTypography;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 4, 16, 8),
          child: SegmentedButton<ThemeMode>(
            segments: [
              ButtonSegment(
                value: ThemeMode.system,
                label: Text(l10n.prefsThemeSystem),
                icon: const Icon(Icons.brightness_auto_outlined),
              ),
              ButtonSegment(
                value: ThemeMode.light,
                label: Text(l10n.prefsThemeLight),
                icon: const Icon(Icons.light_mode_outlined),
              ),
              ButtonSegment(
                value: ThemeMode.dark,
                label: Text(l10n.prefsThemeDark),
                icon: const Icon(Icons.dark_mode_outlined),
              ),
            ],
            selected: {settings.themeMode},
            onSelectionChanged: (s) => settings.setThemeMode(s.first),
          ),
        ),
        // Material You supersedes the seed, so say so rather than leaving the
        // picker below looking broken.
        if (defaultTargetPlatform == TargetPlatform.android)
          SwitchListTile(
            secondary: const Icon(Icons.colorize_outlined),
            title: Text(l10n.prefsDynamicColourTitle),
            subtitle: Text(l10n.prefsDynamicColourSubtitle),
            value: settings.useDynamicColor,
            onChanged: settings.setUseDynamicColor,
          ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(l10n.prefsColour, style: theme.textTheme.bodyMedium),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
          child: Wrap(
            spacing: 10,
            runSpacing: 10,
            children: [
              for (final preset in SeedPreset.values)
                _SeedSwatch(
                  color: preset.color,
                  label: preset.labelOf(l10n),
                  selected: settings.seedPreset == preset,
                  onTap: () => settings.setSeedPreset(preset),
                ),
              _SeedSwatch(
                color: settings.seedColor,
                label: l10n.prefsSeedCustom,
                selected: settings.seedPreset == null,
                custom: true,
                onTap: () => _pickCustomSeed(context),
              ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 4),
          child: Text(l10n.prefsShelfMaterial, style: theme.textTheme.bodyMedium),
        ),
        RadioGroup<ShelfMaterial>(
          groupValue: settings.shelfMaterial,
          onChanged: (v) {
            if (v != null) settings.setShelfMaterial(v);
          },
          child: Column(
            children: [
              for (final material in ShelfMaterial.values)
                RadioListTile<ShelfMaterial>(
                  value: material,
                  title: Text(material.labelOf(l10n)),
                  secondary: Container(
                    width: 44,
                    height: 16,
                    decoration:
                        shelfBoardDecoration(material, theme.brightness),
                  ),
                ),
            ],
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
          child: Text(l10n.prefsSpineSize, style: theme.textTheme.bodyMedium),
        ),
        _ScaleSlider(
          label: l10n.prefsSpineTitleScale,
          value: typography.clampedTitle,
          onChanged: (v) => settings.setSpineTypography(
            SpineTypography(titleScale: v, widthScale: typography.widthScale),
          ),
        ),
        _ScaleSlider(
          label: l10n.prefsSpineThickness,
          value: typography.clampedWidth,
          onChanged: (v) => settings.setSpineTypography(
            SpineTypography(titleScale: typography.titleScale, widthScale: v),
          ),
        ),
      ],
    );
  }
}

class _SeedSwatch extends StatelessWidget {
  const _SeedSwatch({
    required this.color,
    required this.label,
    required this.selected,
    required this.onTap,
    this.custom = false,
  });

  final Color color;
  final String label;
  final bool selected;
  final bool custom;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Semantics(
      label: label,
      button: true,
      selected: selected,
      child: Tooltip(
        message: label,
        child: InkWell(
          onTap: onTap,
          customBorder: const CircleBorder(),
          child: Container(
            width: 48,
            height: 48,
            decoration: BoxDecoration(
              color: color,
              shape: BoxShape.circle,
              border: Border.all(
                color: selected
                    ? theme.colorScheme.onSurface
                    : theme.colorScheme.outlineVariant,
                width: selected ? 3 : 1,
              ),
            ),
            child: custom
                ? Icon(
                    Icons.tune,
                    size: 18,
                    color: ThemeData.estimateBrightnessForColor(color) ==
                            Brightness.dark
                        ? Colors.white
                        : Colors.black87,
                  )
                : null,
          ),
        ),
      ),
    );
  }
}

class _ScaleSlider extends StatelessWidget {
  const _ScaleSlider({
    required this.label,
    required this.value,
    required this.onChanged,
  });

  final String label;
  final double value;
  final ValueChanged<double> onChanged;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16),
      child: Row(
        children: [
          SizedBox(width: 80, child: Text(label)),
          Expanded(
            child: Slider(
              min: SpineTypography.min,
              max: SpineTypography.max,
              divisions: 12,
              value: value,
              label: '${(value * 100).round()}%', // i18n-ignore
              onChanged: onChanged,
            ),
          ),
        ],
      ),
    );
  }
}

/// Adds or removes the bundled sample books. The row says what is there and
/// does the one thing that makes sense: remove them if they are on the shelf,
/// add them if not.
class _SamplesTile extends StatefulWidget {
  const _SamplesTile({required this.repository});

  final LibraryRepository repository;

  @override
  State<_SamplesTile> createState() => _SamplesTileState();
}

class _SamplesTileState extends State<_SamplesTile> {
  // Made once: a new stream per build would resubscribe, re-hash the assets and
  // flash the count back to 0 whenever Preferences rebuilds.
  late final SampleLibrary _samples = SampleLibrary(widget.repository);
  late final Stream<int> _count = _samples.watchCount();

  Future<void> _tap(int count) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    if (count == 0) {
      await addSamplesWithFeedback(messenger, l10n, _samples);
      return;
    }
    final ok = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(l10n.prefsSamplesRemoveTitle),
        content: Text(l10n.prefsSamplesRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, true),
            child: Text(l10n.samplesRemoveAction),
          ),
        ],
      ),
    );
    if (ok != true) return;
    try {
      final removed = await _samples.remove();
      messenger.showSnackBar(
          appSnackBar(content: Text(l10n.prefsSamplesRemoved(removed))));
    } catch (e) {
      messenger.showSnackBar(appSnackBar(
          content: Text(l10n.prefsSamplesRemoveFailed('$e'))));
    }
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<int>(
      stream: _count,
      builder: (context, snapshot) {
        final count = snapshot.data ?? 0;
        final l10n = L10n.of(context);
        return ListTile(
          leading: const Icon(Icons.auto_stories_outlined),
          title: Text(count == 0 ? l10n.prefsSamplesAdd : l10n.prefsSamplesRemove),
          subtitle: Text(count == 0
              ? l10n.prefsSamplesAddSubtitle
              : l10n.prefsSamplesRemoveSubtitle(
                  count, SampleLibrary.shelfName)),
          onTap: () => _tap(count),
        );
      },
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
        final l10n = L10n.of(context);
        return ListTile(
          leading: const Icon(Icons.delete_outline),
          title: Text(l10n.prefsTrashTitle),
          subtitle: Text(count == 0
              ? l10n.prefsTrashNone
              : l10n.prefsTrashCount(count, TrashService.graceperiod.inDays)),
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
      title: Text(wallpaper.labelOf(L10n.of(context))),
      trailing: selected
          ? Icon(Icons.check, color: Theme.of(context).colorScheme.primary)
          : null,
    );
  }
}

/// "Move every book to the trash" (next features #1).
///
/// **Scoped to this device on purpose.** It trashes locally and leaves the
/// server alone: that reuses the 30-day grace period, cannot harm anyone the
/// library is shared with, and stays recoverable. The books coming back on the
/// next sync is the honest answer rather than a bug — pressing Sync means you
/// want the library — and the confirmation says so rather than letting it be a
/// surprise.
///
/// The confirmation is a typed word, not a Yes/No. For something that touches
/// every book, a dialog you can dismiss by reflex is not a confirmation.
class _ClearLibraryTile extends StatelessWidget {
  const _ClearLibraryTile({required this.repository});

  final LibraryRepository repository;

  static const _word = 'DELETE';

  Future<void> _run(BuildContext context) async {
    final books = await repository.watchAllBooks().first;
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final l10n = L10n.of(context);
    if (books.isEmpty) {
      messenger.showSnackBar(
        appSnackBar(content: Text(l10n.prefsClearEmpty)),
      );
      return;
    }

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => _ConfirmClearDialog(count: books.length),
    );
    if (confirmed != true || !context.mounted) return;

    for (final book in books) {
      await repository.trashBook(book.id);
    }
    if (!context.mounted) return;
    messenger.showSnackBar(appSnackBar(
      content: Text(l10n.trashedBooks(books.length)),
      // Straight afterwards, because the disk space is the usual reason for
      // doing this at all and a second trip to find it is a poor reward.
      action: SnackBarAction(
        label: l10n.prefsClearEmptyTrash,
        onPressed: () async {
          final trashed = await repository.watchTrashedBooks().first;
          for (final book in trashed) {
            await repository.trash.deleteNow(book);
          }
        },
      ),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(Icons.delete_forever, color: scheme.error),
      title: Text(L10n.of(context).prefsClearTitle,
          style: TextStyle(color: scheme.error)),
      subtitle: Text(L10n.of(context).prefsClearSubtitle),
      onTap: () => _run(context),
    );
  }
}

class _ConfirmClearDialog extends StatefulWidget {
  const _ConfirmClearDialog({required this.count});

  final int count;

  @override
  State<_ConfirmClearDialog> createState() => _ConfirmClearDialogState();
}

class _ConfirmClearDialogState extends State<_ConfirmClearDialog> {
  final _typed = TextEditingController();

  @override
  void dispose() {
    _typed.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final ok = _typed.text.trim().toUpperCase() == _ClearLibraryTile._word;
    return AlertDialog(
      title: Text(l10n.prefsClearDialogTitle(widget.count)),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.prefsClearDialogBody(TrashService.graceperiod.inDays)),
          const SizedBox(height: 12),
          Text(l10n.prefsClearDialogDiskNote),
          const SizedBox(height: 16),
          TextField(
            controller: _typed,
            autofocus: true,
            onChanged: (_) => setState(() {}),
            decoration: InputDecoration(
              labelText: l10n.prefsClearTypeToConfirm(_ClearLibraryTile._word),
              border: const OutlineInputBorder(),
              isDense: true,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(context, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          style: FilledButton.styleFrom(
            backgroundColor: Theme.of(context).colorScheme.error,
          ),
          onPressed: ok ? () => Navigator.pop(context, true) : null,
          child: Text(l10n.prefsClearConfirm),
        ),
      ],
    );
  }
}
