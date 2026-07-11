import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/book_file_validation.dart';
import '../data/library_repository.dart';
import '../data/metadata.dart';
import '../settings/app_settings.dart';

/// Add a book: search Open Library / Google Books and pick an edition, or create
/// one yourself (for a PDF no library has) — optionally attaching the file.
class AddBookPage extends StatefulWidget {
  const AddBookPage({
    super.key,
    required this.repository,
    required this.settings,
  });

  final LibraryRepository repository;
  final AppSettingsStore settings;

  @override
  State<AddBookPage> createState() => _AddBookPageState();
}

class _AddBookPageState extends State<AddBookPage> {
  final _queryController = TextEditingController();
  // Optional details used only when creating a book by hand (online lookup
  // sometimes finds nothing). Author is its own field — not the subtitle.
  final _authorController = TextEditingController();
  final _yearController = TextEditingController();
  List<BookSearchResult>? _results;
  bool _searching = false;
  String? _addingWorkKey;
  String? _error;
  String _lastQuery = '';

  String? _filePath;
  String? _fileName;
  bool _dragging = false;

  /// Sentinel for the busy indicator while creating a custom book.
  static const _customKey = '__custom__';

  bool get _busy => _addingWorkKey != null;

  @override
  void dispose() {
    _queryController.dispose();
    _authorController.dispose();
    _yearController.dispose();
    super.dispose();
  }

  Future<void> _acceptFile(String path, String name) async {
    final kind = await classifyBookFile(path);
    if (!kind.isBook) {
      setState(() => _error = 'Only PDF or EPUB files can be attached.');
      return;
    }
    setState(() {
      _filePath = path;
      _fileName = name;
      _error = null;
      // Seed the title from the filename when the user hasn't typed one.
      if (_queryController.text.trim().isEmpty) {
        _queryController.text = _titleFromFilename(name);
      }
    });
  }

  /// The filename without its extension, as a starting title.
  static String _titleFromFilename(String name) {
    final dot = name.lastIndexOf('.');
    return (dot > 0 ? name.substring(0, dot) : name).trim();
  }

  Future<void> _pickFile() async {
    const group = XTypeGroup(label: 'Books', extensions: ['pdf', 'epub']);
    final picked = await openFile(acceptedTypeGroups: const [group]);
    if (picked != null) await _acceptFile(picked.path, picked.name);
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
      final id = await widget.repository.addFromSearch(
        result,
        importGenres: widget.settings.importOpenLibraryGenres,
      );
      if (_filePath != null) await widget.repository.attachFile(id, _filePath!);
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

  /// Creates a bare custom book from the typed title, attaching the picked file
  /// and — for a PDF — using its first page as the cover.
  Future<void> _create() async {
    final title = _queryController.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'Enter a title to create a book.');
      return;
    }
    setState(() {
      _addingWorkKey = _customKey;
      _error = null;
    });
    try {
      final authors = _authorController.text
          .split(',')
          .map((s) => s.trim())
          .where((s) => s.isNotEmpty)
          .toList();
      final id = await widget.repository.createCustomBook(
        title: title,
        author: authors.isEmpty ? null : authors.first,
        publishedYear: int.tryParse(_yearController.text.trim()),
      );
      if (authors.length > 1) await widget.repository.setAuthors(id, authors);
      if (_filePath != null) {
        // attachFile auto-generates a first-page cover for a PDF.
        await widget.repository.attachFile(id, _filePath!);
      }
      if (!mounted) return;
      Navigator.of(context).pop(title);
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _addingWorkKey = null;
        _error = 'Could not create “$title”: $e';
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
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
                    : null,
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 0, 16, 4),
            child: Row(
              children: [
                Expanded(
                  flex: 2,
                  child: TextField(
                    controller: _authorController,
                    decoration: const InputDecoration(
                      hintText: 'Author(s) — for a book you create',
                      prefixIcon: Icon(Icons.person_outline),
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: TextField(
                    controller: _yearController,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      hintText: 'Year',
                      border: OutlineInputBorder(),
                      isDense: true,
                    ),
                  ),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16),
            child: Row(
              children: [
                FilledButton.tonalIcon(
                  onPressed: _busy ? null : _search,
                  icon: const Icon(Icons.search),
                  label: const Text('Search'),
                ),
                const SizedBox(width: 10),
                FilledButton.icon(
                  onPressed: _busy ? null : _create,
                  icon: _addingWorkKey == _customKey
                      ? const SizedBox(
                          width: 18,
                          height: 18,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: const Text('Create book'),
                ),
              ],
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
            child: _fileDropPane(theme),
          ),
          if (_error != null)
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
              child: Text(
                _error!,
                style: TextStyle(color: theme.colorScheme.error),
              ),
            ),
          Expanded(child: _buildResults()),
        ],
      ),
    );
  }

  Widget _fileDropPane(ThemeData theme) {
    return DropTarget(
      onDragEntered: (_) => setState(() => _dragging = true),
      onDragExited: (_) => setState(() => _dragging = false),
      onDragDone: (details) {
        setState(() => _dragging = false);
        if (details.files.isNotEmpty) {
          final f = details.files.first;
          _acceptFile(f.path, f.name);
        }
      },
      child: InkWell(
        onTap: _pickFile,
        child: Container(
          height: 76,
          decoration: BoxDecoration(
            border: Border.all(
              color: _dragging ? theme.colorScheme.primary : theme.dividerColor,
              width: _dragging ? 2.5 : 1,
            ),
            borderRadius: BorderRadius.circular(10),
            color: _dragging
                ? theme.colorScheme.primary.withValues(alpha: 0.06)
                : null,
          ),
          child: Center(
            child: Text(
              _fileName == null
                  ? 'Attach a file (optional): drop a PDF/EPUB here or click'
                  : 'Attached: $_fileName',
              style: theme.textTheme.bodyMedium,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildResults() {
    final results = _results;
    if (results == null) {
      return const Center(
        child: Text('Search for a book, or create one above.'),
      );
    }
    if (results.isEmpty) {
      return Center(
        child: Text(
          'No results for “$_lastQuery”.\n'
          'Use “Create book” above to add it yourself.',
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
          enabled: !_busy,
          onTap: () => _add(r),
        );
      },
    );
  }
}
