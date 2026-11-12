import 'package:drift/drift.dart' show OrderingTerm;
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../l10n/gen/app_localizations.dart';
import '../stats/book_reading_stats.dart';
import '../stats/duration_label.dart';

/// "Your reading" on the book page: time, sittings, dates and, where the unit
/// allows it, pace and an estimate of the time left. Absent entirely until the
/// book has a recorded sitting.
///
/// It watches only this book's sittings (`reading_sessions.book_id` is indexed
/// as `idx_reading_sessions_book`), so the page updates the moment a sitting
/// ends and opening a book costs one narrow query.
class ReadingStatsSection extends StatelessWidget {
  const ReadingStatsSection({
    super.key,
    required this.book,
    required this.repository,
  });

  final Book book;
  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    final db = repository.db;
    final sessions = (db.select(db.readingSessions)
          ..where((s) => s.bookId.equals(book.id))
          ..orderBy([(s) => OrderingTerm.asc(s.startedAt)]))
        .watch();
    return StreamBuilder<List<ReadingSession>>(
      stream: sessions,
      builder: (context, snapshot) {
        final reading = BookReading.of(snapshot.data ?? const []);
        if (reading == null) return const SizedBox.shrink();
        return StreamBuilder<List<BookFile>>(
          stream: repository.watchFilesOf(book.id),
          builder: (context, files) => _Body(
            book: book,
            reading: reading,
            paceUnitsAreComparable:
                _pagesComparable(files.data ?? const <BookFile>[]),
          ),
        );
      },
    );
  }

  /// Whether sittings and [Book.pageCount] count the same thing.
  ///
  /// A PDF sitting records PDF page numbers, which are what the page count is
  /// about. An EPUB sitting records the *chapter* it ended in (the reader writes
  /// `chapter + 1`), and the book has no chapter count in the database, so a
  /// pages-a-minute figure would really be chapters a minute and "pageCount
  /// minus chapter" is nonsense. Sittings do not record which file they came
  /// from, so a book that has an EPUB at all gets time and sittings only.
  static bool _pagesComparable(List<BookFile> files) =>
      files.isNotEmpty && files.every((f) => f.format.toLowerCase() == 'pdf');
}

class _Body extends StatelessWidget {
  const _Body({
    required this.book,
    required this.reading,
    required this.paceUnitsAreComparable,
  });

  final Book book;
  final BookReading reading;
  final bool paceUnitsAreComparable;

  @override
  Widget build(BuildContext context) {
    final l10n = L10n.of(context);
    final theme = Theme.of(context);
    final pace = paceUnitsAreComparable ? reading.pagesPerMinute : null;
    // A finished book has nothing left to estimate.
    final left = paceUnitsAreComparable && book.finishedAt == null
        ? BookReading.minutesLeft(
            pace: pace,
            pageCount: book.pageCount,
            currentPage: book.lastReadPage,
          )
        : null;
    final rows = <(String, String)>[
      (l10n.detailReadingTimeLabel, formatMinutes(l10n, reading.minutes)),
      (l10n.detailReadingSittingsLabel, '${reading.sittings}'), // i18n-ignore
      (l10n.detailReadingFirstLabel, l10n.detailReadingDate(reading.first)),
      (l10n.detailReadingLastLabel, l10n.detailReadingDate(reading.last)),
      if (pace != null)
        (l10n.detailReadingPaceLabel, l10n.detailReadingPace(pace)),
      if (left != null)
        (
          l10n.detailReadingTimeLeftLabel,
          l10n.detailReadingTimeLeft(formatMinutes(l10n, left)),
        ),
    ];
    return Padding(
      padding: const EdgeInsets.only(top: 8, bottom: 8),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(l10n.detailReadingTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 8),
          for (final (label, value) in rows)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 2),
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(
                    child: Text(label, style: theme.textTheme.bodyMedium),
                  ),
                  const SizedBox(width: 12),
                  Flexible(
                    child: Text(
                      value,
                      textAlign: TextAlign.end,
                      style: theme.textTheme.bodyMedium
                          ?.copyWith(fontWeight: FontWeight.w600),
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );
  }
}
