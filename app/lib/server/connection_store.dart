import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'server_client.dart';

/// Persists the optional connection to a Vellum sync server: base URL, bearer
/// token, and the signed-in account. The app stays local-first — this only adds
/// a way to pull a shared library down onto the device.
class ServerConnection extends ChangeNotifier {
  ServerConnection._(this._prefs);

  static const _urlKey = 'server.url';
  static const _tokenKey = 'server.token';
  static const _emailKey = 'server.email';
  static const _masterKey = 'server.isMaster';

  final SharedPreferences _prefs;

  static Future<ServerConnection> load() async =>
      ServerConnection._(await SharedPreferences.getInstance());

  String get baseUrl => _prefs.getString(_urlKey) ?? '';
  String? get token => _prefs.getString(_tokenKey);
  String get email => _prefs.getString(_emailKey) ?? '';
  bool get isMaster => _prefs.getBool(_masterKey) ?? false;

  bool get isConnected =>
      (token?.isNotEmpty ?? false) && baseUrl.isNotEmpty;

  /// A token-less client for [url], used to log in / register.
  VellumServerClient anonymousClient(String url) =>
      VellumServerClient(baseUrl: normalizeUrl(url));

  /// The authenticated client for the current session, or null if disconnected.
  VellumServerClient? get client => isConnected
      ? VellumServerClient(baseUrl: baseUrl, token: token)
      : null;

  Future<void> saveSession({
    required String url,
    required AuthResult auth,
  }) async {
    await _prefs.setString(_urlKey, normalizeUrl(url));
    await _prefs.setString(_tokenKey, auth.token);
    await _prefs.setString(_emailKey, auth.user.email);
    await _prefs.setBool(_masterKey, auth.user.isMaster);
    notifyListeners();
  }

  /// Forget the session (keeps the last URL as a convenience default). Tells the
  /// server to invalidate the token too, best-effort — offline is fine, the
  /// local credentials are cleared regardless.
  Future<void> disconnect() async {
    try {
      await client?.logout();
    } catch (_) {
      // Offline or already-invalid token — clearing locally is enough.
    }
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_emailKey);
    await _prefs.remove(_masterKey);
    notifyListeners();
  }

  /// Adds a scheme if missing and trims a trailing slash so paths concatenate.
  static String normalizeUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'http://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }
}
