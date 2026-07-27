/// Background sync on Android (plan 5 #40).
///
/// **The policy is the feature.** The scheduling rules — how often, under what
/// conditions, and when to give up — are pure Dart in [BackgroundSyncPolicy] so
/// they can be tested; the plugin call that hands them to WorkManager is a thin
/// wrapper around that decision. A background job whose *policy* is only
/// exercised on a device is one nobody can reason about.
///
/// Every default here is battery-conscious and the whole thing is **off unless
/// asked for**: a local-first app already works without it, so the only thing
/// background sync can do to a user who didn't want it is drain their phone.
library;

import 'dart:io';

import 'package:workmanager/workmanager.dart';

import '../data/database.dart';
import '../data/library_repository.dart';
import '../settings/app_settings.dart';
import 'connection_store.dart';
import 'sync_service.dart';

/// How often background sync runs, when it runs at all.
enum BackgroundSyncInterval {
  off('Off', null),
  everySixHours('Every 6 hours', Duration(hours: 6)),
  daily('Daily', Duration(days: 1));

  const BackgroundSyncInterval(this.label, this.period);

  final String label;

  /// Null for [off]. WorkManager's own floor is 15 minutes; nothing here comes
  /// close, deliberately — a library changes on the scale of days.
  final Duration? period;

  String get key => name;

  static BackgroundSyncInterval parse(String? raw) => values.firstWhere(
        (i) => i.key == raw,
        orElse: () => BackgroundSyncInterval.off,
      );
}

/// Why a scheduled run was skipped, so the decision can be asserted and — when
/// it matters — explained.
enum SkipReason {
  disabled,
  notAndroid,
  noServer,
  notDue,
}

/// The outcome of asking "should this run now?".
class SyncDecision {
  const SyncDecision.run() : skip = null;
  const SyncDecision.skip(this.skip);

  final SkipReason? skip;

  bool get shouldRun => skip == null;
}

/// The rules, with no plugin and no platform channel in sight.
class BackgroundSyncPolicy {
  const BackgroundSyncPolicy({
    required this.interval,
    required this.hasServer,
    required this.isAndroid,
    this.lastRunAt,
  });

  final BackgroundSyncInterval interval;

  /// Whether a server is configured at all. Without one there is nothing to
  /// sync *to*, and waking a phone to discover that is pure waste.
  final bool hasServer;

  /// iOS has no equivalent contract and desktop is always running; this is an
  /// Android feature and says so rather than silently doing nothing elsewhere.
  final bool isAndroid;

  final DateTime? lastRunAt;

  /// Constraints handed to WorkManager.
  ///
  /// **Wi-Fi and charging**, both required, both non-negotiable defaults rather
  /// than options: syncing a library can mean downloading book files, and doing
  /// that on someone's mobile data or on their last 8% of battery is the kind
  /// of thing that gets an app uninstalled. Someone who wants it *now* has the
  /// manual sync button, which has no constraints at all.
  bool get requiresWifi => true;
  bool get requiresCharging => true;

  /// Battery-not-low is implied by charging, but stated so a future change to
  /// the charging rule doesn't silently drop it too.
  bool get requiresBatteryNotLow => true;

  SyncDecision decide({DateTime? now}) {
    if (!isAndroid) return const SyncDecision.skip(SkipReason.notAndroid);
    final period = interval.period;
    if (period == null) return const SyncDecision.skip(SkipReason.disabled);
    if (!hasServer) return const SyncDecision.skip(SkipReason.noServer);

    final last = lastRunAt;
    if (last == null) return const SyncDecision.run();
    final elapsed = (now ?? DateTime.now()).difference(last);
    // A clock that moved backwards (timezone change, NTP correction) reads as a
    // negative elapsed time. Treat that as "due" rather than "never again" —
    // the cost of one extra sync is nothing; the cost of a stuck schedule is a
    // library that silently stops updating.
    if (elapsed.isNegative) return const SyncDecision.run();
    return elapsed >= period
        ? const SyncDecision.run()
        : const SyncDecision.skip(SkipReason.notDue);
  }

  /// Backoff after a failed run.
  ///
  /// Doubling from 30 minutes, capped at 6 hours. Capped because a phone that
  /// was offline for a week must not come back with a 4-day backoff still to
  /// wait out; started at 30 minutes because the overwhelmingly likely cause is
  /// "not on the home Wi-Fi right now", which fixes itself.
  static Duration backoffAfter(int consecutiveFailures) {
    if (consecutiveFailures <= 0) return Duration.zero;
    const base = Duration(minutes: 30);
    const cap = Duration(hours: 6);
    final doubled = base * (1 << (consecutiveFailures - 1).clamp(0, 10));
    return doubled > cap ? cap : doubled;
  }
}

/// The entry point WorkManager calls in a **background isolate**.
///
/// `vm:entry-point` keeps it alive through tree-shaking in release builds —
/// without it the release APK schedules a task whose callback has been compiled
/// away, and the failure is invisible until someone's phone quietly stops
/// syncing.
///
/// The isolate has none of the app's state: it opens its own database handle,
/// its own settings and its own connection, does one sync, and exits. That is
/// why the work here is deliberately small — a delta pull and a push, not the
/// cover backfill or the reading-position pass, both of which can wait for a
/// foreground launch.
///
/// It returns `true` even when there was nothing to do, and `false` only on a
/// real failure, because `false` is what tells WorkManager to back off.
@pragma('vm:entry-point')
void backgroundSyncCallback() {
  Workmanager().executeTask((task, inputData) async {
    if (task != backgroundSyncTaskName) return true;
    try {
      final settings = await AppSettingsStore.load();
      final connection = await ServerConnection.load();
      final client = connection.client;
      // No server, or signed out since the task was scheduled: nothing to do,
      // and reporting failure would start a pointless backoff.
      if (client == null) return true;

      final repository = await LibraryRepository.open(VellumDatabase());
      try {
        await SyncService(repository).sync(
          client,
          cursor: connection.syncCursor,
          onCursor: connection.setSyncCursor,
        );
        await settings.setLastBackgroundSyncAt(DateTime.now());
        return true;
      } finally {
        // Always closed: a background isolate that leaves the database open
        // holds a lock the foreground app will trip over.
        await repository.db.close();
      }
    } catch (_) {
      // Offline, or a server that has gone away. `false` asks WorkManager for
      // the exponential backoff registered with the task.
      return false;
    }
  });
}

/// The WorkManager task name. One task, one name — re-registering under the
/// same one replaces the schedule rather than stacking a second copy of it.
const backgroundSyncTaskName = 'vellum.background-sync';

/// Hands the current policy to WorkManager, or cancels the schedule when the
/// setting is off.
///
/// Idempotent and safe to call on every launch: `ExistingPeriodicWorkPolicy`
/// replaces the registration, so changing the interval in Preferences takes
/// effect without leaving the old schedule behind.
///
/// A no-op off Android — the plugin's other platforms have different contracts
/// (iOS gives no guarantees at all), and pretending otherwise would be worse
/// than saying so in the settings screen.
Future<void> applySchedule(BackgroundSyncPolicy policy) async {
  if (!policy.isAndroid) return;
  try {
    // Registered before scheduling: the plugin needs the entry point on hand
    // before it can hand work to it.
    await Workmanager().initialize(backgroundSyncCallback);
    final period = policy.interval.period;
    if (period == null) {
      await Workmanager().cancelByUniqueName(backgroundSyncTaskName);
      return;
    }
    await Workmanager().registerPeriodicTask(
      backgroundSyncTaskName,
      backgroundSyncTaskName,
      frequency: period,
      // Constraints, not preferences: see the doc comments on `requiresWifi`.
      constraints: Constraints(
        networkType: NetworkType.unmetered,
        requiresCharging: policy.requiresCharging,
        requiresBatteryNotLow: policy.requiresBatteryNotLow,
      ),
      existingWorkPolicy: ExistingPeriodicWorkPolicy.update,
      backoffPolicy: BackoffPolicy.exponential,
      backoffPolicyDelay: BackgroundSyncPolicy.backoffAfter(1),
    );
  } catch (_) {
    // A phone with no WorkManager, or a plugin that failed to register: the
    // app still syncs at launch, which is what it did before this feature.
  }
}

/// Reads the policy out of settings.
BackgroundSyncPolicy policyFrom(
  AppSettingsStore settings, {
  required bool hasServer,
  bool? isAndroid,
}) =>
    BackgroundSyncPolicy(
      interval: BackgroundSyncInterval.parse(settings.backgroundSyncInterval),
      hasServer: hasServer,
      isAndroid: isAndroid ?? Platform.isAndroid,
      lastRunAt: settings.lastBackgroundSyncAt,
    );
