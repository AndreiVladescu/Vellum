import 'dart:async';
import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/timezone.dart' as tz;

import '../data/library_repository.dart';
import '../l10n/gen/app_localizations.dart';
import '../l10n/platform_l10n.dart';
import '../settings/app_settings.dart';

/// System notifications for loan due dates (roadmap v1.4.2).
///
/// **Approach.** The OS is asked to deliver each reminder at a fixed future
/// moment (`zonedSchedule`), so a reminder arrives even if Vellum is closed,
/// with no background job of our own. What to schedule is a pure function
/// ([LoanReminderPlanner]); the whole set is recomputed and swapped in whenever
/// the loans change and at launch ([LoanReminderService]), so adding, editing,
/// returning or deleting a loan needs no special case.
///
/// The `timezone` package is already in the lockfile (a dependency of the
/// notification plugin). Its location database and a "which zone is this
/// device in" plugin are *not* needed: every reminder is an absolute instant
/// computed from the local wall-clock time in Dart, and handed over as UTC.

/// Local time of day the reminders are delivered: late enough not to wake
/// anyone, early enough to still be useful that day.
const loanReminderHour = 9;

const loanPayloadPrefix = 'loan:';

enum LoanReminderKind { dayBefore, dueDay, overdue }

/// One notification to be scheduled.
@immutable
class PlannedReminder {
  const PlannedReminder({
    required this.id,
    required this.at,
    required this.kind,
    required this.loanId,
    required this.title,
    required this.body,
  });

  final int id;
  final DateTime at;
  final LoanReminderKind kind;
  final String loanId;
  final String title;
  final String body;

  /// What a tapped notification carries, so the app knows it is one of ours.
  String get payload => '$loanPayloadPrefix$loanId';

  @override
  bool operator ==(Object other) =>
      other is PlannedReminder &&
      other.id == id &&
      other.at == at &&
      other.kind == kind &&
      other.title == title &&
      other.body == body;

  @override
  int get hashCode => Object.hash(id, at, kind, title, body);
}

/// Decides which reminders should exist, as of "now". Pure.
class LoanReminderPlanner {
  const LoanReminderPlanner._();

  /// Android allows a few hundred pending alarms per app; a personal library
  /// never gets near this, but the cap keeps a pathological one from tripping it.
  static const maxReminders = 60;

  /// For every active loan with a due date:
  /// - a reminder the morning before it is due,
  /// - one the morning it is due,
  /// - and, once it is past due, one at the next morning — rescheduled each
  ///   time the app starts or the loans change, so a book still out keeps being
  ///   mentioned without a repeating alarm.
  /// Moments already in the past are dropped. Loans without a date, and returned
  /// ones, get nothing.
  static List<PlannedReminder> plan(
    List<LoanEntry> loans,
    L10n l10n, {
    DateTime? now,
  }) {
    final at = now ?? DateTime.now();
    final out = <PlannedReminder>[];
    for (final entry in loans) {
      final loan = entry.loan;
      final due = loan.dueAt;
      if (loan.returnedAt != null || due == null) continue;
      final dueLocal = due.toLocal();
      final dueDay = DateTime(dueLocal.year, dueLocal.month, dueLocal.day);
      final title = entry.book.title;
      final borrower = loan.borrower;

      void add(LoanReminderKind kind, DateTime when, String body) {
        if (!when.isAfter(at)) return;
        out.add(PlannedReminder(
          id: reminderId(loan.id, kind),
          at: when,
          kind: kind,
          loanId: loan.id,
          title: title,
          body: body,
        ));
      }

      add(LoanReminderKind.dayBefore, _morning(dueDay, -1),
          l10n.loanReminderTomorrow(borrower));
      add(LoanReminderKind.dueDay, _morning(dueDay, 0),
          l10n.loanReminderToday(borrower));
      final next = _nextMorning(at);
      if (DateTime(next.year, next.month, next.day).isAfter(dueDay)) {
        add(LoanReminderKind.overdue, next, l10n.loanReminderOverdue(borrower));
      }
    }
    out.sort((a, b) => a.at.compareTo(b.at));
    return out.length > maxReminders ? out.sublist(0, maxReminders) : out;
  }

  /// A stable id per loan and kind, so rescheduling replaces rather than
  /// duplicates. FNV-1a over the loan id, folded into 29 bits to leave room for
  /// the kind and stay a positive 32-bit int (what Android notification ids are).
  static int reminderId(String loanId, LoanReminderKind kind) {
    var hash = 0x811c9dc5;
    for (final unit in loanId.codeUnits) {
      hash = ((hash ^ unit) * 0x01000193) & 0xffffffff;
    }
    return ((hash & 0x1fffffff) << 2) | kind.index;
  }

  static DateTime _morning(DateTime day, int offsetDays) =>
      DateTime(day.year, day.month, day.day + offsetDays, loanReminderHour);

  static DateTime _nextMorning(DateTime now) {
    final today = DateTime(now.year, now.month, now.day, loanReminderHour);
    return today.isAfter(now)
        ? today
        : DateTime(now.year, now.month, now.day + 1, loanReminderHour);
  }
}

/// The part that touches the OS, behind an interface so tests use a fake.
abstract class ReminderNotifier {
  /// False where scheduling isn't offered (everything but Android); callers
  /// then do nothing, quietly.
  bool get supported;

  /// Asks for the runtime notification permission (Android 13+).
  Future<bool> requestPermission();

  /// Makes the set of scheduled loan reminders exactly [reminders].
  Future<void> replaceAll(List<PlannedReminder> reminders);
}

/// Tapped loan notifications, as loan ids. The app listens and opens the loans
/// list. A stream rather than a callback so the plugin's global handler needs
/// no reference to the widget tree.
class LoanReminderTaps {
  LoanReminderTaps._();
  static final _controller = StreamController<String>.broadcast();
  static Stream<String> get stream => _controller.stream;

  /// The plugin's tap handler. Passed to every `initialize` call in the app,
  /// because the plugin is a singleton and the last initializer's handler wins.
  static void handle(NotificationResponse response) {
    final payload = response.payload;
    if (payload != null && payload.startsWith(loanPayloadPrefix)) {
      _controller.add(payload.substring(loanPayloadPrefix.length));
    }
  }
}

/// [ReminderNotifier] on top of flutter_local_notifications. Android only:
/// the Linux/Windows backends can't schedule, and a desktop window is on screen
/// anyway.
class LocalReminderNotifier implements ReminderNotifier {
  LocalReminderNotifier({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;
  late final L10n _l10n = platformL10n();
  bool _ready = false;

  static const channelId = 'vellum.loans';

  @override
  bool get supported => !kIsWeb && Platform.isAndroid;

  Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
      onDidReceiveNotificationResponse: LoanReminderTaps.handle,
    );
    _ready = true;
  }

  /// If the app was started by tapping a reminder, true.
  Future<bool> launchedByReminder() async {
    if (!supported) return false;
    await _init();
    final details = await _plugin.getNotificationAppLaunchDetails();
    final payload = details?.notificationResponse?.payload;
    return details?.didNotificationLaunchApp == true &&
        payload != null &&
        payload.startsWith(loanPayloadPrefix);
  }

  @override
  Future<bool> requestPermission() async {
    if (!supported) return false;
    await _init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    return await android?.requestNotificationsPermission() ?? false;
  }

  @override
  Future<void> replaceAll(List<PlannedReminder> reminders) async {
    if (!supported) return;
    await _init();
    // Only ours: other pending notifications are left alone.
    for (final pending in await _plugin.pendingNotificationRequests()) {
      if (pending.payload?.startsWith(loanPayloadPrefix) ?? false) {
        await _plugin.cancel(id: pending.id);
      }
    }
    for (final r in reminders) {
      await _plugin.zonedSchedule(
        id: r.id,
        title: r.title,
        body: r.body,
        payload: r.payload,
        // The instant is what matters; UTC avoids needing a device-zone lookup.
        scheduledDate: tz.TZDateTime.from(r.at, tz.UTC),
        notificationDetails: NotificationDetails(
          android: AndroidNotificationDetails(
            channelId,
            _l10n.loanReminderChannelName,
            channelDescription: _l10n.loanReminderChannelDescription,
          ),
        ),
        // Inexact: a reminder a few minutes late is fine, and the exact-alarm
        // permission is something the user has to grant by hand on new Android.
        androidScheduleMode: AndroidScheduleMode.inexactAllowWhileIdle,
      );
    }
  }
}

/// Keeps the scheduled reminders in step with the loans and the preference.
class LoanReminderService {
  LoanReminderService({
    required this.loans,
    required this.settings,
    required this.notifier,
    L10n? l10n,
    DateTime Function()? clock,
  })  : _l10nOverride = l10n,
        _clock = clock ?? DateTime.now;

  final Stream<List<LoanEntry>> loans;
  final AppSettingsStore settings;
  final ReminderNotifier notifier;
  final L10n? _l10nOverride;
  final DateTime Function() _clock;

  StreamSubscription<List<LoanEntry>>? _sub;
  List<LoanEntry> _latest = const [];
  List<PlannedReminder>? _applied;
  Future<void> _chain = Future.value();

  void start() {
    if (!notifier.supported) return;
    _sub = loans.listen((entries) {
      _latest = entries;
      refresh();
    });
    settings.addListener(refresh);
  }

  void dispose() {
    _sub?.cancel();
    settings.removeListener(refresh);
  }

  /// Recomputes and applies the schedule. Calls queue, so two quick changes
  /// can't interleave their cancel-and-reschedule. A failed schedule is
  /// swallowed: it must never break the app.
  Future<void> refresh() => _chain =
      _chain.then((_) => _apply()).catchError((Object _) {});

  Future<void> _apply() async {
    final wanted = settings.loanReminders
        ? LoanReminderPlanner.plan(_latest, _l10nOverride ?? platformL10n(),
            now: _clock())
        : const <PlannedReminder>[];
    if (listEquals(wanted, _applied)) return;
    await notifier.replaceAll(wanted);
    _applied = wanted;
  }
}
