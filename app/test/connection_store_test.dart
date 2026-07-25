import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/server/connection_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('clearAllSyncCursors removes every server cursor, keeps other prefs',
      () async {
    SharedPreferences.setMockInitialValues({
      'sync.cursor.http://a.test': '2024-01-01 00:00:00',
      'sync.cursor.http://b.test': '2024-02-01 00:00:00',
      'server.url': 'http://a.test',
      'server.isMaster': true,
    });
    final conn = await ServerConnection.load();

    await conn.clearAllSyncCursors();

    final prefs = await SharedPreferences.getInstance();
    expect(
      prefs.getKeys().where((k) => k.startsWith('sync.cursor.')),
      isEmpty,
      reason: 'all cursors dropped, not just the current URL',
    );
    expect(prefs.getString('server.url'), 'http://a.test',
        reason: 'unrelated prefs are untouched');
  });

  test('warns once when the token loads from plaintext prefs (no keyring)',
      () async {
    // With no secure-storage platform channel registered, the read throws and
    // load() falls back to the plaintext-prefs token — the insecure path (L2).
    SharedPreferences.setMockInitialValues({
      'server.url': 'http://a.test',
      'server.token': 'plaintext-tok',
      'server.email': 'reader@example.com',
    });
    final conn = await ServerConnection.load();

    expect(conn.isConnected, true);
    expect(conn.shouldWarnInsecureToken, true,
        reason: 'a plaintext-loaded token arms the honesty notice');

    await conn.dismissInsecureTokenWarning();
    expect(conn.shouldWarnInsecureToken, false,
        reason: 'dismissal is one-time and persists');
  });
}
