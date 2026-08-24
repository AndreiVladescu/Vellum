import 'dart:async';

import 'package:flutter/material.dart';

import '../add_book/isbn.dart';
import '../book_detail/book_detail_page.dart';
import '../data/catalogue_enrich.dart';
import '../data/database.dart';
import '../data/library_repository.dart';
import '../server/connection_store.dart';
import '../settings/app_settings.dart';
import '../snack_bars.dart';
import '../widgets/page_insets.dart';

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
            padding: pageInsets(context, EdgeInsets.zero),
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
            case 'lookup':
              await lookUpWishlistBook(context, repository, book);
            case 'own':
              await repository.wishlist.markOwned(book.id);
              messenger.showSnackBar(SnackBar(
                content: Text('“${book.title}” moved to your library'),
              ));
            case 'remove':
              // Through the trash like every other delete (plan 5 #52) — a
              // wishlist entry can be a mis-tap too.
              await repository.trashBook(book.id);
              messenger.showSnackBar(appSnackBar(
                content: Text('“${book.title}” removed'),
                action: SnackBarAction(
                  label: 'Undo',
                  onPressed: () => repository.restoreBook(book.id),
                ),
              ));
          }
        },
        itemBuilder: (context) => const [
          // A book jotted down by hand has no cover and no details, and no
          // file to take them from — so it is asked about online, by its ISBN
          // if you have the barcode in front of you.
          PopupMenuItem(value: 'lookup', child: Text('Look up online…')),
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
  final isbnController = TextEditingController();
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
            controller: isbnController,
            keyboardType: TextInputType.text,
            decoration: const InputDecoration(
              labelText: 'ISBN (optional)',
              hintText: '978… or the ten-digit form',
              helperText: 'With one of these, the rest fills itself in',
              helperMaxLines: 2,
            ),
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
  final isbn = toIsbn13(isbnController.text);
  isbnController.dispose();
  if (added != true) return null;

  // An ISBN is the whole record: title, author, publisher, cover. Ten digits or
  // thirteen — a barcode and a copyright page say the same thing two ways.
  if (isbn != null) {
    final found = await repository.metadata.lookupByIsbn(isbn);
    if (found != null) {
      return repository.wishlist.addFromSearch(
        found,
        note: note.isEmpty ? null : note,
      );
    }
  }
  if (title.isEmpty) return null;
  final id = await repository.wishlist.add(
    title: title,
    author: author.isEmpty ? null : author,
    note: note.isEmpty ? null : note,
  );
  // No file to take a cover from, so ask the catalogues — quietly, and only
  // for the blanks. A wishlist entry with a cover looks like a book rather
  // than a to-do item.
  unawaited(() async {
    try {
      final book = await repository.watchBook(id).first;
      if (book != null) {
        await repository.enrich.fill(book, isbn: isbn);
      }
    } catch (_) {
      // Offline, or nothing found: the entry stands as typed.
    }
  }());
  return id;
}

/// Asks the catalogues about a wishlist entry — by ISBN when the reader has
/// one, otherwise by what the book already says about itself.
Future<void> lookUpWishlistBook(
  BuildContext context,
  LibraryRepository repository,
  Book book,
) async {
  final controller = TextEditingController(text: book.isbn ?? '');
  final asked = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: const Text('Look up online'),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            decoration: const InputDecoration(
              labelText: 'ISBN (optional)',
              hintText: '978… or the ten-digit form',
              helperText: 'Leave it empty to search by title and author',
              helperMaxLines: 2,
            ),
            onSubmitted: (_) => Navigator.pop(dialogContext, true),
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
          child: const Text('Look up'),
        ),
      ],
    ),
  );
  final typed = controller.text.trim();
  controller.dispose();
  if (asked != true || !context.mounted) return;

  final messenger = ScaffoldMessenger.of(context);
  final isbn = typed.isEmpty ? null : toIsbn13(typed);
  if (typed.isNotEmpty && isbn == null) {
    messenger.showSnackBar(
      const SnackBar(content: Text('That is not an ISBN.')),
    );
    return;
  }
  messenger.showSnackBar(const SnackBar(
    content: Text('Looking it up…'),
    duration: Duration(seconds: 2),
  ));
  try {
    final outcome = await repository.enrich.fill(book, isbn: isbn);
    messenger.showSnackBar(SnackBar(
      content: Text(switch (outcome) {
        EnrichOutcome.filled => 'Filled in what was missing',
        EnrichOutcome.alreadyComplete => 'Nothing to add — it already knows',
        EnrichOutcome.notFound => 'No catalogue has this one',
      }),
    ));
  } catch (e) {
    messenger.showSnackBar(SnackBar(content: Text('Lookup failed: $e')));
  }
}
