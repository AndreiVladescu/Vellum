import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../settings/app_settings.dart';
import 'filename_metadata.dart';
import 'folder_import_service.dart';
import 'import_plan.dart';

/// The bulk folder import wizard (plan 5 #15): pick a folder, review what the
/// import *would* do, then run it.
///
/// The dry-run step is the design: someone arriving with 500 downloaded PDFs
/// needs to see the guessed titles and the duplicates **before** anything is
/// written, and to be able to deselect rows. Nothing here writes until "Import"
/// is pressed.
class FolderImportPage extends StatefulWidget {
  const FolderImportPage({
    super.key,
    required this.repository,
    required this.settings,
    this.initialFolder,
    this.initialFiles,
  });

  final LibraryRepository repository;
  final AppSettingsStore settings;

  /// Skip the picker and scan this folder immediately — used by the watched
  /// folder's launch prompt.
  final String? initialFolder;

  /// Skip the picker and review these exact files — a multi-file share (plan 5
  /// #20), which arrives as paths with no folder to watch.
  final List<String>? initialFiles;

  @override
  State<FolderImportPage> createState() => _FolderImportPageState();
}

enum _Phase { pick, scanning, review, importing, done }

class _FolderImportPageState extends State<FolderImportPage> {
  late final FolderImportService _service =
      FolderImportService(widget.repository);

  _Phase _phase = _Phase.pick;
  String? _folder;
  List<ImportCandidate> _plan = const [];
  final Set<String> _selected = {};
  var _progress = (done: 0, total: 0, label: '');
  bool _cancelRequested = false;
  ImportReport? _report;
  bool _fetchMetadata = false;
  int _enriched = 0;

  @override
  void initState() {
    super.initState();
    final files = widget.initialFiles;
    final initial = widget.initialFolder;
    if (files != null && files.isNotEmpty) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scanFiles(files));
    } else if (initial != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) => _scan(initial));
    }
  }

  /// The shared-files variant of [_scan]: same dry run, no folder behind it (so
  /// no "watch this folder" offer on the summary).
  Future<void> _scanFiles(List<String> paths) async {
    setState(() {
      _phase = _Phase.scanning;
      _cancelRequested = false;
      _progress = (done: 0, total: paths.length, label: '');
    });
    final plan = await _service.scanFiles(
      [for (final path in paths) File(path)],
      onProgress: (done, total, label) {
        if (mounted) {
          setState(() => _progress = (done: done, total: total, label: label));
        }
      },
      isCancelled: () async => _cancelRequested,
    );
    if (!mounted) return;
    _applyPlan(plan);
  }

  Future<void> _pickFolder() async {
    final picked = await getDirectoryPath(confirmButtonText: 'Scan');
    if (picked == null) return;
    await _scan(picked);
  }

  Future<void> _scan(String path) async {
    setState(() {
      _folder = path;
      _phase = _Phase.scanning;
      _cancelRequested = false;
      _progress = (done: 0, total: 0, label: '');
    });
    final plan = await _service.scan(
      Directory(path),
      onProgress: (done, total, label) {
        if (mounted) {
          setState(() => _progress = (done: done, total: total, label: label));
        }
      },
      isCancelled: () async => _cancelRequested,
    );
    if (!mounted) return;
    _applyPlan(plan);
  }

  void _applyPlan(List<ImportCandidate> plan) {
    setState(() {
      _plan = plan;
      _selected
        ..clear()
        ..addAll([
          for (final c in plan)
            if (c.selectedByDefault) c.path,
        ]);
      // Above ~50 books, one online lookup each is minutes of waiting on a free
      // service, so the default flips to "import now, fetch metadata later".
      _fetchMetadata = _selected.length <= 50;
      _phase = _Phase.review;
    });
  }

  Future<void> _runImport() async {
    final chosen = [
      for (final c in _plan)
        if (_selected.contains(c.path)) c,
    ];
    setState(() {
      _phase = _Phase.importing;
      _cancelRequested = false;
      _progress = (done: 0, total: chosen.length, label: '');
    });
    final report = await _service.import(
      chosen,
      onProgress: (done, total, label) {
        if (mounted) {
          setState(() => _progress = (done: done, total: total, label: label));
        }
      },
      isCancelled: () async => _cancelRequested,
    );
    if (!mounted) return;
    setState(() => _report = report);

    if (_fetchMetadata && !report.cancelled) {
      final ids = [
        for (final o in report.outcomes)
          if (o.bookId != null) o.bookId!,
      ];
      setState(() => _progress = (done: 0, total: ids.length, label: ''));
      final enriched = await _service.enrich(
        ids,
        onProgress: (done, total, label) {
          if (mounted) {
            setState(() => _progress = (done: done, total: total, label: label));
          }
        },
        isCancelled: () async => _cancelRequested,
      );
      if (!mounted) return;
      setState(() => _enriched = enriched);
    }
    if (!mounted) return;
    setState(() => _phase = _Phase.done);
  }

  /// True when this page is reviewing shared files rather than a folder, which
  /// changes only the wording — the flow underneath is identical.
  bool get _isShare => widget.initialFiles != null;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: Text(_isShare ? 'Import shared books' : 'Import a folder'),
        actions: [
          if (_phase == _Phase.scanning || _phase == _Phase.importing)
            TextButton(
              onPressed: _cancelRequested
                  ? null
                  : () => setState(() => _cancelRequested = true),
              child: Text(_cancelRequested ? 'Stopping…' : 'Cancel'),
            ),
        ],
      ),
      body: switch (_phase) {
        _Phase.pick => _PickStep(onPick: _pickFolder),
        _Phase.scanning => _BusyStep(
            title: _isShare
                ? 'Checking the shared files…'
                : 'Looking through ${_folder ?? 'the folder'}…',
            progress: _progress,
          ),
        _Phase.review => _reviewStep(context),
        _Phase.importing => _BusyStep(
            title: _report == null
                ? 'Importing…'
                : 'Fetching metadata (this can be stopped safely)…',
            progress: _progress,
          ),
        _Phase.done => _doneStep(context),
      },
      // No bar when the scan found nothing: "0 of 0 selected · Import" under an
      // empty-folder message is noise, not an affordance.
      bottomNavigationBar: _phase == _Phase.review && _plan.isNotEmpty
          ? _reviewBar(context)
          : null,
    );
  }

  Widget _reviewStep(BuildContext context) {
    if (_plan.isEmpty) {
      return _EmptyMessage(
        icon: Icons.folder_off_outlined,
        title: 'No PDFs or EPUBs here',
        detail: _folder == null
            ? 'None of the shared files is a PDF or EPUB.'
            : 'Vellum looked in $_folder and every folder inside it.',
      );
    }
    final counts = summarize(_plan);
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Align(
            alignment: Alignment.centerLeft,
            child: Text(
              [
                '${_plan.length} file${_plan.length == 1 ? '' : 's'} found',
                if (counts[ImportStatus.duplicateFile]! > 0)
                  '${counts[ImportStatus.duplicateFile]} already in your library',
                if (counts[ImportStatus.probableDuplicate]! > 0)
                  '${counts[ImportStatus.probableDuplicate]} look like books you have',
                if (counts[ImportStatus.skip]! > 0)
                  "${counts[ImportStatus.skip]} couldn't be read",
              ].join(' · '),
              style: Theme.of(context).textTheme.bodyMedium,
            ),
          ),
        ),
        Expanded(
          child: ListView.builder(
            itemCount: _plan.length,
            itemBuilder: (context, i) => _CandidateTile(
              candidate: _plan[i],
              selected: _selected.contains(_plan[i].path),
              onChanged: (on) => setState(() {
                if (on) {
                  _selected.add(_plan[i].path);
                } else {
                  _selected.remove(_plan[i].path);
                }
              }),
              onEdit: () => _editRow(i),
            ),
          ),
        ),
      ],
    );
  }

  /// Lets the user fix a guessed title/author before it becomes a book — the
  /// file-name heuristic is right most of the time, not always.
  Future<void> _editRow(int index) async {
    final candidate = _plan[index];
    final title = TextEditingController(
      text: candidate.meta.title ?? filenameStem(candidate.path),
    );
    final authors =
        TextEditingController(text: candidate.meta.authors.join(', '));
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Edit before importing'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: title,
              decoration: const InputDecoration(labelText: 'Title'),
              autofocus: true,
            ),
            const SizedBox(height: 12),
            TextField(
              controller: authors,
              decoration: const InputDecoration(
                labelText: 'Author(s)',
                helperText: 'Comma-separated',
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved != true || !mounted) return;
    setState(() {
      _plan[index] = candidate.copyWith(
        meta: FilenameMeta(
          title: title.text.trim().isEmpty ? null : title.text.trim(),
          authors: [
            for (final a in authors.text.split(','))
              if (a.trim().isNotEmpty) a.trim(),
          ],
          publisher: candidate.meta.publisher,
          year: candidate.meta.year,
        ),
      );
    });
  }

  Widget _reviewBar(BuildContext context) {
    final count = _selected.length;
    return SafeArea(
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 8, 16, 8),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            CheckboxListTile(
              contentPadding: EdgeInsets.zero,
              controlAffinity: ListTileControlAffinity.leading,
              value: _fetchMetadata,
              onChanged: (v) => setState(() => _fetchMetadata = v ?? false),
              title: const Text('Look up covers and descriptions online'),
              subtitle: Text(
                _fetchMetadata
                    ? 'One lookup at a time after importing — you can stop it '
                        'and it will carry on next time'
                    : 'Import straight from file names now; you can fetch '
                        'metadata later per book',
              ),
            ),
            Row(
              children: [
                Expanded(
                  child: Text(
                    '$count of ${_plan.length} selected',
                    style: Theme.of(context).textTheme.bodyMedium,
                  ),
                ),
                TextButton(
                  onPressed: () => setState(() {
                    if (_selected.length == _plan.length) {
                      _selected.clear();
                    } else {
                      _selected
                        ..clear()
                        ..addAll([for (final c in _plan) c.path]);
                    }
                  }),
                  child: Text(_selected.length == _plan.length
                      ? 'Select none'
                      : 'Select all'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: count == 0 ? null : _runImport,
                  icon: const Icon(Icons.download_outlined),
                  label: Text(count == 0 ? 'Import' : 'Import $count'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _doneStep(BuildContext context) {
    final report = _report!;
    final folder = _folder;
    return ListView(
      padding: const EdgeInsets.all(16),
      children: [
        Text(
          report.cancelled
              ? 'Stopped after ${report.imported} book'
                  '${report.imported == 1 ? '' : 's'}'
              : 'Imported ${report.imported} book'
                  '${report.imported == 1 ? '' : 's'}',
          style: Theme.of(context).textTheme.headlineSmall,
        ),
        const SizedBox(height: 8),
        if (_fetchMetadata)
          Text('$_enriched matched online. Books that didn’t match keep their '
              'file-name details — open one and use “Find online” to try again.'),
        if (report.failures.isNotEmpty) ...[
          const SizedBox(height: 16),
          Text('${report.failures.length} failed',
              style: Theme.of(context).textTheme.titleMedium),
          for (final f in report.failures)
            ListTile(
              dense: true,
              leading: const Icon(Icons.error_outline),
              title: Text(filenameStem(f.path)),
              subtitle: Text(f.error!),
            ),
        ],
        if (folder != null) ...[
          const SizedBox(height: 16),
          ListenableBuilder(
            listenable: widget.settings,
            builder: (context, _) => SwitchListTile(
              contentPadding: EdgeInsets.zero,
              secondary: const Icon(Icons.folder_special_outlined),
              title: const Text('Watch this folder'),
              subtitle: const Text(
                  'Offer to import new books from it when Vellum starts'),
              value: widget.settings.watchedImportFolder == folder,
              onChanged: (on) =>
                  widget.settings.setWatchedImportFolder(on ? folder : null),
            ),
          ),
        ],
        const SizedBox(height: 24),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Back to the shelf'),
        ),
      ],
    );
  }
}

class _PickStep extends StatelessWidget {
  const _PickStep({required this.onPick});

  final VoidCallback onPick;

  @override
  Widget build(BuildContext context) {
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              const Icon(Icons.folder_open, size: 56),
              const SizedBox(height: 16),
              Text('Add a folder of books',
                  style: Theme.of(context).textTheme.headlineSmall),
              const SizedBox(height: 8),
              const Text(
                'Vellum looks for PDFs and EPUBs, including inside subfolders, '
                'and shows you what it found before importing anything.',
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 24),
              FilledButton.icon(
                onPressed: onPick,
                icon: const Icon(Icons.folder_open),
                label: const Text('Choose folder…'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _BusyStep extends StatelessWidget {
  const _BusyStep({required this.title, required this.progress});

  final String title;
  final ({int done, int total, String label}) progress;

  @override
  Widget build(BuildContext context) {
    final total = progress.total;
    return Center(
      child: ConstrainedBox(
        constraints: const BoxConstraints(maxWidth: 420),
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Text(title, textAlign: TextAlign.center),
              const SizedBox(height: 16),
              LinearProgressIndicator(
                value: total == 0 ? null : progress.done / total,
              ),
              const SizedBox(height: 8),
              Text(
                total == 0
                    ? 'Scanning…'
                    : '${progress.done} of $total · ${progress.label}',
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _EmptyMessage extends StatelessWidget {
  const _EmptyMessage({
    required this.icon,
    required this.title,
    required this.detail,
  });

  final IconData icon;
  final String title;
  final String detail;

  @override
  Widget build(BuildContext context) => Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 48),
              const SizedBox(height: 12),
              Text(title, style: Theme.of(context).textTheme.titleLarge),
              const SizedBox(height: 8),
              Text(detail, textAlign: TextAlign.center),
            ],
          ),
        ),
      );
}

class _CandidateTile extends StatelessWidget {
  const _CandidateTile({
    required this.candidate,
    required this.selected,
    required this.onChanged,
    required this.onEdit,
  });

  final ImportCandidate candidate;
  final bool selected;
  final ValueChanged<bool> onChanged;
  final VoidCallback onEdit;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final (label, color) = switch (candidate.status) {
      ImportStatus.newBook => ('New', theme.colorScheme.primary),
      ImportStatus.duplicateFile => ('Already here', theme.colorScheme.outline),
      ImportStatus.probableDuplicate =>
        ('Possible duplicate', theme.colorScheme.tertiary),
      ImportStatus.skip => ('Unreadable', theme.colorScheme.error),
    };
    final authors = candidate.meta.authors.join(', ');
    return CheckboxListTile(
      value: selected,
      onChanged: candidate.status == ImportStatus.skip
          ? null
          : (v) => onChanged(v ?? false),
      controlAffinity: ListTileControlAffinity.leading,
      isThreeLine: true,
      title: Text(
        candidate.meta.title ?? filenameStem(candidate.path),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            [
              if (authors.isNotEmpty) authors,
              candidate.format.toUpperCase(),
              if (candidate.matchedTitle != null)
                'matches “${candidate.matchedTitle}”',
              if (candidate.error != null) candidate.error!,
            ].join(' · '),
            maxLines: 2,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.bodySmall,
          ),
          Text(label, style: theme.textTheme.labelSmall?.copyWith(color: color)),
        ],
      ),
      secondary: IconButton(
        icon: const Icon(Icons.edit_outlined),
        tooltip: 'Edit title and author',
        onPressed: candidate.status == ImportStatus.skip ? null : onEdit,
      ),
    );
  }
}
