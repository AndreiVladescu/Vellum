import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/external_open.dart';
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
        return Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            _read(context, files: files, pdf: pdf, epub: epub, unit: unit,
                label: label),
            if (files.isNotEmpty) ...[
              const SizedBox(width: 8),
              _OpenExternally(files: files, repository: repository),
            ],
          ],
        );
      },
    );
  }

  Widget _read(
    BuildContext context, {
    required List<BookFile> files,
    required BookFile? pdf,
    required BookFile? epub,
    required String unit,
    required String label,
  }) {
    final started = book.readingProgress != null;
    return FilledButton.icon(
          onPressed: pdf == null && epub == null
              ? null
              : () async {
                  final navigator = Navigator.of(context);
                  // The jump prompt needs the context, so it goes first; the
                  // status write is fire-and-forget either way.
                  await _maybeOfferJump(context, unit);
                  // The one automatic status transition (plan 5 #18):
                  // unread -> reading. Unambiguous and reversible; everything
                  // else is the reader's own call.
                  await repository.readingStatus.noteOpened(book.id);
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
  }
}

/// Hands the book to whatever the system opens PDFs and EPUBs with.
///
/// Sits next to Read because it is the same intention taking a different route:
/// Vellum's reader keeps your position, highlights and notes, and someone who
/// wants Okular or Calibre for this one book should not have to go hunting
/// through the file list for the path. Where a book has both formats it asks
/// which — the answer is not always "the PDF", and guessing wastes a launch.
class _OpenExternally extends StatelessWidget {
  const _OpenExternally({required this.files, required this.repository});

  final List<BookFile> files;
  final LibraryRepository repository;

  static const _mimeTypes = {
    'pdf': 'application/pdf',
    'epub': 'application/epub+zip',
  };

  Future<void> _open(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final file = files.length == 1 ? files.first : await _pick(context);
    if (file == null) return;

    final onDisk = repository.fileOf(file);
    if (!onDisk.existsSync()) {
      messenger.showSnackBar(
        const SnackBar(content: Text('That file is missing from the library.')),
      );
      return;
    }
    final opened = await openExternally(
      onDisk,
      mimeType: _mimeTypes[file.format],
    );
    if (!opened) {
      messenger.showSnackBar(
        SnackBar(
          content: Text(
            'Nothing on this system is set up to open a ${file.format}.',
          ),
        ),
      );
    }
  }

  Future<BookFile?> _pick(BuildContext context) => showDialog<BookFile>(
        context: context,
        builder: (dialogContext) => SimpleDialog(
          title: const Text('Open which file?'),
          children: [
            for (final file in files)
              SimpleDialogOption(
                onPressed: () => Navigator.pop(dialogContext, file),
                child: Text(file.format.toUpperCase()),
              ),
          ],
        ),
      );

  @override
  Widget build(BuildContext context) => IconButton.filledTonal(
        icon: const Icon(Icons.open_in_new),
        tooltip: 'Open in another app',
        onPressed: () => _open(context),
      );
}
