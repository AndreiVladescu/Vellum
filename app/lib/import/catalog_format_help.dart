import 'dart:io';
import '../widgets/page_insets.dart';

import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

import '../data/external_open.dart';
import '../l10n/gen/app_localizations.dart';
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
    final l10n = L10n.of(context);
    final location = await getSaveLocation(
      suggestedName: 'vellum_import_template.csv',
      acceptedTypeGroups: const [
        XTypeGroup(label: 'CSV', extensions: ['csv']), // i18n-ignore: format name
      ],
    );
    if (location == null) return;
    final file = File(location.path);
    await file.writeAsString(catalogTemplateCsv);
    messenger.showSnackBar(
      appSnackBar(
        content: Text(l10n.catalogHelpSaved(location.path)),
        action: SnackBarAction(
          label: l10n.catalogHelpOpen,
          onPressed: () => openOrShare(file, mimeType: 'text/csv'),
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final muted = TextStyle(color: theme.colorScheme.onSurfaceVariant);
    return ListView(
      controller: controller,
      padding: pageInsets(context, EdgeInsets.fromLTRB(20, 0, 20, 28)),
      children: [
        Text(l10n.catalogHelpTitle, style: theme.textTheme.titleLarge),
        const SizedBox(height: 8),
        Text(
          l10n.catalogHelpIntro,
          style: muted,
        ),
        const SizedBox(height: 16),
        Row(
          children: [
            FilledButton.icon(
              onPressed: () => _saveTemplate(context),
              icon: const Icon(Icons.download),
              label: Text(l10n.catalogHelpSaveTemplate),
            ),
            const SizedBox(width: 8),
            TextButton.icon(
              onPressed: () {
                Clipboard.setData(const ClipboardData(text: catalogTemplateCsv));
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(content: Text(l10n.catalogHelpCopied)),
                );
              },
              icon: const Icon(Icons.copy_all_outlined),
              label: Text(l10n.catalogHelpCopy),
            ),
          ],
        ),
        const SizedBox(height: 20),
        Text(l10n.catalogHelpColumns, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        for (final (name, note, aliases) in catalogColumns)
          Padding(
            padding: const EdgeInsets.only(bottom: 8),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Text(_columnName(l10n, name),
                        style: theme.textTheme.bodyMedium),
                    if (note.isNotEmpty) ...[
                      const SizedBox(width: 6),
                      Text('(${note == 'required' ? l10n.catalogHelpRequired : note})', // i18n-ignore: wraps a translated word in parentheses
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
        Text(l10n.catalogHelpValuesTitle, style: theme.textTheme.titleMedium),
        const SizedBox(height: 8),
        _Point(l10n.catalogHelpMultiTitle, l10n.catalogHelpMultiBody),
        _Point(l10n.catalogHelpIsbnTitle, l10n.catalogHelpIsbnBody),
        _Point(l10n.catalogHelpNumbersTitle, l10n.catalogHelpNumbersBody),
        _Point(l10n.catalogHelpJsonTitle, l10n.catalogHelpJsonBody),
        _Point(l10n.catalogHelpFilesTitle, l10n.catalogHelpFilesBody),
        const SizedBox(height: 12),
        Text(
          l10n.catalogHelpGuide,
          style: muted,
        ),
      ],
    );
  }
}

/// [catalogColumns]' English column names in the reader's language. The
/// English name is the identity, so the table and its tests stay as they were.
String _columnName(L10n l10n, String name) => switch (name) {
      'Title' => l10n.catalogHelpColTitle,
      'Author(s)' => l10n.catalogHelpColAuthors,
      'Subtitle' => l10n.catalogHelpColSubtitle,
      'ISBN' => l10n.catalogHelpColIsbn,
      'Publisher' => l10n.catalogHelpColPublisher,
      'Year' => l10n.catalogHelpColYear,
      'Pages' => l10n.catalogHelpColPages,
      'Series' => l10n.catalogHelpColSeries,
      'Number in series' => l10n.catalogHelpColSeriesNumber,
      'Genres' => l10n.catalogHelpColGenres,
      'Description' => l10n.catalogHelpColDescription,
      _ => name,
    };

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
