import 'package:flutter/material.dart';

import '../data/database.dart';
import '../l10n/gen/app_localizations.dart';
import 'duration_label.dart';
import 'heatmap_grid.dart';
import 'insights_range.dart';

/// The square for one day on a heat map: shaded by minutes, and labelled for a
/// screen reader with the same figures the sheet opens with.
HeatmapCell heatmapCellFor(
  L10n l10n,
  DateTime day, {
  required Map<DateTime, int> minutes,
  required Map<DateTime, int> pages,
}) {
  final m = minutes[day] ?? 0;
  final p = pages[day] ?? 0;
  return HeatmapCell(
    day: day,
    value: m,
    label: m == 0 && p == 0
        ? l10n.insightsDayLabelNone(day)
        : l10n.insightsDayLabelRead(day, formatMinutes(l10n, m), p),
  );
}

/// Shows what was read on [day]: pages, time, sittings and the books, each of
/// which opens its detail page through [onOpenBook].
///
/// A modal bottom sheet rather than a popover: it takes focus when it opens,
/// closes with Escape or the back gesture, and reads the same for a keyboard,
/// a screen reader and a thumb.
Future<void> showDayDetailSheet(
  BuildContext context, {
  required DateTime day,
  required List<ReadingSession> sessions,
  required List<Book> books,
  required void Function(Book book) onOpenBook,
}) {
  final detail = DayDetail.of(sessions, day);
  final byId = {for (final b in books) b.id: b};
  return showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) {
      final l10n = L10n.of(sheetContext);
      final theme = Theme.of(sheetContext);
      return SafeArea(
        child: ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.sizeOf(sheetContext).height * 0.7,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 16),
            children: [
              Text(
                l10n.insightsDayTitle(detail.day),
                style: theme.textTheme.titleMedium,
              ),
              const SizedBox(height: 8),
              if (detail.isEmpty)
                Text(l10n.insightsDayNone)
              else ...[
                Wrap(
                  spacing: 16,
                  runSpacing: 4,
                  children: [
                    Text(l10n.insightsDayTime(
                        formatMinutes(l10n, detail.minutes))),
                    Text(l10n.insightsDayPages(detail.pages)),
                    Text(l10n.insightsDaySittings(detail.sittings)),
                  ],
                ),
                const SizedBox(height: 16),
                Text(l10n.insightsDayBooks, style: theme.textTheme.labelLarge),
                for (final entry in detail.books)
                  _bookTile(sheetContext, l10n, entry, byId[entry.bookId],
                      onOpenBook),
              ],
            ],
          ),
        ),
      );
    },
  );
}

Widget _bookTile(
  BuildContext sheetContext,
  L10n l10n,
  ({String bookId, int minutes, int pages}) entry,
  Book? book,
  void Function(Book book) onOpenBook,
) {
  return ListTile(
    contentPadding: EdgeInsets.zero,
    title: Text(book?.title ?? l10n.insightsDayUnknownBook),
    subtitle: Text(l10n.insightsDayBookLine(
        formatMinutes(l10n, entry.minutes), entry.pages)),
    trailing: book == null ? null : const Icon(Icons.chevron_right),
    onTap: book == null
        ? null
        : () {
            Navigator.pop(sheetContext);
            onOpenBook(book);
          },
  );
}
