// Send to a device (plan 5 #53), app side.
//
// The server tests cover what happens when the request lands. What matters
// here is the gate: the file and the mailer both live on the server, so an
// unconnected app — or one talking to a server with no SMTP — must not offer a
// button that can only fail.
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/book_detail/send_to_device_sheet.dart';
import 'package:vellum/server/connection_store.dart';
import 'package:vellum/server/server_client.dart';

void main() {
  Future<ServerConnection> connection({
    required bool connected,
    List<String> features = const [],
  }) async {
    SharedPreferences.setMockInitialValues({
      if (connected) ...{
        'server.url': 'http://server.test',
        'server.token': 'tok',
        'server.email': 'reader@example.com',
      },
    });
    final conn = await ServerConnection.load();
    if (connected) {
      conn.applyCapabilities(Capabilities(
        serverVersion: '0.1.0',
        syncProtocol: 1,
        features: features,
      ));
    }
    return conn;
  }

  test('offered only when the server advertises send_to_device', () async {
    final withMail = await connection(
      connected: true,
      features: const ['delta_pull', 'mail', 'send_to_device'],
    );
    expect(SendToDeviceSheet.availableOn(withMail), isTrue);
  });

  test('a server with no mailer does not offer it', () async {
    final noMail = await connection(
      connected: true,
      features: const ['delta_pull'],
    );
    expect(SendToDeviceSheet.availableOn(noMail), isFalse);
  });

  test('standalone (no server at all) does not offer it', () async {
    expect(SendToDeviceSheet.availableOn(await connection(connected: false)),
        isFalse);
    expect(SendToDeviceSheet.availableOn(null), isFalse,
        reason: 'a caller with no connection to hand');
  });

  test('a connected server that never answered the handshake stays quiet',
      () async {
    // capabilities == null: better to hide the action than to guess.
    SharedPreferences.setMockInitialValues({
      'server.url': 'http://server.test',
      'server.token': 'tok',
      'server.email': 'reader@example.com',
    });
    final conn = await ServerConnection.load();
    expect(conn.isConnected, isTrue);
    expect(SendToDeviceSheet.availableOn(conn), isFalse);
  });

  group('SendTarget', () {
    test('round-trips through JSON', () {
      const target = SendTarget(label: 'My Kindle', address: 'me@kindle.com');
      final decoded = SendTarget.fromJson(target.toJson());
      expect(decoded.label, 'My Kindle');
      expect(decoded.address, 'me@kindle.com');
    });

    test('a malformed row decodes to blanks rather than throwing', () {
      // The server owns validation; the client must not crash on a surprise.
      final decoded = SendTarget.fromJson(const {});
      expect(decoded.label, '');
      expect(decoded.address, '');
    });
  });
}
