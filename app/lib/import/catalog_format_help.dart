import 'dart:io';
import '../widgets/page_insets.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/external_open.dart';
import '../snack_bars.dart';

/// A ready-made catalogue file, which is also the documentation.
///
/// **Why a file you can save rather than only a page you can read.** The
/// question behind "how do I structure it?" is usually not what the columns
/// mean — it is what the first line should literally say. A template answers
/// that by being openable in whatever spreadsheet the person already uses, with
/// two rows showing the shapes that are easy to get wrong: several authors in
/// one cell, a quoted list of tags, an empty series column.
///
/// [catalogFormatHelpTest] keeps this honest by importing it: if the reader and
/// the template ever disagree, the test fails rather than the user.
const catalogTemplateCsv = '''
title,authors,published_year,publisher,isbn,page_count,series,series_index,tags,description
The Left Hand of Darkness,Ursula K. Le Guin,1969,Ace Books,9780441007318,304,Hainish Cycle,4,"science fiction; classics",An envoy to a world without fixed gender.
Good Omens,Terry Pratchett & Neil Gaiman,1990,Gollancz,9780575048003,288,,,"fantasy; humour",The world ends on Saturday. Just before dinner.
''';

/// The columns the reader understands, and what else each may be called.
///
/// Kept beside the template on purpose: these are the two halves of one answer,
/// and a list of column names in a different file is a list that goes stale.
const catalogColumns = <(String, String, String)>[
  ('Title', 'required', 'title, book title'),
  ('Author(s)', '', 'authors, author, author_sort, creator'),
  ('Subtitle', '', 'subtitle'),
  ('ISBN', '', 'isbn, isbn13, isbn-13, isbn_13'),
  ('Publisher', '', 'publisher'),
  ('Year', '', 'published_year, year, year published'),
  ('Pages', '', 'page_count, pages, number of pages'),
  ('Series', '', 'series'),
  ('Number in series', '', 'series_index, volume'),
  ('Genres', '', 'tags, genres, bookshelves, subjects'),
  ('Description', '', 'description, comments, summary'),
];

/// How to structure a catalogue file, shown where you would go looking for it.
class CatalogFormatSheet extends StatelessWidget {
  const CatalogFormatSheet({super.key});

  static Future<void> show(BuildContext context) => showModalBottomSheet<void>(
        context: context,
        showDragHandle: true,
        isScrollControlled: true,
        builder: (_) => DraggableScrollableSheet(
          expand: false,
          initialChildSize: 0.8,
          maxChildSize: 0.95,
          builder: (_, controller) =>
              CatalogFormatSheet._scrollable(controller),
        ),
      );

  static Widget _scrollable(ScrollController controller) =>
      _SheetBody(controller: controller);

  @override
  Widget build(BuildContext context) => const _SheetBody();
}

class _SheetBody extends StatelessWidget {
  const _SheetBody({this.controller});

  final ScrollController? controller;

  Future<void> _saveTemplate(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final location = await getSaveLocation(
      suggestedName: 'vellum_import_template.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']),
      ],
    );
    if (location == null) return;
    final file = File(location.path);
    await file.writeAsString(catalogTemplateCsv);
    messenger.showSnackBar(
      appSnackBar(
        content: Text('Saved to ${location.path}'),
        action: SnackBarAction(
          label: 'Open',
          onPressed: () => openExternally(file, mimeType: 'text/csv'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return ListView(
      controller: controller,
      padding: pageInsets(context, EdgeInsets.fromLTRB(20, 0, 20, 28)),
      children: [
        Text('How to structure the file', style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          'One header row, one book per row, and a column called title. '
          'Everything else is optional, unrecognised columns are ignored, and '
          'the order never matters — so an export from somewhere else usually '
          'imports without editing.',
          style: muted,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () => _saveTemplate(context),
              icon: const Icon(Icons.download),
              label: const Text('Save a template'),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: catalogTemplateCsv));
                ScaffoldMessenger.of(context).showSnackBar(
                  const SnackBar(content: Text('Template copied')),
                );
              },
              icon: const Icon(Icons.copy_all_outlined),
              label: const Text('Copy'),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text('Columns', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final (name, note, aliases) in catalogColumns)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(name, style: theme.textTheme.bodyMedium),
                    if (note.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text('($note)',
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.primary,
                          )),
                    ],
                  ],
                ),
                Text(aliases,
                    style: theme.textTheme.bodySmall?.copyWith(
                      fontFamily: 'monospace',
                      color: theme.colorScheme.onSurfaceVariant,
                    )),
              ],
            ),
          ),
        const SizedBox(height: 12),
        Text('Getting the values right', style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        const _Point(
          'Several authors or tags in one cell',
          'Separate them with ; or , or &. If you use commas, wrap the cell in '
              'quotes: "fantasy, humour".',
        ),
        const _Point(
          'ISBNs',
          'Hyphens and spaces are fine. A value that is not 10 or 13 '
              'characters once cleaned up is left out rather than stored wrong.',
        ),
        const _Point(
          'Year and pages',
          'Plain numbers. Anything else is left empty rather than guessed at.',
        ),
        const _Point(
          'JSON works too',
          'A list of objects, or an object with a "books" list, using the same '
              'names. The format is read from the contents, not the extension.',
        ),
        const _Point(
          'Files are not part of it',
          'A catalogue creates books with no PDF or EPUB attached. To bring the '
              'files, import the folder they are in — matching books are '
              'recognised rather than duplicated.',
        ),
        const SizedBox(height: 12),
        Text(
          'The full guide, including how file names are read during a folder '
          'import, is in docs/IMPORTING.md.',
          style: muted,
        ),
      ],
    );
  }
}

class _Point extends StatelessWidget {
  const _Point(this.title, this.body);

  final String title;
  final String body;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.only(bottom: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: theme.textTheme.bodyMedium),
          Text(body,
              style: theme.textTheme.bodySmall?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              )),
        ],
      ),
    );
  }
}
