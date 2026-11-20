// VELLUM_NO_KEYRING keeps a profiling or demo run away from the real app's
// keyring: the files are isolated with XDG_DATA_HOME, the keyring is not.
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/server/connection_store.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  setUp(() {
    // The real app's session, as it sits in the shared keyring.
    FlutterSecureStorage.setMockInitialValues({'server.token': 'real-token'});
    SharedPreferences.setMockInitialValues({
      'server.url': 'https://library.example.com',
    });
  });
  tearDown(() => ServerConnection.debugKeyringDisabled = null);

  test('normally the token comes from the keyring', () async {
    ServerConnection.debugKeyringDisabled = false;
    final c = await ServerConnection.load();
    expect(c.isConnected, isTrue);
  });

  test('with the keyring disabled, the real token is never read', () async {
    ServerConnection.debugKeyringDisabled = true;
    final c = await ServerConnection.load();
    expect(c.isConnected, isFalse);
  });

  test('with the keyring disabled, a sign-out leaves the real token', () async {
    ServerConnection.debugKeyringDisabled = true;
    final c = await ServerConnection.load();
    await c.clearExpiredSession();
    expect(
      await const FlutterSecureStorage().read(key: 'server.token'),
      'real-token',
    );
  });

  test('without the switch, the same sign-out does clear it', () async {
    // The control: proves the test above would notice a deletion.
    ServerConnection.debugKeyringDisabled = false;
    final c = await ServerConnection.load();
    await c.clearExpiredSession();
    expect(
      await const FlutterSecureStorage().read(key: 'server.token'),
      isNull,
    );
  });
}
