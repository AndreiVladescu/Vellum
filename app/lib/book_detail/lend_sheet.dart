import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import 'physical_copies_section.dart';

/// A bottom-sheet "mini menu" for lending, reachable straight from the book's
/// app bar so lending doesn't require scrolling to the Physical-copies section.
///
/// It uses the same per-copy loan model: each physical copy can be lent to one
/// borrower at a time and returned later (history is kept). A book with no
/// physical copy on record gets a one-tap "add a copy and lend it" path.
class LendSheet extends StatelessWidget {
  const LendSheet({super.key, required this.book, required this.repository});

  final Book book;
  final LibraryRepository repository;

  /// Creates a placeholder physical copy, then lends it — the smooth path for a
  /// book that isn't tracked on paper yet. No-ops if the borrower prompt is
  /// cancelled, so it never leaves an empty copy behind.
  Future<void> _addCopyAndLend(BuildContext context) async {
    final name = await promptBorrower(context);
    if (name == null) return;
    final copyId = await repository.addPhysicalCopy(book.id);
    await repository.lendCopy(copyId, name);
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: StreamBuilder<List<PhysicalCopy>>(
        stream: repository.watchCopiesOf(book.id),
        builder: (context, snapshot) {
          final copies = snapshot.data ?? const <PhysicalCopy>[];
          return SingleChildScrollView(
            child: Padding(
              padding: const EdgeInsets.fromLTRB(20, 4, 20, 16),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'Lend “${book.title}”',
                    style: theme.textTheme.titleMedium,
                  ),
                  const SizedBox(height: 8),
                  if (copies.isEmpty)
                    ListTile(
                      contentPadding: EdgeInsets.zero,
                      leading: const Icon(Icons.add),
                      title: const Text('Lend a copy'),
                      subtitle: const Text(
                        'No physical copy on record yet — this adds one, then '
                        'lends it out.',
                      ),
                      onTap: () => _addCopyAndLend(context),
                    )
                  else
                    for (final c in copies)
                      PhysicalCopyTile(copy: c, repository: repository),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}
