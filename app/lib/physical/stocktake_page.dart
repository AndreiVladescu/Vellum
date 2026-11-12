import 'package:flutter/material.dart';
import '../widgets/page_insets.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../l10n/gen/app_localizations.dart';
import 'stocktake.dart';

/// Walk a shelf and check it against the map (plan 5 #30).
///
/// Two phases, deliberately: **counting** (tick what you can see, which is all
/// you can do with a book in your hand) and then the **report**. Nothing is
/// written until the report, and even then only when the user picks an action —
/// this reconciles the map against reality, it does not quietly rewrite either.
class StocktakePage extends StatefulWidget {
  const StocktakePage({
    super.key,
    required this.repository,
    required this.environmentId,
    required this.scopeLabel,
    this.shelfId,
  });

  final LibraryRepository repository;
  final String environmentId;

  /// What is being counted, for the title: a room name or a shelf label.
  final String scopeLabel;

  /// Null counts the whole room; otherwise just this shelf.
  final String? shelfId;

  @override
  State<StocktakePage> createState() => _StocktakePageState();
}

class _StocktakePageState extends State<StocktakePage> {
  List<PlacedBook> _scope = const [];
  List<Book> _library = const [];
  Map<String, String> _elsewhere = const {};
  final _found = <String>{};
  bool _loading = true;
  StocktakeResult? _result;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    final repo = widget.repository;
    final placed = await repo.layout.watchPlacedBooks(widget.environmentId).first;
    final shelves = await repo.layout.watchShelves(widget.environmentId).first;
    final scope = widget.shelfId == null
        ? placed
        : onShelf(shelfId: widget.shelfId!, placed: placed, shelves: shelves);
    final library = await repo.watchAllBooks().first;
    if (!mounted) return;
    setState(() {
      _scope = scope;
      _library = library;
      _loading = false;
    });
  }

  /// Where else the map thinks a book is, for the "unexpected" list. Resolved
  /// once at report time rather than per row: it costs a query per book, and
  /// only the handful that turned up unexpectedly need it.
  Future<void> _finish() async {
    final unexpectedIds = _found.where(
      (id) => !_scope.any((p) => p.book.id == id),
    );
    final elsewhere = <String, String>{};
    for (final id in unexpectedIds) {
      final sightings = await widget.repository.layout.sightingsOf(id);
      if (sightings.isNotEmpty) elsewhere[id] = sightings.first.display;
    }
    if (!mounted) return;
    setState(() {
      _elsewhere = elsewhere;
      _result = reconcile(
        placed: _scope,
        foundBookIds: _found,
        library: _library,
        locationOf: (id) => _elsewhere[id],
      );
    });
  }

  /// Removes a placement the shelf says isn't there. The one destructive
  /// action offered, and only per row after a confirmation — a stocktake that
  /// bulk-deleted "missing" books would be a very effective way to lose a map.
  Future<void> _removePlacement(PlacedBook entry) async {
    final l10n = L10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.stocktakeRemoveTitle(entry.book.title)),
        content: Text(l10n.stocktakeRemoveBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.stocktakeRemove),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await widget.repository.layout.removePlacement(entry.placement);
    if (!mounted) return;
    setState(() {
      _scope = [
        for (final e in _scope)
          if (e.placement.id != entry.placement.id) e,
      ];
    });
    await _finish();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final result = _result;
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.stocktakeTitle(widget.scopeLabel)),
        actions: [
          if (result == null && !_loading)
            TextButton(
              onPressed: _finish,
              child: Text(l10n.stocktakeFinish),
            ),
          if (result != null)
            TextButton(
              onPressed: () => setState(() => _result = null),
              child: Text(l10n.stocktakeBackToList),
            ),
        ],
      ),
      body: _loading
          ? const Center(child: CircularProgressIndicator())
          : result != null
              ? _report(result)
              : _checklist(),
    );
  }

  Widget _checklist() {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    if (_scope.isEmpty) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Text(
            l10n.stocktakeNothingHere,
            textAlign: TextAlign.center,
          ),
        ),
      );
    }
    // Deduplicated by book: two copies of one title are one line to tick, which
    // is what the person holding the book can actually answer.
    final byBook = <String, PlacedBook>{};
    for (final entry in _scope) {
      byBook.putIfAbsent(entry.book.id, () => entry);
    }
    final rows = byBook.values.toList()
      ..sort((a, b) =>
          a.book.title.toLowerCase().compareTo(b.book.title.toLowerCase()));
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
          child: Text(
            l10n.stocktakeTickPrompt(_found.length, rows.length),
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ),
        Expanded(
          child: ListView(
            padding: pageInsets(context, EdgeInsets.zero),
            children: [
              for (final entry in rows)
                CheckboxListTile(
                  value: _found.contains(entry.book.id),
                  onChanged: (on) => setState(() {
                    if (on ?? false) {
                      _found.add(entry.book.id);
                    } else {
                      _found.remove(entry.book.id);
                    }
                  }),
                  title: Text(entry.book.title),
                  subtitle: entry.book.subtitle == null
                      ? null
                      : Text(entry.book.subtitle!),
                ),
            ],
          ),
        ),
      ],
    );
  }

  Widget _report(StocktakeResult result) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    if (result.isClean) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(32),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(Icons.verified_outlined,
                  size: 56, color: theme.colorScheme.primary),
              const SizedBox(height: 16),
              Text(l10n.stocktakeAllMatch, style: theme.textTheme.titleMedium),
              const SizedBox(height: 6),
              Text(
                l10n.stocktakeAllMatchBody(result.confirmed.length),
                textAlign: TextAlign.center,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
              ),
            ],
          ),
        ),
      );
    }
    return ListView(
      padding: pageInsets(context, EdgeInsets.zero),
      children: [
        if (result.missing.isNotEmpty) ...[
          _Header(
            l10n.stocktakeMissing(result.missing.length),
            l10n.stocktakeMissingNote,
          ),
          for (final entry in result.missing)
            ListTile(
              leading: Icon(Icons.help_outline, color: theme.colorScheme.error),
              title: Text(entry.book.title),
              trailing: TextButton(
                onPressed: () => _removePlacement(entry),
                child: Text(l10n.stocktakeRemoveFromMap),
              ),
            ),
        ],
        if (result.unexpected.isNotEmpty) ...[
          _Header(
            l10n.stocktakeUnexpected(result.unexpected.length),
            l10n.stocktakeUnexpectedNote,
          ),
          for (final entry in result.unexpected)
            ListTile(
              leading: const Icon(Icons.new_releases_outlined),
              title: Text(entry.book.title),
              subtitle: Text(entry.isUnplaced
                  ? l10n.stocktakeUnplaced
                  : l10n.stocktakePlacedIn(entry.placedElsewhere!)),
            ),
        ],
        _Header(l10n.stocktakeConfirmed(result.confirmed.length), ''),
        for (final entry in result.confirmed)
          ListTile(
            dense: true,
            leading: const Icon(Icons.check, size: 18),
            title: Text(entry.book.title),
          ),
      ],
    );
  }
}

class _Header extends StatelessWidget {
  const _Header(this.title, this.subtitle);

  final String title;
  final String subtitle;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 20, 16, 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title,
              style: theme.textTheme.titleSmall
                  ?.copyWith(color: theme.colorScheme.primary)),
          if (subtitle.isNotEmpty)
            Text(subtitle,
                style: TextStyle(color: theme.colorScheme.onSurfaceVariant)),
        ],
      ),
    );
  }
}
