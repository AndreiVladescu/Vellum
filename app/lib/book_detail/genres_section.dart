import 'package:flutter/material.dart';

import '../data/library_repository.dart';

/// Editable genre ("tag") chips for a book. Each genre is removable (the ✕),
/// tapping one filters the shelf by it, and the trailing "＋ Add" chip opens a
/// sheet to attach an existing or brand-new genre. Reactive: the chips follow
/// [LibraryRepository.watchGenresOf], so add/remove shows instantly.
class GenresSection extends StatelessWidget {
  const GenresSection({
    super.key,
    required this.repository,
    required this.bookId,
    this.onGenreTap,
  });

  final LibraryRepository repository;
  final String bookId;

  /// Tapping a genre chip closes the book page and filters the shelf by it.
  final void Function(String genre)? onGenreTap;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<String>>(
      stream: repository.watchGenresOf(bookId),
      initialData: const [],
      builder: (context, snapshot) {
        final genres = snapshot.data ?? const [];
        return Wrap(
          spacing: 6,
          runSpacing: 6,
          crossAxisAlignment: WrapCrossAlignment.center,
          children: [
            for (final genre in genres)
              InputChip(
                label: Text(genre),
                visualDensity: VisualDensity.compact,
                // Tap to filter the shelf by this genre…
                onPressed: onGenreTap == null
                    ? null
                    : () {
                        Navigator.of(context).pop();
                        onGenreTap!(genre);
                      },
                // …and the ✕ removes it from the book.
                onDeleted: () => repository.removeGenre(bookId, genre),
              ),
            ActionChip(
              avatar: const Icon(Icons.add, size: 18),
              label: const Text('Add'),
              visualDensity: VisualDensity.compact,
              onPressed: () => _openAddSheet(context),
            ),
          ],
        );
      },
    );
  }

  void _openAddSheet(BuildContext context) {
    showModalBottomSheet<void>(
      context: context,
      showDragHandle: true,
      isScrollControlled: true,
      builder: (_) => _AddGenreSheet(repository: repository, bookId: bookId),
    );
  }
}

/// Bottom sheet to add genres to a book: type a new one (Enter to add), or tap
/// a suggestion drawn from genres already used elsewhere in the library. Stays
/// open so several can be added in a row.
class _AddGenreSheet extends StatefulWidget {
  const _AddGenreSheet({required this.repository, required this.bookId});

  final LibraryRepository repository;
  final String bookId;

  @override
  State<_AddGenreSheet> createState() => _AddGenreSheetState();
}

class _AddGenreSheetState extends State<_AddGenreSheet> {
  final _controller = TextEditingController();
  String _query = '';

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  Future<void> _add(String name) async {
    if (name.trim().isEmpty) return;
    await widget.repository.addGenre(widget.bookId, name);
    _controller.clear();
    if (mounted) setState(() => _query = '');
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 0, 20, 20 + bottom),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text('Add genre', style: Theme.of(context).textTheme.titleLarge),
          const SizedBox(height: 12),
          TextField(
            controller: _controller,
            autofocus: true,
            textCapitalization: TextCapitalization.words,
            decoration: const InputDecoration(
              hintText: 'e.g. Engineering',
              prefixIcon: Icon(Icons.sell_outlined),
              border: OutlineInputBorder(),
            ),
            onChanged: (v) => setState(() => _query = v),
            onSubmitted: _add,
          ),
          const SizedBox(height: 12),
          // Suggestions: existing genres the book doesn't already have,
          // narrowed by what's typed, so you reuse tags instead of duplicating.
          StreamBuilder<List<String>>(
            stream: widget.repository.watchAllGenreNames(),
            initialData: const [],
            builder: (context, allSnap) {
              return StreamBuilder<List<String>>(
                stream: widget.repository.watchGenresOf(widget.bookId),
                initialData: const [],
                builder: (context, mineSnap) {
                  final mine = (mineSnap.data ?? const []).toSet();
                  final q = _query.trim().toLowerCase();
                  final suggestions = [
                    for (final g in allSnap.data ?? const [])
                      if (!mine.contains(g) &&
                          (q.isEmpty || g.toLowerCase().contains(q)))
                        g,
                  ];
                  if (suggestions.isEmpty) return const SizedBox.shrink();
                  return Align(
                    alignment: Alignment.centerLeft,
                    child: Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final g in suggestions)
                          ActionChip(
                            label: Text(g),
                            visualDensity: VisualDensity.compact,
                            onPressed: () => _add(g),
                          ),
                      ],
                    ),
                  );
                },
              );
            },
          ),
          const SizedBox(height: 16),
          Align(
            alignment: Alignment.centerRight,
            child: FilledButton(
              onPressed: () => Navigator.of(context).pop(),
              child: const Text('Done'),
            ),
          ),
        ],
      ),
    );
  }
}
