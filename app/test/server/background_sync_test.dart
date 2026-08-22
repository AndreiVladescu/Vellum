// Background sync scheduling (plan 5 #40).
//
// The plugin call is a wrapper; the *policy* is the feature, and it is the part
// that decides whether someone's phone wakes up on mobile data at 3% battery.
// So it is pure Dart and tested here rather than only on a device.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/server/background_sync.dart';
import 'package:vellum/server/continue_widget.dart';

BackgroundSyncPolicy _policy({
  BackgroundSyncInterval interval = BackgroundSyncInterval.daily,
  bool hasServer = true,
  bool isAndroid = true,
  DateTime? lastRunAt,
}) =>
    BackgroundSyncPolicy(
      interval: interval,
      hasServer: hasServer,
      isAndroid: isAndroid,
      lastRunAt: lastRunAt,
    );

void main() {
  final now = DateTime(2026, 7, 27, 12);

  group('constraints', () {
    test('Wi-Fi and charging are required, not optional', () {
      // Syncing can mean downloading book files. Doing that on mobile data or
      // on someone's last 8% is how an app gets uninstalled — the manual sync
      // button is the escape hatch, and it has no constraints at all.
      final policy = _policy();
      expect(policy.requiresWifi, isTrue);
      expect(policy.requiresCharging, isTrue);
      expect(policy.requiresBatteryNotLow, isTrue);
    });
  });

  group('when it runs', () {
    test('off by default means never', () {
      final decision = _policy(interval: BackgroundSyncInterval.off)
          .decide(now: now);
      expect(decision.shouldRun, isFalse);
      expect(decision.skip, SkipReason.disabled);
    });

    test('never on a platform without the contract', () {
      // Silently doing nothing on desktop would look like a bug; saying which
      // platform it is makes the behaviour legible.
      final decision = _policy(isAndroid: false).decide(now: now);
      expect(decision.skip, SkipReason.notAndroid);
    });

    test('never without a server — there is nothing to sync to', () {
      final decision = _policy(hasServer: false).decide(now: now);
      expect(decision.skip, SkipReason.noServer);
    });

    test('the first run is always due', () {
      expect(_policy(lastRunAt: null).decide(now: now).shouldRun, isTrue);
    });

    test('due exactly at the interval, not a moment before', () {
      bool dueAfter(Duration ago) =>
          _policy(lastRunAt: now.subtract(ago)).decide(now: now).shouldRun;
      expect(dueAfter(const Duration(hours: 23, minutes: 59)), isFalse);
      expect(dueAfter(const Duration(days: 1)), isTrue);
      expect(dueAfter(const Duration(days: 3)), isTrue);
    });

    test('a six-hourly schedule is due six hours later', () {
      final policy = _policy(
        interval: BackgroundSyncInterval.everySixHours,
        lastRunAt: now.subtract(const Duration(hours: 6)),
      );
      expect(policy.decide(now: now).shouldRun, isTrue);

      final tooSoon = _policy(
        interval: BackgroundSyncInterval.everySixHours,
        lastRunAt: now.subtract(const Duration(hours: 5)),
      );
      expect(tooSoon.decide(now: now).skip, SkipReason.notDue);
    });

    test('a clock that moved backwards does not stall the schedule forever',
        () {
      // A timezone change or an NTP correction can put `lastRunAt` in the
      // future. One extra sync costs nothing; a schedule that never fires again
      // means a library that silently stops updating.
      final policy = _policy(lastRunAt: now.add(const Duration(days: 2)));
      expect(policy.decide(now: now).shouldRun, isTrue);
    });
  });

  group('backoff', () {
    test('no failures means no wait', () {
      expect(BackgroundSyncPolicy.backoffAfter(0), Duration.zero);
      expect(BackgroundSyncPolicy.backoffAfter(-1), Duration.zero);
    });

    test('doubles from half an hour', () {
      expect(BackgroundSyncPolicy.backoffAfter(1), const Duration(minutes: 30));
      expect(BackgroundSyncPolicy.backoffAfter(2), const Duration(hours: 1));
      expect(BackgroundSyncPolicy.backoffAfter(3), const Duration(hours: 2));
      expect(BackgroundSyncPolicy.backoffAfter(4), const Duration(hours: 4));
    });

    test('caps, so a week offline does not owe four days of waiting', () {
      expect(BackgroundSyncPolicy.backoffAfter(5), const Duration(hours: 6));
      expect(BackgroundSyncPolicy.backoffAfter(50), const Duration(hours: 6));
      // And no overflow at absurd counts, which is what the shift clamp is for.
      expect(BackgroundSyncPolicy.backoffAfter(1000), const Duration(hours: 6));
    });
  });

  group('intervals', () {
    test('parse falls back to off for anything unknown', () {
      expect(BackgroundSyncInterval.parse('daily'), BackgroundSyncInterval.daily);
      expect(
        BackgroundSyncInterval.parse('everySixHours'),
        BackgroundSyncInterval.everySixHours,
      );
      expect(BackgroundSyncInterval.parse(null), BackgroundSyncInterval.off);
      expect(BackgroundSyncInterval.parse('hourly'), BackgroundSyncInterval.off);
    });

    test('every period clears WorkManager\'s 15-minute floor', () {
      for (final interval in BackgroundSyncInterval.values) {
        final period = interval.period;
        if (period == null) continue;
        expect(period, greaterThanOrEqualTo(const Duration(minutes: 15)));
      }
    });
  });

  group('the widget snapshot', () {
    Book book({double? progress, int? page, DateTime? lastRead}) => Book(
          id: 'b1',
          title: 'Dune',
          readingProgress: progress,
          lastReadPage: page,
          lastReadAt: lastRead,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          needsPush: false, syncExcluded: false,
          readerNotesNeedsPush: false,
      statusNeedsPush: false,
          needsProgressPush: false,
          status: 'unread',
          readCount: 0,
        );

    test('shows the title and how far in you are', () {
      final data = snapshotFor(book(progress: 0.42, page: 214));
      expect(data.title, 'Dune');
      expect(data.subtitle, '42% · page 214');
      expect(data.isEmpty, isFalse);
    });

    test('a book with no page number still reports a percentage', () {
      expect(snapshotFor(book(progress: 0.42)).subtitle, '42%');
    });

    test('nothing on the go is an empty state, not a stale book', () {
      // A widget that kept showing a book you finished last month is worse than
      // one that admits there's nothing to continue.
      expect(snapshotFor(null).isEmpty, isTrue);
      expect(snapshotFor(book()).isEmpty, isTrue);
      expect(snapshotFor(book(progress: 0.98)).isEmpty, isTrue,
          reason: '98% counts as finished, same as the shelf strip');
      expect(snapshotFor(book(progress: 1.0)).isEmpty, isTrue);
    });

    test('the cover path is carried through when there is one', () {
      final data = snapshotFor(book(progress: 0.1), coverPath: '/tmp/x.jpg');
      expect(data.coverPath, '/tmp/x.jpg');
      expect(snapshotFor(book(progress: 0.1)).coverPath, isNull);
    });
  });
}
