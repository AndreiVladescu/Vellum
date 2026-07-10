import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';

/// Personal reader notes for a book — stored locally, never synced to a server.
class ReaderNotesSection extends StatefulWidget {
  const ReaderNotesSection({
    super.key,
    required this.book,
    required this.repository,
  });

  final Book book;
  final LibraryRepository repository;

  @override
  State<ReaderNotesSection> createState() => ReaderNotesSectionState();
}

class ReaderNotesSectionState extends State<ReaderNotesSection> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.book.readerNotes ?? '',
  );
  bool _dirty = false;

  @override
  void didUpdateWidget(covariant ReaderNotesSection oldWidget) {
    super.didUpdateWidget(oldWidget);
    // Pick up external changes (e.g. a revert) unless the user is mid-edit.
    if (!_dirty && (widget.book.readerNotes ?? '') != _controller.text) {
      _controller.text = widget.book.readerNotes ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('My notes', style: theme.textTheme.titleMedium),
            ),
            if (_dirty)
              TextButton(
                onPressed: () async {
                  await widget.repository.setReaderNotes(
                    widget.book.id,
                    _controller.text,
                  );
                  if (mounted) setState(() => _dirty = false);
                },
                child: const Text('Save'),
              ),
          ],
        ),
        Text(
          'Private to this device — never shared with a server.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          minLines: 3,
          maxLines: 8,
          onChanged: (_) {
            if (!_dirty) setState(() => _dirty = true);
          },
          decoration: const InputDecoration(
            hintText: 'Thoughts, quotes, where you left off…',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}
