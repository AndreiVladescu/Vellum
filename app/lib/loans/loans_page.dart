import 'package:flutter/material.dart';

import '../data/library_repository.dart';

/// Cross-library view of physical loans: what's lent out right now (with a
/// Return action), and a collapsed history of past loans. Loan data lives
/// per-copy on the detail page; this is the "who has my books?" overview.
class LoansPage extends StatelessWidget {
  const LoansPage({super.key, required this.repository});

  final LibraryRepository repository;

  static String _date(DateTime d) =>
      '${d.year}-${d.month.toString().padLeft(2, '0')}-'
      '${d.day.toString().padLeft(2, '0')}';

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Scaffold(
      appBar: AppBar(title: const Text('Loans')),
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
                  Text('No loans yet', style: theme.textTheme.titleMedium),
                  const SizedBox(height: 6),
                  Text(
                    'Lend a physical copy from its book page to track it here.',
                    textAlign: TextAlign.center,
                    style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () => Navigator.of(context).pop(),
                    icon: const Icon(Icons.shelves),
                    label: const Text('Go to your shelf'),
                  ),
                ],
              ),
            );
          }

          return ListView(
            children: [
              _SectionHeader('Out now (${active.length})'),
              if (active.isEmpty)
                const Padding(
                  padding: EdgeInsets.fromLTRB(16, 4, 16, 12),
                  child: Text('Nothing is lent out.'),
                )
              else
                for (final e in active)
                  ListTile(
                    leading: const Icon(Icons.book_outlined),
                    title: Text(e.book.title),
                    subtitle: Text(
                        '${e.loan.borrower} · since ${_date(e.loan.loanedAt)}'),
                    trailing: TextButton(
                      onPressed: () => repository.returnLoan(e.loan.id),
                      child: const Text('Return'),
                    ),
                  ),
              if (returned.isNotEmpty)
                ExpansionTile(
                  title: Text('History (${returned.length})'),
                  childrenPadding: EdgeInsets.zero,
                  children: [
                    for (final e in returned)
                      ListTile(
                        dense: true,
                        leading: const Icon(Icons.history),
                        title: Text(e.book.title),
                        subtitle: Text(
                          '${e.loan.borrower} · ${_date(e.loan.loanedAt)} → '
                          '${_date(e.loan.returnedAt!)}',
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
