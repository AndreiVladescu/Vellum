import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';

/// The "Digital formats" list: attached PDF/EPUB files plus an attach action.
class DigitalFormatsSection extends StatelessWidget {
  const DigitalFormatsSection({
    super.key,
    required this.book,
    required this.repository,
  });

  final Book book;
  final LibraryRepository repository;

  Future<void> _attach(BuildContext context) async {
    const typeGroup = XTypeGroup(label: 'Books', extensions: ['pdf', 'epub']);
    final picked = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (picked == null) return;
    await repository.attachFile(book.id, picked.path);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Attached ${picked.name}')));
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
                  child: Text(
                    'Digital formats',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _attach(context),
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Attach file'),
                ),
              ],
            ),
            if (files.isEmpty)
              Text(
                'No files yet — attach a PDF or EPUB.',
                style: theme.textTheme.bodySmall,
              )
            else
              for (final f in files)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    f.format == 'pdf'
                        ? Icons.picture_as_pdf_outlined
                        : Icons.book_outlined,
                  ),
                  title: Text(f.format.toUpperCase()),
                  subtitle: Text(
                    '${(f.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                  ),
                ),
          ],
        );
      },
    );
  }
}
