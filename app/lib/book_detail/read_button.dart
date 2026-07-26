import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../reader/epub_reader_page.dart';
import '../reader/reader_page.dart';

/// The primary Read / Resume-reading action for a book's digital files.
/// Opens the PDF reader when the book has a PDF, else the EPUB reader.
class ReadButton extends StatelessWidget {
  const ReadButton({super.key, required this.book, required this.repository});

  final Book book;
  final LibraryRepository repository;

  /// If another device is further ahead, ask whether to resume there (plan 5
  /// #5). No feature flag needed: the cache of other devices' positions is only
  /// ever filled while the user has opted in, and switching the option off
  /// clears it — so with the feature off there is nothing to offer and this
  /// costs one empty query.
  ///
  /// Returns once any accepted jump has been written, so the reader opens at the
  /// new position. Never adopts a remote position silently: two devices disagreeing
  /// about where you are is exactly the case where guessing is worse than
  /// asking.
  Future<void> _maybeOfferJump(BuildContext context, String localUnit) async {
    final positions = repository.readingPositions;
    final remotes = await positions.watchRemotePositions(book.id).first;
    final offer = positions.offerFor(
      book: book,
      remotes: remotes,
      localUnit: localUnit,
    );
    if (offer == null || !context.mounted) return;

    final here = book.lastReadPage;
    final jump = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Resume where you left off?'),
        content: Text(
          'You were on ${offer.description}.\n\n'
          '${here == null ? "You haven't opened it on this device." : 'This '
              'device is at $localUnit $here '
              '(${((book.readingProgress ?? 0) * 100).round()}%).'}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(here == null ? 'Start here' : 'Stay at $localUnit $here'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text('Go to $localUnit ${offer.page}'),
          ),
        ],
      ),
    );
    if (jump == true) await positions.applyOffer(book.id, offer);
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BookFile>>(
      stream: repository.watchFilesOf(book.id),
      builder: (context, snapshot) {
        final files = snapshot.data ?? const <BookFile>[];
        final pdf = files.where((f) => f.format == 'pdf').firstOrNull;
        final epub = files.where((f) => f.format == 'epub').firstOrNull;
        final started = book.readingProgress != null;
        // The saved position counts PDF pages or EPUB chapters, depending on
        // which reader this book opens into.
        final unit = readingUnitForFormats([for (final f in files) f.format]);
        final label = !started
            ? 'Read'
            : 'Resume reading · '
                  '${(book.readingProgress! * 100).round()}% '
                  '($unit ${book.lastReadPage})';
        return FilledButton.icon(
          onPressed: pdf == null && epub == null
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  await _maybeOfferJump(context, unit);
                  // An accepted jump wrote to the book row, so re-read it:
                  // `book` is the snapshot this widget was built with.
                  final current =
                      await repository.watchBook(book.id).first ?? book;
                  await navigator.push(
                    MaterialPageRoute(
                      builder: (_) => pdf != null
                          ? ReaderPage(
                              book: current,
                              file: repository.fileOf(pdf),
                              repository: repository,
                            )
                          : EpubReaderPage(
                              book: current,
                              file: repository.fileOf(epub!),
                              repository: repository,
                            ),
                    ),
                  );
                },
          icon: Icon(started ? Icons.play_arrow : Icons.menu_book),
          label: Text(files.isEmpty ? 'Read (no digital copy yet)' : label),
        );
      },
    );
  }
}
