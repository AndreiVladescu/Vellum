import 'package:flutter/material.dart';

import '../../widgets/page_insets.dart';
import 'package:flutter/services.dart';

import '../../data/database.dart';
import 'annotation_locator.dart';
import 'annotation_store.dart';
import 'markdown_export.dart';
import '../../l10n/gen/app_localizations.dart';

/// The per-book annotations list (plan 5 #22): jump to, edit, delete, export.
///
/// Shown as a side sheet from either reader, and as a section on the book's
/// detail page. [onJump] is optional because the detail page has nowhere to jump
/// *to* — there, the panel is a reading record rather than a navigation aid.
///
/// With [maxInline] set the panel shrink-wraps to at most that many entries and
/// hands the rest to a button that opens the full panel in a sheet. That is how
/// the detail page uses it: a reader with a hundred highlights would otherwise
/// push everything below annotations off the end of a phone screen, or trap the
/// list in a fixed-height box that fights the page's own scroll.
class AnnotationsPanel extends StatelessWidget {
  const AnnotationsPanel({
    super.key,
    required this.book,
    required this.store,
    this.onJump,
    this.authors = const [],
    this.maxInline,
  });

  final Book book;
  final AnnotationStore store;

  /// Called with a resolved locator when the user taps an entry.
  final void Function(AnnotationLocator locator)? onJump;

  final List<String> authors;

  /// Show at most this many entries, with a button for the rest. Null lists all.
  final int? maxInline;

  /// The rest of the list, in a sheet of its own.
  void _openAll(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => SizedBox(
        height: MediaQuery.of(context).size.height * 0.7,
        child: AnnotationsPanel(
          book: book,
          store: store,
          authors: authors,
          onJump: onJump,
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<Annotation>>(
      stream: store.watchForBook(book.id),
      builder: (context, snapshot) {
        final annotations = snapshot.data ?? const <Annotation>[];
        final l10n = L10n.of(context);
        final limit = maxInline;
        final shown =
            limit == null ? null : annotations.take(limit).toList();
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          mainAxisSize: shown == null ? MainAxisSize.max : MainAxisSize.min,
          children: [
            Padding(
              padding: const EdgeInsets.fromLTRB(16, 12, 8, 4),
              child: Row(
                children: [
                  Expanded(
                    child: Text(
                      annotations.isEmpty
                          ? l10n.annotationsNone
                          : l10n.annotationsCount(annotations.length),
                      style: Theme.of(context).textTheme.titleMedium,
                    ),
                  ),
                  if (annotations.isNotEmpty)
                    IconButton(
                      icon: const Icon(Icons.copy_all_outlined),
                      tooltip: l10n.annotationsCopyTooltip,
                      onPressed: () async {
                        await Clipboard.setData(ClipboardData(
                          text: MarkdownExport.forBook(
                            l10n: l10n,
                            book: book,
                            annotations: annotations,
                            authors: authors,
                          ),
                        ));
                        if (!context.mounted) return;
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(content: Text(l10n.annotationsCopied)),
                        );
                      },
                    ),
                ],
              ),
            ),
            if (annotations.isEmpty)
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                child: Text(l10n.annotationsEmptyHint),
              )
            else if (shown != null) ...[
              for (final annotation in shown)
                AnnotationTile(
                  annotation: annotation,
                  store: store,
                  onJump: onJump,
                ),
              if (shown.length < annotations.length)
                ListTile(
                  leading: const Icon(Icons.more_horiz),
                  title: Text(l10n.annotationsShowAll(annotations.length)),
                  onTap: () => _openAll(context),
                ),
            ] else
              Expanded(
                child: ListView.separated(
                  // The panel is a bottom sheet, so its last row would
                  // otherwise come to rest under the gesture bar.
                  padding: EdgeInsets.only(bottom: sheetBottomInset(context)),
                  itemCount: annotations.length,
                  separatorBuilder: (_, _) => const Divider(height: 1),
                  itemBuilder: (context, i) => AnnotationTile(
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

class AnnotationTile extends StatelessWidget {
  const AnnotationTile({
    super.key,
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
        AnnotationKind.ink => Icons.draw_outlined,
        null => Icons.label_outline,
      };

  String _where(L10n l10n) {
    if (annotation.page != null) return l10n.annotationsPage(annotation.page!);
    if (annotation.chapter != null) {
      return l10n.annotationsChapter(annotation.chapter! + 1);
    }
    return '';
  }

  Future<void> _editNote(BuildContext context) async {
    final controller = TextEditingController(text: annotation.note ?? '');
    final l10n = L10n.of(context);
    final saved = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(annotation.quotedText == null
            ? l10n.annotationsNoteTitle
            : l10n.annotationsNoteOnHighlight),
        content: TextField(
          controller: controller,
          autofocus: true,
          maxLines: 5,
          minLines: 3,
          decoration: InputDecoration(
            hintText: l10n.annotationsNoteHint,
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.save),
          ),
        ],
      ),
    );
    if (saved == true) await store.setNote(annotation.id, controller.text);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final locator = AnnotationLocator.decode(annotation.locator);
    final quote = annotation.quotedText;
    final note = annotation.note;
    return ListTile(
      leading: Icon(_icon,
          color: annotation.color == null ? null : Color(annotation.color!)),
      title: Text(
        quote ?? note ?? _where(l10n),
        maxLines: 3,
        overflow: TextOverflow.ellipsis,
        style: quote != null
            ? theme.textTheme.bodyMedium
                ?.copyWith(fontStyle: FontStyle.italic)
            : theme.textTheme.bodyMedium,
      ),
      subtitle: Text([
        _where(l10n),
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
          PopupMenuItem(value: 'note', child: Text(l10n.annotationsEditNote)),
          if (quote != null || note != null)
            PopupMenuItem(value: 'copy', child: Text(l10n.annotationsCopyText)),
          PopupMenuItem(value: 'delete', child: Text(l10n.delete)),
        ],
      ),
    );
  }
}
