import 'dart:io';

import 'package:flutter_local_notifications/flutter_local_notifications.dart';

/// Notifications in the Android status bar.
///
/// The bell in the app bar only helps someone who has already opened the app,
/// which is exactly the person who did not need telling. This is the other
/// case: the phone in a pocket, and a request for a book sitting unanswered.
///
/// **Android only, and deliberately.** The desktop builds have a window you can
/// see; a tray notification there would be a second copy of something already
/// on screen. On iOS the plugin needs a different permission dance and Vellum
/// has no iOS build, so claiming support would be claiming something untested.
///
/// The policy — *whether* to post, and what to say — is [TrayDecision] below,
/// which is pure Dart and tested. Everything in this class is the plugin call
/// that carries out that decision, for the same reason `BackgroundSyncPolicy`
/// is split from the WorkManager call.
class NotificationTray {
  NotificationTray({FlutterLocalNotificationsPlugin? plugin})
      : _plugin = plugin ?? FlutterLocalNotificationsPlugin();

  final FlutterLocalNotificationsPlugin _plugin;

  /// One channel, named for what it is about rather than for the app — Android
  /// shows this name in the system settings, where "Vellum" would tell nobody
  /// anything about what they are turning off.
  static const _channelId = 'vellum.borrowing';
  static const _channelName = 'Borrowing';
  static const _channelDescription =
      'Requests to borrow your books, and answers to yours';

  /// Fixed id, so a second notification replaces the first rather than
  /// stacking. Someone who has been away for a week wants one line saying what
  /// is waiting, not seven.
  static const _notificationId = 1;

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

  /// Asks for permission to post, on the versions of Android that require it
  /// (13+). Returns false when refused or unavailable — the caller should then
  /// leave the preference off rather than pretending it is on.
  ///
  /// Called from the foreground, never from the background isolate: a
  /// permission prompt needs an activity to appear over.
  Future<bool> requestPermission() async {
    if (!Platform.isAndroid) return false;
    await _init();
    final android = _plugin.resolvePlatformSpecificImplementation<
        AndroidFlutterLocalNotificationsPlugin>();
    if (android == null) return false;
    return await android.requestNotificationsPermission() ?? false;
  }

  /// Posts (or replaces) the one notification.
  Future<void> show({required String title, required String body}) async {
    if (!Platform.isAndroid) return;
    await _init();
    await _plugin.show(
      id: _notificationId,
      title: title,
      body: body,
      notificationDetails: const NotificationDetails(
        android: AndroidNotificationDetails(
          _channelId,
          _channelName,
          channelDescription: _channelDescription,
          importance: Importance.defaultImportance,
          // Not `high`: this is a library, and nothing in it is urgent enough
          // to earn a heads-up banner over whatever someone is doing.
          priority: Priority.defaultPriority,
        ),
      ),
    );
  }

  /// Takes the notification away — after the list has been read, there is
  /// nothing left for it to point at.
  Future<void> clear() async {
    if (!Platform.isAndroid) return;
    await _init();
    await _plugin.cancel(id: _notificationId);
  }
}

/// Whether the background check should post anything, and what it should say.
///
/// Pure so it can be tested: the interesting cases are the ones a device makes
/// awkward to reach — nothing new since last time, the same thing seen twice,
/// the count that has to read as a sentence.
class TrayDecision {
  const TrayDecision.post(this.title, this.body) : silent = false;
  const TrayDecision.silent()
      : silent = true,
        title = '',
        body = '';

  final bool silent;
  final String title;
  final String body;

  /// [unread] is how many are waiting; [newest] the most recent one's title;
  /// [lastShownAt] and [newestAt] decide whether this is news.
  ///
  /// Nothing is posted when there is nothing unread, and nothing is posted
  /// again for something already announced — a notification that reappears
  /// every six hours for the same unanswered request is how people learn to
  /// turn notifications off.
  factory TrayDecision.forUnread({
    required int unread,
    required String? newest,
    required DateTime? newestAt,
    required DateTime? lastShownAt,
  }) {
    if (unread <= 0 || newest == null) return const TrayDecision.silent();
    if (newestAt != null &&
        lastShownAt != null &&
        !newestAt.isAfter(lastShownAt)) {
      return const TrayDecision.silent();
    }
    // The newest one as the headline, because it is the sentence the server
    // already wrote for a person; the count only when it adds something.
    final body = unread == 1 ? newest : '$newest · and ${unread - 1} more';
    return TrayDecision.post('Vellum', body);
  }
}
