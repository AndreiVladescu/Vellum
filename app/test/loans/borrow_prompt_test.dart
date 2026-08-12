import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/loans/borrow_requests.dart';
import 'package:vellum/server/connection_store.dart';

/// The dialog says who is being asked (issue #10 item 8).
///
/// "It is not clear who I ask for a book" — so the sentence names them, and
/// falls back to "The owner" where the app has not been told, which is what a
/// library on an older server can honestly say.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  const secureStorage =
      MethodChannel('plugins.it_nomads.com/flutter_secure_storage');
  setUp(() {
    // A live session, or `promptBorrowRequest` returns before it draws
    // anything: with no client there is nobody to ask. The token falls back to
    // prefs when secure storage is unavailable, which the mock above makes it.
    SharedPreferences.setMockInitialValues({
      'server.url': 'http://test.local',
      'server.token': 't',
    });
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, (call) async => null);
  });
  tearDown(() {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(secureStorage, null);
  });

  Future<void> pump(WidgetTester tester, {String? owner}) async {
    late ServerConnection connection;
    await tester.runAsync(() async {
      connection = await ServerConnection.load();
    });
    await tester.pumpWidget(MaterialApp(
      home: Builder(
        builder: (context) => Scaffold(
          body: TextButton(
            onPressed: () => promptBorrowRequest(
                context, connection, 'b1', 'Dune', owner: owner),
            child: const Text('ask'),
          ),
        ),
      ),
    ));
    await tester.tap(find.text('ask'));
    await tester.pumpAndSettle();
  }

  testWidgets('names the owner when the app knows them', (tester) async {
    await pump(tester, owner: 'Ana');
    expect(find.textContaining('Ana sees this in their app'), findsOneWidget);
  });

  testWidgets('and says "the owner" when it does not', (tester) async {
    await pump(tester);
    expect(find.textContaining('The owner sees this'), findsOneWidget);
  });

  testWidgets('and promises an answer either way', (tester) async {
    // The other half of the report: not being told when it was approved.
    await pump(tester, owner: 'Ana');
    expect(find.textContaining('you are told'), findsOneWidget);
  });
}
