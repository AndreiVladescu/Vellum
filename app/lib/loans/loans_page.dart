import 'package:flutter/material.dart';
import '../widgets/page_insets.dart';
import 'package:flutter/services.dart';

import '../data/library_repository.dart';
import '../l10n/gen/app_localizations.dart';
import '../server/connection_store.dart';
import 'borrow_requests.dart';
import 'due_dates.dart';

/// Cross-library view of physical loans: what's lent out right now (with a
/// Return action), and a collapsed history of past loans. Loan data lives
/// per-copy on the detail page; this is the "who has my books?" overview.
class LoansPage extends StatelessWidget {
  const LoansPage({super.key, required this.repository, this.connection});

  final LibraryRepository repository;

  /// Needed only for borrow requests (plan 5 #49); the action is hidden
  /// without a connection or against a server that doesn't offer them.
  final ServerConnection? connection;

  bool get _requestsAvailable =>
      connection != null &&
      connection!.isConnected &&
      (connection!.capabilities?.hasFeature('borrow_requests') ?? false);


  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.loansTitle),
        actions: [
          if (_requestsAvailable)
            IconButton(
              tooltip: l10n.borrowTitle,
              icon: const Icon(Icons.pan_tool_alt_outlined),
              onPressed: () => Navigator.of(context).push(
                MaterialPageRoute<void>(
                  builder: (_) =>
                      BorrowRequestsPage(connection: connection!),
                ),
              ),
            ),
        ],
      ),
      body: StreamBuilder<List<LoanEntry>>(
        stream: repository.watchAllLoans(),
        builder: (context, snapshot) {
          final all = snapshot.data ?? const [];
          final active = [for (final e in all) if (e.loan.returnedAt == null) e];
          final returned =
              [for (final e in all) if (e.loan.returnedAt != null) e];

          if (all.isEmpty) {
            return Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.swap_horiz,
                      size: 56,
                      color: theme.colorScheme.primary.withValues(alpha: 0.7)),
                  const SizedBox(height: 16),
                  Text(l10n.loansEmptyTitle,
                      style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    l10n.loansEmptyBody,
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.shelves),
                    label: Text(l10n.loansGoToShelf),
                  ),
                ],
              ),
            );
          }

          return ListView(
            padding: pageInsets(context, EdgeInsets.zero),
            children: [
              _SectionHeader(l10n.loansOutNow(active.length)),
              if (active.isEmpty)
                Padding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text(l10n.loansNothingLent),
                )
              else
                // Most urgent first (plan 5 #27): overdue, then by due date,
                // with undated loans last — nothing is expected of them.
                for (final e in _byUrgency(active))
                  _ActiveLoanTile(entry: e, repository: repository),
              if (returned.isNotEmpty)
                ExpansionTile(
                  title: Text(l10n.loansHistory(returned.length)),
                  childrenPadding: EdgeInsets.zero,
                  children: [
                    for (final e in returned)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.history),
                        title: Text(e.book.title),
                        subtitle: Text(
                          l10n.loansHistoryLine(
                            e.loan.borrower,
                            _date(e.loan.loanedAt),
                            _date(e.loan.returnedAt!),
                          ),
                        ),
                      ),
                  ],
                ),
            ],
          );
        },
      ),
    );
  }
}

/// `YYYY-MM-DD`, shared by the page and its tiles.
String _date(DateTime d) =>
    '${d.year}-${d.month.toString().padLeft(2, '0')}-'
    '${d.day.toString().padLeft(2, '0')}';

/// Active loans ordered by how much they need attention.
List<LoanEntry> _byUrgency(List<LoanEntry> entries) {
  final ordered = LoanDue.sortByUrgency([for (final e in entries) e.loan]);
  final byId = {for (final e in entries) e.loan.id: e};
  return [for (final loan in ordered) byId[loan.id]!];
}

/// One lent-out book, badged with how overdue it is and offering the nudge.
class _ActiveLoanTile extends StatelessWidget {
  const _ActiveLoanTile({required this.entry, required this.repository});

  final LoanEntry entry;
  final LibraryRepository repository;

  Future<void> _nudge(BuildContext context) async {
    final l10n = L10n.of(context);
    final message =
        LoanDue.reminderMessage(l10n, entry.loan, entry.book.title);
    await Clipboard.setData(ClipboardData(text: message));
    // Copying rather than sending: Vellum has no idea which app you'd message
    // this person in, and a half-integrated share sheet that fails on desktop
    // is worse than text on the clipboard that works everywhere.
    await repository.markReminderSent(entry.loan.id);
    if (!context.mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(l10n.loansReminderCopied)),
    );
  }

  Future<void> _editDue(BuildContext context) async {
    final now = DateTime.now();
    final picked = await showDatePicker(
      context: context,
      initialDate: entry.loan.dueAt ?? now.add(const Duration(days: 14)),
      firstDate: now.subtract(const Duration(days: 365)),
      lastDate: now.add(const Duration(days: 365 * 5)),
    );
    if (picked == null) return;
    await repository.updateLoan(
      entry.loan.id,
      dueAt: picked,
      contact: entry.loan.borrowerContact,
      notes: entry.loan.notes,
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = L10n.of(context);
    final urgency = LoanDue.urgencyOf(entry.loan);
    final colour = switch (urgency) {
      LoanUrgency.overdue => theme.colorScheme.error,
      LoanUrgency.dueToday => theme.colorScheme.tertiary,
      _ => theme.colorScheme.onSurfaceVariant,
    };
    return ListTile(
      leading: Icon(
        urgency == LoanUrgency.overdue
            ? Icons.error_outline
            : Icons.book_outlined,
        color: urgency.needsAttention ? colour : null,
      ),
      title: Text(entry.book.title),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(entry.loan.borrowerContact == null
              ? l10n.loansSince(entry.loan.borrower, _date(entry.loan.loanedAt))
              : l10n.loansSinceWithContact(
                  entry.loan.borrower,
                  entry.loan.borrowerContact!,
                  _date(entry.loan.loanedAt),
                )),
          Text(
            LoanDue.describe(l10n, entry.loan),
            style: theme.textTheme.bodySmall?.copyWith(
              color: colour,
              fontWeight:
                  urgency.needsAttention ? FontWeight.bold : FontWeight.normal,
            ),
          ),
        ],
      ),
      isThreeLine: true,
      trailing: PopupMenuButton<String>(
        onSelected: (choice) async {
          switch (choice) {
            case 'return':
              await repository.returnLoan(entry.loan.id);
            case 'nudge':
              await _nudge(context);
            case 'due':
              await _editDue(context);
          }
        },
        itemBuilder: (context) => [
          PopupMenuItem(value: 'return', child: Text(l10n.loansMenuReturned)),
          PopupMenuItem(value: 'nudge', child: Text(l10n.loansMenuReminder)),
          PopupMenuItem(value: 'due', child: Text(l10n.loansMenuChangeDue)),
        ],
      ),
    );
  }
}

class _SectionHeader extends StatelessWidget {
  const _SectionHeader(this.title);

  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Padding(
      padding: const EdgeInsets.fromLTRB(16, 16, 16, 4),
      child: Text(title,
          style: theme.textTheme.titleSmall
              ?.copyWith(color: theme.colorScheme.primary)),
    );
  }
}
