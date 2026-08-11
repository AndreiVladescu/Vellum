import 'package:flutter/foundation.dart';
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'cert_trust.dart';
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
  ServerConnection._(this._prefs, this._storage, this._token, this._tokenInsecure);

  static const _urlKey = 'server.url';
  static const _tokenKey = 'server.token';
  static const _emailKey = 'server.email';
  static const _masterKey = 'server.isMaster';
  static const _userIdKey = 'server.userId';
  static const _certPrefix = 'server.cert.';
  static const _insecureAckKey = 'server.insecureTokenAck';

  final SharedPreferences _prefs;
  final FlutterSecureStorage _storage;
  String? _token;

  /// The server's `GET /api/capabilities` response (plan 5 #6), fetched once
  /// per connect via [fetchCapabilities] and cached here for the life of the
  /// session — `client` mints a fresh [VellumServerClient] on every access,
  /// so nowhere else to cache it. Null until fetched, or if the server
  /// predates the endpoint / is unreachable; callers should treat that as
  /// "no info available", not an error.
  Capabilities? _capabilities;
  Capabilities? get capabilities => _capabilities;

  /// Seeds the cached handshake without a round trip, so a test can exercise
  /// a capability gate (plan 5 #6, #53) against a server it never contacts.
  @visibleForTesting
  void applyCapabilities(Capabilities value) {
    _capabilities = value;
    notifyListeners();
  }

  /// True when the session token is (or was loaded) in plaintext preferences
  /// because the OS secure store was unavailable — a keyring-less headless Linux
  /// box, typically. Drives the honesty notice on the server page (L2).
  bool _tokenInsecure;

  static Future<ServerConnection> load() async {
    final prefs = await SharedPreferences.getInstance();
    const storage = FlutterSecureStorage();
    String? token;
    var insecure = false;
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
      // No keyring available — fall back to the prefs-stored token, and flag
      // that it's sitting there unencrypted.
      token = prefs.getString(_tokenKey);
      insecure = token != null && token.isNotEmpty;
    }
    return ServerConnection._(prefs, storage, token, insecure);
  }

  String get baseUrl => _prefs.getString(_urlKey) ?? '';
  String? get token => _token;
  String get email => _prefs.getString(_emailKey) ?? '';
  bool get isMaster => _prefs.getBool(_masterKey) ?? false;

  /// This account's id on the server, as the server knows it. Empty when not
  /// signed in — and also on a session saved before this was recorded, so
  /// callers must treat empty as "unknown", never as "nobody".
  ///
  /// It is what lets the library tell its own rows from other people's: a shelf
  /// carries the id of whoever made it, and "someone else's shelf" is a
  /// comparison that needs both halves.
  String get userId => _prefs.getString(_userIdKey) ?? '';

  bool get isConnected => (_token?.isNotEmpty ?? false) && baseUrl.isNotEmpty;

  /// Whether to show the "secure storage unavailable" notice: the token is
  /// stored in plaintext *and* the user hasn't dismissed the warning yet.
  bool get shouldWarnInsecureToken =>
      _tokenInsecure &&
      isConnected &&
      !(_prefs.getBool(_insecureAckKey) ?? false);

  /// Records that the user has acknowledged the plaintext-token notice, so it
  /// isn't shown again unless a new insecure session re-arms it.
  Future<void> dismissInsecureTokenWarning() async {
    await _prefs.setBool(_insecureAckKey, true);
    notifyListeners();
  }

  String _cursorKey(String url) => 'sync.cursor.$url';

  /// The reading-position channel's own cursor (plan 5 #5). Separate from
  /// [syncCursor] because that pass runs on its own after a sync: sharing one
  /// cursor would let either pass advance it past rows the other hasn't seen.
  /// Sits under the same `sync.cursor.` prefix so [clearAllSyncCursors] wipes
  /// it too.
  String _readingCursorKey(String url) => 'sync.cursor.reading.$url';

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

  /// Cursor for the reading-position pass, or null to force a full pull of it.
  String? get readingCursor {
    final url = baseUrl;
    return url.isEmpty ? null : _prefs.getString(_readingCursorKey(url));
  }

  Future<void> setReadingCursor(String value) async {
    final url = baseUrl;
    if (url.isNotEmpty) {
      await _prefs.setString(_readingCursorKey(url), value);
    }
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

  String _certKey(String url) => '$_certPrefix${normalizeUrl(url)}';

  /// The imported self-signed certificate (PEM) the app should trust for [url],
  /// or null to use only the system trust store. Kept in preferences (a public
  /// certificate is not a secret), keyed by URL so distinct servers each keep
  /// their own.
  String? certFor(String url) {
    final pem = _prefs.getString(_certKey(url));
    return (pem != null && pem.isNotEmpty) ? pem : null;
  }

  /// The certificate trusted for the currently-configured server.
  String? get serverCert => baseUrl.isEmpty ? null : certFor(baseUrl);

  /// Import (or, with null/blank, forget) the trusted certificate for [url].
  Future<void> setCert(String url, String? pem) async {
    final key = _certKey(url);
    if (pem == null || pem.trim().isEmpty) {
      await _prefs.remove(key);
    } else {
      await _prefs.setString(key, pem.trim());
    }
    notifyListeners();
  }

  /// A token-less client for [url], used to log in / register. Trusts any
  /// certificate imported for that URL.
  VellumServerClient anonymousClient(String url) => VellumServerClient(
    baseUrl: normalizeUrl(url),
    httpClient: clientTrusting(certFor(url)),
  );

  /// The authenticated client for the current session, or null if disconnected.
  VellumServerClient? get client => isConnected
      ? VellumServerClient(
          baseUrl: baseUrl,
          token: _token,
          httpClient: clientTrusting(serverCert),
        )
      : null;

  /// Fetches and caches [capabilities] for the current connection. Best-effort
  /// and silent on failure (offline, or a server old enough to predate the
  /// endpoint) — this is informational only and must never block or fail a
  /// sign-in or sync because of it. Call once per connect; a `ListenableBuilder`
  /// on this connection picks up the result once it arrives.
  Future<void> fetchCapabilities() async {
    final c = client;
    if (c == null) return;
    try {
      _capabilities = await c.capabilities();
      notifyListeners();
    } catch (_) {
      // Leave whatever was cached (possibly null) — see the doc comment.
    }
  }

  Future<void> saveSession({
    required String url,
    required AuthResult auth,
  }) async {
    final normalized = normalizeUrl(url);
    await _prefs.setString(_urlKey, normalized);
    await _prefs.setString(_emailKey, auth.user.email);
    await _prefs.setBool(_masterKey, auth.user.isMaster);
    await _prefs.setString(_userIdKey, auth.user.id);
    // A fresh session starts with a full pull: the delta cursor can't tell that
    // a book was newly *shared* with this account (sharing doesn't bump a book's
    // updated_at), so clearing it here guarantees newly-visible books arrive.
    await _prefs.remove(_cursorKey(normalized));
    await _prefs.remove(_readingCursorKey(normalized));
    _capabilities = null;
    _token = auth.token;
    try {
      await _storage.write(key: _tokenKey, value: auth.token);
      _tokenInsecure = false;
    } catch (_) {
      // fallback: keep it in prefs if the secure store is unavailable, and
      // re-arm the honesty notice so the user learns their token is unencrypted.
      await _prefs.setString(_tokenKey, auth.token);
      _tokenInsecure = true;
      await _prefs.remove(_insecureAckKey);
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
    _tokenInsecure = false;
    _capabilities = null;
    try {
      await _storage.delete(key: _tokenKey);
    } catch (_) {
      // ignore: the prefs removal below clears any fallback copy.
    }
    await _prefs.remove(_tokenKey);
    await _prefs.remove(_emailKey);
    await _prefs.remove(_masterKey);
    await _prefs.remove(_userIdKey);
    await _prefs.remove(_insecureAckKey);
    if (baseUrl.isNotEmpty) {
      await _prefs.remove(_cursorKey(baseUrl));
      await _prefs.remove(_readingCursorKey(baseUrl));
    }
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
    if (baseUrl.isNotEmpty) {
      await _prefs.remove(_cursorKey(baseUrl));
      await _prefs.remove(_readingCursorKey(baseUrl));
    }
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
