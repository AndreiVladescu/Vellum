import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../../data/database.dart';
import 'annotation_locator.dart';
import 'annotation_store.dart';
import 'markdown_export.dart';

/// The per-book annotations list (plan 5 #22): jump to, edit, delete, export.
///
/// Shown as a side sheet from either reader, and as a section on the book's
/// detail page. [onJump] is optional because the detail page has nowhere to jump
/// *to* — there, the panel is a reading record rather than a navigation aid.
class AnnotationsPanel extends StatelessWidget {
  const AnnotationsPanel({
    super.key,
    required this.book,
    required this.store,
    this.onJump,
    this.authors = const [],
  });

  final Book book;
  final AnnotationStore store;

  /// Called with a resolved locator when the user taps an entry.
  final void Function(AnnotationLocator locator)? onJump;

  final List<String> authors;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Annotation>>(
      stream: store.watchForBook(book.id),
      builder: (context, snapshot) {
        final annotations = snapshot.data ?? const <Annotation>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      annotations.isEmpty
                          ? 'No annotations yet'
                          : '${annotations.length} annotation'
                              '${annotations.length == 1 ? '' : 's'}',
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (annotations.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.copy_all_outlined),
                      tooltip: 'Copy as Markdown',
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(
                          text: MarkdownExport.forBook(
                            book: book,
                            annotations: annotations,
                            authors: authors,
                          ),
                        ));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                              content: Text('Annotations copied as Markdown')),
                        );
                      },
                    ),
                ],
              ),
            ),
            if (annotations.isEmpty)
              const Padding(
                padding: EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text(
                  'Bookmark a page, or select text and highlight it, while '
                  'reading.',
                ),
              )
            else
              Expanded(
                child: ListView.separated(
                  itemCount: annotations.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => _AnnotationTile(
                    annotation: annotations[i],
                    store: store,
                    onJump: onJump,
                  ),
                ),
              ),
          ],
        );
      },
    );
  }
}

class _AnnotationTile extends StatelessWidget {
  const _AnnotationTile({
    required this.annotation,
    required this.store,
    this.onJump,
  });

  final Annotation annotation;
  final AnnotationStore store;
  final void Function(AnnotationLocator locator)? onJump;

  IconData get _icon => switch (AnnotationKind.parse(annotation.kind)) {
        AnnotationKind.bookmark => Icons.bookmark_outline,
        AnnotationKind.highlight => Icons.format_color_text,
        AnnotationKind.note => Icons.sticky_note_2_outlined,
        null => Icons.label_outline,
      };

  String get _where {
    if (annotation.page != null) return 'Page ${annotation.page}';
    if (annotation.chapter != null) return 'Chapter ${annotation.chapter! + 1}';
    return '';
  }

  Future<void> _editNote(BuildContext context) async {
    final controller = TextEditingController(text: annotation.note ?? '');
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(annotation.quotedText == null ? 'Note' : 'Note on highlight'),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 3,
          decoration: const InputDecoration(
            hintText: 'What did you want to remember?',
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Save'),
          ),
        ],
      ),
    );
    if (saved == true) await store.setNote(annotation.id, controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final locator = AnnotationLocator.decode(annotation.locator);
    final quote = annotation.quotedText;
    final note = annotation.note;
    return ListTile(
      leading: Icon(_icon,
          color: annotation.color == null ? null : Color(annotation.color!)),
      title: Text(
        quote ?? note ?? _where,
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: quote != null
            ? theme.textTheme.bodyMedium
                ?.copyWith(fontStyle: FontStyle.italic)
            : theme.textTheme.bodyMedium,
      ),
      subtitle: Text([
        _where,
        if (quote != null && note != null && note.isNotEmpty) note,
      ].where((s) => s.isNotEmpty).join(' · '),
          maxLines: 2, overflow: TextOverflow.ellipsis),
      onTap: locator == null || onJump == null
          ? null
          : () => onJump!(locator),
      trailing: PopupMenuButton<String>(
        onSelected: (choice) async {
          switch (choice) {
            case 'note':
              await _editNote(context);
            case 'copy':
              await Clipboard.setData(ClipboardData(
                text: [quote, note].whereType<String>().join('\n\n'),
              ));
            case 'delete':
              await store.delete(annotation.id);
          }
        },
        itemBuilder: (context) => [
          const PopupMenuItem(value: 'note', child: Text('Edit note…')),
          if (quote != null || note != null)
            const PopupMenuItem(value: 'copy', child: Text('Copy text')),
          const PopupMenuItem(value: 'delete', child: Text('Delete')),
        ],
      ),
    );
  }
}
