import 'package:flutter/material.dart';
import 'package:intl/intl.dart';

import '../data/database.dart';
import '../l10n/gen/app_localizations.dart';
import '../widgets/page_insets.dart';
import 'library_stats.dart';
import 'library_stats_queries.dart';

/// Library statistics (roadmap v1.3.5): the collection by genre, year, format
/// and author, the unread pile, and books added per month.
///
/// Reading insights answers "what have I read?"; this answers "what do I
/// have?". The books arrive from one drift `watch()` stream
/// ([LibraryStatsQueries]), so adding or trashing a book updates the page
/// while it is open. Charts are plain widgets -- a row per bar -- so there is
/// no chart dependency.
class LibraryStatsPage extends StatelessWidget {
  const LibraryStatsPage({super.key, required this.db, this.now});

  final VellumDatabase db;

  /// Overrides "today" for tests.
  final DateTime? now;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).libraryStatsTitle)),
      body: StreamBuilder<List<LibraryStatsBook>>(
        stream: LibraryStatsQueries.watchBooks(db),
        builder: (context, snap) {
          if (!snap.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final stats = LibraryStatsCalculator.compute(
            snap.data!,
            now: now ?? DateTime.now(),
          );
          return LibraryStatsView(stats: stats);
        },
      ),
    );
  }
}

/// The page body for already-computed [stats]. Split from the page so a test
/// can pump it without a database.
class LibraryStatsView extends StatefulWidget {
  const LibraryStatsView({super.key, required this.stats});

  final LibraryStats stats;

  @override
  State<LibraryStatsView> createState() => _LibraryStatsViewState();
}

class _LibraryStatsViewState extends State<LibraryStatsView> {
  bool _byYear = false; // false = decades
  bool _allTime = false; // false = last 12 months

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final s = widget.stats;
    if (s.total == 0) {
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Text(l10n.libraryStatsEmpty, textAlign: TextAlign.center),
        ),
      );
    }
    final formatBars = [
      for (final kind in HoldingKind.values)
        if (s.byFormat[kind]! > 0)
          StatCount(_formatLabel(l10n, kind), s.byFormat[kind]!),
    ];
    final yearBars = _byYear ? s.byYear : s.byDecade;

    return ListView(
      padding: pageInsets(context, const EdgeInsets.all(16)),
      children: [
        Text(
          l10n.libraryStatsTotal(s.total),
          style: Theme.of(context).textTheme.titleLarge,
        ),
        _Section(
          title: l10n.libraryStatsGenres,
          child: s.byGenre.isEmpty
              ? Text(l10n.libraryStatsGenresNone)
              : _BarList(bars: s.byGenre),
        ),
        _Section(
          title: l10n.libraryStatsYears,
          trailing: _Toggle(
            firstLabel: l10n.libraryStatsDecades,
            secondLabel: l10n.libraryStatsByYear,
            second: _byYear,
            onChanged: (v) => setState(() => _byYear = v),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _BarList(bars: yearBars),
              if (s.unknownYear > 0)
                Padding(
                  padding: const EdgeInsets.only(top: 8),
                  child: Text(
                    l10n.libraryStatsUnknownYear(s.unknownYear),
                    style: Theme.of(context).textTheme.bodySmall,
                  ),
                ),
            ],
          ),
        ),
        _Section(
          title: l10n.libraryStatsFormats,
          child: _BarList(bars: formatBars),
        ),
        _Section(
          title: l10n.libraryStatsAuthors,
          child: s.topAuthors.isEmpty
              ? Text(l10n.libraryStatsAuthorsNone)
              : _BarList(bars: s.topAuthors),
        ),
        _Section(
          title: l10n.libraryStatsUnread,
          child: _UnreadPileCard(s.unread),
        ),
        _Section(
          title: l10n.libraryStatsAdded,
          trailing: _Toggle(
            firstLabel: l10n.libraryStatsAddedLastYear,
            secondLabel: l10n.libraryStatsAddedAllTime,
            second: _allTime,
            onChanged: (v) => setState(() => _allTime = v),
          ),
          child: _MonthColumns(
            months: _allTime ? s.addedAllTime : s.addedLastYear,
          ),
        ),
      ],
    );
  }

  static String _formatLabel(L10n l10n, HoldingKind kind) => switch (kind) {
    HoldingKind.pdf => l10n.libraryStatsFormatPdf,
    HoldingKind.epub => l10n.libraryStatsFormatEpub,
    HoldingKind.otherDigital => l10n.libraryStatsFormatOther,
    HoldingKind.physical => l10n.libraryStatsFormatPhysical,
    HoldingKind.several => l10n.libraryStatsFormatSeveral,
    HoldingKind.none => l10n.libraryStatsFormatNone,
  };
}

/// A heading with an optional control at its right, above [child].
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.trailing});

  final String title;
  final Widget child;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(
                child: Text(
                  title,
                  style: Theme.of(context).textTheme.titleMedium,
                  semanticsLabel: title,
                ),
              ),
            ],
          ),
          if (trailing != null)
            Padding(padding: const EdgeInsets.only(top: 8), child: trailing),
          const SizedBox(height: 12),
          child,
        ],
      ),
    );
  }
}

/// A two-way switch between two views of the same chart.
class _Toggle extends StatelessWidget {
  const _Toggle({
    required this.firstLabel,
    required this.secondLabel,
    required this.second,
    required this.onChanged,
  });

  final String firstLabel;
  final String secondLabel;
  final bool second;
  final ValueChanged<bool> onChanged;

  @override
  Widget build(BuildContext context) {
    // SegmentedButton takes a *set* of selected values, even for single choice.
    return SegmentedButton<bool>(
      showSelectedIcon: false,
      segments: [
        ButtonSegment(value: false, label: Text(firstLabel)),
        ButtonSegment(value: true, label: Text(secondLabel)),
      ],
      selected: {second},
      onSelectionChanged: (v) => onChanged(v.first),
    );
  }
}

/// Horizontal bars, one per row: label, bar scaled to the tallest, count.
class _BarList extends StatelessWidget {
  const _BarList({required this.bars});

  final List<StatCount> bars;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final max = LibraryStatsCalculator.maxCount(bars.map((b) => b.count));
    return Column(
      children: [
        for (final b in bars)
          Semantics(
            label: l10n.libraryStatsBarLabel(b.label, b.count),
            excludeSemantics: true,
            child: Padding(
              padding: const EdgeInsets.symmetric(vertical: 3),
              child: Row(
                children: [
                  SizedBox(
                    width: 110,
                    child: Text(
                      b.label,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Align(
                      alignment: Alignment.centerLeft,
                      // widthFactor is the fraction of the available width.
                      child: FractionallySizedBox(
                        widthFactor: b.count / max,
                        child: Container(
                          height: 14,
                          decoration: BoxDecoration(
                            color: scheme.primary,
                            borderRadius: BorderRadius.circular(3),
                          ),
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  SizedBox(
                    width: 40,
                    child: Text(
                      '${b.count}',
                      textAlign: TextAlign.end,
                    ), // i18n-ignore (a number)
                  ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// Vertical columns, one per month, scrolling sideways when there are many.
class _MonthColumns extends StatelessWidget {
  const _MonthColumns({required this.months});

  final List<MonthCount> months;

  static const _chartHeight = 120.0;
  static const _columnWidth = 36.0;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final scheme = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).toString();
    final short = DateFormat.MMM(locale);
    final long = DateFormat.yMMM(locale);
    final max = LibraryStatsCalculator.maxCount(months.map((m) => m.count));
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      reverse: true, // start at the newest month
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.end,
        children: [
          for (final m in months)
            Semantics(
              label: l10n.libraryStatsBarLabel(long.format(m.month), m.count),
              excludeSemantics: true,
              child: SizedBox(
                width: _columnWidth,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      '${m.count}',
                      style: Theme.of(context).textTheme.labelSmall,
                    ), // i18n-ignore (a number)
                    const SizedBox(height: 2),
                    Container(
                      width: 16,
                      height: _chartHeight * m.count / max,
                      decoration: BoxDecoration(
                        color: scheme.primary,
                        borderRadius: BorderRadius.circular(3),
                      ),
                    ),
                    const SizedBox(height: 4),
                    // January also shows its year, so a long axis stays legible.
                    Text(
                      m.month.month == 1
                          ? DateFormat.y(locale).format(m.month)
                          : short.format(m.month),
                      style: Theme.of(context).textTheme.labelSmall,
                      maxLines: 1,
                      overflow: TextOverflow.clip,
                    ),
                  ],
                ),
              ),
            ),
        ],
      ),
    );
  }
}

class _UnreadPileCard extends StatelessWidget {
  const _UnreadPileCard(this.pile);

  final UnreadPile pile;

  /// "812 KB" / "3.4 MB" / "1.2 GB". Units are the same in every language.
  static String _size(int bytes) {
    const kb = 1024;
    if (bytes < kb * kb) return '${(bytes / kb).round()} KB';
    if (bytes < kb * kb * kb) {
      return '${(bytes / (kb * kb)).toStringAsFixed(1)} MB';
    }
    return '${(bytes / (kb * kb * kb)).toStringAsFixed(1)} GB';
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.libraryStatsUnreadBooks(pile.books), style: text.titleLarge),
        if (pile.books > 0) ...[
          const SizedBox(height: 4),
          if (pile.estimatedPages > 0)
            Text(l10n.libraryStatsUnreadPages(pile.estimatedPages)),
          if (pile.withoutPageCount > 0 && pile.estimatedPages > 0)
            Text(
              l10n.libraryStatsUnreadPagesGuess(pile.withoutPageCount),
              style: text.bodySmall,
            ),
          if (pile.totalBytes > 0)
            Text(l10n.libraryStatsUnreadSize(_size(pile.totalBytes))),
        ],
      ],
    );
  }
}
