import 'dart:async';
import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:http/http.dart' as http;

import 'server_client.dart';

/// One hint from the server's event stream (plan 5 #8).
class LiveEvent {
  const LiveEvent({required this.kind, required this.id, required this.op});

  /// `book`, `shelf`, `copy`, `loan` — or `lagged` when this client fell far
  /// enough behind that the server stopped keeping its place.
  final String kind;
  final String id;
  final String op;

  bool get isLagged => kind == 'lagged';
}

/// Parses a `text/event-stream` body into [LiveEvent]s.
///
/// Hand-rolled rather than a package: SSE is a line format with four fields and
/// we use two of them, and the alternative is a dependency for thirty lines.
/// Events are separated by a blank line; a line starting with `:` is a
/// keep-alive comment and is dropped.
Stream<LiveEvent> parseEventStream(Stream<String> lines) async* {
  String? event;
  final data = StringBuffer();
  await for (final raw in lines) {
    final line = raw.trimRight();
    if (line.isEmpty) {
      // Blank line: dispatch whatever has accumulated.
      if (event != null && data.isNotEmpty) {
        final payload = _decode(data.toString());
        yield LiveEvent(
          kind: event,
          id: payload['id']?.toString() ?? '',
          op: payload['op']?.toString() ?? '',
        );
      }
      event = null;
      data.clear();
      continue;
    }
    if (line.startsWith(':')) continue; // keep-alive comment
    if (line.startsWith('event:')) {
      event = line.substring('event:'.length).trim();
    } else if (line.startsWith('data:')) {
      data.write(line.substring('data:'.length).trim());
    }
  }
}

Map<String, dynamic> _decode(String raw) {
  try {
    final decoded = jsonDecode(raw);
    return decoded is Map<String, dynamic> ? decoded : const {};
  } catch (_) {
    return const {};
  }
}

/// Subscribes to the server's change hints and runs a delta pull shortly after
/// one arrives (plan 5 #8).
///
/// Three rules shape this, and they are what keep a live channel from becoming
/// a second sync path:
///
/// - **A hint only triggers the existing pull.** Nothing here merges anything,
///   so row-level LWW stays the single conflict model.
/// - **Debounced and coalesced.** A console edit touching thirty books is one
///   pull, not thirty; the burst settles first.
/// - **Silent and disposable.** A dropped stream, an offline server, or a
///   server too old to have the endpoint all end in "no live updates" — never
///   an error the user has to dismiss. The app is local-first; the launch and
///   manual syncs remain the guarantee, and this is only ever a shortcut.
class LiveSyncTrigger {
  LiveSyncTrigger({
    required this.client,
    required this.onHint,
    required this.isConnected,
    this.debounce = const Duration(seconds: 3),
    this.retryDelay = const Duration(seconds: 30),
    http.Client Function()? httpClientFactory,
  }) : _httpClientFactory = httpClientFactory ?? http.Client.new;

  /// The current server client, or null when not connected.
  final VellumServerClient? Function() client;

  /// Run a delta pull. Called at most once per [debounce] window.
  final Future<void> Function() onHint;

  /// Whether the server advertises `live_events` and we are connected.
  final bool Function() isConnected;

  final Duration debounce;

  /// How long to wait before reconnecting a dropped stream. Deliberately long:
  /// a server that is down should not be hammered by every app on the LAN.
  final Duration retryDelay;

  final http.Client Function() _httpClientFactory;

  StreamSubscription<LiveEvent>? _sub;
  Timer? _debounceTimer;
  Timer? _retryTimer;
  http.Client? _http;
  bool _stopped = false;

  /// Whether a stream is currently open — for tests and the server page.
  bool get isListening => _sub != null;

  void start() {
    _stopped = false;
    _connect();
  }

  Future<void> _connect() async {
    if (_stopped || _sub != null) return;
    if (!isConnected()) {
      _scheduleRetry();
      return;
    }
    final c = client();
    if (c == null) {
      _scheduleRetry();
      return;
    }
    try {
      final http = _httpClientFactory();
      _http = http;
      final stream = await c.openEventStream(http);
      _sub = parseEventStream(stream).listen(
        _onEvent,
        onError: (_) => _dropAndRetry(),
        onDone: _dropAndRetry,
        cancelOnError: true,
      );
    } catch (_) {
      // Offline, an old server with no /api/events, or TLS trouble — all the
      // same outcome: no live updates, try again later.
      _dropAndRetry();
    }
  }

  /// Feeds one event in as though it had arrived on the stream — so the part
  /// worth testing (coalescing) can be tested without a socket.
  @visibleForTesting
  void debugHandleEvent(LiveEvent event) => _onEvent(event);

  void _onEvent(LiveEvent event) {
    // A `lagged` event means we missed hints; the answer is the same delta
    // pull, which is exactly what each missed hint would have caused.
    _debounceTimer?.cancel();
    _debounceTimer = Timer(debounce, () async {
      try {
        await onHint();
      } catch (_) {
        // A failed pull is not this class's problem — the next launch or
        // manual sync still covers it.
      }
    });
  }

  void _dropAndRetry() {
    _sub?.cancel();
    _sub = null;
    _http?.close();
    _http = null;
    _scheduleRetry();
  }

  void _scheduleRetry() {
    if (_stopped) return;
    _retryTimer?.cancel();
    _retryTimer = Timer(retryDelay, _connect);
  }

  void dispose() {
    _stopped = true;
    _debounceTimer?.cancel();
    _retryTimer?.cancel();
    _sub?.cancel();
    _sub = null;
    _http?.close();
    _http = null;
  }
}
