import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../data/metadata.dart';
import 'custom_book_page.dart';

/// Search Open Library and pick the edition to add to the shelf.
class AddBookPage extends StatefulWidget {
  const AddBookPage({super.key, required this.repository});

  final LibraryRepository repository;

  @override
  State<AddBookPage> createState() => _AddBookPageState();
}

class _AddBookPageState extends State<AddBookPage> {
  final _queryController = TextEditingController();
  List<BookSearchResult>? _results;
  bool _searching = false;
  String? _addingWorkKey;
  String? _error;

  /// The query behind the current [_results]; used to offer create-on-empty.
  String _lastQuery = '';

  /// Sentinel for the busy indicator while creating a custom book.
  static const _customKey = '__custom__';

  @override
  void dispose() {
    _queryController.dispose();
    super.dispose();
  }

  Future<void> _search() async {
    final query = _queryController.text.trim();
    if (query.isEmpty) return;
    setState(() {
      _searching = true;
      _error = null;
    });
    try {
      final results = await widget.repository.metadata.search(query);
      if (!mounted) return;
      setState(() {
        _results = results;
        _lastQuery = query;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = 'Search failed — are you online?\n$e');
    } finally {
      if (mounted) setState(() => _searching = false);
    }
  }

  Future<void> _add(BookSearchResult result) async {
    setState(() => _addingWorkKey = result.workKey);
    try {
      await widget.repository.addFromSearch(result);
      if (!mounted) return;
      Navigator.of(context).pop(result.title);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _addingWorkKey = null;
        _error = 'Could not add “${result.title}”: $e';
      });
    }
  }

  /// Enter either searches, or — when the last search found nothing — creates a
  /// custom book from the typed title.
  Future<void> _submit() async {
    final q = _queryController.text.trim();
    if (q.isEmpty) return;
    if (_results != null && _results!.isEmpty && q == _lastQuery) {
      await _createFromQuery(q);
    } else {
      await _search();
    }
  }

  /// Creates a bare custom book titled [q] — for a book no library has.
  Future<void> _createFromQuery(String q) async {
    setState(() {
      _addingWorkKey = _customKey;
      _error = null;
    });
    try {
      await widget.repository.createCustomBook(title: q);
      if (!mounted) return;
      Navigator.of(context).pop(q);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _addingWorkKey = null;
        _error = 'Could not create “$q”: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Add a book'),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_note),
            tooltip: 'Create a custom book',
            onPressed: () async {
              final title = await Navigator.of(context).push<String>(
                MaterialPageRoute(
                  builder: (_) => CustomBookPage(repository: widget.repository),
                ),
              );
              if (title != null && context.mounted) {
                Navigator.of(context).pop(title);
              }
            },
          ),
        ],
      ),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _queryController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _submit(),
              decoration: InputDecoration(
                hintText: 'Title, author, or ISBN',
                prefixIcon: const Icon(Icons.search),
                border: const OutlineInputBorder(),
                suffixIcon: _searching
                    ? const Padding(
                        padding: EdgeInsets.all(12),
                        child: SizedBox(
                          width: 20,
                          height: 20,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        ),
                      )
                    : IconButton(
                        icon: const Icon(Icons.arrow_forward),
                        onPressed: _search,
                      ),
              ),
            ),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _buildResults() {
    final results = _results;
    if (results == null) {
      return const Center(
        child: Text('Search Open Library to find your book.'),
      );
    }
    if (results.isEmpty) {
      final q = _lastQuery;
      return Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('No results for “$q”.', textAlign: TextAlign.center),
              const SizedBox(height: 12),
              FilledButton.icon(
                onPressed:
                    _addingWorkKey != null ? null : () => _createFromQuery(q),
                icon: const Icon(Icons.add),
                label: Text('Create “$q” as a custom book'),
              ),
              const SizedBox(height: 8),
              Text('or press Enter again',
                  style: Theme.of(context).textTheme.bodySmall),
            ],
          ),
        ),
      );
    }
    return ListView.builder(
      itemCount: results.length,
      itemBuilder: (context, i) {
        final r = results[i];
        final adding = _addingWorkKey == r.workKey;
        return ListTile(
          leading: SizedBox(
            width: 40,
            height: 56,
            child: r.thumbnailUrl == null
                ? const Icon(Icons.menu_book_outlined)
                : Image.network(
                    r.thumbnailUrl.toString(),
                    fit: BoxFit.cover,
                    errorBuilder: (_, _, _) =>
                        const Icon(Icons.menu_book_outlined),
                  ),
          ),
          title: Text(r.title),
          subtitle: Text(
            [
              r.authorLine,
              if (r.firstPublishYear != null) '${r.firstPublishYear}',
            ].join(' · '),
          ),
          trailing: adding
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(strokeWidth: 2),
                )
              : const Icon(Icons.add),
          enabled: _addingWorkKey == null,
          onTap: () => _add(r),
        );
      },
    );
  }
}
