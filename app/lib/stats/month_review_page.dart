import 'package:flutter/material.dart';

import '../book_detail/book_detail_page.dart';
import '../data/database.dart';
import '../data/library_repository.dart';
import '../l10n/gen/app_localizations.dart';
import '../settings/app_settings.dart';
import '../widgets/page_insets.dart';
import 'day_detail_sheet.dart';
import 'duration_label.dart';
import 'heatmap_grid.dart';
import 'month_review.dart';

/// Opens a book's detail page, the way the author and wishlist pages do.
void openBookDetail(
  BuildContext context, {
  required LibraryRepository repository,
  required AppSettingsStore settings,
  required Book book,
}) {
  Navigator.of(context).push(MaterialPageRoute<void>(
    builder: (_) => BookDetailPage(
      book: book,
      repository: repository,
      settings: settings,
    ),
  ));
}

/// Month by month (roadmap v1.3.2): one calendar month of reading, with
/// arrows and a list to move between months.
///
/// Both reads are drift `watch()` streams, so a sitting recorded while this
/// page is open shows up in it. The wording of the month-on-month line is
/// neutral on purpose: it is a record to look at, not a target to have missed.
class MonthReviewPage extends StatefulWidget {
  const MonthReviewPage({
    super.key,
    required this.repository,
    required this.settings,
    this.now,
  });

  final LibraryRepository repository;
  final AppSettingsStore settings;

  /// Overrides "today" for tests.
  final DateTime? now;

  @override
  State<MonthReviewPage> createState() => _MonthReviewPageState();
}

class _MonthReviewPageState extends State<MonthReviewPage> {
  late DateTime _month = MonthReviews.monthOf(widget.now ?? DateTime.now());

  DateTime get _today => widget.now ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final db = widget.repository.db;
    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).monthTitle)),
      body: StreamBuilder<List<ReadingSession>>(
        stream: db.select(db.readingSessions).watch(),
        builder: (context, sessionSnap) => StreamBuilder<List<Book>>(
          stream: db.select(db.books).watch(),
          builder: (context, bookSnap) {
            if (!sessionSnap.hasData || !bookSnap.hasData) {
              return const Center(child: CircularProgressIndicator());
            }
            return _body(context, sessionSnap.data!, bookSnap.data!);
          },
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    List<ReadingSession> sessions,
    List<Book> books,
  ) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final today = _today;
    final current = MonthReviews.monthOf(today);
    final first = MonthReviews.firstMonth(sessions, today: today);
    // The page can be open while history is cleared; never sit on a month
    // outside the range that is now offered.
    final month = _month.isAfter(current)
        ? current
        : (_month.isBefore(first) ? first : _month);
    final review = MonthReviews.review(
      sessions: sessions,
      books: books,
      month: month,
      today: today,
      minuteGoal: widget.settings.readingGoalMinutes,
    );
    final canGoBack = month.isAfter(first);
    final canGoForward = month.isBefore(current);

    return ListView(
      padding: pageInsets(context, const EdgeInsets.all(16)),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: l10n.monthPreviousTooltip,
              onPressed:
                  canGoBack ? () => setState(() => _month = MonthReviews.addMonths(month, -1)) : null,
            ),
            Expanded(
              child: TextButton(
                onPressed: () => _pickMonth(context, sessions, month),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Flexible(
                      child: Text(
                        l10n.monthHeading(month),
                        style: theme.textTheme.titleLarge,
                        textAlign: TextAlign.center,
                      ),
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: l10n.monthNextTooltip,
              onPressed:
                  canGoForward ? () => setState(() => _month = MonthReviews.addMonths(month, 1)) : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (review.isEmpty)
          _EmptyMonth(month: month)
        else ...[
          _stats(context, review),
          const SizedBox(height: 20),
          _calendar(context, review, sessions, books),
          const SizedBox(height: 20),
          _comparison(context, sessions, review),
          if (review.goalDaysMet != null) ...[
            const SizedBox(height: 12),
            Text(
              l10n.monthGoalDays(
                review.goalDaysMet!,
                formatMinutes(l10n, widget.settings.readingGoalMinutes!),
              ),
              style: theme.textTheme.bodyMedium,
            ),
          ],
          if (review.finished.isNotEmpty) ...[
            const SizedBox(height: 20),
            Card(
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(16),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(l10n.insightsBooksFinished,
                        style: theme.textTheme.titleMedium),
                    const SizedBox(height: 4),
                    for (final book in review.finished)
                      ListTile(
                        contentPadding: EdgeInsets.zero,
                        title: Text(book.title),
                        trailing: const Icon(Icons.chevron_right),
                        onTap: () => openBookDetail(
                          context,
                          repository: widget.repository,
                          settings: widget.settings,
                          book: book,
                        ),
                      ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ],
    );
  }

  Future<void> _pickMonth(
    BuildContext context,
    List<ReadingSession> sessions,
    DateTime selected,
  ) async {
    final l10n = L10n.of(context);
    final months = MonthReviews.monthsWithReading(sessions, today: _today);
    final picked = await showModalBottomSheet<DateTime>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
                child: Text(l10n.monthPickerTitle,
                    style: Theme.of(sheetContext).textTheme.titleMedium),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final m in months)
                      ListTile(
                        title: Text(l10n.monthHeading(m)),
                        selected: m == selected,
                        trailing: m == selected ? const Icon(Icons.check) : null,
                        onTap: () => Navigator.pop(sheetContext, m),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _month = picked);
  }

  Widget _stats(BuildContext context, MonthReview review) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final best = review.best;
    final longest = review.longestSitting;
    final average = review.averageMinutesPerReadingDay;
    final tiles = <({String label, String value, String? sub})>[
      (
        label: l10n.insightsPagesRead,
        value: '${review.pages}', // i18n-ignore
        sub: null,
      ),
      (
        label: l10n.monthTimeRead,
        value: formatMinutes(l10n, review.minutes),
        sub: null,
      ),
      (
        label: l10n.insightsDaysRead,
        value: l10n.monthDaysReadValue(review.readingDays, review.daysElapsed),
        sub: null,
      ),
      if (average != null)
        (
          label: l10n.monthAveragePerDay,
          value: formatMinutes(l10n, average),
          sub: null,
        ),
      if (longest != null)
        (
          label: l10n.monthLongestSitting,
          value: formatMinutes(l10n, longest.minutes),
          sub: l10n.monthDayShort(longest.day),
        ),
      if (best != null)
        (
          label: l10n.monthBestDay,
          value: best.pages > 0
              ? l10n.monthBestDayPages(best.pages)
              : formatMinutes(l10n, best.minutes),
          sub: l10n.monthDayShort(best.day),
        ),
    ];
    return Wrap(
      spacing: 12,
      runSpacing: 12,
      children: [
        for (final tile in tiles)
          Card(
            margin: EdgeInsets.zero,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(tile.value, style: theme.textTheme.headlineSmall),
                  Text(tile.label, style: theme.textTheme.bodySmall),
                  if (tile.sub != null)
                    Text(
                      tile.sub!,
                      style: theme.textTheme.bodySmall
                          ?.copyWith(color: theme.colorScheme.outline),
                    ),
                ],
              ),
            ),
          ),
      ],
    );
  }

  Widget _calendar(
    BuildContext context,
    MonthReview review,
    List<ReadingSession> sessions,
    List<Book> books,
  ) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final material = MaterialLocalizations.of(context);
    final firstDow = material.firstDayOfWeekIndex;
    final blanks = MonthReviews.leadingBlanks(review.month, firstDow);
    final rows = MonthReviews.weekRows(review.month, firstDow);
    final total = MonthReviews.daysInMonth(review.month.year, review.month.month);
    final cells = <HeatmapCell?>[
      for (var i = 0; i < blanks; i++) null,
      for (var d = 1; d <= total; d++)
        heatmapCellFor(
          l10n,
          DateTime(review.month.year, review.month.month, d),
          minutes: review.minutesByDay,
          pages: review.pagesByDay,
        ),
      // Pad to whole weeks so the layout maths never sees a short last row.
      for (var i = blanks + total; i < rows * 7; i++) null,
    ];
    const maxCell = 44.0;
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.monthCalendarTitle, style: theme.textTheme.titleMedium),
            const SizedBox(height: 2),
            Text(l10n.monthCalendarSub, style: theme.textTheme.bodySmall),
            const SizedBox(height: 12),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: maxCell * 7),
              child: Column(
                children: [
                  ExcludeSemantics(
                    child: Row(
                      children: [
                        for (final weekday in MonthReviews.weekdayOrder(firstDow))
                          Expanded(
                            child: Text(
                              material.narrowWeekdays[weekday],
                              textAlign: TextAlign.center,
                              style: theme.textTheme.bodySmall,
                            ),
                          ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 4),
                  HeatmapGrid(
                    cells: cells,
                    rows: rows,
                    columns: 7,
                    rowMajor: true,
                    maxCell: maxCell,
                    showDayNumbers: true,
                    color: theme.colorScheme.primary,
                    empty: theme.colorScheme.surfaceContainerHighest,
                    onColor: theme.colorScheme.onPrimary,
                    textColor: theme.colorScheme.onSurface,
                    focusColor: theme.colorScheme.tertiary,
                    semanticsLabel: l10n.monthHeading(review.month),
                    onDayTap: (day) => showDayDetailSheet(
                      context,
                      day: day,
                      sessions: sessions,
                      books: books,
                      onOpenBook: (book) => openBookDetail(
                        context,
                        repository: widget.repository,
                        settings: widget.settings,
                        book: book,
                      ),
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

  Widget _comparison(
    BuildContext context,
    List<ReadingSession> sessions,
    MonthReview review,
  ) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final prev = MonthReviews.addMonths(review.month, -1);
    final figures =
        MonthReviews.previousFigures(sessions: sessions, review: review);
    final pages = MonthReviews.compare(review.pages, figures.pages);
    final time = MonthReviews.compare(review.minutes, figures.minutes);
    final partial = MonthReviews.isPartial(review);
    final lines = <String>[
      if (pages.trend == MonthTrend.none && time.trend == MonthTrend.none)
        l10n.monthCompareNone(prev)
      else ...[
        partial
            ? l10n.monthComparePagesSoFar(pages.trend.name, pages.percent, prev)
            : l10n.monthComparePages(pages.trend.name, pages.percent, prev),
        partial
            ? l10n.monthCompareTimeSoFar(time.trend.name, time.percent, prev)
            : l10n.monthCompareTime(time.trend.name, time.percent, prev),
      ],
    ];
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(l10n.monthCompareTitle(prev),
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            for (final line in lines)
              Padding(
                padding: const EdgeInsets.only(bottom: 4),
                child: Text(line),
              ),
          ],
        ),
      ),
    );
  }
}

class _EmptyMonth extends StatelessWidget {
  const _EmptyMonth({required this.month});

  final DateTime month;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.event_note_outlined, size: 48),
          const SizedBox(height: 12),
          Text(l10n.monthEmptyTitle(month), textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(l10n.monthEmptyBody, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
