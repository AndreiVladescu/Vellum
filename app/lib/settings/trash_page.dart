import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';

/// The trash (plan 5 #52): books removed from the library but not yet deleted.
///
/// Everything here is still fully present on disk — cover, files, copies — and
/// nothing has been said to the server. A book leaves this list either by being
/// restored, or by the launch sweep (or "Delete now") running the real delete
/// once its grace period is up.
class TrashPage extends StatelessWidget {
  const TrashPage({super.key, required this.repository});

  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Trash')),
      body: StreamBuilder<List<Book>>(
        stream: repository.watchTrashedBooks(),
        builder: (context, snapshot) {
          final books = snapshot.data;
          if (books == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (books.isEmpty) return const _EmptyTrash();
          return ListView.builder(
            itemCount: books.length + 1,
            itemBuilder: (context, index) {
              if (index == 0) return _TrashHeader(repository: repository);
              return _TrashTile(
                book: books[index - 1],
                repository: repository,
              );
            },
          );
        },
      ),
    );
  }
}

class _EmptyTrash extends StatelessWidget {
  const _EmptyTrash();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.delete_outline,
            size: 56,
            color: theme.colorScheme.primary.withValues(alpha: 0.7),
          ),
          const SizedBox(height: 16),
          Text('The trash is empty', style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            'Books you remove wait here for '
            '${TrashService.graceperiod.inDays} days.',
            style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// The one explanation the list itself can't carry, plus "empty the trash" —
/// which exists so a user who *meant* the delete doesn't have to tap through
/// every book to get their disk space back.
class _TrashHeader extends StatelessWidget {
  const _TrashHeader({required this.repository});

  final LibraryRepository repository;

  Future<void> _emptyAll(BuildContext context) async {
    final books = await repository.watchTrashedBooks().first;
    if (books.isEmpty || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete ${books.length} book'
            '${books.length == 1 ? '' : 's'} for good?'),
        content: const Text(
          'Their covers and attached files are deleted from this device, and '
          'the deletion is sent to your server on the next sync. This can’t '
          'be undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final book in books) {
      await repository.trash.deleteNow(book);
    }
    messenger.showSnackBar(
      SnackBar(content: Text('Deleted ${books.length} book'
          '${books.length == 1 ? '' : 's'}')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 12, 16, 4),
      child: Row(
        children: [
          Expanded(
            child: Text(
              'Deleted for good ${TrashService.graceperiod.inDays} days after '
              'you remove them. Until then nothing has been deleted and your '
              'server hasn’t been told.',
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: () => _emptyAll(context),
            child: const Text('Empty'),
          ),
        ],
      ),
    );
  }
}

class _TrashTile extends StatelessWidget {
  const _TrashTile({required this.book, required this.repository});

  final Book book;
  final LibraryRepository repository;

  Future<void> _deleteNow(BuildContext context) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text('Delete “${book.title}” for good?'),
        content: const Text(
          'Its cover and any attached files are deleted from this device, and '
          'the deletion is sent to your server on the next sync. This can’t be '
          'undone.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.trash.deleteNow(book);
    messenger.showSnackBar(
      SnackBar(content: Text('“${book.title}” deleted')),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cover = repository.coverFileOf(book);
    return ListTile(
      leading: SizedBox(
        width: 40,
        height: 56,
        child: ClipRRect(
          borderRadius: BorderRadius.circular(4),
          child: cover != null
              ? Image.file(
                  cover,
                  fit: BoxFit.cover,
                  errorBuilder: (_, _, _) => const _NoCover(),
                )
              : const _NoCover(),
        ),
      ),
      title: Text(book.title),
      subtitle: Text(_remainingLabel()),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.restore_from_trash_outlined),
            tooltip: 'Restore',
            onPressed: () => repository.restoreBook(book.id),
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever_outlined),
            tooltip: 'Delete now',
            onPressed: () => _deleteNow(context),
          ),
        ],
      ),
    );
  }

  /// How long this book has left, in the units a person would use. Counted from
  /// the purge date rather than shown as an absolute one: "3 days left" is the
  /// question being asked, not "which Tuesday".
  String _remainingLabel() {
    final purge = TrashService.purgeDateOf(book);
    if (purge == null) return '';
    final left = purge.difference(DateTime.now());
    if (left.isNegative) return 'Deleted on the next launch';
    if (left.inDays >= 1) {
      return 'Deleted in ${left.inDays} day${left.inDays == 1 ? '' : 's'}';
    }
    if (left.inHours >= 1) {
      return 'Deleted in ${left.inHours} hour${left.inHours == 1 ? '' : 's'}';
    }
    return 'Deleted within the hour';
  }
}

class _NoCover extends StatelessWidget {
  const _NoCover();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      color: theme.colorScheme.surfaceContainerHighest,
      alignment: Alignment.center,
      child: Icon(
        Icons.menu_book_outlined,
        size: 18,
        color: theme.colorScheme.onSurfaceVariant,
      ),
    );
  }
}
