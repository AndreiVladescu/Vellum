import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/server/connection_store.dart';
import 'package:vellum/server/server_client.dart';
import 'package:vellum/server/sharing_page.dart';

/// The Sharing screen loading its four lists.
///
/// It threw on every visit, on every platform:
///
///   `type '({List<ServerBook> books, String serverNow})' is not a subtype`
///   `of type 'List<ServerBook>' in type cast`
///
/// The four requests went through `Future.wait`, which erases a heterogeneous
/// list to `List<dynamic>`, so `results[3] as List<ServerBook>` compiled
/// happily. `listBooks` returns a record carrying `server_now` beside the
/// books, and had done since delta pull was added — nothing could catch it
/// until someone opened the page.
///
/// A widget test rather than a unit test on purpose: the failure was in wiring
/// a real response shape into a real screen, which is precisely what a test of
/// either half alone would have missed.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  // flutter_secure_storage's channel would otherwise hang ServerConnection
  // .load(); a null-returning mock sends it down the plaintext-prefs
  // fallback, as `drawer_header_test.dart` does.
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

  /// Answers each endpoint the page asks for, in the shape the server sends —
  /// `/api/books` wrapped in an object with `server_now`, the rest bare.
  VellumServerClient clientFor({List<String> bookTitles = const ['Dune']}) {
    return VellumServerClient(
      baseUrl: 'http://test',
      token: 't',
      httpClient: MockClient((req) async {
        final path = req.url.path;
        if (path.startsWith('/api/groups')) {
          return http.Response('[]', 200);
        }
        if (path.startsWith('/api/shares')) {
          return http.Response('[]', 200);
        }
        if (path.startsWith('/api/share-links')) {
          return http.Response('[]', 200);
        }
        if (path.startsWith('/api/books')) {
          final books = [
            for (final (i, t) in bookTitles.indexed)
              '{"id":"b$i","title":"$t","authors":[],"updated_at":"2026-01-01"}',
          ].join(',');
          return http.Response(
            '{"books":[$books],"server_now":"2026-08-11T10:00:00Z"}',
            200,
          );
        }
        return http.Response('{}', 404);
      }),
    );
  }

  Future<void> pump(WidgetTester tester, VellumServerClient client) async {
    late ServerConnection connection;
    await tester.runAsync(() async {
      connection = await ServerConnection.load();
    });
    await tester.pumpWidget(MaterialApp(
      home: SharingPage(connection: connection, client: client),
    ));
    for (var i = 0; i < 6; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  testWidgets('loads its sections instead of throwing', (tester) async {
    await pump(tester, clientFor(bookTitles: ['Dune', 'Piranesi']));

    // The regression surfaced as the error state, carrying the cast message.
    expect(find.textContaining('is not a subtype'), findsNothing);
    expect(find.text('Retry'), findsNothing,
        reason: 'the error state means the load threw');
    // The page shows its three sections; the books it fetched are not listed
    // here, they populate the "new share" and "new link" pickers.
    expect(find.text('Groups'), findsOneWidget);
    expect(find.text('Shared with people'), findsOneWidget);
    expect(find.text('Public links'), findsOneWidget);
  });

  testWidgets('an empty library is not an error', (tester) async {
    await pump(tester, clientFor(bookTitles: const []));
    expect(find.textContaining('is not a subtype'), findsNothing);
    expect(find.text('Retry'), findsNothing);
    expect(find.text('Groups'), findsOneWidget);
  });
}
