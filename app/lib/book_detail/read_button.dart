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
        final unit = pdf != null ? 'page' : 'chapter';
        final label = !started
            ? 'Read'
            : 'Resume reading · '
                  '${(book.readingProgress! * 100).round()}% '
                  '($unit ${book.lastReadPage})';
        return FilledButton.icon(
          onPressed: pdf == null && epub == null
              ? null
              : () => Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => pdf != null
                          ? ReaderPage(
                              book: book,
                              file: repository.fileOf(pdf),
                              repository: repository,
                            )
                          : EpubReaderPage(
                              book: book,
                              file: repository.fileOf(epub!),
                              repository: repository,
                            ),
                    ),
                  ),
          icon: Icon(started ? Icons.play_arrow : Icons.menu_book),
          label: Text(files.isEmpty ? 'Read (no digital copy yet)' : label),
        );
      },
    );
  }
}
