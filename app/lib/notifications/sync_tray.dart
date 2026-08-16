import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// The body line under a sync's progress notification, e.g. "Pushing books —
/// 12 of 40". Pure so the wording is testable without a device.
///
/// [total] of 0 means the phase hasn't reported a count yet (the very start,
/// or a phase like "Checking for changes" that has nothing to count) — shown
/// as just the phase name, since "0 of 0" would look like nothing is
/// happening rather than like something with no number to give.
String syncProgressBody(int done, int total, String phase) =>
    total <= 0 ? phase : '$phase — $done of $total';

/// A status-bar notification with a progress bar, live for one sync.
///
/// **Android only.** Desktop has a window you can see the same progress in;
/// a notification there would be a second copy of it. Paired with
/// [SyncForegroundService] (Kotlin) via the same channel and notification id,
/// so the placeholder that anchors the foreground service is replaced by
/// this class's first real update rather than sitting next to it as a
/// second notification.
class SyncNotificationTray {
  SyncNotificationTray({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// Must match `SyncForegroundService.CHANNEL_ID` / `NOTIFICATION_ID`.
  static const _channelId = 'vellum.sync';
  static const _channelName = 'Syncing';
  static const _channelDescription =
      'Progress while your library syncs with the server';
  static const _notificationId = 2;

  bool _ready = false;

  Future<void> _init() async {
    if (_ready) return;
    await _plugin.initialize(
      settings: const InitializationSettings(
        android: AndroidInitializationSettings('@mipmap/ic_launcher'),
      ),
    );
    _ready = true;
  }

  /// The initial, indeterminate notification — shown before the first phase
  /// has anything to count.
  Future<void> start() async {
    if (!Platform.isAndroid) return;
    await _init();
    await _plugin.show(
      id: _notificationId,
      title: 'Vellum',
      body: 'Starting sync…',
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          onlyAlertOnce: true,
          showProgress: true,
          indeterminate: true,
        ),
      ),
    );
  }

  /// One update per phase change is plenty — [onlyAlertOnce] keeps a
  /// per-book progress tick from re-alerting on every call, and the system
  /// already throttles identical rapid updates on its own.
  Future<void> update(int done, int total, String phase) async {
    if (!Platform.isAndroid) return;
    await _init();
    await _plugin.show(
      id: _notificationId,
      title: 'Vellum',
      body: syncProgressBody(done, total, phase),
      notificationDetails: NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.low,
          priority: Priority.low,
          ongoing: true,
          onlyAlertOnce: true,
          showProgress: true,
          indeterminate: total <= 0,
          maxProgress: total > 0 ? total : 0,
          progress: total > 0 ? done : 0,
        ),
      ),
    );
  }

  /// Replaces the progress notification with a plain, dismissible result —
  /// not `ongoing`, so it behaves like any other notification once the
  /// service backing it has already stopped.
  Future<void> finish(String message) async {
    if (!Platform.isAndroid) return;
    await _init();
    await _plugin.show(
      id: _notificationId,
      title: 'Vellum',
      body: message,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.low,
          priority: Priority.low,
        ),
      ),
    );
  }

  /// Takes the notification away outright, for a sync that failed before it
  /// had anything worth reporting.
  Future<void> clear() async {
    if (!Platform.isAndroid) return;
    await _init();
    await _plugin.cancel(id: _notificationId);
  }
}
