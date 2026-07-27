import 'package:flutter/material.dart';

import '../book_detail/book_detail_page.dart';
import '../data/database.dart';
import '../data/library_repository.dart';
import '../server/connection_store.dart';
import '../settings/app_settings.dart';

/// Books you want but don't own (plan 5 #21a).
///
/// A list rather than a shelf, deliberately: a shelf is a picture of what you
/// have, and drawing wanted books as spines standing on it would be the one
/// thing this feature must not say. Each entry is still a real book — tap
/// through to the same detail page — so buying it is "attach the file" or
/// "add a copy" rather than a re-entry.
class WishlistPage extends StatelessWidget {
  const WishlistPage({
    super.key,
    required this.repository,
    this.settings,
    this.connection,
  });

  final LibraryRepository repository;
  final AppSettingsStore? settings;
  final ServerConnection? connection;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Wishlist')),
      body: StreamBuilder<List<Book>>(
        stream: repository.wishlist.watchWishlist(),
        builder: (context, snapshot) {
          final books = snapshot.data;
          if (books == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (books.isEmpty) return const _EmptyWishlist();
          return ListView.separated(
            itemCount: books.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _WishTile(
              book: books[i],
              repository: repository,
              settings: settings,
              connection: connection,
            ),
          );
        },
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () => promptAddToWishlist(context, repository),
        icon: const Icon(Icons.add),
        label: const Text('Add a book you want'),
      ),
    );
  }
}

class _EmptyWishlist extends StatelessWidget {
  const _EmptyWishlist();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(
              Icons.bookmark_add_outlined,
              size: 56,
              color: theme.colorScheme.primary.withValues(alpha: 0.7),
            ),
            const SizedBox(height: 16),
            Text('Nothing on your wishlist', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Books you want but don’t own yet live here — add one by hand, '
              'scan a barcode in a shop, or fill a gap in a series you '
              'collect.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}

class _WishTile extends StatelessWidget {
  const _WishTile({
    required this.book,
    required this.repository,
    required this.settings,
    required this.connection,
  });

  final Book book;
  final LibraryRepository repository;
  final AppSettingsStore? settings;
  final ServerConnection? connection;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return ListTile(
      leading: const Icon(Icons.bookmark_border),
      title: Text(book.title),
      subtitle: book.readerNotes == null
          ? (book.publishedYear == null ? null : Text('${book.publishedYear}'))
          : Text(
              book.readerNotes!,
              maxLines: 2,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
      onTap: () => Navigator.of(context).push(MaterialPageRoute(
        builder: (_) => BookDetailPage(
          book: book,
          repository: repository,
          settings: settings,
          connection: connection,
        ),
      )),
      trailing: PopupMenuButton<String>(
        onSelected: (action) async {
          final messenger = ScaffoldMessenger.of(context);
          switch (action) {
            case 'own':
              await repository.wishlist.markOwned(book.id);
              messenger.showSnackBar(SnackBar(
                content: Text('“${book.title}” moved to your library'),
              ));
            case 'remove':
              // Through the trash like every other delete (plan 5 #52) — a
              // wishlist entry can be a mis-tap too.
              await repository.trashBook(book.id);
              messenger.showSnackBar(SnackBar(
                content: Text('“${book.title}” removed'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => repository.restoreBook(book.id),
                ),
              ));
          }
        },
        itemBuilder: (context) => const [
          PopupMenuItem(value: 'own', child: Text('I own this now')),
          PopupMenuItem(value: 'remove', child: Text('Remove from wishlist')),
        ],
      ),
    );
  }
}

/// The by-hand entry point: a title is the only thing required, because the
/// whole point is to catch a book you heard about thirty seconds ago.
Future<String?> promptAddToWishlist(
  BuildContext context,
  LibraryRepository repository, {
  String? initialTitle,
}) async {
  final titleController = TextEditingController(text: initialTitle ?? '');
  final authorController = TextEditingController();
  final noteController = TextEditingController();
  final added = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Add to wishlist'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: titleController,
            autofocus: true,
            decoration: const InputDecoration(labelText: 'Title'),
          ),
          TextField(
            controller: authorController,
            decoration: const InputDecoration(labelText: 'Author (optional)'),
          ),
          TextField(
            controller: noteController,
            decoration: const InputDecoration(
              labelText: 'Note (optional)',
              hintText: 'Why you want it, where you saw it…',
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: const Text('Add'),
        ),
      ],
    ),
  );
  final title = titleController.text.trim();
  titleController.dispose();
  final author = authorController.text.trim();
  authorController.dispose();
  final note = noteController.text.trim();
  noteController.dispose();
  if (added != true || title.isEmpty) return null;
  return repository.wishlist.add(
    title: title,
    author: author.isEmpty ? null : author,
    note: note.isEmpty ? null : note,
  );
}
