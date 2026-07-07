import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/book_file_validation.dart';
import '../data/library_repository.dart';

/// Create a book by hand — for a PDF you can't find in an online library.
/// Attach the file by dropping it here or picking it.
class CustomBookPage extends StatefulWidget {
  const CustomBookPage({super.key, required this.repository});

  final LibraryRepository repository;

  @override
  State<CustomBookPage> createState() => _CustomBookPageState();
}

class _CustomBookPageState extends State<CustomBookPage> {
  final _title = TextEditingController();
  final _author = TextEditingController();
  final _year = TextEditingController();
  final _description = TextEditingController();

  String? _filePath;
  String? _fileName;
  bool _dragging = false;
  bool _saving = false;
  String? _error;

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _year.dispose();
    _description.dispose();
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
    });
  }

  Future<void> _pickFile() async {
    const group = XTypeGroup(label: 'Books', extensions: ['pdf', 'epub']);
    final picked = await openFile(acceptedTypeGroups: const [group]);
    if (picked != null) await _acceptFile(picked.path, picked.name);
  }

  Future<void> _create() async {
    final title = _title.text.trim();
    if (title.isEmpty) {
      setState(() => _error = 'A title is required.');
      return;
    }
    setState(() {
      _saving = true;
      _error = null;
    });
    try {
      final id = await widget.repository.createCustomBook(
        title: title,
        author: _author.text.trim().isEmpty ? null : _author.text.trim(),
        publishedYear: int.tryParse(_year.text.trim()),
        description: _description.text.trim().isEmpty
            ? null
            : _description.text.trim(),
      );
      if (_filePath != null) {
        await widget.repository.attachFile(id, _filePath!);
      }
      if (mounted) Navigator.of(context).pop(title);
    } catch (e) {
      if (mounted) {
        setState(() {
          _saving = false;
          _error = 'Could not create the book: $e';
        });
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Custom book')),
      body: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          TextField(
            controller: _title,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'Title',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _author,
            decoration: const InputDecoration(
              labelText: 'Author',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _year,
            keyboardType: TextInputType.number,
            decoration: const InputDecoration(
              labelText: 'Published year',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 12),
          TextField(
            controller: _description,
            minLines: 2,
            maxLines: 5,
            decoration: const InputDecoration(
              labelText: 'Description',
              border: OutlineInputBorder(),
            ),
          ),
          const SizedBox(height: 16),
          DropTarget(
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
                height: 110,
                decoration: BoxDecoration(
                  border: Border.all(
                    color: _dragging
                        ? theme.colorScheme.primary
                        : theme.dividerColor,
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
                        ? 'Drop a PDF or EPUB here, or click to choose'
                        : 'Attached: $_fileName',
                    style: theme.textTheme.bodyMedium,
                  ),
                ),
              ),
            ),
          ),
          if (_error != null) ...[
            const SizedBox(height: 12),
            Text(_error!, style: TextStyle(color: theme.colorScheme.error)),
          ],
          const SizedBox(height: 20),
          FilledButton(
            onPressed: _saving ? null : _create,
            child: _saving
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Create book'),
          ),
        ],
      ),
    );
  }
}
