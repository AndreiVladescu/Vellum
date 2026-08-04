import 'package:flutter/material.dart';

import '../data/library_repository.dart';

/// Every series you own, and what is missing from each.
///
/// Gap detection is not new — a book's own page has shown "you're missing 2"
/// since plan 5 #17. What it could not do is answer the question a reader
/// actually asks, which runs the other way: *what am I missing?* To find that
/// out you had to open a book in every series and check, which means you only
/// ever discovered a gap in a series you were already thinking about.
///
/// Series with something missing sort first, because that is the entire reason
/// to open this screen.
class SeriesPage extends StatelessWidget {
  const SeriesPage({super.key, required this.repository});

  final LibraryRepository repository;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Series')),
      body: StreamBuilder<List<SeriesPlace>>(
        stream: repository.seriesService.watchAll(),
        builder: (context, snapshot) {
          final series = snapshot.data;
          if (series == null) {
            return const Center(child: CircularProgressIndicator());
          }
          if (series.isEmpty) return const _Empty();
          return ListView.separated(
            itemCount: series.length,
            separatorBuilder: (_, _) => const Divider(height: 1),
            itemBuilder: (context, i) => _SeriesTile(
              place: series[i],
              repository: repository,
            ),
          );
        },
      ),
    );
  }
}

class _SeriesTile extends StatelessWidget {
  const _SeriesTile({required this.place, required this.repository});

  final SeriesPlace place;
  final LibraryRepository repository;

  /// `1, 2, 4` rather than `1.0, 2.0, 4.0` — a volume number is written the way
  /// it is on the spine, and a novella at 1.5 keeps its half.
  static String _volume(double v) =>
      v == v.roundToDouble() ? v.round().toString() : v.toString();

  Future<void> _wish(BuildContext context, int volume) async {
    final messenger = ScaffoldMessenger.of(context);
    await repository.wishlist.addSeriesGap(
      seriesName: place.name,
      volume: volume,
    );
    messenger.showSnackBar(SnackBar(
      content: Text('${place.name} vol. $volume added to your wishlist'),
    ));
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final owned = place.owned.map(_volume).join(', ');
    return ListTile(
      leading: Icon(
        place.hasGaps ? Icons.report_problem_outlined : Icons.check_circle_outline,
        color: place.hasGaps ? theme.colorScheme.error : null,
      ),
      title: Text(place.name),
      subtitle: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(owned.isEmpty
              ? '${place.owned.length} book(s), unnumbered'
              : 'You have $owned'),
          if (place.hasGaps)
            Padding(
              padding: const EdgeInsets.only(top: 4),
              child: Wrap(
                spacing: 6,
                runSpacing: 4,
                children: [
                  Text('Missing', style: theme.textTheme.labelMedium),
                  for (final gap in place.gaps)
                    // A gap already wished for is shown as such rather than
                    // offered again — the wishlist is the record that you have
                    // already decided about that volume.
                    if (place.wanted.contains(gap.toDouble()))
                      Chip(
                        label: Text('$gap · wanted'),
                        visualDensity: VisualDensity.compact,
                      )
                    else
                      ActionChip(
                        label: Text('$gap'),
                        avatar: const Icon(Icons.add, size: 16),
                        visualDensity: VisualDensity.compact,
                        onPressed: () => _wish(context, gap),
                      ),
                ],
              ),
            ),
        ],
      ),
      isThreeLine: place.hasGaps,
    );
  }
}

class _Empty extends StatelessWidget {
  const _Empty();

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.format_list_numbered,
                size: 56,
                color: theme.colorScheme.primary.withValues(alpha: 0.7)),
            const SizedBox(height: 16),
            Text('No series yet', style: theme.textTheme.titleMedium),
            const SizedBox(height: 6),
            Text(
              'Set a series and volume number on a book’s page, and the ones '
              'you are missing show up here.',
              textAlign: TextAlign.center,
              style: TextStyle(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
