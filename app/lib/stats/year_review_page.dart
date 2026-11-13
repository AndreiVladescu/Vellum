import 'dart:io';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../l10n/gen/app_localizations.dart';
import '../settings/app_settings.dart';
import '../widgets/page_insets.dart';
import 'duration_label.dart';
import 'month_review.dart';
import 'month_review_page.dart' show openBookDetail;
import 'year_card.dart';
import 'year_review.dart';

/// Year in review (roadmap v1.3.5): one calendar year of reading, a picture
/// of it to save or share, and arrows and a list to move between years.
///
/// Like the month page, it reads drift `watch()` streams, so it follows a
/// sitting recorded while it is open. The wording stays neutral: it is a
/// record, not a target.
class YearReviewPage extends StatefulWidget {
  const YearReviewPage({
    super.key,
    required this.repository,
    required this.settings,
    this.now,
    this.initialYear,
  });

  final LibraryRepository repository;
  final AppSettingsStore settings;

  /// Overrides "today" for tests.
  final DateTime? now;

  /// The year to open on; defaults to the current one.
  final int? initialYear;

  @override
  State<YearReviewPage> createState() => _YearReviewPageState();
}

class _YearReviewPageState extends State<YearReviewPage> {
  late int _year =
      widget.initialYear ?? (widget.now ?? DateTime.now()).toLocal().year;

  // Identifies the card's RepaintBoundary so it can be turned into a PNG.
  final GlobalKey _cardKey = GlobalKey();
  bool _busy = false;

  DateTime get _today => widget.now ?? DateTime.now();

  @override
  Widget build(BuildContext context) {
    final db = widget.repository.db;
    final repo = widget.repository;
    return Scaffold(
      appBar: AppBar(title: Text(L10n.of(context).yearTitle)),
      // Four streams, nested: StreamBuilder takes one each. The page shows a
      // spinner until all four have delivered their first value.
      body: StreamBuilder<List<ReadingSession>>(
        stream: db.select(db.readingSessions).watch(),
        builder: (context, sessionSnap) => StreamBuilder<List<Book>>(
          stream: db.select(db.books).watch(),
          builder: (context, bookSnap) =>
              StreamBuilder<Map<String, List<String>>>(
            stream: repo.watchAuthorsByBook(),
            builder: (context, authorSnap) =>
                StreamBuilder<Map<String, List<String>>>(
              stream: repo.watchGenresByBook(),
              builder: (context, genreSnap) {
                if (!sessionSnap.hasData ||
                    !bookSnap.hasData ||
                    !authorSnap.hasData ||
                    !genreSnap.hasData) {
                  return const Center(child: CircularProgressIndicator());
                }
                return _body(
                  context,
                  sessionSnap.data!,
                  bookSnap.data!,
                  authorSnap.data!,
                  genreSnap.data!,
                );
              },
            ),
          ),
        ),
      ),
    );
  }

  Widget _body(
    BuildContext context,
    List<ReadingSession> sessions,
    List<Book> books,
    Map<String, List<String>> authors,
    Map<String, List<String>> genres,
  ) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final years = YearReviews.yearsWithActivity(
        sessions: sessions, books: books, today: _today);
    final newest = years.first;
    final oldest = years.last;
    // History can be cleared while the page is open; stay inside the range
    // that is offered.
    final year = _year > newest ? newest : (_year < oldest ? oldest : _year);
    final review = YearReviews.review(
      sessions: sessions,
      books: books,
      year: year,
      authorsByBook: authors,
      genresByBook: genres,
      bookGoal: widget.settings.readingGoalBooks,
    );

    return ListView(
      padding: pageInsets(context, const EdgeInsets.all(16)),
      children: [
        Row(
          children: [
            IconButton(
              icon: const Icon(Icons.chevron_left),
              tooltip: l10n.yearPreviousTooltip,
              onPressed:
                  year > oldest ? () => setState(() => _year = year - 1) : null,
            ),
            Expanded(
              child: TextButton(
                onPressed: () => _pickYear(context, years, year),
                child: Row(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text(
                      l10n.yearHeading('$year'), // i18n-ignore
                      style: theme.textTheme.titleLarge,
                    ),
                    const Icon(Icons.arrow_drop_down),
                  ],
                ),
              ),
            ),
            IconButton(
              icon: const Icon(Icons.chevron_right),
              tooltip: l10n.yearNextTooltip,
              onPressed:
                  year < newest ? () => setState(() => _year = year + 1) : null,
            ),
          ],
        ),
        const SizedBox(height: 12),
        if (review.isEmpty)
          _EmptyYear(year: year)
        else ...[
          _picture(context, review),
          const SizedBox(height: 20),
          if (review.longestSitting != null) ...[
            Text(
              '${l10n.monthLongestSitting}: ' // i18n-ignore
              '${formatMinutes(l10n, review.longestSitting!.minutes)} '
              '(${l10n.monthDayShort(review.longestSitting!.day)})', // i18n-ignore
            ),
            const SizedBox(height: 12),
          ],
          if (review.goalBooks != null) ...[
            _goal(context, review),
            const SizedBox(height: 12),
          ],
          _comparison(context, sessions, books, review),
          if (review.topAuthors.isNotEmpty) ...[
            const SizedBox(height: 12),
            _topList(context, l10n.yearTopAuthors, review.topAuthors),
          ],
          if (review.topGenres.isNotEmpty) ...[
            const SizedBox(height: 12),
            _topList(context, l10n.yearTopGenres, review.topGenres),
          ],
          if (review.finished.isNotEmpty) ...[
            const SizedBox(height: 12),
            _finishedList(context, review),
          ],
        ],
      ],
    );
  }

  /// The card, scaled down to fit a narrow screen, with its save/share button.
  Widget _picture(BuildContext context, YearReview review) {
    final l10n = L10n.of(context);
    return Column(
      children: [
        Center(
          // FittedBox shrinks the fixed-size card on a phone. It sits outside
          // the RepaintBoundary, so the saved picture is still full size.
          child: FittedBox(
            fit: BoxFit.scaleDown,
            child: RepaintBoundary(
              key: _cardKey,
              child: YearCard(review: review),
            ),
          ),
        ),
        const SizedBox(height: 12),
        FilledButton.icon(
          onPressed: _busy ? null : () => _export(review.year),
          icon: Icon(_isMobile ? Icons.ios_share : Icons.save_alt),
          label: Text(
              _isMobile ? l10n.yearSharePicture : l10n.yearSavePicture),
        ),
      ],
    );
  }

  bool get _isMobile =>
      defaultTargetPlatform == TargetPlatform.android ||
      defaultTargetPlatform == TargetPlatform.iOS;

  /// Phones share a temporary file (there is no save dialog there); desktops
  /// ask where to save, as the backup export does.
  Future<void> _export(int year) async {
    final l10n = L10n.of(context);
    final messenger = ScaffoldMessenger.of(context);
    final name = 'vellum-year-$year.png';
    setState(() => _busy = true);
    try {
      final bytes = await captureYearCard(_cardKey);
      if (_isMobile) {
        final file = File(p.join((await getTemporaryDirectory()).path, name));
        await file.writeAsBytes(bytes, flush: true);
        await SharePlus.instance.share(ShareParams(
          files: [XFile(file.path, mimeType: 'image/png')],
        ));
      } else {
        final location = await getSaveLocation(
          suggestedName: name,
          acceptedTypeGroups: const [
            XTypeGroup(label: 'PNG', extensions: ['png']), // i18n-ignore
          ],
        );
        if (location == null) return; // cancelled
        await File(location.path).writeAsBytes(bytes, flush: true);
        messenger.showSnackBar(
            SnackBar(content: Text(l10n.yearPictureSaved(location.path))));
      }
    } catch (e) {
      messenger.showSnackBar(
          SnackBar(content: Text(l10n.yearPictureFailed('$e'))));
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  Widget _goal(BuildContext context, YearReview review) {
    final l10n = L10n.of(context);
    final goal = review.goalBooks!;
    return _card(
      context,
      title: l10n.insightsBooksFinished,
      children: [
        Text(l10n.yearGoalProgress(review.booksFinished, goal)),
        const SizedBox(height: 8),
        LinearProgressIndicator(
          value: (review.booksFinished / goal).clamp(0.0, 1.0),
        ),
        if (review.goalReached == true) ...[
          const SizedBox(height: 8),
          Text(l10n.yearGoalReached),
        ],
      ],
    );
  }

  Widget _comparison(
    BuildContext context,
    List<ReadingSession> sessions,
    List<Book> books,
    YearReview review,
  ) {
    final l10n = L10n.of(context);
    final prev = '${review.year - 1}'; // i18n-ignore
    final figures = YearReviews.previousFigures(
        sessions: sessions, books: books, year: review.year);
    final booksCmp =
        MonthReviews.compare(review.booksFinished, figures.books);
    final pagesCmp = MonthReviews.compare(review.pages, figures.pages);
    final timeCmp = MonthReviews.compare(review.minutes, figures.minutes);
    final none = booksCmp.trend == MonthTrend.none &&
        pagesCmp.trend == MonthTrend.none &&
        timeCmp.trend == MonthTrend.none;
    return _card(
      context,
      title: l10n.yearCompareTitle(prev),
      children: [
        if (none)
          Text(l10n.yearCompareTime('none', 0, prev))
        else ...[
          Text(l10n.yearCompareBooks(booksCmp.trend.name, booksCmp.percent, prev)),
          const SizedBox(height: 4),
          Text(l10n.yearComparePages(pagesCmp.trend.name, pagesCmp.percent, prev)),
          const SizedBox(height: 4),
          Text(l10n.yearCompareTime(timeCmp.trend.name, timeCmp.percent, prev)),
        ],
      ],
    );
  }

  Widget _topList(BuildContext context, String title,
      List<({String name, int count})> entries) {
    final l10n = L10n.of(context);
    return _card(
      context,
      title: title,
      children: [
        for (final e in entries)
          Padding(
            padding: const EdgeInsets.only(bottom: 4),
            child: Text(l10n.yearTopEntry(e.name, e.count)),
          ),
      ],
    );
  }

  Widget _finishedList(BuildContext context, YearReview review) {
    return _card(
      context,
      title: L10n.of(context).insightsBooksFinished,
      children: [
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
    );
  }

  Widget _card(BuildContext context,
      {required String title, required List<Widget> children}) {
    return Card(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(title, style: Theme.of(context).textTheme.titleMedium),
            const SizedBox(height: 8),
            ...children,
          ],
        ),
      ),
    );
  }

  Future<void> _pickYear(
      BuildContext context, List<int> years, int selected) async {
    final l10n = L10n.of(context);
    final picked = await showModalBottomSheet<int>(
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
                child: Text(l10n.yearPickerTitle,
                    style: Theme.of(sheetContext).textTheme.titleMedium),
              ),
              Flexible(
                child: ListView(
                  shrinkWrap: true,
                  children: [
                    for (final y in years)
                      ListTile(
                        title: Text(l10n.yearHeading('$y')), // i18n-ignore
                        selected: y == selected,
                        trailing: y == selected ? const Icon(Icons.check) : null,
                        onTap: () => Navigator.pop(sheetContext, y),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
    if (picked != null && mounted) setState(() => _year = picked);
  }
}

class _EmptyYear extends StatelessWidget {
  const _EmptyYear({required this.year});

  final int year;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 32),
      child: Column(
        children: [
          const Icon(Icons.event_note_outlined, size: 48),
          const SizedBox(height: 12),
          Text(l10n.yearEmptyTitle('$year'), // i18n-ignore
              textAlign: TextAlign.center),
          const SizedBox(height: 8),
          Text(l10n.yearEmptyBody, textAlign: TextAlign.center),
        ],
      ),
    );
  }
}
