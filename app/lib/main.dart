import 'package:flutter/material.dart';

import 'add_book/add_book_page.dart';
import 'data/database.dart';
import 'data/library_repository.dart';
import 'shelf/shelf_view.dart';

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  final repository = await LibraryRepository.open(VellumDatabase());
  runApp(VellumApp(repository: repository));
}

class VellumApp extends StatelessWidget {
  const VellumApp({super.key, required this.repository});

  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vellum',
      theme: ThemeData(
        colorSchemeSeed: const Color(0xFF7A5C3E), // leather-ish brown
        brightness: Brightness.light,
      ),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF7A5C3E),
        brightness: Brightness.dark,
      ),
      home: LibraryPage(repository: repository),
    );
  }
}

class LibraryPage extends StatelessWidget {
  const LibraryPage({super.key, required this.repository});

  final LibraryRepository repository;

  Future<void> _openAddBook(BuildContext context) async {
    final addedTitle = await Navigator.of(context).push<String>(
      MaterialPageRoute(builder: (_) => AddBookPage(repository: repository)),
    );
    if (addedTitle != null && context.mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(content: Text('“$addedTitle” added to your shelf')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Vellum')),
      body: StreamBuilder<List<Book>>(
        stream: repository.watchAllBooks(),
        builder: (context, snapshot) {
          final books = snapshot.data ?? const [];
          if (books.isEmpty) {
            return const Center(
              child: Text('Your shelf is empty.\nAdd your first book!',
                  textAlign: TextAlign.center),
            );
          }
          return ShelfView(
            books: books,
            onBookTap: (book) => _showBookDetails(context, book),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => _openAddBook(context),
        icon: const Icon(Icons.add),
        label: const Text('Add book'),
      ),
    );
  }

  void _showBookDetails(BuildContext context, Book book) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (sheetContext) => _BookDetailsSheet(
        book: book,
        repository: repository,
      ),
    );
  }
}

class _BookDetailsSheet extends StatelessWidget {
  const _BookDetailsSheet({required this.book, required this.repository});

  final Book book;
  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    final cover = repository.coverFileOf(book);
    final theme = Theme.of(context);
    return FutureBuilder<BookDetails>(
      future: repository.detailsFor(book.id),
      builder: (context, snapshot) {
        final details =
            snapshot.data ?? (authors: <String>[], genres: <String>[]);
        return ConstrainedBox(
          constraints: BoxConstraints(
            maxHeight: MediaQuery.of(context).size.height * 0.75,
          ),
          child: ListView(
            shrinkWrap: true,
            padding: const EdgeInsets.fromLTRB(24, 0, 24, 24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  if (cover != null)
                    ClipRRect(
                      borderRadius: BorderRadius.circular(6),
                      child: Image.file(cover,
                          width: 90, height: 132, fit: BoxFit.cover),
                    ),
                  const SizedBox(width: 16),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(book.title, style: theme.textTheme.titleLarge),
                        if (book.subtitle != null)
                          Text(book.subtitle!,
                              style: theme.textTheme.titleSmall),
                        const SizedBox(height: 6),
                        Text(
                          [
                            details.authors.join(', '),
                            if (book.publishedYear != null)
                              '${book.publishedYear}',
                            if (book.pageCount != null)
                              '${book.pageCount} pages',
                          ].where((s) => s.isNotEmpty).join(' · '),
                          style: theme.textTheme.bodyMedium,
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              if (details.genres.isNotEmpty) ...[
                const SizedBox(height: 12),
                Wrap(
                  spacing: 6,
                  runSpacing: 6,
                  children: [
                    for (final genre in details.genres)
                      Chip(
                        label: Text(genre),
                        visualDensity: VisualDensity.compact,
                      ),
                  ],
                ),
              ],
              if (book.description != null) ...[
                const SizedBox(height: 12),
                Text(book.description!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 16),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: () async {
                    await repository.deleteBook(book);
                    if (context.mounted) Navigator.of(context).pop();
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove from library'),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
