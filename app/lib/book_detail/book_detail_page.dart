import 'package:desktop_drop/desktop_drop.dart';
import 'package:file_selector/file_selector.dart';
import 'package:flutter/material.dart';

import '../data/book_file_validation.dart';
import '../data/database.dart';
import '../data/library_repository.dart';
import 'cover_thumb.dart';
import 'edit_book_sheet.dart';
import 'formats_section.dart';
import 'genres_section.dart';
import 'lend_sheet.dart';
import 'physical_copies_section.dart';
import 'read_button.dart';
import 'reader_notes_section.dart';

/// Full-page book view: metadata, digital formats, physical copies, and the
/// Read / Resume reading action.
class BookDetailPage extends StatelessWidget {
  const BookDetailPage({
    super.key,
    required this.book,
    required this.repository,
    this.onGenreTap,
  });

  /// Snapshot used before the first stream event arrives.
  final Book book;
  final LibraryRepository repository;

  /// Tapping a genre chip closes this page and filters the shelf by that genre.
  final void Function(String genre)? onGenreTap;

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
        return _BookDetailBody(
          book: current,
          repository: repository,
          onGenreTap: onGenreTap,
        );
      },
    );
  }
}

class _BookDetailBody extends StatefulWidget {
  const _BookDetailBody({
    required this.book,
    required this.repository,
    this.onGenreTap,
  });

  final Book book;
  final LibraryRepository repository;
  final void Function(String genre)? onGenreTap;

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
    builder: (_) => EditBookSheet(
      book: book,
      repository: repository,
      onPickCover: _pickCover,
      onCoverFromFirstPage: _coverFromFirstPage,
    ),
  );

  /// The lend "mini menu": pick a physical copy to lend out or mark returned,
  /// without hunting through the page. See [LendSheet].
  void _openLendSheet() => showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (_) => LendSheet(book: book, repository: repository),
  );

  /// A sheet listing custom shelves with checkmarks; tapping one toggles this
  /// book's membership. Live via the shelves + membership streams.
  void _openShelfPicker() => showModalBottomSheet<void>(
    context: context,
    builder: (sheetContext) => SafeArea(
      child: StreamBuilder<List<Shelf>>(
        stream: repository.watchShelves(),
        builder: (context, shelvesSnap) {
          final shelves = shelvesSnap.data ?? const [];
          return StreamBuilder<Set<String>>(
            stream: repository.watchShelfIdsFor(book.id),
            builder: (context, memberSnap) {
              final member = memberSnap.data ?? const <String>{};
              return Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Padding(
                    padding: EdgeInsets.fromLTRB(16, 16, 16, 8),
                    child: Align(
                      alignment: Alignment.centerLeft,
                      child: Text('Add to shelf'),
                    ),
                  ),
                  if (shelves.isEmpty)
                    const Padding(
                      padding: EdgeInsets.all(16),
                      child: Text('No shelves yet — create one below.'),
                    ),
                  for (final shelf in shelves)
                    CheckboxListTile(
                      title: Text(shelf.name),
                      value: member.contains(shelf.id),
                      onChanged: (on) => (on ?? false)
                          ? repository.addToShelf(book.id, shelf.id)
                          : repository.removeFromShelf(book.id, shelf.id),
                    ),
                  ListTile(
                    leading: const Icon(Icons.add),
                    title: const Text('New shelf…'),
                    onTap: () async {
                      final name = await _promptNewShelfName();
                      if (name != null && name.isNotEmpty) {
                        final id = await repository.createShelf(name);
                        await repository.addToShelf(book.id, id);
                      }
                    },
                  ),
                ],
              );
            },
          );
        },
      ),
    ),
  );

  Future<String?> _promptNewShelfName() {
    final controller = TextEditingController();
    return showDialog<String>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('New shelf'),
        content: TextField(
          controller: controller,
          autofocus: true,
          decoration: const InputDecoration(hintText: 'Shelf name'),
          onSubmitted: (v) => Navigator.pop(context, v.trim()),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.pop(context, controller.text.trim()),
            child: const Text('Create'),
          ),
        ],
      ),
    );
  }

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
            icon: const Icon(Icons.handshake_outlined),
            tooltip: 'Lend or return',
            onPressed: _openLendSheet,
          ),
          IconButton(
            icon: const Icon(Icons.bookmark_add_outlined),
            tooltip: 'Add to shelf',
            onPressed: _openShelfPicker,
          ),
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
                  CoverThumb(cover: cover, onTap: _pickCover),
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
                                const SizedBox(height: 10),
                                GenresSection(
                                  repository: repository,
                                  bookId: book.id,
                                  onGenreTap: widget.onGenreTap,
                                ),
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
              ReadButton(book: book, repository: repository),
              if (book.description != null) ...[
                const SizedBox(height: 20),
                Text('About', style: theme.textTheme.titleMedium),
                const SizedBox(height: 8),
                Text(book.description!, style: theme.textTheme.bodyMedium),
              ],
              const SizedBox(height: 24),
              DigitalFormatsSection(book: book, repository: repository),
              const SizedBox(height: 24),
              PhysicalCopiesSection(book: book, repository: repository),
              const SizedBox(height: 24),
              ReaderNotesSection(book: book, repository: repository),
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
