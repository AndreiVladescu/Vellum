import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../reader/reader_page.dart';

/// Full-page book view: metadata, digital formats, physical copies, and the
/// Read / Resume reading action.
class BookDetailPage extends StatelessWidget {
  const BookDetailPage({super.key, required this.book, required this.repository});

  /// Snapshot used before the first stream event arrives.
  final Book book;
  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    // Watch the row so reading progress / edits update live.
    return StreamBuilder<Book?>(
      stream: repository.watchBook(book.id),
      initialData: book,
      builder: (context, snapshot) {
        final current = snapshot.data;
        if (current == null) {
          // Book was deleted while this page was open.
          return const Scaffold(body: SizedBox.shrink());
        }
        return _BookDetailBody(book: current, repository: repository);
      },
    );
  }
}

class _BookDetailBody extends StatelessWidget {
  const _BookDetailBody({required this.book, required this.repository});

  final Book book;
  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = repository.coverFileOf(book);
    return Scaffold(
      appBar: AppBar(title: Text(book.title)),
      body: ListView(
        padding: const EdgeInsets.all(24),
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              if (cover != null && cover.existsSync())
                ClipRRect(
                  borderRadius: BorderRadius.circular(8),
                  child: Image.file(cover,
                      width: 110, height: 162, fit: BoxFit.cover),
                ),
              const SizedBox(width: 20),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(book.title, style: theme.textTheme.headlineSmall),
                    if (book.subtitle != null)
                      Text(book.subtitle!, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    FutureBuilder<BookDetails>(
                      future: repository.detailsFor(book.id),
                      builder: (context, snapshot) {
                        final details = snapshot.data;
                        return Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              [
                                if (details != null &&
                                    details.authors.isNotEmpty)
                                  details.authors.join(', '),
                                if (book.publishedYear != null)
                                  '${book.publishedYear}',
                                if (book.pageCount != null)
                                  '${book.pageCount} pages',
                                if (book.publisher != null) book.publisher!,
                              ].join(' · '),
                              style: theme.textTheme.bodyMedium,
                            ),
                            if (book.isbn != null)
                              Text('ISBN ${book.isbn}',
                                  style: theme.textTheme.bodySmall),
                            if (details != null &&
                                details.genres.isNotEmpty) ...[
                              const SizedBox(height: 10),
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
                          ],
                        );
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          _ReadButton(book: book, repository: repository),
          if (book.description != null) ...[
            const SizedBox(height: 20),
            Text('About', style: theme.textTheme.titleMedium),
            const SizedBox(height: 8),
            Text(book.description!, style: theme.textTheme.bodyMedium),
          ],
          const SizedBox(height: 24),
          _DigitalFormatsSection(book: book, repository: repository),
          const SizedBox(height: 24),
          _PhysicalCopiesSection(book: book, repository: repository),
          const SizedBox(height: 32),
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
  }
}

class _ReadButton extends StatelessWidget {
  const _ReadButton({required this.book, required this.repository});

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
                    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
                        content: Text(
                            'Only PDF reading is supported for now — '
                            'EPUB is coming later.')));
                    return;
                  }
                  Navigator.of(context).push(MaterialPageRoute(
                    builder: (_) => ReaderPage(
                      book: book,
                      file: repository.fileOf(pdf),
                      repository: repository,
                    ),
                  ));
                },
          icon: Icon(started ? Icons.play_arrow : Icons.menu_book),
          label: Text(files.isEmpty ? 'Read (no digital copy yet)' : label),
        );
      },
    );
  }
}

class _DigitalFormatsSection extends StatelessWidget {
  const _DigitalFormatsSection({required this.book, required this.repository});

  final Book book;
  final LibraryRepository repository;

  Future<void> _attach(BuildContext context) async {
    const typeGroup = XTypeGroup(
      label: 'Books',
      extensions: ['pdf', 'epub'],
    );
    final picked = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (picked == null) return;
    await repository.attachFile(book.id, picked.path);
    if (context.mounted) {
      ScaffoldMessenger.of(context)
          .showSnackBar(SnackBar(content: Text('Attached ${picked.name}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<BookFile>>(
      stream: repository.watchFilesOf(book.id),
      builder: (context, snapshot) {
        final files = snapshot.data ?? const <BookFile>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Digital formats',
                      style: theme.textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: () => _attach(context),
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Attach file'),
                ),
              ],
            ),
            if (files.isEmpty)
              Text('No files yet — attach a PDF or EPUB.',
                  style: theme.textTheme.bodySmall)
            else
              for (final f in files)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(f.format == 'pdf'
                      ? Icons.picture_as_pdf_outlined
                      : Icons.book_outlined),
                  title: Text(f.format.toUpperCase()),
                  subtitle: Text(
                      '${(f.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB'),
                ),
          ],
        );
      },
    );
  }
}

class _PhysicalCopiesSection extends StatelessWidget {
  const _PhysicalCopiesSection({required this.book, required this.repository});

  final Book book;
  final LibraryRepository repository;

  Future<void> _addCopy(BuildContext context) async {
    final location = TextEditingController();
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add physical copy'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: location,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Location',
                hintText: 'e.g. living room, shelf 3',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await repository.addPhysicalCopy(
        book.id,
        location: location.text.trim().isEmpty ? null : location.text.trim(),
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
      );
    }
    location.dispose();
    notes.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<PhysicalCopy>>(
      stream: repository.watchCopiesOf(book.id),
      builder: (context, snapshot) {
        final copies = snapshot.data ?? const <PhysicalCopy>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text('Physical copies',
                      style: theme.textTheme.titleMedium),
                ),
                TextButton.icon(
                  onPressed: () => _addCopy(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add copy'),
                ),
              ],
            ),
            if (copies.isEmpty)
              Text("You don't own this one on paper (yet).",
                  style: theme.textTheme.bodySmall)
            else
              for (final c in copies)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: const Icon(Icons.place_outlined),
                  title: Text(c.location ?? 'Somewhere…'),
                  subtitle: c.notes == null ? null : Text(c.notes!),
                ),
          ],
        );
      },
    );
  }
}
