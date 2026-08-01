import 'package:flutter/material.dart';

import '../data/database.dart';

/// Where a batch of selected books should go, and whether they *leave* where
/// they are (next features #4).
///
/// **Why this asks two questions instead of one.** "Move" is only well defined
/// when you are looking at a shelf — from the whole library there is nothing to
/// leave, so a sheet that only asked "which shelf?" would be quietly wrong half
/// the time. Two buttons on a sheet that is already open costs nothing, and it
/// is the difference between a batch action you can trust and one you have to
/// check afterwards.
class ShelfTargetSheet extends StatelessWidget {
  const ShelfTargetSheet({
    super.key,
    required this.shelves,
    required this.count,
    required this.canMove,
  });

  final List<Shelf> shelves;

  /// How many books are being placed — named in the title, because the whole
  /// risk of a batch action is not knowing how big the batch is.
  final int count;

  /// Whether *Move here* is on offer: only when the books are on a shelf they
  /// could leave.
  final bool canMove;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final books = count == 1 ? '1 book' : '$count books';
    return SafeArea(
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 4),
            child: Text('Put $books on a shelf',
                style: theme.textTheme.titleMedium),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 12),
            child: Text(
              canMove
                  ? 'Move takes them off the shelf you are viewing; Add leaves '
                      'them on both.'
                  : 'You are viewing the whole library, so there is no shelf '
                      'to move them off.',
              style: theme.textTheme.bodySmall,
            ),
          ),
          const Divider(height: 1),
          Flexible(
            child: ListView.builder(
              shrinkWrap: true,
              itemCount: shelves.length,
              itemBuilder: (context, i) {
                final shelf = shelves[i];
                return ListTile(
                  leading: const Icon(Icons.shelves),
                  title: Text(shelf.name),
                  trailing: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      TextButton(
                        onPressed: () => Navigator.pop(
                          context,
                          (shelf: shelf, move: false),
                        ),
                        child: const Text('Add here'),
                      ),
                      if (canMove) ...[
                        const SizedBox(width: 8),
                        FilledButton(
                          onPressed: () => Navigator.pop(
                            context,
                            (shelf: shelf, move: true),
                          ),
                          child: const Text('Move here'),
                        ),
                      ],
                    ],
                  ),
                );
              },
            ),
          ),
        ],
      ),
    );
  }
}
