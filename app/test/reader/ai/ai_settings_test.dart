// Where the model lives.
//
// Three fields, one of which is a secret — so what is pinned here is that the
// key never lands in plain preferences while a secure store is working, and
// that the sheet can tell a model on this machine from one across the internet,
// which is the difference between "nothing leaves the device" and "this does".
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/reader/ai/ai_settings.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  Future<AiSettings> settings([Map<String, Object> initial = const {}]) async {
    SharedPreferences.setMockInitialValues(initial);
    return AiSettings.forTesting(await SharedPreferences.getInstance());
  }

  test('nothing is configured until an address and a model are named',
      () async {
    final ai = await settings();
    expect(ai.isConfigured, false);

    await ai.save(baseUrl: 'http://localhost:11434', model: '');
    expect(ai.isConfigured, false, reason: 'an address alone asks nothing');

    await ai.save(baseUrl: 'http://localhost:11434', model: 'llama3.2');
    expect(ai.isConfigured, true);
  });

  test('a key is optional — a model on your own machine wants none', () async {
    final ai = await settings();
    await ai.save(baseUrl: 'http://localhost:11434', model: 'llama3.2');
    expect(ai.isConfigured, true);
    expect(ai.apiKey, isNull);
  });

  test('the host is what the warning names', () async {
    final ai = await settings();
    await ai.save(baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o-mini');
    expect(ai.host, 'api.openai.com');
    expect(ai.isLocal, false, reason: 'this one leaves the device');
  });

  test('a model on this machine is known to be on this machine', () async {
    final ai = await settings();
    for (final url in [
      'http://localhost:11434',
      'http://127.0.0.1:1234/v1',
    ]) {
      await ai.save(baseUrl: url, model: 'llama3.2');
      expect(ai.isLocal, true, reason: url);
    }
  });

  test('a machine on the network is not "this machine"', () async {
    final ai = await settings();
    await ai.save(baseUrl: 'http://192.168.1.20:11434', model: 'llama3.2');
    expect(ai.isLocal, false,
        reason: 'it is still someone else’s computer, even at home');
  });

  test('the address is tidied on the way in', () async {
    final ai = await settings();
    await ai.save(baseUrl: '  http://localhost:11434  ', model: ' llama3.2 ');
    expect(ai.baseUrl, 'http://localhost:11434');
    expect(ai.model, 'llama3.2');
  });

  test('clearing the key clears it everywhere', () async {
    final ai = await settings();
    await ai.save(
        baseUrl: 'https://api.openai.com/v1',
        model: 'gpt-4o-mini',
        apiKey: 'sk-test');
    await ai.save(
        baseUrl: 'https://api.openai.com/v1', model: 'gpt-4o-mini', apiKey: '');

    expect(ai.apiKey, isNull);
    final prefs = await SharedPreferences.getInstance();
    expect(prefs.getString('reader.ai.key'), isNull,
        reason: 'a removed key must not survive in plain settings');
  });

  test('a saved setting outlives the object holding it', () async {
    final ai = await settings();
    await ai.save(baseUrl: 'http://localhost:11434', model: 'llama3.2');

    final reopened =
        AiSettings.forTesting(await SharedPreferences.getInstance());
    expect(reopened.baseUrl, 'http://localhost:11434');
    expect(reopened.model, 'llama3.2');
  });
}
