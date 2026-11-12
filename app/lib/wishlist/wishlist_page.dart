import 'dart:async';

import 'package:flutter/material.dart';

import '../add_book/isbn.dart';
import '../l10n/gen/app_localizations.dart';
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
      appBar: AppBar(title: Text(L10n.of(context).wishlistTitle)),
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
        label: Text(L10n.of(context).wishlistAddFab),
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
            Text(L10n.of(context).wishlistEmptyTitle,
                style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              L10n.of(context).wishlistEmptyBody,
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
          ? (book.publishedYear == null ? null : Text('${book.publishedYear}')) // i18n-ignore: a year
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
          final l10n = L10n.of(context);
          switch (action) {
            case 'lookup':
              await lookUpWishlistBook(context, repository, book);
            case 'own':
              await repository.wishlist.markOwned(book.id);
              messenger.showSnackBar(SnackBar(
                content: Text(l10n.wishlistMovedSnack(book.title)),
              ));
            case 'remove':
              // Through the trash like every other delete (plan 5 #52) — a
              // wishlist entry can be a mis-tap too.
              await repository.trashBook(book.id);
              messenger.showSnackBar(appSnackBar(
                content: Text(l10n.wishlistRemovedSnack(book.title)),
                action: SnackBarAction(
                  label: l10n.undo,
                  onPressed: () => repository.restoreBook(book.id),
                ),
              ));
          }
        },
        itemBuilder: (context) => [
          // A book jotted down by hand has no cover and no details, and no
          // file to take them from — so it is asked about online, by its ISBN
          // if you have the barcode in front of you.
          PopupMenuItem(
              value: 'lookup',
              child: Text(L10n.of(context).wishlistMenuLookUp)),
          PopupMenuItem(
              value: 'own', child: Text(L10n.of(context).wishlistMenuOwn)),
          PopupMenuItem(
              value: 'remove',
              child: Text(L10n.of(context).wishlistMenuRemove)),
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
  final l10n = L10n.of(context);
  final titleController = TextEditingController(text: initialTitle ?? '');
  final authorController = TextEditingController();
  final noteController = TextEditingController();
  final isbnController = TextEditingController();
  final added = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.wishlistAddTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: titleController,
            autofocus: true,
            decoration: InputDecoration(labelText: l10n.wishlistFieldTitle),
          ),
          TextField(
            controller: authorController,
            decoration: InputDecoration(labelText: l10n.wishlistFieldAuthor),
          ),
          TextField(
            controller: isbnController,
            keyboardType: TextInputType.text,
            decoration: InputDecoration(
              labelText: l10n.wishlistFieldIsbn,
              hintText: l10n.wishlistIsbnHint,
              helperText: l10n.wishlistIsbnHelperAdd,
              helperMaxLines: 2,
            ),
          ),
          TextField(
            controller: noteController,
            decoration: InputDecoration(
              labelText: l10n.wishlistFieldNote,
              hintText: l10n.wishlistNoteHint,
            ),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.wishlistAddConfirm),
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
  final l10n = L10n.of(context);
  final controller = TextEditingController(text: book.isbn ?? '');
  final asked = await showDialog<bool>(
    context: context,
    builder: (dialogContext) => AlertDialog(
      title: Text(l10n.wishlistLookUpTitle),
      content: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          TextField(
            controller: controller,
            autofocus: true,
            decoration: InputDecoration(
              labelText: l10n.wishlistFieldIsbn,
              hintText: l10n.wishlistIsbnHint,
              helperText: l10n.wishlistIsbnHelperLookUp,
              helperMaxLines: 2,
            ),
            onSubmitted: (_) => Navigator.pop(dialogContext, true),
          ),
        ],
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.pop(dialogContext, false),
          child: Text(l10n.cancel),
        ),
        FilledButton(
          onPressed: () => Navigator.pop(dialogContext, true),
          child: Text(l10n.wishlistLookUpConfirm),
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
      SnackBar(content: Text(l10n.wishlistNotAnIsbn)),
    );
    return;
  }
  messenger.showSnackBar(SnackBar(
    content: Text(l10n.wishlistLookingUp),
    duration: Duration(seconds: 2),
  ));
  try {
    final outcome = await repository.enrich.fill(book, isbn: isbn);
    messenger.showSnackBar(SnackBar(
      content: Text(switch (outcome) {
        EnrichOutcome.filled => l10n.wishlistFilled,
        EnrichOutcome.alreadyComplete => l10n.wishlistAlreadyComplete,
        EnrichOutcome.notFound => l10n.wishlistNotFound,
      }),
    ));
  } catch (e) {
    messenger.showSnackBar(
        SnackBar(content: Text(l10n.wishlistLookupFailed('$e'))));
  }
}
