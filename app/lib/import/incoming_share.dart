import 'dart:async';

import 'package:flutter/services.dart';

/// Books opened or shared into Vellum from another app (plan 5 #20).
///
/// The Android side (`MainActivity.kt`) has already copied each `content://`
/// stream into the app's cache and hands over plain file paths — a content URI is
/// only readable while the granting intent lives, so resolving it later is a race
/// the user eventually loses.
///
/// Two arrival shapes, both of which have to work:
/// - **cold start**, where the share *is* what launched the app: the paths are
///   waiting and [takeInitialFiles] collects them once.
/// - **warm resume**, where Vellum is already running: they arrive on [files].
///
/// A no-op on platforms with no such host (desktop): [takeInitialFiles] returns
/// empty and [files] never emits, so callers need no platform checks.
/// What a launcher long-press asked for (plan 5 #40).
///
/// A closed set parsed from the string the Android side sends: an unknown value
/// opens the app normally rather than throwing, because a shortcut from an
/// older install of the app is a real thing that happens.
enum LauncherShortcut {
  scan,
  continueReading,
  add;

  static LauncherShortcut? parse(String? raw) => switch (raw) {
        'scan' => LauncherShortcut.scan,
        'continue' => LauncherShortcut.continueReading,
        'add' => LauncherShortcut.add,
        _ => null,
      };
}

class IncomingShare {
  IncomingShare({MethodChannel? channel})
      : _channel = channel ?? const MethodChannel(channelName) {
    _channel.setMethodCallHandler((call) async {
      if (call.method == 'onShortcut') {
        final raw = call.arguments?.toString();
        final shortcut = LauncherShortcut.parse(raw);
        if (shortcut != null) _shortcuts.add(shortcut);
        return null;
      }
      if (call.method == 'onFiles') {
        final paths = [
          for (final path in (call.arguments as List? ?? const []))
            path.toString(),
        ];
        if (paths.isNotEmpty) _controller.add(paths);
      }
      return null;
    });
  }

  static const channelName = 'com.avladescu.vellum/incoming_share';

  final MethodChannel _channel;
  final _controller = StreamController<List<String>>.broadcast();

  /// Files shared while the app was already running.
  Stream<List<String>> get files => _controller.stream;

  final _shortcuts = StreamController<LauncherShortcut>.broadcast();

  /// Launcher shortcuts tapped while the app was already running (plan 5 #40).
  Stream<LauncherShortcut> get shortcuts => _shortcuts.stream;

  /// The shortcut that launched this run, if any. Consumed once, like
  /// [takeInitialFiles] — a hot restart must not re-trigger it.
  Future<LauncherShortcut?> takeInitialShortcut() async {
    try {
      final raw = await _channel.invokeMethod<String>('takeShortcut');
      return LauncherShortcut.parse(raw);
    } on MissingPluginException {
      return null; // desktop, or a host build without the handler
    } catch (_) {
      return null;
    }
  }

  /// The files that launched this run, if any. Consumed once — the host clears
  /// them, so a hot restart doesn't re-import the same share.
  Future<List<String>> takeInitialFiles() async {
    try {
      final result = await _channel.invokeMethod<List<Object?>>(
        'takeInitialFiles',
      );
      return [for (final path in result ?? const []) path.toString()];
    } on MissingPluginException {
      // Desktop, or an older host build: nothing shares into Vellum here.
      return const [];
    } catch (_) {
      // A malformed reply is not worth failing a launch over.
      return const [];
    }
  }

  Future<void> dispose() async {
    await _shortcuts.close();
    _channel.setMethodCallHandler(null);
    await _controller.close();
  }
}
