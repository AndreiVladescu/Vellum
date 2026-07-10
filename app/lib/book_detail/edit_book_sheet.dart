import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';

/// Bottom sheet to edit a book's core details and change its cover.
class EditBookSheet extends StatefulWidget {
  const EditBookSheet({
    super.key,
    required this.book,
    required this.repository,
    required this.onPickCover,
    required this.onCoverFromFirstPage,
  });

  final Book book;
  final LibraryRepository repository;
  final Future<void> Function() onPickCover;
  final Future<void> Function() onCoverFromFirstPage;

  @override
  State<EditBookSheet> createState() => EditBookSheetState();
}

class EditBookSheetState extends State<EditBookSheet> {
  late final _title = TextEditingController(text: widget.book.title);
  final _author = TextEditingController();
  late final _subtitle = TextEditingController(
    text: widget.book.subtitle ?? '',
  );
  late final _year = TextEditingController(
    text: widget.book.publishedYear?.toString() ?? '',
  );
  late final _pages = TextEditingController(
    text: widget.book.pageCount?.toString() ?? '',
  );
  late final _description = TextEditingController(
    text: widget.book.description ?? '',
  );
  bool _gettingPages = false;

  Future<void> _getPagesFromFile() async {
    setState(() => _gettingPages = true);
    final count = await widget.repository.pageCountFromFile(widget.book.id);
    if (!mounted) return;
    setState(() => _gettingPages = false);
    if (count == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('No PDF attached, or its pages couldn’t be read.'),
        ),
      );
      return;
    }
    _pages.text = count.toString();
  }

  @override
  void initState() {
    super.initState();
    // Authors live in their own table; load the current ones into the field.
    widget.repository.detailsFor(widget.book.id).then((details) {
      if (mounted) _author.text = details.authors.join(', ');
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _subtitle.dispose();
    _year.dispose();
    _pages.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    await widget.repository.updateBookDetails(
      widget.book.id,
      title: title,
      subtitle: _subtitle.text,
      publishedYear: int.tryParse(_year.text.trim()),
      pageCount: int.tryParse(_pages.text.trim()),
      description: _description.text,
    );
    await widget.repository.setAuthors(widget.book.id, _author.text.split(','));
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit details', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _author,
              decoration: const InputDecoration(
                labelText: 'Author(s)',
                helperText: 'Separate multiple authors with commas',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _subtitle,
              decoration: const InputDecoration(labelText: 'Subtitle'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _year,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Published year',
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _pages,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(labelText: 'Pages'),
                  ),
                ),
              ],
            ),
            Align(
              alignment: Alignment.centerRight,
              child: TextButton.icon(
                onPressed: _gettingPages ? null : _getPagesFromFile,
                icon: _gettingPages
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Icon(Icons.picture_as_pdf_outlined, size: 18),
                label: const Text('Get page count from file'),
              ),
            ),
            const SizedBox(height: 4),
            TextField(
              controller: _description,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => widget.onPickCover(),
              icon: const Icon(Icons.image_outlined),
              label: const Text('Change cover…'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onCoverFromFirstPage();
              },
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Use first page of the PDF as cover'),
            ),
            const SizedBox(height: 6),
            Text(
              'Tip: you can also drag an image, PDF, or EPUB onto the book '
              'page.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
