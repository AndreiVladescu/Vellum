// Reading insights and the month page at the size a heavy reader's history
// reaches — see docs/PERFORMANCE.md (2026-11 round). Both are computed in Dart
// over every sitting, on the UI isolate, so their cost is a frame's cost.
//
// Like library_bench.dart: printed timings for reading, generous budgets as a
// regression guard (an accidental O(n²) fails; a slow CI runner does not).
import 'dart:math';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/stats/insights_range.dart';
import 'package:vellum/stats/insights_summary.dart';
import 'package:vellum/stats/month_review.dart';

const _budgetMs = 2000;

void main() {
  final today = DateTime(2026, 11, 13, 21);
  final rng = Random(4);

  List<ReadingSession> sittings(int n) => [
        for (var i = 0; i < n; i++)
          () {
            final start = today.subtract(Duration(
              days: i ~/ 4,
              hours: rng.nextInt(12),
              minutes: rng.nextInt(60),
            ));
            final page = rng.nextInt(400);
            return ReadingSession(
              id: 's$i',
              bookId: 'b${rng.nextInt(400)}',
              startedAt: start,
              endedAt: start.add(Duration(minutes: 5 + rng.nextInt(80))),
              startPage: page,
              endPage: page + rng.nextInt(60),
              deviceLabel: ['Phone', 'Desktop', null][rng.nextInt(3)],
              needsPush: false,
            );
          }(),
      ];

  final books = [
    for (var i = 0; i < 4000; i++)
      Book(
        id: 'b$i',
        title: 'Book $i',
        createdAt: today,
        updatedAt: today,
        needsPush: false,
        syncExcluded: false,
        readerNotesNeedsPush: false,
        statusNeedsPush: false,
        statusInferred: false,
        needsProgressPush: false,
        status: i % 10 == 0 ? 'finished' : 'unread',
        finishedAt: i % 10 == 0 ? today.subtract(Duration(days: i ~/ 4)) : null,
        readCount: 0,
      ),
  ];

  for (final n in [4000, 16000]) {
    test('insights over $n sittings', () async {
      final input = InsightsInput(
        sessions: sittings(n),
        books: books,
        genresByBook: const {},
        formatsByBook: const {},
      );
      for (final range in InsightsRange.values) {
        final sw = Stopwatch()..start();
        final summary = InsightsSummary(input, range, today);
        // The getters the page reads too: streaks, best day, this week.
        summary
          ..currentStreak
          ..longestStreak
          ..best
          ..thisWeekPages
          ..lastWeekPages;
        sw.stop();
        // ignore: avoid_print
        print('  $n sittings, ${range.name}: ${sw.elapsedMilliseconds} ms');
        expect(sw.elapsedMilliseconds, lessThan(_budgetMs));
      }
      // What the page actually runs: every range, in a background isolate.
      final bg = Stopwatch()..start();
      final all = await InsightsSummary.forEveryRange(input, today);
      bg.stop();
      expect(all.length, InsightsRange.values.length);
      // ignore: avoid_print
      print('  $n sittings, every range in the background: '
          '${bg.elapsedMilliseconds} ms wall');
      expect(bg.elapsedMilliseconds, lessThan(_budgetMs * 2));

      final sw = Stopwatch()..start();
      for (var m = 0; m < 4; m++) {
        MonthReviews.review(
          sessions: input.sessions,
          books: books,
          month: MonthReviews.addMonths(MonthReviews.monthOf(today), -m),
          today: today,
          minuteGoal: 30,
        );
      }
      sw.stop();
      // ignore: avoid_print
      print('  $n sittings, 4 months reviewed: ${sw.elapsedMilliseconds} ms');
      expect(sw.elapsedMilliseconds, lessThan(_budgetMs));
    });
  }
}
