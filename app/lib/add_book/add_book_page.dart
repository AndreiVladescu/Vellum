import 'package:flutter/material.dart';

import '../data/library_repository.dart';
import '../data/metadata.dart';

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
      setState(() => _results = results);
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

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Add a book')),
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 8),
            child: TextField(
              controller: _queryController,
              autofocus: true,
              textInputAction: TextInputAction.search,
              onSubmitted: (_) => _search(),
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
      return const Center(child: Text('No results — try different words.'));
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
          subtitle: Text([
            r.authorLine,
            if (r.firstPublishYear != null) '${r.firstPublishYear}',
          ].join(' · ')),
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
