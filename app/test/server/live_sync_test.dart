// Live sync hints, app side (plan 5 #8).
//
// The server tests cover what goes out. What matters here is that a burst of
// hints becomes *one* pull, that a hint never becomes a merge, and that every
// way the stream can fail ends in silence rather than an error the user has to
// dismiss — the app is local-first, and live updates are only ever a shortcut.
import 'dart:async';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/server/live_sync.dart';

void main() {
  group('parseEventStream', () {
    Stream<String> lines(String body) =>
        Stream.fromIterable(body.split('\n'));

    test('reads an event and its data', () async {
      final events = await parseEventStream(lines(
        'event: book\n'
        'data: {"id":"dune","op":"upsert"}\n'
        '\n',
      )).toList();
      expect(events, hasLength(1));
      expect(events.single.kind, 'book');
      expect(events.single.id, 'dune');
      expect(events.single.op, 'upsert');
    });

    test('keep-alive comments are not events', () async {
      // Otherwise every 20 seconds would trigger a pointless pull.
      final events = await parseEventStream(lines(
        ': keep-alive\n'
        '\n'
        ': keep-alive\n'
        '\n',
      )).toList();
      expect(events, isEmpty);
    });

    test('several events in one chunk are all read', () async {
      final events = await parseEventStream(lines(
        'event: book\ndata: {"id":"a","op":"upsert"}\n'
        '\n'
        'event: shelf\ndata: {"id":"s","op":"delete"}\n'
        '\n',
      )).toList();
      expect([for (final e in events) '${e.kind}:${e.id}:${e.op}'],
          ['book:a:upsert', 'shelf:s:delete']);
    });

    test('a lagged event is surfaced as such', () async {
      final events = await parseEventStream(lines(
        'event: lagged\ndata: {"missed":12}\n'
        '\n',
      )).toList();
      expect(events.single.isLagged, isTrue);
    });

    test('malformed data does not kill the stream', () async {
      final events = await parseEventStream(lines(
        'event: book\ndata: not json\n'
        '\n'
        'event: book\ndata: {"id":"ok","op":"upsert"}\n'
        '\n',
      )).toList();
      expect(events, hasLength(2));
      expect(events.first.id, '', reason: 'unparseable, but not fatal');
      expect(events.last.id, 'ok');
    });

    test('an event with no terminating blank line is not dispatched early',
        () async {
      // A half-arrived event must wait for its separator rather than fire with
      // whatever has turned up so far.
      final events = await parseEventStream(lines(
        'event: book\ndata: {"id":"partial","op":"upsert"}',
      )).toList();
      expect(events, isEmpty);
    });
  });

  group('LiveSyncTrigger', () {
    /// A trigger fed from a controller we own, so the test decides exactly
    /// when a hint arrives.
    ({LiveSyncTrigger trigger, StreamController<LiveEvent> events, List<int> pulls})
        build({Duration debounce = const Duration(milliseconds: 40)}) {
      final pulls = <int>[];
      final events = StreamController<LiveEvent>();
      final trigger = LiveSyncTrigger(
        client: () => null,
        isConnected: () => false,
        debounce: debounce,
        onHint: () async => pulls.add(1),
      );
      return (trigger: trigger, events: events, pulls: pulls);
    }

    test('a burst of hints becomes one pull', () async {
      final h = build();
      addTearDown(h.trigger.dispose);
      // Drive the debounce directly: the transport is the server's contract,
      // the coalescing is this class's.
      for (var i = 0; i < 5; i++) {
        h.trigger.debugHandleEvent(
          const LiveEvent(kind: 'book', id: 'x', op: 'upsert'),
        );
      }
      expect(h.pulls, isEmpty, reason: 'nothing fires during the burst');
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(h.pulls, hasLength(1), reason: 'one pull once it settles');
    });

    test('a later hint after the window fires again', () async {
      final h = build();
      addTearDown(h.trigger.dispose);
      h.trigger.debugHandleEvent(
        const LiveEvent(kind: 'book', id: 'a', op: 'upsert'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      h.trigger.debugHandleEvent(
        const LiveEvent(kind: 'book', id: 'b', op: 'upsert'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(h.pulls, hasLength(2));
    });

    test('a lagged event triggers the same pull as any other hint', () async {
      // Missing hints and receiving one have the same remedy.
      final h = build();
      addTearDown(h.trigger.dispose);
      h.trigger.debugHandleEvent(
        const LiveEvent(kind: 'lagged', id: '', op: ''),
      );
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(h.pulls, hasLength(1));
    });

    test('a failing pull is swallowed', () async {
      // The launch and manual syncs remain the guarantee; a live pull that
      // fails must not surface anything.
      var attempts = 0;
      final trigger = LiveSyncTrigger(
        client: () => null,
        isConnected: () => false,
        debounce: const Duration(milliseconds: 20),
        onHint: () async {
          attempts++;
          throw StateError('offline');
        },
      );
      addTearDown(trigger.dispose);
      trigger.debugHandleEvent(
        const LiveEvent(kind: 'book', id: 'x', op: 'upsert'),
      );
      await Future<void>.delayed(const Duration(milliseconds: 100));
      expect(attempts, 1);
    });

    test('disposing cancels a pending pull', () async {
      final h = build();
      h.trigger.debugHandleEvent(
        const LiveEvent(kind: 'book', id: 'x', op: 'upsert'),
      );
      h.trigger.dispose();
      await Future<void>.delayed(const Duration(milliseconds: 120));
      expect(h.pulls, isEmpty, reason: 'a disposed trigger must go quiet');
    });

    test('it never opens a stream when not connected', () async {
      final h = build();
      addTearDown(h.trigger.dispose);
      h.trigger.start();
      await Future<void>.delayed(const Duration(milliseconds: 30));
      expect(h.trigger.isListening, isFalse,
          reason: 'standalone must stay a non-event');
    });
  });
}
