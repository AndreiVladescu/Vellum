import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/notifications/notifications_button.dart';
import 'package:vellum/notifications/notifications_page.dart';
import 'package:vellum/server/connection_store.dart';
import 'package:vellum/server/server_client.dart';

/// Being told what happened, instead of having to go and look.
///
/// Two things worth pinning. The bell shows **nothing** when there is nothing —
/// a control that is always there and always says zero teaches people to stop
/// looking at it, and it must also stay quiet on a server too old to have the
/// endpoint rather than showing an error in the app bar. And the list has to
/// survive a kind it has never heard of: the server sends a sentence, so a new
/// kind is a thing to display, not a thing to crash on.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // Same reason as sharing_page_test: without this, ServerConnection.load()
  // hangs on flutter_secure_storage's channel.
  const secureStorage =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  /// A client answering `/api/notifications` with [items] and [unread], and
  /// recording every write so a test can assert what was sent.
  ({VellumServerClient client, List<String> writes}) clientFor({
    required List<Map<String, dynamic>> items,
    int? unread,
    int status = 200,
  }) {
    final writes = <String>[];
    final client = VellumServerClient(
      baseUrl: 'http://test',
      token: 't',
      httpClient: MockClient((req) async {
        if (req.method == 'POST') {
          writes.add(req.url.path);
          return http.Response('{}', 200);
        }
        if (status != 200) return http.Response('{"error":"nope"}', status);
        // Bytes, not a string. `http.Response(String, …)` with no content-type
        // encodes the body as latin-1 and throws on the curly quotes the server
        // actually writes — the mock has to be as UTF-8 as the real thing.
        return http.Response.bytes(
          utf8.encode(jsonEncode({
            'unread': unread ?? items.where((n) => n['read_at'] == null).length,
            'notifications': items,
          })),
          200,
          headers: {'content-type': 'application/json'},
        );
      }),
    );
    return (client: client, writes: writes);
  }

  Map<String, dynamic> notification({
    String id = 'n1',
    String kind = 'borrow.requested',
    String title = 'Ana would like to borrow “Dune”',
    String? body,
    String? readAt,
  }) =>
      {
        'id': id,
        'kind': kind,
        'title': title,
        'body': body,
        'book_id': 'b1',
        'created_at': '2026-08-11 09:00:00',
        'read_at': readAt,
      };

  Future<ServerConnection> connection(WidgetTester tester) async {
    late ServerConnection c;
    await tester.runAsync(() async => c = await ServerConnection.load());
    return c;
  }

  Future<void> settle(WidgetTester tester) async {
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  group('the bell', () {
    Future<void> pumpButton(
      WidgetTester tester,
      VellumServerClient client,
      ServerConnection conn,
    ) async {
      await tester.pumpWidget(MaterialApp(
        home: Scaffold(
          appBar: AppBar(
            actions: [NotificationsButton(connection: conn, client: client)],
          ),
        ),
      ));
      await settle(tester);
    }

    testWidgets('shows a count when something is waiting', (tester) async {
      final conn = await connection(tester);
      final fake = clientFor(items: [notification()], unread: 3);
      await pumpButton(tester, fake.client, conn);

      expect(find.byIcon(Icons.notifications_none), findsOneWidget);
      expect(find.text('3'), findsOneWidget, reason: 'the badge');
    });

    testWidgets('is absent entirely when there is nothing', (tester) async {
      final conn = await connection(tester);
      final fake = clientFor(items: const [], unread: 0);
      await pumpButton(tester, fake.client, conn);

      expect(find.byIcon(Icons.notifications_none), findsNothing);
      expect(find.byType(IconButton), findsNothing);
    });

    testWidgets('stays quiet on a server that has never heard of it',
        (tester) async {
      // A 404 is what an older server answers. An error icon in the app bar
      // would be noise about a feature this person may not even use.
      final conn = await connection(tester);
      final fake = clientFor(items: const [], status: 404);
      await pumpButton(tester, fake.client, conn);

      expect(find.byType(IconButton), findsNothing);
    });
  });

  group('the list', () {
    Future<void> pumpPage(
      WidgetTester tester,
      VellumServerClient client,
      ServerConnection conn,
    ) async {
      await tester.pumpWidget(MaterialApp(
        home: NotificationsPage(connection: conn, client: client),
      ));
      await settle(tester);
    }

    testWidgets('shows what happened, and what they said about it',
        (tester) async {
      final conn = await connection(tester);
      final fake = clientFor(items: [
        notification(body: 'They said: “for the weekend”'),
      ]);
      await pumpPage(tester, fake.client, conn);

      expect(find.text('Ana would like to borrow “Dune”'), findsOneWidget);
      expect(find.textContaining('for the weekend'), findsOneWidget);
    });

    testWidgets('an unknown kind is shown, not swallowed', (tester) async {
      final conn = await connection(tester);
      final fake = clientFor(items: [
        notification(kind: 'something.invented.later', title: 'A new thing'),
      ]);
      await pumpPage(tester, fake.client, conn);

      expect(find.text('A new thing'), findsOneWidget);
      expect(find.byIcon(Icons.notifications_none), findsOneWidget,
          reason: 'a neutral icon rather than a blank or a crash');
    });

    testWidgets('tapping one marks it read', (tester) async {
      final conn = await connection(tester);
      final fake = clientFor(items: [notification()]);
      await pumpPage(tester, fake.client, conn);

      await tester.tap(find.text('Ana would like to borrow “Dune”'));
      await settle(tester);
      expect(fake.writes, contains('/api/notifications/n1/read'));
    });

    testWidgets('"Mark all read" is offered while something is unread',
        (tester) async {
      final conn = await connection(tester);
      final fake = clientFor(items: [notification()]);
      await pumpPage(tester, fake.client, conn);
      expect(find.text('Mark all read'), findsOneWidget);
    });

    testWidgets('and is gone once everything has been seen', (tester) async {
      // A separate test rather than a second pump in the one above: pumping
      // another NotificationsPage reuses the same State, so the first load's
      // items would still be on screen and the assertion would be about
      // nothing.
      final conn = await connection(tester);
      final fake = clientFor(items: [
        notification(readAt: '2026-08-11 10:00:00'),
      ]);
      await pumpPage(tester, fake.client, conn);
      expect(find.text('Mark all read'), findsNothing);
    });

    testWidgets('an old server says so instead of showing an error',
        (tester) async {
      final conn = await connection(tester);
      final fake = clientFor(items: const [], status: 404);
      await pumpPage(tester, fake.client, conn);

      expect(find.textContaining('older than notifications'), findsOneWidget);
    });

    testWidgets('an empty list says nothing has happened', (tester) async {
      final conn = await connection(tester);
      final fake = clientFor(items: const []);
      await pumpPage(tester, fake.client, conn);

      expect(find.text('Nothing has happened yet.'), findsOneWidget);
    });
  });
}
