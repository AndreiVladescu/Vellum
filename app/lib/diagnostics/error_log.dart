/// The last few errors, kept in memory so a bug report can include them.
///
/// Vellum had no central error handling: Flutter's default prints framework
/// errors to the console and nothing else. This adds two hooks
/// (`FlutterError.onError`, `PlatformDispatcher.onError`) that *record* and then
/// hand the error on to whatever was installed before, so the console output in
/// debug and any other handler behave exactly as they did.
///
/// **In memory only.** Nothing is written to disk and nothing is sent anywhere;
/// the log is read when someone presses "Copy diagnostics" and is gone when the
/// app closes. Messages can contain paths or titles, so they are scrubbed when
/// the report is built (see `diagnostics_report.dart`), not here.
library;

import 'package:flutter/foundation.dart';

/// One recorded error.
class LoggedError {
  const LoggedError({
    required this.time,
    required this.type,
    required this.message,
    required this.frames,
  });

  final DateTime time;
  final String type;
  final String message;

  /// The top few stack frames, as printed by the VM.
  final List<String> frames;
}

class ErrorLog {
  ErrorLog({this.capacity = 30, this.frameCount = 5});

  /// The app-wide log, fed by [install].
  static final ErrorLog instance = ErrorLog();

  final int capacity;
  final int frameCount;
  final List<LoggedError> _entries = [];

  /// Oldest first.
  List<LoggedError> get entries => List.unmodifiable(_entries);

  void record(Object error, StackTrace? stack, {DateTime? at}) {
    final lines = (stack ?? StackTrace.empty)
        .toString()
        .split('\n')
        .map((l) => l.trim())
        .where((l) => l.isNotEmpty)
        .take(frameCount)
        .toList();
    _entries.add(
      LoggedError(
        time: at ?? DateTime.now(),
        type: error.runtimeType.toString(),
        message: error.toString(),
        frames: lines,
      ),
    );
    // A ring: the oldest goes when a new one arrives past the cap.
    while (_entries.length > capacity) {
      _entries.removeAt(0);
    }
  }

  bool _installed = false;

  /// Hooks the two global handlers, chaining to whatever was there. Safe to
  /// call more than once.
  void install() {
    if (_installed) return;
    _installed = true;

    final previousFlutter = FlutterError.onError;
    FlutterError.onError = (details) {
      record(details.exception, details.stack);
      if (previousFlutter != null) {
        previousFlutter(details);
      } else {
        FlutterError.presentError(details);
      }
    };

    final previousPlatform = PlatformDispatcher.instance.onError;
    PlatformDispatcher.instance.onError = (error, stack) {
      record(error, stack);
      // Not handled here: false lets the engine report it as it always did.
      return previousPlatform?.call(error, stack) ?? false;
    };
  }
}
