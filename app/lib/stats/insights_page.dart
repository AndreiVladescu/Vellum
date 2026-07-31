import 'package:flutter/material.dart';
import '../widgets/page_insets.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import 'stats_queries.dart';

/// Reading insights (plan 5 #19).
///
/// Built from data the app was already collecting and discarding, and it never
/// leaves the device — unlike a cloud tracker, nothing here is uploaded, and
/// "Clear reading history" really does delete it.
///
/// Charts are hand-drawn with `CustomPaint` rather than pulling in a charting
/// package: there are two of them, they follow the app's colour scheme, and the
/// dependency would outweigh the drawing.
class InsightsPage extends StatefulWidget {
  const InsightsPage({super.key, required this.repository});

  final LibraryRepository repository;

  @override
  State<InsightsPage> createState() => _InsightsPageState();
}

class _InsightsPageState extends State<InsightsPage> {
  late Future<_Insights> _insights;

  @override
  void initState() {
    super.initState();
    _insights = _load();
  }

  Future<_Insights> _load() async {
    final db = widget.repository.db;
    final sessions = await db.select(db.readingSessions).get();
    final books = await db.select(db.books).get();
    final genresByBook = await widget.repository.watchGenresByBook().first;
    return _Insights(
      sessions: sessions,
      books: books,
      genresByBook: genresByBook,
    );
  }

  Future<void> _clearHistory() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Clear reading history?'),
        content: const Text(
          'Deletes every recorded reading session on this device. Your books, '
          'positions, and annotations are untouched. This can’t be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Clear'),
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
      SnackBar(content: Text('Cleared $removed session(s)')),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Reading insights'),
        actions: [
          IconButton(
            icon: const Icon(Icons.delete_sweep_outlined),
            tooltip: 'Clear reading history',
            onPressed: _clearHistory,
          ),
        ],
      ),
      body: FutureBuilder<_Insights>(
        future: _insights,
        builder: (context, snapshot) {
          if (!snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }
          final data = snapshot.data!;
          if (data.sessions.isEmpty && data.finishedPerMonth.isEmpty) {
            return const Center(
              child: Padding(
                padding: EdgeInsets.all(24),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.insights_outlined, size: 48),
                    SizedBox(height: 12),
                    Text('Nothing to show yet'),
                    SizedBox(height: 8),
                    Text(
                      'Read a few pages and this fills in. Everything here stays '
                      'on this device.',
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              ),
            );
          }
          return ListView(
            padding: pageInsets(context, EdgeInsets.all(16)),
            children: [
              _StatRow(stats: [
                (label: 'Current streak', value: '${data.currentStreak}d'),
                (label: 'Longest streak', value: '${data.longestStreak}d'),
                (
                  label: 'Pages / session',
                  value: data.averagePages.toStringAsFixed(0)
                ),
                (label: 'Days read', value: '${data.readingDays.length}'),
              ]),
              const SizedBox(height: 24),
              Text('Pages a day (last 30)',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SizedBox(
                height: 90,
                child: CustomPaint(
                  painter: _SparklinePainter(
                    values: [for (final p in data.pagesSeries) p.value],
                    color: Theme.of(context).colorScheme.primary,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              const SizedBox(height: 24),
              Text('Reading days (last 12 weeks)',
                  style: Theme.of(context).textTheme.titleMedium),
              const SizedBox(height: 8),
              SizedBox(
                height: 108,
                child: CustomPaint(
                  painter: _HeatmapPainter(
                    series: data.heatmapSeries,
                    color: Theme.of(context).colorScheme.primary,
                    empty: Theme.of(context).colorScheme.surfaceContainerHighest,
                  ),
                  child: const SizedBox.expand(),
                ),
              ),
              if (data.finishedPerMonth.isNotEmpty) ...[
                const SizedBox(height: 24),
                Text('Books finished',
                    style: Theme.of(context).textTheme.titleMedium),
                for (final entry in data.finishedMonthsNewestFirst)
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text('${entry.key.year}-'
                        '${entry.key.month.toString().padLeft(2, '0')}'),
                    trailing: Text('${entry.value}'),
                  ),
              ],
              if (data.genreSplit.isNotEmpty) ...[
                const SizedBox(height: 16),
                Text('What you finish',
                    style: Theme.of(context).textTheme.titleMedium),
                for (final slice in data.genreSplit.take(6))
                  ListTile(
                    dense: true,
                    contentPadding: EdgeInsets.zero,
                    title: Text(slice.genre),
                    trailing: Text('${slice.count}'),
                  ),
              ],
              const SizedBox(height: 24),
              Text(
                'Reading history never leaves this device and is not synced.',
                style: Theme.of(context).textTheme.bodySmall,
              ),
            ],
          );
        },
      ),
    );
  }
}

/// Everything the page shows, computed once from one fetch.
class _Insights {
  _Insights({
    required this.sessions,
    required this.books,
    required Map<String, List<String>> genresByBook,
  })  : pagesSeries = ReadingStats.dailySeries(
          ReadingStats.pagesPerDay(sessions),
        ),
        heatmapSeries = ReadingStats.dailySeries(
          ReadingStats.minutesPerDay(sessions),
          days: 84,
        ),
        readingDays = ReadingStats.readingDays(sessions),
        averagePages = ReadingStats.averagePagesPerSession(sessions),
        finishedPerMonth = ReadingStats.finishedPerMonth(books),
        genreSplit = ReadingStats.finishedByGenre(
          books: books,
          genresByBook: genresByBook,
        );

  final List<ReadingSession> sessions;
  final List<Book> books;
  final List<({DateTime day, int value})> pagesSeries;
  final List<({DateTime day, int value})> heatmapSeries;
  final Set<DateTime> readingDays;
  final double averagePages;
  final Map<DateTime, int> finishedPerMonth;
  final List<({String genre, int count})> genreSplit;

  int get currentStreak => ReadingStats.currentStreak(readingDays);
  int get longestStreak => ReadingStats.longestStreak(readingDays);

  List<MapEntry<DateTime, int>> get finishedMonthsNewestFirst {
    final entries = finishedPerMonth.entries.toList()
      ..sort((a, b) => b.key.compareTo(a.key));
    return entries;
  }
}

class _StatRow extends StatelessWidget {
  const _StatRow({required this.stats});

  final List<({String label, String value})> stats;

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
                ],
              ),
            ),
          ),
      ],
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

/// A calendar heat map, weeks as columns.
class _HeatmapPainter extends CustomPainter {
  _HeatmapPainter({
    required this.series,
    required this.color,
    required this.empty,
  });

  final List<({DateTime day, int value})> series;
  final Color color;
  final Color empty;

  @override
  void paint(Canvas canvas, Size size) {
    if (series.isEmpty) return;
    const rows = 7;
    final columns = (series.length / rows).ceil();
    final cell = (size.width / columns).clamp(4.0, size.height / rows);
    final gap = cell * 0.15;
    final max = series.fold<int>(0, (m, e) => e.value > m ? e.value : m);
    for (var i = 0; i < series.length; i++) {
      final column = i ~/ rows;
      final row = i % rows;
      final value = series[i].value;
      final intensity = max == 0 ? 0.0 : (value / max).clamp(0.0, 1.0);
      canvas.drawRRect(
        RRect.fromRectAndRadius(
          Rect.fromLTWH(
            column * cell,
            row * cell,
            cell - gap,
            cell - gap,
          ),
          const Radius.circular(2),
        ),
        Paint()
          ..color = value == 0
              ? empty
              : color.withValues(alpha: 0.25 + 0.75 * intensity),
      );
    }
  }

  @override
  bool shouldRepaint(_HeatmapPainter old) => old.series != series;
}
