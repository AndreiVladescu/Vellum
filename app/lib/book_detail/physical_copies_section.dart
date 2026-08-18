import 'package:flutter/material.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../snack_bars.dart';
import '../widgets/page_insets.dart';
import 'copy_photos.dart';

/// Prompts for a borrower's name. Returns the trimmed name, or null if the user
/// cancelled or left it blank. Shared by the inline copy tile and the lend sheet
/// so both flows collect a borrower the same way.
/// What a lend dialog collected (plan 5 #27).
class LendDetails {
  const LendDetails({
    required this.borrower,
    this.dueAt,
    this.contact,
    this.photograph = false,
  });

  final String borrower;

  /// Null means no agreed return date — a real arrangement, not a blank field.
  final DateTime? dueAt;
  final String? contact;

  /// Whether to photograph the copy's condition as it goes out (plan 5 #51).
  /// Opt-in per loan, not a setting: it matters for the borrowed-by-a-stranger
  /// case and is noise for lending to a flatmate.
  final bool photograph;
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
  bool photograph = false;

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
                const SizedBox(height: 8),
                // Condition photo (plan 5 #51). Offered here because *before*
                // the book leaves is the only moment the shot is worth
                // anything — afterwards it proves nothing.
                CheckboxListTile(
                  value: photograph,
                  onChanged: (v) => setState(() => photograph = v ?? false),
                  contentPadding: EdgeInsets.zero,
                  controlAffinity: ListTileControlAffinity.leading,
                  dense: true,
                  title: const Text('Photograph its condition first'),
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
                  photograph: photograph,
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
              // One row per copy used to sit inline here — lend/return button,
              // photo strip and all — which made a book with three or four
              // copies most of the page. Now it's a single summary that opens
              // the same detail in an overlay instead of always paying for it.
              OutlinedButton.icon(
                onPressed: () => showCopiesSheet(
                  context,
                  book: book,
                  repository: repository,
                ),
                icon: const Icon(Icons.inventory_2_outlined),
                label: Text(
                  copies.length == 1
                      ? '1 physical copy'
                      : '${copies.length} physical copies',
                ),
              ),
          ],
        );
      },
    );
  }
}

/// Opens the "Physical copies" overlay for [book]: every copy's location,
/// lending state and photos, each still fully interactive — lend, return,
/// photograph, delete — just off the book page instead of always on it.
void showCopiesSheet(
  BuildContext context, {
  required Book book,
  required LibraryRepository repository,
}) {
  showModalBottomSheet<void>(
    context: context,
    showDragHandle: true,
    isScrollControlled: true,
    builder: (sheetContext) =>
        _CopiesSheet(book: book, repository: repository),
  );
}

class _CopiesSheet extends StatelessWidget {
  const _CopiesSheet({required this.book, required this.repository});

  final Book book;
  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return SafeArea(
      child: ConstrainedBox(
        // Leaves room to see there's more to scroll to, rather than a sheet
        // that grows to fill the screen for two copies and looks like a bug
        // for twelve.
        constraints: BoxConstraints(
          maxHeight: MediaQuery.sizeOf(context).height * 0.85,
        ),
        child: StreamBuilder<List<PhysicalCopy>>(
          stream: repository.watchCopiesOf(book.id),
          builder: (context, snapshot) {
            final copies = snapshot.data ?? const <PhysicalCopy>[];
            return Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Padding(
                  padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
                  child: Text(
                    'Physical copies of “${book.title}”',
                    style: theme.textTheme.titleMedium,
                  ),
                ),
                Flexible(
                  child: copies.isEmpty
                      // The last copy in here was just deleted — rather than
                      // the sheet vanishing under whoever's thumb, it says so.
                      ? Padding(
                          padding: const EdgeInsets.fromLTRB(20, 0, 20, 24),
                          child: Text(
                            "None left — they've all been deleted.",
                            style: theme.textTheme.bodySmall,
                          ),
                        )
                      : ListView.separated(
                          shrinkWrap: true,
                          padding: EdgeInsets.fromLTRB(
                            16,
                            0,
                            16,
                            16 + sheetBottomInset(context),
                          ),
                          itemCount: copies.length,
                          separatorBuilder: (_, _) => const SizedBox(height: 10),
                          itemBuilder: (context, i) => _CopyCard(
                            copy: copies[i],
                            repository: repository,
                          ),
                        ),
                ),
              ],
            );
          },
        ),
      ),
    );
  }
}

/// One physical copy, as a card rather than a bare row: location, lending
/// state, condition photos and past borrowers, plus lend/return and delete.
class _CopyCard extends StatelessWidget {
  const _CopyCard({required this.copy, required this.repository});

  final PhysicalCopy copy;
  final LibraryRepository repository;

  static String _date(DateTime d) =>
      '${d.year}-'
      '${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  Future<void> _lend(BuildContext context) async {
    final details = await promptBorrower(context);
    if (details == null) return;
    try {
      await repository.lendCopy(
        copy.id,
        details.borrower,
        dueAt: details.dueAt,
        contact: details.contact,
      );
    } on StateError catch (e) {
      // The button is only shown for a free copy, so this means a sync landed
      // someone else's loan while the borrower was being typed in.
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    if (details.photograph && context.mounted) {
      await addCopyPhoto(context, repository, copy.id,
          caption: 'Lent to ${details.borrower}');
    }
  }

  Future<void> _return(BuildContext context, Loan active) async {
    await repository.returnLoan(active.id);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(appSnackBar(
      content: Text('Returned by ${active.borrower}'),
      action: SnackBarAction(
        label: 'Photograph it',
        onPressed: () => addCopyPhoto(context, repository, copy.id,
            caption: 'Returned by ${active.borrower}'),
      ),
    ));
  }

  /// Deletes the copy — its placement, loan history and photos go with it
  /// (`PhysicalService.deletePhysicalCopy`), so this asks first and says so,
  /// with a sharper warning when it would also drop an active loan.
  Future<void> _delete(BuildContext context, {required bool hasActiveLoan}) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        title: const Text('Delete this copy?'),
        content: Text(
          hasActiveLoan
              ? "It's currently on loan — deleting it removes that loan, its "
                  "history and its condition photos too. This can't be undone."
              : 'Its loan history and condition photos go with it. '
                  "This can't be undone.",
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogContext).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(dialogContext).colorScheme.error,
            ),
            onPressed: () => Navigator.of(dialogContext).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (confirmed != true || !context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    await repository.deletePhysicalCopy(copy.id);
    messenger.showSnackBar(appSnackBar(content: const Text('Copy deleted.')));
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
        return Card(
          margin: EdgeInsets.zero,
          clipBehavior: Clip.antiAlias,
          child: Padding(
            padding: const EdgeInsets.fromLTRB(12, 10, 4, 4),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Padding(
                      padding: const EdgeInsets.only(top: 2),
                      child: Icon(
                        active != null
                            ? Icons.person_outline
                            : Icons.place_outlined,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // Where the copy *is* comes from its placement when
                          // it has one (plan 5 #50); the free-text field is
                          // only a note, and showing it as the location goes
                          // stale the first time the shelf is rearranged.
                          StreamBuilder<CopyLocation?>(
                            stream: repository.layout.watchLocationOf(copy.id),
                            builder: (context, snapshot) {
                              final placed = snapshot.data;
                              if (placed != null) {
                                return Row(
                                  children: [
                                    Flexible(
                                      child: Text(placed.display,
                                          style: theme.textTheme.titleSmall),
                                    ),
                                    const SizedBox(width: 6),
                                    Icon(Icons.push_pin_outlined,
                                        size: 13,
                                        color: theme.colorScheme.outline),
                                  ],
                                );
                              }
                              return Text(copy.location ?? 'Somewhere…',
                                  style: theme.textTheme.titleSmall);
                            },
                          ),
                          const SizedBox(height: 2),
                          Text(
                            [
                              // Labelled as a note, so it doesn't read as the
                              // location once a placement supersedes it.
                              if (copy.location != null &&
                                  copy.location!.trim().isNotEmpty)
                                'Note: ${copy.location}',
                              if (copy.notes != null) copy.notes!,
                              status,
                            ].join('\n'),
                            style: theme.textTheme.bodySmall,
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      tooltip: 'Delete this copy',
                      icon: const Icon(Icons.delete_outline, size: 20),
                      onPressed: () =>
                          _delete(context, hasActiveLoan: active != null),
                    ),
                  ],
                ),
                CopyPhotoStrip(copyId: copy.id, repository: repository),
                if (past.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.only(left: 30, top: 2, bottom: 4),
                    child: Text(
                      'Previously lent to ${past.map((l) => l.borrower).join(', ')}',
                      style: theme.textTheme.bodySmall,
                    ),
                  ),
                Align(
                  alignment: Alignment.centerRight,
                  child: active != null
                      ? TextButton(
                          onPressed: () => _return(context, active),
                          child: const Text('Return'),
                        )
                      : TextButton(
                          onPressed: () => _lend(context),
                          child: const Text('Lend'),
                        ),
                ),
              ],
            ),
          ),
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
    if (details == null) return;
    try {
      await repository.lendCopy(
        copy.id,
        details.borrower,
        dueAt: details.dueAt,
        contact: details.contact,
      );
    } on StateError catch (e) {
      // The button is only shown for a free copy, so this means a sync landed
      // someone else's loan while the borrower was being typed in. Say so
      // rather than crashing into a red screen.
      if (context.mounted) {
        ScaffoldMessenger.of(context)
            .showSnackBar(SnackBar(content: Text(e.message)));
      }
      return;
    }
    // The photo is attached after the loan exists, and its caption names the
    // borrower — that is what makes a shot from June mean anything in October.
    if (details.photograph && context.mounted) {
      await addCopyPhoto(context, repository, copy.id,
          caption: 'Lent to ${details.borrower}');
    }
  }

  /// Returning is the other half of the argument the photos exist to settle, so
  /// the offer is made again — as a snackbar action rather than another
  /// dialog, because most returns are uneventful and shouldn't cost a tap.
  Future<void> _return(BuildContext context, Loan active) async {
    await repository.returnLoan(active.id);
    if (!context.mounted) return;
    final messenger = ScaffoldMessenger.of(context);
    messenger.showSnackBar(appSnackBar(
      content: Text('Returned by ${active.borrower}'),
      action: SnackBarAction(
        label: 'Photograph it',
        onPressed: () => addCopyPhoto(context, repository, copy.id,
            caption: 'Returned by ${active.borrower}'),
      ),
    ));
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
                      onPressed: () => _return(context, active),
                      child: const Text('Return'),
                    )
                  : TextButton(
                      onPressed: () => _lend(context),
                      child: const Text('Lend'),
                    ),
            ),
            CopyPhotoStrip(copyId: copy.id, repository: repository),
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
