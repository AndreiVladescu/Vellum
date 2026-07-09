import 'dart:io';

import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/book_file_validation.dart';
import '../data/database.dart';
import '../data/library_repository.dart';
import '../reader/reader_page.dart';

/// Full-page book view: metadata, digital formats, physical copies, and the
/// Read / Resume reading action.
class BookDetailPage extends StatelessWidget {
  const BookDetailPage({
    super.key,
    required this.book,
    required this.repository,
  });

  /// Snapshot used before the first stream event arrives.
  final Book book;
  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    // Watch the row so reading progress / edits update live.
    return StreamBuilder<Book?>(
      stream: repository.watchBook(book.id),
      initialData: book,
      builder: (context, snapshot) {
        final current = snapshot.data;
        if (current == null) {
          // Book was deleted while this page was open.
          return const Scaffold(body: SizedBox.shrink());
        }
        return _BookDetailBody(book: current, repository: repository);
      },
    );
  }
}

class _BookDetailBody extends StatefulWidget {
  const _BookDetailBody({required this.book, required this.repository});

  final Book book;
  final LibraryRepository repository;

  @override
  State<_BookDetailBody> createState() => _BookDetailBodyState();
}

class _BookDetailBodyState extends State<_BookDetailBody> {
  bool _dragging = false;

  Book get book => widget.book;
  LibraryRepository get repository => widget.repository;

  /// Handles files dropped anywhere on the page: images become the cover,
  /// PDFs/EPUBs are attached, anything else is rejected.
  Future<void> _handleDrop(List<XFile> files) async {
    var attached = 0;
    var coverChanged = false;
    String? message;
    for (final file in files) {
      final kind = await classifyBookFile(file.path);
      if (kind == BookFileKind.image) {
        await repository.setCoverFromFile(book.id, file.path);
        coverChanged = true;
        message = 'Cover updated';
      } else if (kind.isBook) {
        await repository.attachFile(book.id, file.path);
        attached++;
      } else {
        message = 'Only PDF, EPUB, or image files are accepted';
      }
    }
    if (coverChanged) await _evictCover();
    if (attached > 0) {
      message = 'Attached $attached file${attached == 1 ? '' : 's'}';
    }
    if (mounted && message != null) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text(message)));
    }
  }

  Future<void> _pickCover() async {
    const group = XTypeGroup(
      label: 'Images',
      extensions: ['jpg', 'jpeg', 'png', 'gif', 'webp'],
    );
    final picked = await openFile(acceptedTypeGroups: const [group]);
    if (picked == null) return;
    if (await classifyBookFile(picked.path) != BookFileKind.image) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text("That doesn't look like an image.")),
        );
      }
      return;
    }
    await repository.setCoverFromFile(book.id, picked.path);
    await _evictCover();
  }

  /// The cover always writes to the same path, so drop it from the image cache
  /// to force a reload after a change.
  Future<void> _evictCover() async {
    final cover = repository.coverFileOf(book);
    if (cover != null) await FileImage(cover).evict();
    if (mounted) setState(() {});
  }

  Future<void> _coverFromFirstPage() async {
    final ok = await repository.setCoverFromFirstPage(book.id);
    if (ok) await _evictCover();
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            ok
                ? 'Cover set from the first page'
                : 'Attach a PDF first to use its first page',
          ),
        ),
      );
    }
  }

  void _openEditSheet() => showModalBottomSheet<void>(
    context: context,
    isScrollControlled: true,
    builder: (_) => _EditBookSheet(
      book: book,
      repository: repository,
      onPickCover: _pickCover,
      onCoverFromFirstPage: _coverFromFirstPage,
    ),
  );

  Future<void> _revert() async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Revert to library defaults?'),
        content: const Text(
          'This restores the title, description, year, and cover to the '
          'values from the online library. Your reader notes and attached '
          'files are kept.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Revert'),
          ),
        ],
      ),
    );
    if (ok != true) return;
    await repository.revertToDefault(book);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('Reverted to library defaults')),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = repository.coverFileOf(book);
    return Scaffold(
      appBar: AppBar(
        title: Text(book.title),
        actions: [
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit details',
            onPressed: _openEditSheet,
          ),
        ],
      ),
      body: DropTarget(
        onDragEntered: (_) => setState(() => _dragging = true),
        onDragExited: (_) => setState(() => _dragging = false),
        onDragDone: (details) {
          setState(() => _dragging = false);
          _handleDrop(details.files);
        },
        child: Container(
          foregroundDecoration: _dragging
              ? BoxDecoration(
                  border: Border.all(
                    color: theme.colorScheme.primary,
                    width: 3,
                  ),
                  color: theme.colorScheme.primary.withValues(alpha: 0.06),
                )
              : null,
          child: ListView(
            padding: const EdgeInsets.all(24),
            children: [
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _CoverThumb(cover: cover, onTap: _pickCover),
                  const SizedBox(width: 20),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(book.title, style: theme.textTheme.headlineSmall),
                        if (book.subtitle != null)
                          Text(
                            book.subtitle!,
                            style: theme.textTheme.titleMedium,
                          ),
                        const SizedBox(height: 8),
                        FutureBuilder<BookDetails>(
                          future: repository.detailsFor(book.id),
                          builder: (context, snapshot) {
                            final details = snapshot.data;
                            return Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  [
                                    if (details != null &&
                                        details.authors.isNotEmpty)
                                      details.authors.join(', '),
                                    if (book.publishedYear != null)
                                      '${book.publishedYear}',
                                    if (book.pageCount != null)
                                      '${book.pageCount} pages',
                                    if (book.publisher != null) book.publisher!,
                                  ].join(' · '),
                                  style: theme.textTheme.bodyMedium,
                                ),
                                if (book.isbn != null)
                                  Text(
                                    'ISBN ${book.isbn}',
                                    style: theme.textTheme.bodySmall,
                                  ),
                                if (details != null &&
                                    details.genres.isNotEmpty) ...[
                                  const SizedBox(height: 10),
                                  Wrap(
                                    spacing: 6,
                                    runSpacing: 6,
                                    children: [
                                      for (final genre in details.genres)
                                        Chip(
                                          label: Text(genre),
                                          visualDensity: VisualDensity.compact,
                                        ),
                                    ],
                                  ),
                                ],
                              ],
                            );
                          },
                        ),
                      ],
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 20),
              _ReadButton(book: book, repository: repository),
              if (book.description != null) ...[
                const SizedBox(height: 20),
                Text('About', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(book.description!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 24),
              _DigitalFormatsSection(book: book, repository: repository),
              const SizedBox(height: 24),
              _PhysicalCopiesSection(book: book, repository: repository),
              const SizedBox(height: 24),
              _ReaderNotesSection(book: book, repository: repository),
              if (repository.canRevert(book)) ...[
                const SizedBox(height: 12),
                Align(
                  alignment: Alignment.centerLeft,
                  child: TextButton.icon(
                    onPressed: _revert,
                    icon: const Icon(Icons.settings_backup_restore),
                    label: const Text('Revert to library defaults'),
                  ),
                ),
              ],
              const SizedBox(height: 32),
              Align(
                alignment: Alignment.centerLeft,
                child: TextButton.icon(
                  style: TextButton.styleFrom(
                    foregroundColor: theme.colorScheme.error,
                  ),
                  onPressed: () async {
                    // Capture the navigator now: deleting the book makes the
                    // parent StreamBuilder emit null and unmount this widget,
                    // so `context` would no longer be mounted to pop with.
                    final navigator = Navigator.of(context);
                    final confirmed = await showDialog<bool>(
                      context: context,
                      builder: (dialogContext) => AlertDialog(
                        title: Text('Remove “${book.title}”?'),
                        content: const Text(
                          'This deletes the book, its downloaded cover, and '
                          'any attached files from your library. There is no '
                          'undo.',
                        ),
                        actions: [
                          TextButton(
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(false),
                            child: const Text('Cancel'),
                          ),
                          FilledButton(
                            style: FilledButton.styleFrom(
                              backgroundColor: Theme.of(
                                dialogContext,
                              ).colorScheme.error,
                            ),
                            onPressed: () =>
                                Navigator.of(dialogContext).pop(true),
                            child: const Text('Remove'),
                          ),
                        ],
                      ),
                    );
                    if (confirmed != true) return;
                    await repository.deleteBook(book);
                    navigator.pop();
                  },
                  icon: const Icon(Icons.delete_outline),
                  label: const Text('Remove from library'),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ReadButton extends StatelessWidget {
  const _ReadButton({required this.book, required this.repository});

  final Book book;
  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    return StreamBuilder<List<BookFile>>(
      stream: repository.watchFilesOf(book.id),
      builder: (context, snapshot) {
        final files = snapshot.data ?? const <BookFile>[];
        final pdf = files.where((f) => f.format == 'pdf').firstOrNull;
        final started = book.readingProgress != null;
        final label = !started
            ? 'Read'
            : 'Resume reading · '
                  '${(book.readingProgress! * 100).round()}% '
                  '(page ${book.lastReadPage})';
        return FilledButton.icon(
          onPressed: files.isEmpty
              ? null
              : () {
                  if (pdf == null) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                        content: Text(
                          'Only PDF reading is supported for now — '
                          'EPUB is coming later.',
                        ),
                      ),
                    );
                    return;
                  }
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => ReaderPage(
                        book: book,
                        file: repository.fileOf(pdf),
                        repository: repository,
                      ),
                    ),
                  );
                },
          icon: Icon(started ? Icons.play_arrow : Icons.menu_book),
          label: Text(files.isEmpty ? 'Read (no digital copy yet)' : label),
        );
      },
    );
  }
}

class _DigitalFormatsSection extends StatelessWidget {
  const _DigitalFormatsSection({required this.book, required this.repository});

  final Book book;
  final LibraryRepository repository;

  Future<void> _attach(BuildContext context) async {
    const typeGroup = XTypeGroup(label: 'Books', extensions: ['pdf', 'epub']);
    final picked = await openFile(acceptedTypeGroups: const [typeGroup]);
    if (picked == null) return;
    await repository.attachFile(book.id, picked.path);
    if (context.mounted) {
      ScaffoldMessenger.of(
        context,
      ).showSnackBar(SnackBar(content: Text('Attached ${picked.name}')));
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<BookFile>>(
      stream: repository.watchFilesOf(book.id),
      builder: (context, snapshot) {
        final files = snapshot.data ?? const <BookFile>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Digital formats',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _attach(context),
                  icon: const Icon(Icons.attach_file),
                  label: const Text('Attach file'),
                ),
              ],
            ),
            if (files.isEmpty)
              Text(
                'No files yet — attach a PDF or EPUB.',
                style: theme.textTheme.bodySmall,
              )
            else
              for (final f in files)
                ListTile(
                  contentPadding: EdgeInsets.zero,
                  leading: Icon(
                    f.format == 'pdf'
                        ? Icons.picture_as_pdf_outlined
                        : Icons.book_outlined,
                  ),
                  title: Text(f.format.toUpperCase()),
                  subtitle: Text(
                    '${(f.sizeBytes / (1024 * 1024)).toStringAsFixed(1)} MB',
                  ),
                ),
          ],
        );
      },
    );
  }
}

class _PhysicalCopiesSection extends StatelessWidget {
  const _PhysicalCopiesSection({required this.book, required this.repository});

  final Book book;
  final LibraryRepository repository;

  Future<void> _addCopy(BuildContext context) async {
    final location = TextEditingController();
    final notes = TextEditingController();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Add physical copy'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            TextField(
              controller: location,
              autofocus: true,
              decoration: const InputDecoration(
                labelText: 'Location',
                hintText: 'e.g. living room, shelf 3',
              ),
            ),
            const SizedBox(height: 12),
            TextField(
              controller: notes,
              decoration: const InputDecoration(labelText: 'Notes'),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Add'),
          ),
        ],
      ),
    );
    if (confirmed == true) {
      await repository.addPhysicalCopy(
        book.id,
        location: location.text.trim().isEmpty ? null : location.text.trim(),
        notes: notes.text.trim().isEmpty ? null : notes.text.trim(),
      );
    }
    location.dispose();
    notes.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<PhysicalCopy>>(
      stream: repository.watchCopiesOf(book.id),
      builder: (context, snapshot) {
        final copies = snapshot.data ?? const <PhysicalCopy>[];
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Expanded(
                  child: Text(
                    'Physical copies',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                TextButton.icon(
                  onPressed: () => _addCopy(context),
                  icon: const Icon(Icons.add),
                  label: const Text('Add copy'),
                ),
              ],
            ),
            if (copies.isEmpty)
              Text(
                "You don't own this one on paper (yet).",
                style: theme.textTheme.bodySmall,
              )
            else
              for (final c in copies)
                _PhysicalCopyTile(copy: c, repository: repository),
          ],
        );
      },
    );
  }
}

/// One physical copy with its lending state: shows who has it (if anyone),
/// lets you lend it out or mark it returned, and lists past borrowers.
class _PhysicalCopyTile extends StatelessWidget {
  const _PhysicalCopyTile({required this.copy, required this.repository});

  final PhysicalCopy copy;
  final LibraryRepository repository;

  static String _date(DateTime d) =>
      '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _lend(BuildContext context) async {
    final borrower = TextEditingController();
    final name = await showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Lend this copy'),
        content: TextField(
          controller: borrower,
          autofocus: true,
          textInputAction: TextInputAction.done,
          onSubmitted: (v) => Navigator.of(dialogContext).pop(v.trim()),
          decoration: const InputDecoration(
            labelText: 'Borrower',
            hintText: "Who's taking it?",
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () =>
                Navigator.of(dialogContext).pop(borrower.text.trim()),
            child: const Text('Lend'),
          ),
        ],
      ),
    );
    borrower.dispose();
    if (name != null && name.isNotEmpty) {
      await repository.lendCopy(copy.id, name);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return StreamBuilder<List<Loan>>(
      stream: repository.watchLoansOf(copy.id),
      builder: (context, snapshot) {
        final loans = snapshot.data ?? const <Loan>[];
        final active = loans.where((l) => l.returnedAt == null).firstOrNull;
        final past = loans.where((l) => l.returnedAt != null).toList();
        final status = active != null
            ? 'On loan to ${active.borrower} since ${_date(active.loanedAt)}'
            : 'On the shelf';
        return Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            ListTile(
              contentPadding: EdgeInsets.zero,
              leading: Icon(
                active != null ? Icons.person_outline : Icons.place_outlined,
              ),
              title: Text(copy.location ?? 'Somewhere…'),
              subtitle: Text(
                [if (copy.notes != null) copy.notes!, status].join('\n'),
              ),
              isThreeLine: copy.notes != null,
              trailing: active != null
                  ? TextButton(
                      onPressed: () => repository.returnLoan(active.id),
                      child: const Text('Return'),
                    )
                  : TextButton(
                      onPressed: () => _lend(context),
                      child: const Text('Lend'),
                    ),
            ),
            if (past.isNotEmpty)
              Padding(
                padding: const EdgeInsets.only(left: 8, bottom: 8),
                child: Text(
                  'Previously lent to ${past.map((l) => l.borrower).join(', ')}',
                  style: theme.textTheme.bodySmall,
                ),
              ),
          ],
        );
      },
    );
  }
}

/// The book's cover: shows the image and, on hover (desktop), reveals a
/// "Change cover" overlay. Tapping picks a new image — the same mechanic as the
/// server console. A cover-less book shows a clickable "No cover" placeholder.
class _CoverThumb extends StatefulWidget {
  const _CoverThumb({required this.cover, required this.onTap});

  final File? cover;
  final VoidCallback onTap;

  @override
  State<_CoverThumb> createState() => _CoverThumbState();
}

class _CoverThumbState extends State<_CoverThumb> {
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cover = widget.cover;
    final hasCover = cover != null && cover.existsSync();
    return MouseRegion(
      cursor: SystemMouseCursors.click,
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: GestureDetector(
        onTap: widget.onTap,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(8),
          child: SizedBox(
            width: 110,
            height: 162,
            child: Stack(
              fit: StackFit.expand,
              children: [
                if (hasCover)
                  Image.file(cover, fit: BoxFit.cover)
                else
                  Container(
                    color: theme.colorScheme.surfaceContainerHighest,
                    alignment: Alignment.center,
                    child: Text('No cover', style: theme.textTheme.bodySmall),
                  ),
                AnimatedOpacity(
                  opacity: _hover ? 1 : 0,
                  duration: const Duration(milliseconds: 120),
                  child: Container(
                    color: Colors.black54,
                    alignment: Alignment.center,
                    child: const Text(
                      'Change\ncover',
                      textAlign: TextAlign.center,
                      style: TextStyle(color: Colors.white, fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Personal reader notes for a book — stored locally, never synced to a server.
class _ReaderNotesSection extends StatefulWidget {
  const _ReaderNotesSection({required this.book, required this.repository});

  final Book book;
  final LibraryRepository repository;

  @override
  State<_ReaderNotesSection> createState() => _ReaderNotesSectionState();
}

class _ReaderNotesSectionState extends State<_ReaderNotesSection> {
  late final TextEditingController _controller = TextEditingController(
    text: widget.book.readerNotes ?? '',
  );
  bool _dirty = false;

  @override
  void didUpdateWidget(covariant _ReaderNotesSection old) {
    super.didUpdateWidget(old);
    // Pick up external changes (e.g. a revert) unless the user is mid-edit.
    if (!_dirty && (widget.book.readerNotes ?? '') != _controller.text) {
      _controller.text = widget.book.readerNotes ?? '';
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Row(
          children: [
            Expanded(
              child: Text('My notes', style: theme.textTheme.titleMedium),
            ),
            if (_dirty)
              TextButton(
                onPressed: () async {
                  await widget.repository.setReaderNotes(
                    widget.book.id,
                    _controller.text,
                  );
                  if (mounted) setState(() => _dirty = false);
                },
                child: const Text('Save'),
              ),
          ],
        ),
        Text(
          'Private to this device — never shared with a server.',
          style: theme.textTheme.bodySmall,
        ),
        const SizedBox(height: 8),
        TextField(
          controller: _controller,
          minLines: 3,
          maxLines: 8,
          onChanged: (_) {
            if (!_dirty) setState(() => _dirty = true);
          },
          decoration: const InputDecoration(
            hintText: 'Thoughts, quotes, where you left off…',
            border: OutlineInputBorder(),
          ),
        ),
      ],
    );
  }
}

/// Bottom sheet to edit a book's core details and change its cover.
class _EditBookSheet extends StatefulWidget {
  const _EditBookSheet({
    required this.book,
    required this.repository,
    required this.onPickCover,
    required this.onCoverFromFirstPage,
  });

  final Book book;
  final LibraryRepository repository;
  final Future<void> Function() onPickCover;
  final Future<void> Function() onCoverFromFirstPage;

  @override
  State<_EditBookSheet> createState() => _EditBookSheetState();
}

class _EditBookSheetState extends State<_EditBookSheet> {
  late final _title = TextEditingController(text: widget.book.title);
  final _author = TextEditingController();
  late final _subtitle = TextEditingController(
    text: widget.book.subtitle ?? '',
  );
  late final _year = TextEditingController(
    text: widget.book.publishedYear?.toString() ?? '',
  );
  late final _pages = TextEditingController(
    text: widget.book.pageCount?.toString() ?? '',
  );
  late final _description = TextEditingController(
    text: widget.book.description ?? '',
  );

  @override
  void initState() {
    super.initState();
    // Authors live in their own table; load the current ones into the field.
    widget.repository.detailsFor(widget.book.id).then((details) {
      if (mounted) _author.text = details.authors.join(', ');
    });
  }

  @override
  void dispose() {
    _title.dispose();
    _author.dispose();
    _subtitle.dispose();
    _year.dispose();
    _pages.dispose();
    _description.dispose();
    super.dispose();
  }

  Future<void> _save() async {
    final title = _title.text.trim();
    if (title.isEmpty) return;
    await widget.repository.updateBookDetails(
      widget.book.id,
      title: title,
      subtitle: _subtitle.text,
      publishedYear: int.tryParse(_year.text.trim()),
      pageCount: int.tryParse(_pages.text.trim()),
      description: _description.text,
    );
    await widget.repository.setAuthors(
      widget.book.id,
      _author.text.split(','),
    );
    if (mounted) Navigator.of(context).pop();
  }

  @override
  Widget build(BuildContext context) {
    final bottom = MediaQuery.viewInsetsOf(context).bottom;
    return Padding(
      padding: EdgeInsets.fromLTRB(20, 20, 20, 20 + bottom),
      child: SingleChildScrollView(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Text('Edit details', style: Theme.of(context).textTheme.titleLarge),
            const SizedBox(height: 12),
            TextField(
              controller: _title,
              decoration: const InputDecoration(labelText: 'Title'),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _author,
              decoration: const InputDecoration(
                labelText: 'Author(s)',
                helperText: 'Separate multiple authors with commas',
              ),
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _subtitle,
              decoration: const InputDecoration(labelText: 'Subtitle'),
            ),
            const SizedBox(height: 10),
            Row(
              children: [
                Expanded(
                  child: TextField(
                    controller: _year,
                    keyboardType: TextInputType.number,
                    decoration:
                        const InputDecoration(labelText: 'Published year'),
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: TextField(
                    controller: _pages,
                    keyboardType: TextInputType.number,
                    decoration: const InputDecoration(
                      labelText: 'Pages',
                      helperText: 'Sets the physical width',
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),
            TextField(
              controller: _description,
              minLines: 3,
              maxLines: 6,
              decoration: const InputDecoration(labelText: 'Description'),
            ),
            const SizedBox(height: 14),
            OutlinedButton.icon(
              onPressed: () => widget.onPickCover(),
              icon: const Icon(Icons.image_outlined),
              label: const Text('Change cover…'),
            ),
            const SizedBox(height: 8),
            OutlinedButton.icon(
              onPressed: () {
                Navigator.of(context).pop();
                widget.onCoverFromFirstPage();
              },
              icon: const Icon(Icons.picture_as_pdf_outlined),
              label: const Text('Use first page of the PDF as cover'),
            ),
            const SizedBox(height: 6),
            Text(
              'Tip: you can also drag an image, PDF, or EPUB onto the book '
              'page.',
              style: Theme.of(context).textTheme.bodySmall,
            ),
            const SizedBox(height: 16),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton(
                  onPressed: () => Navigator.of(context).pop(),
                  child: const Text('Cancel'),
                ),
                const SizedBox(width: 8),
                FilledButton(onPressed: _save, child: const Text('Save')),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
