import 'package:flutter/material.dart';
import '../widgets/page_insets.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import 'day_detail_sheet.dart';
import 'duration_label.dart';
import 'goals_dialog.dart';
import 'heatmap_grid.dart';
import 'insights_range.dart';
import 'month_review_page.dart';
import 'year_review_page.dart';
import 'reading_goals.dart';
import 'stats_queries.dart';
import '../settings/app_settings.dart';
import '../l10n/gen/app_localizations.dart';

/// Reading insights (plan 5 #19, plan 6 refresh).
///
/// Built from data the app was already collecting and discarding, and it never
/// leaves the device — unlike a cloud tracker, nothing here is uploaded, and
/// "Clear reading history" really does delete it.
///
/// Charts are hand-drawn with `CustomPaint` rather than pulling in a charting
/// package: there are a handful of them, they follow the app's colour scheme,
/// and the dependency would outweigh the drawing. Every chart is a single
/// measure of magnitude (pages, minutes, days) in one hue — never a second
/// series competing for the same axis — so none of them needs a legend: the
/// section title already says what is plotted.
class InsightsPage extends StatefulWidget {
  const InsightsPage({
    super.key,
    required this.repository,
    required this.settings,
  });

  final LibraryRepository repository;

  /// Where the reading goals live (per device, like other preferences).
  final AppSettingsStore settings;

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  late Future<_Fetched> _insights;
  late InsightsRange _range;

  @override
  void initState() {
    super.initState();
    _range = widget.settings.insightsRange;
    _insights = _load();
  }

  void _setRange(InsightsRange range) {
    setState(() => _range = range);
    widget.settings.setInsightsRange(range);
  }

  Future<_Fetched> _load() async {
    final db = widget.repository.db;
    final sessions = await db.select(db.readingSessions).get();
    final books = await db.select(db.books).get();
    final files = await db.select(db.bookFiles).get();
    final genresByBook = await widget.repository.watchGenresByBook().first;
    final formatsByBook = <String, List<String>>{};
    for (final file in files) {
      (formatsByBook[file.bookId] ??= []).add(file.format);
    }
    return _Fetched(
      sessions: sessions,
      books: books,
      genresByBook: genresByBook,
      formatsByBook: formatsByBook,
    );
  }

  Future<void> _clearHistory() async {
    final l10n = L10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.insightsClearTitle),
        content: Text(l10n.insightsClearBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.insightsClearAction),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    final removed =
        await SessionRecorder(widget.repository.db).clearAll();
    if (!mounted) return;
    setState(() => _insights = _load());
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.insightsCleared(removed))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.insightsTitle),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: l10n.insightsClearTooltip,
            onPressed: _clearHistory,
          ),
        ],
      ),
      body: FutureBuilder<_Fetched>(
        future: _insights,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final fetched = snapshot.data!;
          final data = _Insights(fetched, _range, DateTime.now());
          if (data.allSessions.isEmpty &&
              ReadingStats.finishedPerMonth(fetched.books).isEmpty) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Icon(Icons.insights_outlined, size: 48),
                    const SizedBox(height: 12),
                    Text(l10n.insightsEmptyTitle),
                    const SizedBox(height: 8),
                    Text(
                      l10n.insightsEmptyBody,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          final theme = Theme.of(context);
          return ListView(
            padding: pageInsets(context, const EdgeInsets.all(16)),
            children: [
              _RangeControl(range: _range, onChanged: _setRange),
              const SizedBox(height: 16),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.calendar_month_outlined),
                  title: Text(l10n.insightsMonthEntryTitle),
                  subtitle: Text(l10n.insightsMonthEntrySub),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => MonthReviewPage(
                      repository: widget.repository,
                      settings: widget.settings,
                    ),
                  )),
                ),
              ),
              const SizedBox(height: 12),
              Card(
                margin: EdgeInsets.zero,
                child: ListTile(
                  leading: const Icon(Icons.auto_awesome_outlined),
                  title: Text(l10n.yearEntryTitle),
                  subtitle: Text(l10n.yearEntrySub),
                  trailing: const Icon(Icons.chevron_right),
                  onTap: () => Navigator.of(context).push(MaterialPageRoute<void>(
                    builder: (_) => YearReviewPage(
                      repository: widget.repository,
                      settings: widget.settings,
                    ),
                  )),
                ),
              ),
              const SizedBox(height: 12),
              _GoalsCard(
                settings: widget.settings,
                books: data.books,
                minutesPerDay: data.allMinutesPerDay,
              ),
              const SizedBox(height: 20),
              Text(l10n.insightsHabits, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              _StatRow(stats: [
                (
                  label: l10n.insightsCurrentStreak,
                  value: l10n.insightsDaysShort(data.currentStreak),
                  sub: null,
                ),
                (
                  label: l10n.insightsLongestStreak,
                  value: l10n.insightsDaysShort(data.longestStreak),
                  sub: null,
                ),
                (
                  label: l10n.insightsDaysRead,
                  value: '${data.readingDays.length}', // i18n-ignore
                  sub: null,
                ),
              ]),
              const SizedBox(height: 20),
              Text(l10n.insightsTotals, style: theme.textTheme.labelLarge),
              const SizedBox(height: 8),
              _StatRow(stats: [
                (
                  label: l10n.insightsPagesPerSession,
                  value: data.averagePages.toStringAsFixed(0),
                  sub: null,
                ),
                (
                  label: l10n.insightsPagesRead,
                  value: _compact(data.totalPages),
                  sub: null,
                ),
                (
                  label: l10n.insightsTimeReading,
                  value: formatMinutes(l10n, data.totalMinutes),
                  sub: null,
                ),
                (
                  label: l10n.insightsBooksFinished,
                  value: '${data.totalFinished}', // i18n-ignore
                  sub: null,
                ),
                (
                  label: l10n.insightsThisWeek,
                  value: '${data.thisWeekPages}', // i18n-ignore
                  sub: _weekDeltaLabel(
                      l10n, data.thisWeekPages, data.lastWeekPages),
                ),
              ]),
              if (data.best != null) ...[
                const SizedBox(height: 20),
                _BestDayCard(best: data.best!),
              ],
              const SizedBox(height: 24),
              _Section(
                title: switch (_range) {
                  InsightsRange.thisYear => l10n.insightsPagesADayYear,
                  InsightsRange.allTime => l10n.insightsPagesADayAll,
                  _ => l10n.insightsPagesADay,
                },
                child: SizedBox(
                  height: 90,
                  child: CustomPaint(
                    painter: _SparklinePainter(
                      values: [for (final p in data.pagesSeries) p.value],
                      color: theme.colorScheme.primary,
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _Section(
                title: l10n.insightsWhenYouRead,
                subtitle: l10n.insightsWhenYouReadSub,
                child: SizedBox(
                  height: 110,
                  child: CustomPaint(
                    painter: _HourBarsPainter(
                      minutesByHour: data.hourSeries,
                      color: theme.colorScheme.primary,
                      empty: theme.colorScheme.surfaceContainerHighest,
                      labelStyle: theme.textTheme.bodySmall,
                      quarterNames: [
                        l10n.insightsHourMidnight,
                        l10n.insightsHourSix,
                        l10n.insightsHourNoon,
                        l10n.insightsHourEighteen,
                      ],
                    ),
                    child: const SizedBox.expand(),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              _Section(
                title: l10n.insightsReadingDays,
                subtitle: l10n.insightsReadingDaysHint,
                child: HeatmapGrid(
                  cells: [
                    for (final d in data.heatmapSeries)
                      heatmapCellFor(
                        l10n,
                        d.day,
                        minutes: data.allMinutesPerDay,
                        pages: data.allPagesPerDay,
                      ),
                  ],
                  rows: 7,
                  columns: 12,
                  rowMajor: false,
                  maxCell: 28,
                  startAtEnd: true,
                  color: theme.colorScheme.primary,
                  empty: theme.colorScheme.surfaceContainerHighest,
                  onColor: theme.colorScheme.onPrimary,
                  textColor: theme.colorScheme.onSurface,
                  focusColor: theme.colorScheme.tertiary,
                  semanticsLabel: l10n.insightsReadingDays,
                  onDayTap: (day) => showDayDetailSheet(
                    context,
                    day: day,
                    sessions: data.allSessions,
                    books: data.books,
                    onOpenBook: (book) => openBookDetail(
                      context,
                      repository: widget.repository,
                      settings: widget.settings,
                      book: book,
                    ),
                  ),
                ),
              ),
              if (data.deviceSeries.length > 1) ...[
                const SizedBox(height: 20),
                _Section(
                  title: l10n.insightsWhereYouRead,
                  child: Column(
                    children: [
                      for (final d in data.deviceSeries)
                        _BarListRow(
                          label: d.device == ReadingStats.unknownDevice
                              ? l10n.insightsUnknownDevice
                              : d.device,
                          value: formatMinutes(l10n, d.minutes),
                          fraction: d.minutes / data.deviceSeries.first.minutes,
                          color: theme.colorScheme.primary,
                        ),
                    ],
                  ),
                ),
              ],
              if (data.finishedPerMonth.isNotEmpty) ...[
                const SizedBox(height: 20),
                _Section(
                  title: l10n.insightsBooksFinished,
                  child: Column(
                    children: [
                      for (final entry in data.finishedMonthsNewestFirst)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text('${entry.key.year}-' // i18n-ignore
                              '${entry.key.month.toString().padLeft(2, '0')}'),
                          trailing: Text('${entry.value}'), // i18n-ignore
                        ),
                    ],
                  ),
                ),
              ],
              if (data.genreSplit.isNotEmpty) ...[
                const SizedBox(height: 20),
                _Section(
                  title: l10n.insightsWhatYouFinish,
                  child: Column(
                    children: [
                      for (final slice in data.genreSplit.take(6))
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(slice.genre),
                          trailing: Text('${slice.count}'), // i18n-ignore
                        ),
                    ],
                  ),
                ),
              ],
              if (data.formatSplit.isNotEmpty) ...[
                const SizedBox(height: 20),
                _Section(
                  title: l10n.insightsPaperOrScreen,
                  child: Column(
                    children: [
                      for (final slice in data.formatSplit)
                        ListTile(
                          dense: true,
                          contentPadding: EdgeInsets.zero,
                          title: Text(_formatLabel(slice.format)),
                          trailing: Text('${slice.count}'), // i18n-ignore
                        ),
                    ],
                  ),
                ),
              ],
              const SizedBox(height: 24),
              Text(
                l10n.insightsLocalOnly,
                style: theme.textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// "1,234" for a number worth grouping — a lifetime page count is the one
/// figure here big enough to need it.
String _compact(int value) {
  final s = value.toString();
  final out = StringBuffer();
  for (var i = 0; i < s.length; i++) {
    if (i > 0 && (s.length - i) % 3 == 0) out.write(',');
    out.write(s[i]);
  }
  return out.toString();
}

String _formatLabel(String format) => switch (format.toLowerCase()) {
      'pdf' => 'PDF',
      'epub' => 'EPUB',
      _ => format,
    };

/// What goes under the "This week" tile — a plain comparison, not a verdict:
/// this is a personal record, not a target to have missed.
String _weekDeltaLabel(L10n l10n, int thisWeek, int lastWeek) {
  if (lastWeek == 0) {
    return thisWeek == 0 ? l10n.insightsWeekVs : l10n.insightsWeekUpFromZero;
  }
  final delta = thisWeek - lastWeek;
  if (delta == 0) return l10n.insightsWeekSame;
  final sign = delta > 0 ? '+' : '';
  return l10n.insightsWeekDelta('$sign$delta');
}

/// The range choices at the top of the page, with a plain statement of what
/// the chosen one covers and which parts ignore it.
///
/// Chips rather than a segmented button: they wrap onto a second line at a
/// phone width or a large text size instead of overflowing, and each is a
/// focusable, 48 dp-tall control that announces whether it is selected.
class _RangeControl extends StatelessWidget {
  const _RangeControl({required this.range, required this.onChanged});

  final InsightsRange range;
  final ValueChanged<InsightsRange> onChanged;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final labels = {
      InsightsRange.standard: l10n.insightsRangeDefault,
      InsightsRange.last30Days: l10n.insightsRangeLast30,
      InsightsRange.thisYear: l10n.insightsRangeYear,
      InsightsRange.allTime: l10n.insightsRangeAll,
    };
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(l10n.insightsRangeLabel, style: theme.textTheme.labelLarge),
        const SizedBox(height: 8),
        Wrap(
          spacing: 8,
          runSpacing: 4,
          children: [
            for (final entry in labels.entries)
              ChoiceChip(
                label: Text(entry.value),
                selected: range == entry.key,
                onSelected: (_) => onChanged(entry.key),
              ),
          ],
        ),
        const SizedBox(height: 8),
        Text(
          l10n.insightsRangeNote(switch (range) {
            InsightsRange.standard => 'default', // i18n-ignore
            InsightsRange.last30Days => 'last30', // i18n-ignore
            InsightsRange.thisYear => 'year', // i18n-ignore
            InsightsRange.allTime => 'all', // i18n-ignore
          }),
          style: theme.textTheme.bodySmall,
        ),
        Text(
          l10n.insightsRangeFixedNote,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }
}

/// What was fetched, before any range is applied.
class _Fetched {
  const _Fetched({
    required this.sessions,
    required this.books,
    required this.genresByBook,
    required this.formatsByBook,
  });

  final List<ReadingSession> sessions;
  final List<Book> books;
  final Map<String, List<String>> genresByBook;
  final Map<String, List<String>> formatsByBook;
}

/// Everything the page shows: one fetch, with a range applied.
///
/// **Follow the range:** days read, the totals (pages, time, sessions'
/// average, books finished), the best day, the pages-a-day chart, when you
/// read, where you read, and the books-finished, genre and format lists.
/// **Fixed by nature:** the streaks (a streak is a property of the whole
/// history), this week against last, the 12-week heat map, and the goals
/// (a year and a day by definition).
class _Insights {
  _Insights(_Fetched f, InsightsRange range, DateTime today)
      : allSessions = f.sessions,
        books = f.books,
        sessions = RangeFilter.sessions(f.sessions, range, today),
        range = range {
    final inRange = RangeFilter.finishedBooks(f.books, range, today);
    pagesPerDay = ReadingStats.pagesPerDay(sessions);
    allPagesPerDay = ReadingStats.pagesPerDay(allSessions);
    allMinutesPerDay = ReadingStats.minutesPerDay(allSessions);
    pagesSeries = ReadingStats.dailySeries(
      pagesPerDay,
      days: RangeFilter.chartDays(range, allSessions, today),
      today: today,
    );
    heatmapSeries =
        ReadingStats.dailySeries(allMinutesPerDay, days: 84, today: today);
    allReadingDays = ReadingStats.readingDays(allSessions);
    readingDays = ReadingStats.readingDays(sessions);
    averagePages = ReadingStats.averagePagesPerSession(sessions);
    totalPages = ReadingStats.totalPages(sessions);
    totalMinutes = ReadingStats.totalMinutes(sessions);
    totalFinished = ReadingStats.totalFinished(inRange);
    hourSeries = ReadingStats.minutesByHour(sessions);
    deviceSeries = ReadingStats.minutesByDevice(sessions);
    finishedPerMonth = ReadingStats.finishedPerMonth(inRange);
    genreSplit = ReadingStats.finishedByGenre(
      books: inRange,
      genresByBook: f.genresByBook,
    );
    formatSplit = ReadingStats.finishedByFormat(
      books: inRange,
      formatsByBook: f.formatsByBook,
    );
  }

  final InsightsRange range;
  final List<ReadingSession> allSessions;
  final List<ReadingSession> sessions;
  final List<Book> books;
  late final Map<DateTime, int> pagesPerDay;
  late final Map<DateTime, int> allPagesPerDay;
  late final Map<DateTime, int> allMinutesPerDay;
  late final List<({DateTime day, int value})> pagesSeries;
  late final List<({DateTime day, int value})> heatmapSeries;
  late final Set<DateTime> allReadingDays;
  late final Set<DateTime> readingDays;
  late final double averagePages;
  late final int totalPages;
  late final int totalMinutes;
  late final int totalFinished;
  late final List<int> hourSeries;
  late final List<({String device, int minutes})> deviceSeries;
  late final Map<DateTime, int> finishedPerMonth;
  late final List<({String genre, int count})> genreSplit;
  late final List<({String format, int count})> formatSplit;

  int get currentStreak => ReadingStats.currentStreak(allReadingDays);
  int get longestStreak => ReadingStats.longestStreak(allReadingDays);
  ({DateTime day, int pages})? get best => ReadingStats.bestDay(pagesPerDay);
  int get thisWeekPages =>
      ReadingStats.sumTrailingDays(allPagesPerDay, days: 7);
  int get lastWeekPages => ReadingStats.sumTrailingDays(
        allPagesPerDay,
        days: 7,
        endOffsetDays: 7,
      );

  List<MapEntry<DateTime, int>> get finishedMonthsNewestFirst {
    final entries = finishedPerMonth.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return entries;
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.stats});

  final List<({String label, String value, String? sub})> stats;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final stat in stats)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(stat.value, style: theme.textTheme.headlineSmall),
                  Text(stat.label, style: theme.textTheme.bodySmall),
                  if (stat.sub != null)
                    Text(
                      stat.sub!,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }
}

/// A titled card wrapping one chart or list — the shared frame that makes a
/// dozen small sections read as one screen instead of a scroll of headings.
class _Section extends StatelessWidget {
  const _Section({required this.title, required this.child, this.subtitle});

  final String title;
  final String? subtitle;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: theme.textTheme.titleMedium),
            if (subtitle != null) ...[
              const SizedBox(height: 2),
              Text(subtitle!, style: theme.textTheme.bodySmall),
            ],
            const SizedBox(height: 12),
            child,
          ],
        ),
      ),
    );
  }
}

/// The one record worth a card of its own rather than a row in a table — a
/// personal best, not a trend.
class _BestDayCard extends StatelessWidget {
  const _BestDayCard({required this.best});

  final ({DateTime day, int pages}) best;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Card(
      margin: EdgeInsets.zero,
      color: theme.colorScheme.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        child: Row(
          children: [
            Icon(Icons.emoji_events_outlined,
                color: theme.colorScheme.onPrimaryContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    l10n.insightsBestDay(best.pages),
                    style: theme.textTheme.titleSmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                  Text(
                    l10n.insightsBestDayDate(best.day),
                    style: theme.textTheme.bodySmall?.copyWith(
                      color: theme.colorScheme.onPrimaryContainer,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

/// One row of a simple magnitude table: a label, a value, and a same-hue bar
/// behind it scaled to the largest row — a table first, a chart only by
/// accident, which is the right shape for "more than a couple of classes but
/// each one matters" (the device list is rarely more than two or three).
class _BarListRow extends StatelessWidget {
  const _BarListRow({
    required this.label,
    required this.value,
    required this.fraction,
    required this.color,
  });

  final String label;
  final String value;
  final double fraction;
  final Color color;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Expanded(child: Text(label, style: theme.textTheme.bodyMedium)),
              Text(value, style: theme.textTheme.bodyMedium),
            ],
          ),
          const SizedBox(height: 4),
          ClipRRect(
            borderRadius: BorderRadius.circular(3),
            child: LinearProgressIndicator(
              value: fraction.clamp(0.0, 1.0),
              minHeight: 6,
              backgroundColor: theme.colorScheme.surfaceContainerHighest,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

/// A bare sparkline: no axes, no grid, no legend — the shape is the message.
class _SparklinePainter extends CustomPainter {
  _SparklinePainter({required this.values, required this.color});

  final List<int> values;
  final Color color;

  @override
  void paint(Canvas canvas, Size size) {
    if (values.length < 2) return;
    final max = values.reduce((a, b) => a > b ? a : b);
    if (max == 0) return;
    final dx = size.width / (values.length - 1);
    final path = Path();
    for (var i = 0; i < values.length; i++) {
      final x = dx * i;
      final y = size.height - (values[i] / max) * size.height;
      i == 0 ? path.moveTo(x, y) : path.lineTo(x, y);
    }
    canvas.drawPath(
      path,
      Paint()
        ..style = PaintingStyle.stroke
        ..strokeWidth = 2
        ..strokeJoin = StrokeJoin.round
        ..color = color,
    );
    // A soft fill under the line, so a flat stretch still reads as "some".
    final fill = Path.from(path)
      ..lineTo(size.width, size.height)
      ..lineTo(0, size.height)
      ..close();
    canvas.drawPath(fill, Paint()..color = color.withValues(alpha: 0.12));
  }

  @override
  bool shouldRepaint(_SparklinePainter old) =>
      old.values != values || old.color != color;
}

/// Minutes read by hour of day, as 24 columns — one sequential hue, tallest at
/// the hours you actually reach for a book. Rounded at the top like every
/// other bar in the app, square at the baseline, with hour labels at the
/// quarters rather than one per bar, which nobody could read at that width.
class _HourBarsPainter extends CustomPainter {
  _HourBarsPainter({
    required this.minutesByHour,
    required this.color,
    required this.empty,
    required this.labelStyle,
    required this.quarterNames,
  });

  final List<int> minutesByHour;
  final Color color;
  final Color empty;
  final TextStyle? labelStyle;

  /// Labels for hours 0, 6, 12 and 18, already localised.
  final List<String> quarterNames;

  static const _labelHeight = 16.0;
  static const _quarters = [0, 6, 12, 18];

  @override
  void paint(Canvas canvas, Size size) {
    final chartHeight = size.height - _labelHeight;
    if (chartHeight <= 0 || minutesByHour.isEmpty) return;
    final max = minutesByHour.reduce((a, b) => a > b ? a : b);
    final cell = size.width / minutesByHour.length;
    final gap = (cell * 0.2).clamp(1.0, 6.0);
    final barWidth = (cell - gap).clamp(1.0, 24.0);
    for (var hour = 0; hour < minutesByHour.length; hour++) {
      final value = minutesByHour[hour];
      final intensity = max == 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
      // A sliver even at the lowest nonzero value, so an hour that saw one
      // short sitting is still visible next to the hours that saw none.
      final barHeight =
          value == 0 ? 2.0 : (chartHeight * 0.12) + chartHeight * 0.88 * intensity;
      final left = hour * cell + gap / 2;
      final rect = Rect.fromLTWH(
        left,
        chartHeight - barHeight,
        barWidth,
        barHeight,
      );
      canvas.drawRRect(
        RRect.fromRectAndCorners(
          rect,
          topLeft: const Radius.circular(3),
          topRight: const Radius.circular(3),
        ),
        Paint()..color = value == 0 ? empty : color,
      );
    }
    final style = labelStyle;
    if (style == null) return;
    for (var i = 0; i < _quarters.length; i++) {
      final hour = _quarters[i];
      final centre = hour * cell + cell / 2;
      final painter = TextPainter(
        text: TextSpan(text: quarterNames[i], style: style),
        textDirection: TextDirection.ltr,
      )..layout();
      // Clamped so the first and last labels don't run past the chart's own
      // edges — a label that overflows its box is worse than one nudged in.
      final x = (centre - painter.width / 2)
          .clamp(0.0, size.width - painter.width);
      painter.paint(canvas, Offset(x, size.height - _labelHeight + 2));
    }
  }

  @override
  bool shouldRepaint(_HourBarsPainter old) =>
      old.minutesByHour != minutesByHour || old.color != color;
}

/// The reading goals (v1.3.1): both optional, off until the reader sets one.
///
/// Listens to the settings store so a change made in the dialog redraws the
/// card at once. The wording is neutral on purpose: "behind" is a fact about
/// the calendar, not a reprimand, and a goal that is off says nothing at all.
class _GoalsCard extends StatelessWidget {
  const _GoalsCard({
    required this.settings,
    required this.books,
    required this.minutesPerDay,
  });

  final AppSettingsStore settings;
  final List<Book> books;
  final Map<DateTime, int> minutesPerDay;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    return ListenableBuilder(
      listenable: settings,
      builder: (context, _) {
        final bookGoal = settings.readingGoalBooks;
        final minuteGoal = settings.readingGoalMinutes;
        final now = DateTime.now();
        return Card(
          margin: EdgeInsets.zero,
          child: Padding(
            padding: const EdgeInsets.all(16),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        l10n.insightsGoalsTitle,
                        style: theme.textTheme.titleMedium,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.edit_outlined),
                      tooltip: l10n.insightsGoalsEditTooltip,
                      onPressed: () => showGoalsDialog(context, settings),
                    ),
                  ],
                ),
                if (bookGoal == null && minuteGoal == null) ...[
                  Text(l10n.insightsGoalsEmpty),
                  const SizedBox(height: 8),
                  TextButton(
                    onPressed: () => showGoalsDialog(context, settings),
                    child: Text(l10n.insightsGoalsSetAction),
                  ),
                ],
                if (bookGoal != null)
                  _yearGoal(context, l10n, bookGoal, now),
                if (bookGoal != null && minuteGoal != null)
                  const SizedBox(height: 16),
                if (minuteGoal != null)
                  _dayGoal(context, l10n, minuteGoal, now),
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _yearGoal(BuildContext context, L10n l10n, int target, DateTime now) {
    final finished = ReadingGoals.finishedInYear(books, now.year);
    final pace = ReadingGoals.yearPace(
        finished: finished, target: target, today: now);
    final progress = l10n.insightsGoalBooksProgress(finished, target);
    final status = pace.reached
        ? l10n.insightsGoalBooksReached
        : pace.difference == 0
            ? l10n.insightsGoalBooksOnPace
            : pace.difference > 0
                ? l10n.insightsGoalBooksAhead(pace.difference)
                : l10n.insightsGoalBooksBehind(-pace.difference);
    return _GoalRow(
      title: l10n.insightsGoalBooksTitle('${now.year}'), // i18n-ignore
      progressText: progress,
      fraction: finished / target,
      status: status,
    );
  }

  Widget _dayGoal(BuildContext context, L10n l10n, int target, DateTime now) {
    final today = ReadingGoals.minutesToday(minutesPerDay, now);
    final met = ReadingGoals.daysMet(minutesPerDay, target: target, today: now);
    return _GoalRow(
      title: l10n.insightsGoalMinutesTitle,
      progressText: l10n.insightsGoalMinutesProgress(
        formatMinutes(l10n, today),
        formatMinutes(l10n, target),
      ),
      fraction: today / target,
      status: l10n.insightsGoalMinutesDays(met),
    );
  }
}

/// One goal: a title, a drawn bar with a spoken label, and a line of status.
class _GoalRow extends StatelessWidget {
  const _GoalRow({
    required this.title,
    required this.progressText,
    required this.fraction,
    required this.status,
  });

  final String title;
  final String progressText;
  final double fraction;
  final String status;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Text(title, style: theme.textTheme.labelLarge),
        const SizedBox(height: 4),
        Text(progressText, style: theme.textTheme.headlineSmall),
        const SizedBox(height: 8),
        // A bar alone says nothing to a screen reader, so it carries the same
        // sentence the text above shows.
        Semantics(
          label: progressText,
          child: ExcludeSemantics(
            child: ClipRRect(
              borderRadius: BorderRadius.circular(4),
              child: LinearProgressIndicator(
                value: fraction.clamp(0.0, 1.0),
                minHeight: 8,
              ),
            ),
          ),
        ),
        const SizedBox(height: 6),
        Text(
          status,
          style: theme.textTheme.bodySmall
              ?.copyWith(color: theme.colorScheme.outline),
        ),
      ],
    );
  }
}
