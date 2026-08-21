/// Where the model lives, and what it is called.
///
/// Three fields, kept apart from [ReaderSettings] because one of them is a
/// secret: the key goes to the platform's secure store, with the same honest
/// fallback the server token has — a headless Linux box with no keyring can
/// still work, but it is told that the key is sitting in plain preferences.
library;

import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

class AiSettings extends ChangeNotifier {
  AiSettings._(this._prefs, this._storage, this._apiKey, this.keyInsecure);

  static const _urlKey = 'reader.ai.url';
  static const _modelKey = 'reader.ai.model';
  static const _secretKey = 'reader.ai.key';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _storage;
  String? _apiKey;

  /// True when the key had to be kept in plain preferences because the OS
  /// secure store was unavailable. Shown, not hidden.
  final bool keyInsecure;

  static Future<AiSettings> load() async {
    final prefs = await SharedPreferences.getInstance();
    const storage = FlutterSecureStorage();
    String? key;
    var insecure = false;
    try {
      key = await storage.read(key: _secretKey);
    } catch (_) {
      key = prefs.getString(_secretKey);
      insecure = key != null && key.isNotEmpty;
    }
    return AiSettings._(prefs, storage, key, insecure);
  }

  /// For tests and for platforms with no stores at all.
  @visibleForTesting
  static AiSettings forTesting(SharedPreferences prefs) =>
      AiSettings._(prefs, const FlutterSecureStorage(), null, false);

  String get baseUrl => _prefs.getString(_urlKey) ?? '';
  String get model => _prefs.getString(_modelKey) ?? '';
  String? get apiKey => _apiKey;

  /// Enough to try. No key: a model on your own machine wants none, and
  /// demanding one would keep the self-hosted case behind a field it has no
  /// answer for.
  bool get isConfigured => baseUrl.trim().isNotEmpty && model.trim().isNotEmpty;

  /// The host a passage would be sent to, for the sentence that says so.
  String get host {
    final uri = Uri.tryParse(baseUrl.trim());
    return uri?.host.isNotEmpty == true ? uri!.host : baseUrl.trim();
  }

  /// True when the address is on this machine — which is the difference
  /// between "this passage leaves your device" and "it does not".
  bool get isLocal => const ['localhost', '127.0.0.1', '::1', '0.0.0.0']
      .contains(host.toLowerCase());

  Future<void> save({
    required String baseUrl,
    required String model,
    String? apiKey,
  }) async {
    await _prefs.setString(_urlKey, baseUrl.trim());
    await _prefs.setString(_modelKey, model.trim());
    final key = (apiKey ?? '').trim();
    _apiKey = key.isEmpty ? null : key;
    try {
      if (key.isEmpty) {
        await _storage.delete(key: _secretKey);
      } else {
        await _storage.write(key: _secretKey, value: key);
      }
      await _prefs.remove(_secretKey);
    } catch (_) {
      // No keyring. Keeping it in preferences is the only way this works at
      // all here, and [keyInsecure] is what says so on screen.
      if (key.isEmpty) {
        await _prefs.remove(_secretKey);
      } else {
        await _prefs.setString(_secretKey, key);
      }
    }
    notifyListeners();
  }
}
