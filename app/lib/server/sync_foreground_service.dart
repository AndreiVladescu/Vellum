/// Keeps a manual sync's network access alive if the app is backgrounded
/// mid-sync, by anchoring it to a real Android foreground service.
///
/// **Why this exists.** Backgrounding an app on Android suspends its network
/// fairly promptly; a sync request in flight when that happens dies with a
/// DNS lookup failure rather than pausing and resuming. A foreground service
/// is the OS's own "this process is doing something the user asked for and
/// cares about" signal, and is exempt. `SyncForegroundService.kt` does none
/// of the sync work itself — it only exists, with a visible notification, for
/// exactly as long as this class tells it to.
///
/// **Android only, and only for the duration of one sync.** [start] and
/// [stop] must be paired — `try`/`finally` around the sync, like a lock —
/// since a service left running after its sync finished would be a phone
/// stuck reporting it is syncing forever. Everywhere else this is a no-op:
/// desktop isn't backgrounded the same way, and there's no service to start.
library;

import 'dart:io';

import 'package:flutter/services.dart';

class SyncForegroundService {
  static const _channel = MethodChannel('app.vellum.Vellum/sync_service');

  /// Starts the foreground service. Swallows failures — a phone without the
  /// permission granted, or a manufacturer that restricts foreground services
  /// further, should still let the sync attempt run rather than block it on
  /// something that is purely a resilience improvement.
  static Future<void> start() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('start');
    } catch (_) {}
  }

  static Future<void> stop() async {
    if (!Platform.isAndroid) return;
    try {
      await _channel.invokeMethod('stop');
    } catch (_) {}
  }
}
