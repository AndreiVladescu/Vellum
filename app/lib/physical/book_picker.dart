import 'package:flutter/material.dart';

import '../widgets/page_insets.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import 'physical_metrics.dart';

/// Bottom-sheet picker for choosing library books to place in a room.
///
/// Multi-select by default, because putting a real bookcase into Vellum means
/// adding thirty books to one shelf, and doing that one modal at a time is the
/// slowest thing in the physical view. Tick as many as you like, then confirm
/// once.
///
/// Returns the chosen books in the order they appear in the list (title order),
/// which is the order they will be packed onto the shelf — so what you see here
/// is the order they end up in.
class BookPicker extends StatefulWidget {
  const BookPicker({
    super.key,
    required this.repository,
    this.title = 'Add books to the room',
    this.confirmLabel = 'Add',
    this.alreadyPlacedIds = const {},
  });

  final LibraryRepository repository;
  final String title;

  /// Verb on the confirm button, followed by the count once anything is
  /// ticked ("Add 12").
  final String confirmLabel;

  /// Books that already have a copy in this room. They stay selectable — you
  /// can genuinely own two copies — but they are marked, and *Select all*
  /// skips them, because in bulk a second copy is nearly always a mistake.
  final Set<String> alreadyPlacedIds;

  @override
  State<BookPicker> createState() => _BookPickerState();
}

class _BookPickerState extends State<BookPicker> {
  String _query = '';
  final _selected = <String>{};

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<Book>>(
      stream: widget.repository.watchAllBooks(),
      builder: (context, snap) {
        final all = snap.data ?? const <Book>[];
        final q = _query.trim().toLowerCase();
        final books = [
          for (final b in all)
            if (q.isEmpty || b.title.toLowerCase().contains(q)) b,
        ];
        // "Select all" means all of what you are looking at, not all of the
        // library — with a filter typed, the visible list is the intent.
        final selectable = [
          for (final b in books)
            if (!widget.alreadyPlacedIds.contains(b.id)) b.id,
        ];
        final allSelected = selectable.isNotEmpty &&
            selectable.every(_selected.contains);

        return SizedBox(
          height: MediaQuery.of(context).size.height * 0.7,
          child: Column(
            children: [
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 0, 16, 8),
                child: Column(
                  children: [
                    Text(widget.title, style: theme.textTheme.titleMedium),
                    const SizedBox(height: 8),
                    TextField(
                      onChanged: (v) => setState(() => _query = v),
                      decoration: const InputDecoration(
                        prefixIcon: Icon(Icons.search),
                        hintText: 'Find books to place…',
                        border: OutlineInputBorder(),
                        isDense: true,
                      ),
                    ),
                  ],
                ),
              ),
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 8),
                child: Row(
                  children: [
                    TextButton.icon(
                      onPressed: selectable.isEmpty
                          ? null
                          : () => setState(() {
                                if (allSelected) {
                                  _selected.removeAll(selectable);
                                } else {
                                  _selected.addAll(selectable);
                                }
                              }),
                      icon: Icon(allSelected
                          ? Icons.check_box
                          : Icons.check_box_outline_blank),
                      label: Text(
                        allSelected
                            ? 'Clear these ${selectable.length}'
                            : 'Select these ${selectable.length}',
                      ),
                    ),
                    const Spacer(),
                    if (_selected.isNotEmpty)
                      Padding(
                        padding: const EdgeInsets.only(right: 8),
                        child: Text(
                          '${_selected.length} selected',
                          style: theme.textTheme.labelLarge,
                        ),
                      ),
                  ],
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: books.isEmpty
                    ? const Center(child: Text('No books.'))
                    : ListView.builder(
                        itemCount: books.length,
                        itemBuilder: (context, i) {
                          final b = books[i];
                          final here = widget.alreadyPlacedIds.contains(b.id);
                          return CheckboxListTile(
                            value: _selected.contains(b.id),
                            onChanged: (on) => setState(() {
                              if (on == true) {
                                _selected.add(b.id);
                              } else {
                                _selected.remove(b.id);
                              }
                            }),
                            controlAffinity: ListTileControlAffinity.leading,
                            secondary: Container(
                              width: 12,
                              height: 34,
                              decoration: BoxDecoration(
                                color: PhysicalMetrics.color(b),
                                borderRadius: BorderRadius.circular(2),
                              ),
                            ),
                            title: Text(b.title,
                                maxLines: 1, overflow: TextOverflow.ellipsis),
                            subtitle: Text(
                              [
                                if (here) 'already in this room',
                                if (b.pageCount != null) '${b.pageCount} pages',
                              ].join(' · '),
                              style: here
                                  ? TextStyle(color: theme.colorScheme.primary)
                                  : null,
                            ),
                          );
                        },
                      ),
              ),
              const Divider(height: 1),
              Padding(
                padding: EdgeInsets.fromLTRB(
                  16,
                  8,
                  16,
                  // Not `viewPadding`: this sheet has a search field, and
                  // the footer has to clear the keyboard too.
                  8 + sheetBottomInset(context),
                ),
                child: Row(
                  children: [
                    TextButton(
                      onPressed: () => Navigator.pop(context),
                      child: const Text('Cancel'),
                    ),
                    const Spacer(),
                    FilledButton.icon(
                      onPressed: _selected.isEmpty
                          ? null
                          : () => Navigator.pop(context, [
                                for (final b in all)
                                  if (_selected.contains(b.id)) b,
                              ]),
                      icon: const Icon(Icons.library_add),
                      label: Text(
                        _selected.isEmpty
                            ? widget.confirmLabel
                            : '${widget.confirmLabel} ${_selected.length}',
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
