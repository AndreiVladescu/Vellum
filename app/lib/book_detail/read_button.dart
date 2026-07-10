import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../reader/reader_page.dart';

/// The primary Read / Resume-reading action for a book's digital files.
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
        final started = book.readingProgress != null;
        final label = !started
            ? 'Read'
            : 'Resume reading · '
                  '${(book.readingProgress! * 100).round()}% '
                  '(page ${book.lastReadPage})';
        return FilledButton.icon(
          onPressed: files.isEmpty
              ? null
              : () {
                  if (pdf == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Only PDF reading is supported for now — '
                          'EPUB is coming later.',
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReaderPage(
                        book: book,
                        file: repository.fileOf(pdf),
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
