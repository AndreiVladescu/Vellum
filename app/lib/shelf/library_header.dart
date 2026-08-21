import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_queries.dart';

/// Books worth surfacing above the shelf, derived from a [LibraryView].
///
/// A pure function over entries the shelf already has, which is the constraint
/// #25 sets on itself: the strip must not cost a second set of queries. It sees
/// exactly what the shelf sees — so a search or genre filter narrows it too,
/// rather than it contradicting the list underneath.
class LibraryHighlights {
  const LibraryHighlights({
    required this.continueReading,
    required this.recentlyAdded,
  });

  /// Started but not finished, most recently read first.
  final List<Book> continueReading;

  /// Newest by `createdAt`, excluding anything already in [continueReading] so
  /// a book just added and opened doesn't appear twice.
  final List<Book> recentlyAdded;

  bool get isEmpty => continueReading.isEmpty && recentlyAdded.isEmpty;

  /// Reading is "done" at 98%: a PDF's last page often never reports 1.0, and
  /// a finished book lingering in *Continue reading* forever is worse than
  /// dropping one the user might have wanted to re-open from the shelf.
  static const finishedThreshold = 0.98;

  static LibraryHighlights from(LibraryView view, {int limit = 3}) {
    final books = [for (final e in view.entries) e.book];

    final started = [
      for (final b in books)
        if (b.lastReadAt != null &&
            (b.readingProgress ?? 0) > 0 &&
            (b.readingProgress ?? 0) < finishedThreshold)
          b,
    ]..sort((a, b) => b.lastReadAt!.compareTo(a.lastReadAt!));
    final continueReading = started.take(limit).toList();

    final inProgress = {for (final b in continueReading) b.id};
    final recent = [
      for (final b in books)
        if (!inProgress.contains(b.id)) b,
    ]..sort((a, b) => b.createdAt.compareTo(a.createdAt));

    return LibraryHighlights(
      continueReading: continueReading,
      recentlyAdded: recent.take(limit).toList(),
    );
  }
}

/// A compact strip above the shelf: *Continue reading* and *Recently added*
/// (plan 5 #25).
///
/// Collapses to nothing when there's nothing to show, so a fresh library and a
/// filtered-to-nothing search both leave the shelf exactly as it was. Dismissible
/// per session rather than permanently — the value is in reappearing when you
/// come back mid-book, not in being a screen you have to manage.
class LibraryHeader extends StatelessWidget {
  const LibraryHeader({
    super.key,
    required this.highlights,
    required this.onOpen,
    this.onDismiss,
  });

  final LibraryHighlights highlights;

  /// Opens a book — the shelf's own detail route, so tapping here and tapping a
  /// spine land in the same place.
  final void Function(Book book) onOpen;

  final VoidCallback? onDismiss;

  /// Below this many logical pixels of screen height, the header shows its
  /// compact form.
  ///
  /// A phone held in landscape has roughly 400 of them, and an app bar and a
  /// navigation bar take a third of that. The full header — two titled
  /// sections, a card row, a chip row and a divider — is about 200px tall,
  /// which left the shelf underneath a sliver too short to scroll. That is the
  /// reported bug, and it is a *height* problem rather than an orientation one:
  /// a small window on a desktop has it too.
  static const compactBelowHeight = 520.0;

  static bool isCompact(BuildContext context) =>
      MediaQuery.sizeOf(context).height < compactBelowHeight;

  @override
  Widget build(BuildContext context) {
    if (highlights.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    // Compact: what you were in the middle of, and nothing else. *Recently
    // added* and the section headings are the first things to go, because
    // "carry on reading" is the only one of the three that is worth a third of
    // a short screen.
    if (isCompact(context)) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(12, 6, 4, 0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: SingleChildScrollView(
                    scrollDirection: Axis.horizontal,
                    child: Row(children: [
                      for (final book in highlights.continueReading.isNotEmpty
                          ? highlights.continueReading
                          : highlights.recentlyAdded)
                        Padding(
                          padding: const EdgeInsets.only(right: 8),
                          child: _ContinueCard(
                            book: book,
                            onTap: () => onOpen(book),
                            compact: true,
                          ),
                        ),
                    ]),
                  ),
                ),
                if (onDismiss != null)
                  IconButton(
                    icon: const Icon(Icons.close, size: 18),
                    tooltip: 'Hide for now',
                    onPressed: onDismiss,
                  ),
              ],
            ),
            Divider(height: 8, color: theme.dividerColor),
          ],
        ),
      );
    }
    return Padding(
      padding: const EdgeInsets.fromLTRB(12, 8, 4, 0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          if (highlights.continueReading.isNotEmpty)
            _Section(
              title: 'Continue reading',
              trailing: onDismiss == null
                  ? null
                  : IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Hide for now',
                      onPressed: onDismiss,
                    ),
              children: [
                for (final book in highlights.continueReading)
                  _ContinueCard(
                    book: book,
                    onTap: () => onOpen(book),
                  ),
              ],
            ),
          if (highlights.recentlyAdded.isNotEmpty)
            _Section(
              title: 'Recently added',
              trailing: highlights.continueReading.isEmpty && onDismiss != null
                  ? IconButton(
                      icon: const Icon(Icons.close, size: 18),
                      tooltip: 'Hide for now',
                      onPressed: onDismiss,
                    )
                  : null,
              children: [
                for (final book in highlights.recentlyAdded)
                  _RecentChip(book: book, onTap: () => onOpen(book)),
              ],
            ),
          Divider(height: 12, color: theme.dividerColor),
        ],
      ),
    );
  }
}

class _Section extends StatelessWidget {
  const _Section({required this.title, required this.children, this.trailing});

  final String title;
  final List<Widget> children;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            // Expanded, not a bare Text + Spacer: at 2x text scale the title
            // alone is wider than a phone, and a Row won't shrink it (caught by
            // test/widgets/large_text_test.dart).
            Expanded(
              child: Text(
                title,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: Theme.of(context).textTheme.labelLarge,
              ),
            ),
            ?trailing,
          ],
        ),
        const SizedBox(height: 4),
        // Horizontal, so three entries never push the shelf itself off screen
        // on a phone.
        SingleChildScrollView(
          scrollDirection: Axis.horizontal,
          child: Row(children: [
            for (final child in children)
              Padding(
                padding: const EdgeInsets.only(right: 8),
                child: child,
              ),
          ]),
        ),
        const SizedBox(height: 8),
      ],
    );
  }
}

class _ContinueCard extends StatelessWidget {
  const _ContinueCard({
    required this.book,
    required this.onTap,
    this.compact = false,
  });

  final Book book;
  final VoidCallback onTap;

  /// Half the height: the title and the progress bar, with the percentage
  /// folded onto the title's line instead of below it.
  final bool compact;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final progress = (book.readingProgress ?? 0).clamp(0.0, 1.0);
    if (compact) {
      return SizedBox(
        width: 200,
        child: Card(
          margin: EdgeInsets.zero,
          child: InkWell(
            onTap: onTap,
            borderRadius: BorderRadius.circular(12),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      Expanded(
                        child: Text(
                          book.title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall,
                        ),
                      ),
                      if (progress > 0)
                        Text('${(progress * 100).round()}%',
                            style: theme.textTheme.bodySmall),
                    ],
                  ),
                  if (progress > 0) ...[
                    const SizedBox(height: 5),
                    LinearProgressIndicator(value: progress, minHeight: 3),
                  ],
                ],
              ),
            ),
          ),
        ),
      );
    }
    return SizedBox(
      width: 220,
      child: Card(
        margin: EdgeInsets.zero,
        child: InkWell(
          onTap: onTap,
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.all(10),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  book.title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.titleSmall,
                ),
                const SizedBox(height: 6),
                LinearProgressIndicator(value: progress),
                const SizedBox(height: 4),
                Text(
                  '${(progress * 100).round()}%'
                  '${book.lastReadPage == null ? '' : ' · page ${book.lastReadPage}'}',
                  style: theme.textTheme.bodySmall,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

class _RecentChip extends StatelessWidget {
  const _RecentChip({required this.book, required this.onTap});

  final Book book;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) => ActionChip(
        label: Text(
          book.title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
        ),
        avatar: const Icon(Icons.book_outlined, size: 16),
        onPressed: onTap,
      );
}
