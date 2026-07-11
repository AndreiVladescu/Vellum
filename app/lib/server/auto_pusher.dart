import 'dart:async';

import '../data/library_repository.dart';
import 'server_client.dart';
import 'sync_service.dart';

/// Pushes dirty books to the server in the background, shortly after edits
/// settle. Pulls stay launch/manual so a timer never overwrites local state;
/// this only sends what `needsPush` already tracks. Failures are swallowed —
/// the flag keeps the work queued for the next attempt or the next launch sync.
class AutoPusher {
  AutoPusher({
    required this.repository,
    required this.sync,
    required this.client,
    required this.enabled,
    this.debounce = const Duration(seconds: 60),
  });

  final LibraryRepository repository;
  final SyncService sync;

  /// The current server client, or null when not connected.
  final VellumServerClient? Function() client;

  /// Whether background auto-push is switched on (a user preference).
  final bool Function() enabled;

  final Duration debounce;

  StreamSubscription<int>? _sub;
  Timer? _timer;

  /// Begins watching for outstanding work. Idempotent-ish: call once.
  void start() {
    _sub = repository.watchDirtyCount().listen((count) {
      if (count == 0) {
        _timer?.cancel();
        return;
      }
      // Coalesce a burst of edits into one push once things go quiet.
      _timer?.cancel();
      _timer = Timer(debounce, _pushIfIdle);
    });
  }

  Future<void> _pushIfIdle() async {
    if (!enabled()) return;
    final c = client();
    if (c == null || sync.isRunning) return;
    try {
      await sync.push(c);
    } catch (_) {
      // Offline, rejected, or a concurrent sync — needsPush keeps it queued.
    }
  }

  void dispose() {
    _timer?.cancel();
    _sub?.cancel();
  }
}
