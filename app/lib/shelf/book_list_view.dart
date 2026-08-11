import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_queries.dart';
import '../data/reading_status.dart';
import '../widgets/page_insets.dart';

/// The library as a list, one line per book and no artwork.
///
/// The shelf and the cover grid are pictures of a library; this is the library
/// as *data*. Pictures are what make browsing pleasant and scanning slow — past
/// a few hundred books, "which of these have I not started" is not a question
/// you answer by looking at spines.
///
/// It takes [LibraryEntry] rather than plain books, unlike [ShelfView], because
/// the things worth showing here — the author, whether there is a file to open
/// — are exactly the things a spine cannot say, and they already travel with
/// the shelf's query.
class BookListView extends StatelessWidget {
  const BookListView({
    super.key,
    required this.entries,
    required this.detailBuilder,
    this.selected = const {},
    this.onToggleSelected,
    this.selectionMode = false,
  });

  final List<LibraryEntry> entries;
  final Widget Function(Book) detailBuilder;
  final Set<String> selected;
  final void Function(Book)? onToggleSelected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      padding: pageInsets(context, const EdgeInsets.symmetric(vertical: 4)),
      itemCount: entries.length,
      separatorBuilder: (_, _) => const Divider(height: 1),
      itemBuilder: (context, i) => _BookRow(
        entry: entries[i],
        detailBuilder: detailBuilder,
        ticked: selected.contains(entries[i].book.id),
        onToggleSelected: onToggleSelected,
        selectionMode: selectionMode,
      ),
    );
  }
}

class _BookRow extends StatelessWidget {
  const _BookRow({
    required this.entry,
    required this.detailBuilder,
    required this.ticked,
    required this.onToggleSelected,
    required this.selectionMode,
  });

  final LibraryEntry entry;
  final Widget Function(Book) detailBuilder;
  final bool ticked;
  final void Function(Book)? onToggleSelected;
  final bool selectionMode;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final book = entry.book;
    final toggle = onToggleSelected;
    final status = ReadingStatus.values
        .where((s) => s.name == book.status)
        .firstOrNull;

    // Author, year, and how far in you are — the line a spine cannot show.
    // Progress is given as a percentage only while a book is in progress: on a
    // finished book it is noise, and on an unread one it is nothing.
    final progress = book.readingProgress;
    final subtitle = [
      if (entry.authors.isNotEmpty) entry.authors.join(', '),
      if (book.publishedYear != null) '${book.publishedYear}',
      if (book.status == 'reading' && progress != null && progress > 0)
        '${(progress * 100).round()}%',
    ].join(' · ');

    return ListTile(
      dense: true,
      // A checkbox only in selection mode, so the ordinary list stays a list
      // rather than a form. The tick still shows, as a leading icon.
      leading: selectionMode
          ? Checkbox(
              value: ticked,
              onChanged: toggle == null ? null : (_) => toggle(book),
            )
          : Icon(
              // Whether there is something to read is the single most useful
              // thing here: a book with no file cannot be opened, and on the
              // shelf that is invisible until you tap it.
              entry.hasFile ? Icons.menu_book_outlined : Icons.bookmark_border,
              size: 20,
              color: entry.hasFile
                  ? theme.colorScheme.onSurfaceVariant
                  : theme.colorScheme.outline,
            ),
      title: Text(
        book.title,
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      subtitle: subtitle.isEmpty
          ? null
          : Text(subtitle, maxLines: 1, overflow: TextOverflow.ellipsis),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (book.rating != null) ...[
            Icon(Icons.star, size: 14, color: theme.colorScheme.primary),
            const SizedBox(width: 2),
            Text('${book.rating}', style: theme.textTheme.labelSmall),
            const SizedBox(width: 10),
          ],
          // 'unread' is the default and true of most of the library, so saying
          // it on every row would be a column of the same word.
          if (status != null && status != ReadingStatus.unread)
            Text(status.label, style: theme.textTheme.labelSmall),
        ],
      ),
      onTap: selectionMode && toggle != null
          ? () => toggle(book)
          : () {
              // Same reason as `ShelfView._openBook`: focus is restored when a
              // route pops, so leaving with the keyboard up brings it back on
              // return. This view is where searching is most likely.
              FocusScope.of(context).unfocus();
              Navigator.of(context).push(MaterialPageRoute<void>(
                builder: (_) => detailBuilder(book),
              ));
            },
      onLongPress: toggle == null ? null : () => toggle(book),
    );
  }
}
