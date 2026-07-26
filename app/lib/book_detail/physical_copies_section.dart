import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';

/// Prompts for a borrower's name. Returns the trimmed name, or null if the user
/// cancelled or left it blank. Shared by the inline copy tile and the lend sheet
/// so both flows collect a borrower the same way.
/// What a lend dialog collected (plan 5 #27).
class LendDetails {
  const LendDetails({required this.borrower, this.dueAt, this.contact});

  final String borrower;

  /// Null means no agreed return date — a real arrangement, not a blank field.
  final DateTime? dueAt;
  final String? contact;
}

/// Asks who is taking the book, when it's due back, and how to reach them.
///
/// The due date is offered as **presets plus "no date"** rather than a date
/// picker alone: most lending is "a couple of weeks", nobody wants to operate a
/// calendar for that, and "no date" has to be as easy as the others or people
/// will invent a date they don't mean.
Future<LendDetails?> promptBorrower(BuildContext context) async {
  final borrower = TextEditingController();
  final contact = TextEditingController();
  DateTime? due;
  int? selectedPreset;

  final result = await showDialog<LendDetails>(
    context: context,
    builder: (dialogContext) => StatefulBuilder(
      builder: (dialogContext, setState) {
        void pick(int? days) {
          setState(() {
            selectedPreset = days;
            due = days == null
                ? null
                : DateTime.now().add(Duration(days: days));
          });
        }

        return AlertDialog(
          title: const Text('Lend this copy'),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: borrower,
                  autofocus: true,
                  decoration: const InputDecoration(
                    labelText: 'Borrower',
                    hintText: "Who's taking it?",
                  ),
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: contact,
                  decoration: const InputDecoration(
                    labelText: 'Contact (optional)',
                    hintText: 'Phone, email, or how you know them',
                  ),
                ),
                const SizedBox(height: 16),
                const Text('Due back'),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    for (final (label, days) in [
                      ('2 weeks', 14),
                      ('1 month', 30),
                    ])
                      ChoiceChip(
                        label: Text(label),
                        selected: selectedPreset == days,
                        onSelected: (_) => pick(days),
                      ),
                    ChoiceChip(
                      label: const Text('No date'),
                      selected: selectedPreset == null && due == null,
                      onSelected: (_) => pick(null),
                    ),
                    ActionChip(
                      avatar: const Icon(Icons.event, size: 16),
                      label: Text(due != null && selectedPreset == -1
                          ? '${due!.year}-${due!.month.toString().padLeft(2, '0')}'
                              '-${due!.day.toString().padLeft(2, '0')}'
                          : 'Pick a date'),
                      onPressed: () async {
                        final now = DateTime.now();
                        final picked = await showDatePicker(
                          context: dialogContext,
                          initialDate: due ?? now.add(const Duration(days: 14)),
                          firstDate: now,
                          lastDate: now.add(const Duration(days: 365 * 5)),
                        );
                        if (picked != null) {
                          setState(() {
                            due = picked;
                            selectedPreset = -1;
                          });
                        }
                      },
                    ),
                  ],
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('Cancel'),
            ),
            FilledButton(
              onPressed: () {
                final name = borrower.text.trim();
                if (name.isEmpty) return;
                Navigator.of(dialogContext).pop(LendDetails(
                  borrower: name,
                  dueAt: due,
                  contact: contact.text.trim(),
                ));
              },
              child: const Text('Lend'),
            ),
          ],
        );
      },
    ),
  );
  borrower.dispose();
  contact.dispose();
  return result;
}

/// The "Physical copies" list: locations, lend/return, and loan history.
class PhysicalCopiesSection extends StatelessWidget {
  const PhysicalCopiesSection({
    super.key,
    required this.book,
    required this.repository,
  });

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
                PhysicalCopyTile(copy: c, repository: repository),
          ],
        );
      },
    );
  }
}

/// One physical copy with its lending state: shows who has it (if anyone),
/// lets you lend it out or mark it returned, and lists past borrowers.
class PhysicalCopyTile extends StatelessWidget {
  const PhysicalCopyTile({
    super.key,
    required this.copy,
    required this.repository,
  });

  final PhysicalCopy copy;
  final LibraryRepository repository;

  static String _date(DateTime d) =>
      '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _lend(BuildContext context) async {
    final details = await promptBorrower(context);
    if (details != null) {
      await repository.lendCopy(
        copy.id,
        details.borrower,
        dueAt: details.dueAt,
        contact: details.contact,
      );
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
              // Where the copy *is* comes from its placement when it has one
              // (plan 5 #50); the free-text field is only a note, and showing it
              // as the location goes stale the first time the shelf is
              // rearranged.
              title: StreamBuilder<CopyLocation?>(
                stream: repository.layout.watchLocationOf(copy.id),
                builder: (context, snapshot) {
                  final placed = snapshot.data;
                  if (placed != null) {
                    return Row(
                      children: [
                        Flexible(child: Text(placed.display)),
                        const SizedBox(width: 6),
                        Icon(Icons.push_pin_outlined,
                            size: 14,
                            color: Theme.of(context).colorScheme.outline),
                      ],
                    );
                  }
                  return Text(copy.location ?? 'Somewhere…');
                },
              ),
              subtitle: Text(
                [
                  // Labelled as a note, so it doesn't read as the location once
                  // a placement supersedes it.
                  if (copy.location != null &&
                      copy.location!.trim().isNotEmpty)
                    'Note: ${copy.location}',
                  if (copy.notes != null) copy.notes!,
                  status,
                ].join('\n'),
              ),
              isThreeLine: true,
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
