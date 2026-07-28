import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../import/import_plan.dart';
import '../snack_bars.dart';
import 'duplicate_finder.dart';
import 'merge_service.dart';

/// Find and merge duplicate books (plan 5 #21b).
///
/// Pairs are listed strongest-evidence first, and each opens a side-by-side
/// comparison where the user chooses which book survives and, field by field,
/// which value to keep. Nothing merges without that dialog: a merge deletes a
/// book row and cannot be undone.
class DuplicatesPage extends StatefulWidget {
  const DuplicatesPage({super.key, required this.repository});

  final LibraryRepository repository;

  @override
  State<DuplicatesPage> createState() => _DuplicatesPageState();
}

class _DuplicatesPageState extends State<DuplicatesPage> {
  late Future<List<DuplicatePair>> _pairs;
  final _merged = <String>[];

  @override
  void initState() {
    super.initState();
    _pairs = _find();
  }

  Future<List<DuplicatePair>> _find() async {
    final db = widget.repository.db;
    // Live books only. A merge *hard-deletes* the loser and tombstones it, so
    // offering a trashed book would let someone merge a live book into an
    // invisible one — everything moves onto a row the sweep permanently deletes
    // 30 days later, and the merge is the app's one operation with no undo.
    final books = await (db.select(db.books)
          ..where((b) => b.deletedAt.isNull()))
        .get();
    final files = await db.select(db.bookFiles).get();
    final authorsByBook =
        await widget.repository.queries.watchAuthorsByBook().first;
    final hashes = <String, Set<String>>{};
    for (final f in files) {
      hashes.putIfAbsent(f.bookId, () => {}).add(f.sha256);
    }
    return findDuplicates([
      for (final b in books)
        LibraryFingerprint(
          bookId: b.id,
          title: b.title,
          isbn: b.isbn,
          authors: authorsByBook[b.id] ?? const [],
          fileHashes: hashes[b.id] ?? const {},
        ),
    ]);
  }

  Future<void> _openPair(DuplicatePair pair) async {
    final repo = widget.repository;
    final a = await repo.watchBook(pair.a.bookId).first;
    final b = await repo.watchBook(pair.b.bookId).first;
    if (a == null || b == null || !mounted) {
      // One of them was merged or deleted since the scan: refresh instead.
      setState(() => _pairs = _find());
      return;
    }
    final result = await showDialog<MergeLog>(
      context: context,
      builder: (_) => _MergeDialog(repository: repo, a: a, b: b, reason: pair.reason),
    );
    if (result == null || !mounted) return;
    setState(() {
      _merged.add(result.toString());
      _pairs = _find();
    });
    ScaffoldMessenger.of(context).showSnackBar(
      appSnackBar(
        content: const Text('Merged'),
        action: SnackBarAction(
          label: 'What moved',
          onPressed: () => showDialog<void>(
            context: context,
            builder: (_) => AlertDialog(
              title: const Text('What the merge moved'),
              content: SingleChildScrollView(child: Text(result.toString())),
              actions: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Close'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Duplicate books')),
      body: FutureBuilder<List<DuplicatePair>>(
        future: _pairs,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final pairs = snapshot.data!;
          if (pairs.isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.done_all, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      _merged.isEmpty
                          ? 'No duplicates found'
                          : 'No duplicates left',
                      style: Theme.of(context).textTheme.titleLarge,
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'Vellum compares file contents, ISBNs, and titles with '
                      'their authors.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView.separated(
            itemCount: pairs.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) {
              final pair = pairs[i];
              return ListTile(
                leading: Icon(pair.reason.isCertain
                    ? Icons.content_copy
                    : Icons.help_outline),
                title: Text(pair.a.title,
                    maxLines: 1, overflow: TextOverflow.ellipsis),
                subtitle: Text(
                  '${pair.reason.label} · also “${pair.b.title}”',
                  maxLines: 2,
                  overflow: TextOverflow.ellipsis,
                ),
                trailing: const Icon(Icons.chevron_right),
                onTap: () => _openPair(pair),
              );
            },
          );
        },
      ),
    );
  }
}

/// Side-by-side comparison: pick the survivor, then resolve each disagreement.
class _MergeDialog extends StatefulWidget {
  const _MergeDialog({
    required this.repository,
    required this.a,
    required this.b,
    required this.reason,
  });

  final LibraryRepository repository;
  final Book a;
  final Book b;
  final DuplicateReason reason;

  @override
  State<_MergeDialog> createState() => _MergeDialogState();
}

class _MergeDialogState extends State<_MergeDialog> {
  late String _keeperId = widget.a.id;
  final _choices = <String, MergeChoice>{};
  List<MergeConflict> _conflicts = const [];
  bool _busy = false;

  Book get _keeper => _keeperId == widget.a.id ? widget.a : widget.b;
  Book get _loser => _keeperId == widget.a.id ? widget.b : widget.a;

  @override
  void initState() {
    super.initState();
    _loadConflicts();
  }

  Future<void> _loadConflicts() async {
    final conflicts = await MergeService(widget.repository)
        .conflictsBetween(_keeper, _loser);
    if (!mounted) return;
    // Swapping the survivor mirrors every conflict, so previous per-field
    // choices no longer mean what they did — start them over rather than
    // silently reinterpreting them.
    setState(() {
      _conflicts = conflicts;
      _choices.clear();
    });
  }

  Future<void> _merge() async {
    setState(() => _busy = true);
    try {
      final log = await MergeService(widget.repository).merge(
        keeperId: _keeperId,
        loserId: _loser.id,
        choices: _choices,
      );
      if (mounted) Navigator.of(context).pop(log);
    } catch (e) {
      if (!mounted) return;
      setState(() => _busy = false);
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('Merge failed: $e')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return AlertDialog(
      title: const Text('Merge these books?'),
      content: SizedBox(
        width: 520,
        child: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(widget.reason.label, style: theme.textTheme.labelLarge),
              const SizedBox(height: 12),
              const Text('Which one should survive?'),
              RadioGroup<String>(
                groupValue: _keeperId,
                onChanged: (String? id) {
                  if (_busy || id == null) return;
                  setState(() => _keeperId = id);
                  _loadConflicts();
                },
                child: Column(
                  children: [
                    for (final book in [widget.a, widget.b])
                      RadioListTile<String>(
                        contentPadding: EdgeInsets.zero,
                        value: book.id,
                        title: Text(book.title,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                        subtitle: Text([
                          if (book.publisher != null) book.publisher!,
                          if (book.publishedYear != null) '${book.publishedYear}',
                          if (book.isbn != null) book.isbn!,
                        ].join(' · ')),
                      ),
                  ],
                ),
              ),
              if (_conflicts.isNotEmpty) ...[
                const Divider(),
                Text('These differ — pick what to keep:',
                    style: theme.textTheme.labelLarge),
                for (final conflict in _conflicts)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 6),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(conflict.label, style: theme.textTheme.labelMedium),
                        SegmentedButton<MergeChoice>(
                          segments: [
                            ButtonSegment(
                              value: MergeChoice.keeper,
                              label: Text(
                                _short(conflict.keeperValue),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                            ButtonSegment(
                              value: MergeChoice.loser,
                              label: Text(
                                _short(conflict.loserValue),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                          selected: {
                            _choices[conflict.field] ?? MergeChoice.keeper,
                          },
                          onSelectionChanged: _busy
                              ? null
                              : (selection) => setState(() =>
                                  _choices[conflict.field] = selection.first),
                        ),
                      ],
                    ),
                  ),
              ],
              const Divider(),
              Text(
                'Files, physical copies, loans, shelves, authors and genres all '
                'move to the surviving book. “${_loser.title}” is then deleted '
                'here and on the server. This can’t be undone.',
                style: theme.textTheme.bodySmall,
              ),
            ],
          ),
        ),
      ),
      actions: [
        TextButton(
          onPressed: _busy ? null : () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: _busy ? null : _merge,
          child: Text(_busy ? 'Merging…' : 'Merge'),
        ),
      ],
    );
  }

  static String _short(String? value) {
    final text = (value ?? '—').replaceAll('\n', ' ');
    return text.length <= 28 ? text : '${text.substring(0, 27)}…';
  }
}
