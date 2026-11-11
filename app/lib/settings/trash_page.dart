import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../widgets/page_insets.dart';
import '../l10n/gen/app_localizations.dart';

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
      appBar: AppBar(title: Text(L10n.of(context).trashTitle)),
      body: StreamBuilder<List<Book>>(
        stream: repository.watchTrashedBooks(),
        builder: (context, snapshot) {
          final books = snapshot.data;
          if (books == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (books.isEmpty) return const _EmptyTrash();
          return ListView.builder(
            padding: pageInsets(context, EdgeInsets.zero),
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
    final l10n = L10n.of(context);
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
          Text(l10n.trashEmptyTitle, style: theme.textTheme.titleMedium),
          const SizedBox(height: 6),
          Text(
            l10n.trashEmptyBody(TrashService.graceperiod.inDays),
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
    final l10n = L10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.trashEmptyAllTitle(books.length)),
        content: Text(l10n.trashEmptyAllBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    for (final book in books) {
      await repository.trash.deleteNow(book);
    }
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.trashEmptyAllDone(books.length))),
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
              L10n.of(context)
                  .trashHeaderNote(TrashService.graceperiod.inDays),
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ),
          const SizedBox(width: 8),
          TextButton(
            style: TextButton.styleFrom(
              foregroundColor: theme.colorScheme.error,
            ),
            onPressed: () => _emptyAll(context),
            child: Text(L10n.of(context).trashEmptyButton),
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
    final l10n = L10n.of(context);
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: Text(l10n.trashDeleteOneTitle(book.title)),
        content: Text(l10n.trashDeleteOneBody),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: Text(l10n.cancel),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
    if (confirmed != true) return;
    await repository.trash.deleteNow(book);
    messenger.showSnackBar(
      SnackBar(content: Text(l10n.trashDeleteOneDone(book.title))),
    );
  }

  @override
  Widget build(BuildContext context) {
    final cover = repository.coverFileOf(book);
    final l10n = L10n.of(context);
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
      subtitle: Text(_remainingLabel(l10n)),
      trailing: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            icon: const Icon(Icons.restore_from_trash_outlined),
            tooltip: l10n.trashRestoreTooltip,
            onPressed: () => repository.restoreBook(book.id),
          ),
          IconButton(
            icon: const Icon(Icons.delete_forever_outlined),
            tooltip: l10n.trashDeleteNowTooltip,
            onPressed: () => _deleteNow(context),
          ),
        ],
      ),
    );
  }

  /// How long this book has left, in the units a person would use. Counted from
  /// the purge date rather than shown as an absolute one: "3 days left" is the
  /// question being asked, not "which Tuesday".
  String _remainingLabel(L10n l10n) {
    final purge = TrashService.purgeDateOf(book);
    if (purge == null) return '';
    final left = purge.difference(DateTime.now());
    if (left.isNegative) return l10n.trashRemainingLaunch;
    if (left.inDays >= 1) return l10n.trashRemainingDays(left.inDays);
    if (left.inHours >= 1) return l10n.trashRemainingHours(left.inHours);
    return l10n.trashRemainingSoon;
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
