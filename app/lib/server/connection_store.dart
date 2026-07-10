import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'server_client.dart';

/// Persists the optional connection to a Vellum sync server: base URL, bearer
/// token, and the signed-in account. The app stays local-first — this only adds
/// a way to pull a shared library down onto the device.
///
/// The **token** is kept in the platform secure store (Keychain / libsecret /
/// Keystore) rather than plaintext preferences; the URL/email/master flag stay
/// in [SharedPreferences]. If the secure store is unavailable (e.g. no keyring),
/// it transparently falls back to preferences so the app still works.
class ServerConnection extends ChangeNotifier {
  ServerConnection._(this._prefs, this._storage, this._token);

  static const _urlKey = 'server.url';
  static const _tokenKey = 'server.token';
  static const _emailKey = 'server.email';
  static const _masterKey = 'server.isMaster';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _storage;
  String? _token;

  static Future<ServerConnection> load() async {
    final prefs = await SharedPreferences.getInstance();
    const storage = FlutterSecureStorage();
    String? token;
    try {
      token = await storage.read(key: _tokenKey);
      // Migrate a token previously kept in plaintext prefs into the secure
      // store, then scrub the plaintext copy.
      final legacy = prefs.getString(_tokenKey);
      if (legacy != null && legacy.isNotEmpty) {
        if (token == null || token.isEmpty) {
          token = legacy;
          await storage.write(key: _tokenKey, value: legacy);
        }
        await prefs.remove(_tokenKey);
      }
    } catch (_) {
      // No keyring available — fall back to the prefs-stored token.
      token = prefs.getString(_tokenKey);
    }
    return ServerConnection._(prefs, storage, token);
  }

  String get baseUrl => _prefs.getString(_urlKey) ?? '';
  String? get token => _token;
  String get email => _prefs.getString(_emailKey) ?? '';
  bool get isMaster => _prefs.getBool(_masterKey) ?? false;

  bool get isConnected => (_token?.isNotEmpty ?? false) && baseUrl.isNotEmpty;

  String _cursorKey(String url) => 'sync.cursor.$url';

  /// The last server clock a delta pull reached for the current connection, or
  /// null to force a full pull. Keyed by base URL so distinct servers don't
  /// share a cursor.
  String? get syncCursor {
    final url = baseUrl;
    return url.isEmpty ? null : _prefs.getString(_cursorKey(url));
  }

  Future<void> setSyncCursor(String value) async {
    final url = baseUrl;
    if (url.isNotEmpty) await _prefs.setString(_cursorKey(url), value);
  }

  /// Drops every delta-pull cursor (all servers), forcing a full pull next time.
  /// Called after a restore: the swapped-in database may predate a cursor, so a
  /// delta pull from it would silently skip everything changed in between. All
  /// URLs (not just the current one) so a backup made against another server is
  /// covered too.
  Future<void> clearAllSyncCursors() async {
    final keys = _prefs.getKeys().where((k) => k.startsWith('sync.cursor.'));
    for (final k in keys) {
      await _prefs.remove(k);
    }
  }

  /// A token-less client for [url], used to log in / register.
  VellumServerClient anonymousClient(String url) =>
      VellumServerClient(baseUrl: normalizeUrl(url));

  /// The authenticated client for the current session, or null if disconnected.
  VellumServerClient? get client => isConnected
      ? VellumServerClient(baseUrl: baseUrl, token: _token)
      : null;

  Future<void> saveSession({
    required String url,
    required AuthResult auth,
  }) async {
    final normalized = normalizeUrl(url);
    await _prefs.setString(_urlKey, normalized);
    await _prefs.setString(_emailKey, auth.user.email);
    await _prefs.setBool(_masterKey, auth.user.isMaster);
    // A fresh session starts with a full pull: the delta cursor can't tell that
    // a book was newly *shared* with this account (sharing doesn't bump a book's
    // updated_at), so clearing it here guarantees newly-visible books arrive.
    await _prefs.remove(_cursorKey(normalized));
    _token = auth.token;
    try {
      await _storage.write(key: _tokenKey, value: auth.token);
    } catch (_) {
      // fallback: keep it in prefs if the secure store is unavailable.
      await _prefs.setString(_tokenKey, auth.token);
    }
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
    _token = null;
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {
      // ignore: the prefs removal below clears any fallback copy.
    }
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_emailKey);
    await _prefs.remove(_masterKey);
    if (baseUrl.isNotEmpty) await _prefs.remove(_cursorKey(baseUrl));
    notifyListeners();
  }

  /// Clears just the session token after the server rejected it (a 401), so the
  /// UI drops back to the sign-in screen. Keeps the URL/email as convenient
  /// defaults for re-login, and skips the network logout (the token is dead).
  Future<void> clearExpiredSession() async {
    _token = null;
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {
      // ignore: the prefs removal below clears any fallback copy.
    }
    await _prefs.remove(_tokenKey);
    if (baseUrl.isNotEmpty) await _prefs.remove(_cursorKey(baseUrl));
    notifyListeners();
  }

  /// Adds a scheme if missing and trims a trailing slash so paths concatenate.
  /// Defaults to **https** — plain http must be typed explicitly, since it sends
  /// the password and library in cleartext.
  static String normalizeUrl(String url) {
    var u = url.trim();
    if (u.isEmpty) return u;
    if (!u.startsWith('http://') && !u.startsWith('https://')) {
      u = 'https://$u';
    }
    while (u.endsWith('/')) {
      u = u.substring(0, u.length - 1);
    }
    return u;
  }
}
