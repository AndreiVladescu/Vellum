import 'dart:io';

import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/external_open.dart';
import '../data/library_repository.dart';
import '../reader/epub_book.dart';
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

  /// How many chapters an EPUB has, or 0 if it cannot be read.
  ///
  /// Opened here rather than taken from the book row because `pageCount` is the
  /// *paper* book's length — a number from a catalogue, and nothing to do with
  /// how this file is divided.
  static Future<int> _chapterCount(File file) async {
    try {
      final epub = await EpubBook.open(file);
      return epub.chapters.length;
    } catch (_) {
      // A file that will not open has no offer to make; the reader itself
      // says so a moment later.
      return 0;
    }
  }

  /// Opens one file, and asks first whether to start where the *other* file
  /// left off (8/25 request).
  ///
  /// Asked, never applied: a translation and a first edition do not share a
  /// page number, so the percentage is a guess about where the same passage
  /// falls. A guess is a fine thing to offer and a terrible thing to apply.
  Future<void> _openFile(BuildContext context, BookFile file) async {
    final navigator = Navigator.of(context);
    final unit = readingUnitForFormats([file.format]);
    await _maybeOfferJump(context, unit);
    await repository.readingStatus.noteOpened(book.id);
    if (!context.mounted) return;

    final current = await repository.watchBook(book.id).first ?? book;
    // What this file turns in: a PDF's pages, or an EPUB's chapters. The
    // chapter count means opening the EPUB after reading the PDF gets the same
    // offer as the other way round — which is the case that prompted this.
    final pageCount = file.format == 'pdf'
        ? (current.pageCount ?? 0)
        : await _chapterCount(repository.fileOf(file));
    var startAt = 0;
    if (pageCount > 0 && context.mounted) {
      final offer = await repository.readingPositions.offerFromAnotherFile(
        bookId: book.id,
        openingFileId: file.id,
        pageCount: pageCount,
      );
      if (offer != null && context.mounted) {
        final other = await repository.fileById(offer.fromFileId);
        if (!context.mounted) return;
        final take = await showDialog<bool>(
          context: context,
          builder: (dialogContext) => AlertDialog(
            title: const Text('Start where you left off?'),
            content: Text(
              'You were ${(offer.progress * 100).round()}% through '
              '${other == null ? 'another file' : 'the ${other.format.toUpperCase()}'}'
              ' of this book.\n\nThat is about page ${offer.page} here — '
              'the same fraction of a different file, so it may not be the '
              'same passage.',
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(dialogContext, false),
                child: const Text('Start at the beginning'),
              ),
              FilledButton(
                onPressed: () => Navigator.pop(dialogContext, true),
                child: Text('Go to '
                    '${file.format == 'pdf' ? 'page' : 'chapter'} '
                    '${offer.page}'),
              ),
            ],
          ),
        );
        if (take == true) startAt = offer.page;
      }
    }
    if (!context.mounted) return;

    await navigator.push(MaterialPageRoute(
      builder: (_) => file.format == 'pdf'
          ? ReaderPage(
              book: current,
              file: repository.fileOf(file),
              bookFile: file,
              repository: repository,
              initialPage: startAt > 0 ? startAt : null,
            )
          : EpubReaderPage(
              book: current,
              file: repository.fileOf(file),
              bookFile: file,
              repository: repository,
              initialChapter: startAt > 0 ? startAt - 1 : null,
            ),
    ));
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
    final readable = [
      for (final file in files)
        if (file.format == 'pdf' || file.format == 'epub') file,
    ];
    // One readable file is a button. Several is a choice — and it has to be
    // offered, because before this the PDF simply won and the EPUB could not
    // be opened at all (8/25 report).
    if (readable.length > 1) {
      return _FilePickerButton(
        book: book,
        repository: repository,
        files: readable,
        label: label,
        started: started,
        onOpen: (file) => _openFile(context, file),
      );
    }
    return FilledButton.icon(
      onPressed: readable.isEmpty
          ? null
          : () => _openFile(context, readable.single),
      icon: Icon(started ? Icons.play_arrow : Icons.menu_book),
      label: Text(files.isEmpty ? 'Read (no digital copy yet)' : label),
    );
  }
}

/// The Read button for a book that has more than one file: a menu of them,
/// each with its own place in it.
class _FilePickerButton extends StatelessWidget {
  const _FilePickerButton({
    required this.book,
    required this.repository,
    required this.files,
    required this.label,
    required this.started,
    required this.onOpen,
  });

  final Book book;
  final LibraryRepository repository;
  final List<BookFile> files;
  final String label;
  final bool started;
  final void Function(BookFile file) onOpen;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<FilePosition>>(
      future: repository.readingPositions.positionsForBook(book.id),
      builder: (context, snapshot) {
        final places = {
          for (final position in snapshot.data ?? const <FilePosition>[])
            position.fileId: position,
        };
        return MenuAnchor(
          menuChildren: [
            for (final file in files)
              MenuItemButton(
                leadingIcon: Icon(file.format == 'pdf'
                    ? Icons.picture_as_pdf_outlined
                    : Icons.menu_book_outlined),
                onPressed: () => onOpen(file),
                child: Text(_describe(file, places[file.id])),
              ),
          ],
          builder: (context, controller, child) => FilledButton.icon(
            onPressed: () =>
                controller.isOpen ? controller.close() : controller.open(),
            icon: Icon(started ? Icons.play_arrow : Icons.menu_book),
            label: Text(label),
          ),
        );
      },
    );
  }

  /// "PDF · page 214 (38%)", or "EPUB · not started". Its own place, not the
  /// book's: that is the whole point of listing them separately.
  static String _describe(BookFile file, FilePosition? position) {
    final format = file.format.toUpperCase();
    final progress = position?.progress;
    if (progress == null || position?.lastReadPage == null) {
      return '$format · not started';
    }
    final unit = file.format == 'pdf' ? 'page' : 'chapter';
    return '$format · $unit ${position!.lastReadPage} '
        '(${(progress * 100).round()}%)';
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
