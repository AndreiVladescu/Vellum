import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Raised when the server returns a non-2xx response; [message] is the server's
/// `{"error": ...}` text when present, otherwise a generic status line.
class ServerException implements Exception {
  ServerException(this.message);
  final String message;
  @override
  String toString() => message;
}

/// An account as returned by the server.
class ServerUser {
  ServerUser({
    required this.id,
    required this.email,
    required this.displayName,
    required this.isMaster,
  });

  final String id;
  final String email;
  final String displayName;
  final bool isMaster;

  factory ServerUser.fromJson(Map<String, dynamic> j) => ServerUser(
    id: j['id'] as String? ?? '',
    email: j['email'] as String? ?? '',
    displayName: j['display_name'] as String? ?? '',
    isMaster: j['is_master'] as bool? ?? false,
  );
}

/// A book row from the server library (subset the app cares about).
class ServerBook {
  ServerBook({
    required this.id,
    required this.title,
    this.subtitle,
    this.description,
    this.isbn,
    this.publisher,
    this.publishedYear,
    this.pageCount,
    this.spineStyle,
    this.coverPath,
    this.updatedAt,
    this.authors,
    this.genres,
  });

  final String id;
  final String title;
  final String? subtitle;
  final String? description;
  final String? isbn;
  final String? publisher;
  final int? publishedYear;
  final int? pageCount;
  final String? spineStyle;

  /// Authors / genres from the `GET /api/books` list enrichment. Null (not just
  /// empty) when the server predates carrying them, so a pull can tell "the
  /// server has none" (apply, possibly clearing) from "the server didn't say"
  /// (leave local alone).
  final List<String>? authors;
  final List<String>? genres;

  /// Server-relative cover path; non-null means a cover is available to fetch.
  final String? coverPath;

  /// When the server last modified this book, used to decide whether a pull
  /// should overwrite a local row. Null if the server sent no/blank timestamp.
  final DateTime? updatedAt;

  bool get hasCover => coverPath != null && coverPath!.isNotEmpty;

  /// Server timestamps are `datetime('now')` UTC strings ("YYYY-MM-DD HH:MM:SS").
  static DateTime? _parseServerTime(String? s) => (s == null || s.isEmpty)
      ? null
      : DateTime.tryParse('${s.replaceFirst(' ', 'T')}Z');

  factory ServerBook.fromJson(Map<String, dynamic> j) => ServerBook(
    id: j['id'] as String,
    title: j['title'] as String? ?? '',
    subtitle: j['subtitle'] as String?,
    description: j['description'] as String?,
    isbn: j['isbn'] as String?,
    publisher: j['publisher'] as String?,
    publishedYear: j['published_year'] as int?,
    pageCount: j['page_count'] as int?,
    spineStyle: j['spine_style'] as String?,
    coverPath: j['cover_path'] as String?,
    updatedAt: _parseServerTime(j['updated_at'] as String?),
    authors: _stringList(j['authors']),
    genres: _stringList(j['genres']),
  );

  static List<String>? _stringList(dynamic v) =>
      v is List ? [for (final e in v) e.toString()] : null;
}

/// Formats a local [DateTime] as the server's UTC `"YYYY-MM-DD HH:MM:SS"` wire
/// form — the inverse of [ServerBook._parseServerTime]. Null in, null out (the
/// caller then omits the field, preserving the old always-overwrite behavior
/// for servers/clients that predate timestamp-guarded push).
String? formatServerTime(DateTime? dt) {
  if (dt == null) return null;
  final u = dt.toUtc();
  String two(int n) => n.toString().padLeft(2, '0');
  return '${u.year.toString().padLeft(4, '0')}-${two(u.month)}-${two(u.day)} '
      '${two(u.hour)}:${two(u.minute)}:${two(u.second)}';
}

/// Thin REST client for a Vellum sync server. Stateless apart from [baseUrl] and
/// an optional bearer [token]; create a new one when either changes.
class VellumServerClient {
  VellumServerClient({
    required this.baseUrl,
    this.token,
    http.Client? httpClient,
  }) : _http = httpClient ?? http.Client();

  final String baseUrl;
  final String? token;
  final http.Client _http;

  Uri _uri(String path) => Uri.parse('$baseUrl$path');

  /// The bearer header value, or null when unauthenticated.
  String? get _bearer => token == null ? null : 'Bearer $token';

  Map<String, String> get _headers => {
    'content-type': 'application/json',
    'authorization': ?_bearer,
  };

  /// Decodes a JSON object response, throwing [ServerException] on error status.
  dynamic _body(http.Response res) {
    final decoded = res.body.isEmpty ? null : jsonDecode(res.body);
    if (res.statusCode >= 200 && res.statusCode < 300) return decoded;
    final message = decoded is Map && decoded['error'] is String
        ? decoded['error'] as String
        : 'Server error (HTTP ${res.statusCode})';
    throw ServerException(message);
  }

  Future<AuthResult> register({
    required String email,
    required String displayName,
    required String password,
  }) async {
    final res = await _http.post(
      _uri('/api/auth/register'),
      headers: _headers,
      body: jsonEncode({
        'email': email,
        'display_name': displayName,
        'password': password,
      }),
    );
    return AuthResult._(_body(res) as Map<String, dynamic>);
  }

  Future<AuthResult> login({
    required String email,
    required String password,
  }) async {
    final res = await _http.post(
      _uri('/api/auth/login'),
      headers: _headers,
      body: jsonEncode({'email': email, 'password': password}),
    );
    return AuthResult._(_body(res) as Map<String, dynamic>);
  }

  Future<ServerUser> me() async {
    final res = await _http.get(_uri('/api/auth/me'), headers: _headers);
    return ServerUser.fromJson(_body(res) as Map<String, dynamic>);
  }

  /// Invalidates the current session server-side. Best-effort: the caller still
  /// clears local credentials even if this fails (e.g. offline).
  Future<void> logout() async {
    final res = await _http.post(_uri('/api/auth/logout'), headers: _headers);
    _body(res);
  }

  /// Every book visible to the authenticated user (owned + shared).
  Future<List<ServerBook>> listBooks() async {
    final res = await _http.get(_uri('/api/books'), headers: _headers);
    final list = _body(res) as List;
    return [
      for (final b in list) ServerBook.fromJson(b as Map<String, dynamic>),
    ];
  }

  /// The book's cover bytes, or null if it has none (404). Throws on other
  /// errors.
  Future<Uint8List?> downloadCover(String bookId) async {
    final res = await _http.get(
      _uri('/api/books/$bookId/cover'),
      headers: _headers,
    );
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
    throw ServerException('Cover download failed (HTTP ${res.statusCode})');
  }

  /// Upsert a book at [id] (create or update). Used to push local books up.
  /// [updatedAt] is the local row's sync clock; the server only overwrites an
  /// existing row when this is strictly newer than its stored timestamp
  /// (last-write-wins), so a stale push can't clobber a fresher remote edit.
  Future<void> pushBook({
    required String id,
    required String title,
    String? subtitle,
    String? description,
    String? isbn,
    String? publisher,
    int? publishedYear,
    int? pageCount,
    String? spineStyle,
    DateTime? updatedAt,
    List<String>? authors,
    List<String>? genres,
  }) async {
    final res = await _http.put(
      _uri('/api/books/$id'),
      headers: _headers,
      body: jsonEncode({
        'title': title,
        'subtitle': subtitle,
        'description': description,
        'isbn': isbn,
        'publisher': publisher,
        'published_year': publishedYear,
        'page_count': pageCount,
        'spine_style': spineStyle,
        'updated_at': ?formatServerTime(updatedAt),
        // Sent as arrays so the server replaces the joins; omitted (not null)
        // when the caller has nothing to say, to leave server joins untouched.
        'authors': ?authors,
        'genres': ?genres,
      }),
    );
    _body(res);
  }

  /// Book ids the server has tombstoned, so a pull can delete them locally.
  Future<List<String>> listDeletions() async {
    final res = await _http.get(_uri('/api/deletions'), headers: _headers);
    return [
      for (final d in _body(res) as List) (d as Map<String, dynamic>)['book_id'] as String,
    ];
  }

  /// Delete a book on the server (used to propagate a local delete up).
  Future<void> deleteBook(String id) async {
    final res = await _http.delete(_uri('/api/books/$id'), headers: _headers);
    _body(res);
  }

  /// Upload (replace) a book's cover image.
  Future<void> uploadCover(
    String bookId,
    Uint8List bytes, {
    String contentType = 'image/jpeg',
  }) async {
    final res = await _http.put(
      _uri('/api/books/$bookId/cover'),
      headers: {'content-type': contentType, 'authorization': ?_bearer},
      body: bytes,
    );
    _body(res);
  }

  // ---- book files ---------------------------------------------------------

  Future<List<ServerFile>> listFiles(String bookId) async {
    final res = await _http.get(
      _uri('/api/books/$bookId/files'),
      headers: _headers,
    );
    return [
      for (final f in _body(res) as List)
        ServerFile.fromJson(f as Map<String, dynamic>),
    ];
  }

  /// Streams a book file to [dest] by its server id, without holding the whole
  /// file in memory.
  Future<void> downloadFileTo(String fileId, File dest) async {
    final req = http.Request('GET', _uri('/api/files/$fileId'));
    final auth = _bearer;
    if (auth != null) req.headers['authorization'] = auth;
    final res = await _http.send(req);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ServerException('File download failed (HTTP ${res.statusCode})');
    }
    final sink = dest.openWrite();
    try {
      await sink.addStream(res.stream);
    } finally {
      await sink.close();
    }
  }

  /// Streams [source] up as a book file. [format] (e.g. 'pdf') sets the stored
  /// extension.
  Future<void> uploadFileFrom(
    String bookId,
    File source, {
    required String format,
  }) async {
    final mime = switch (format) {
      'pdf' => 'application/pdf',
      'epub' => 'application/epub+zip',
      _ => 'application/octet-stream',
    };
    final filename = Uri.encodeQueryComponent('book.$format');
    final req =
        http.StreamedRequest('POST', _uri('/api/books/$bookId/files?filename=$filename'))
          ..contentLength = await source.length()
          ..headers['content-type'] = mime;
    final auth = _bearer;
    if (auth != null) req.headers['authorization'] = auth;
    source.openRead().listen(
      req.sink.add,
      onError: req.sink.addError,
      onDone: req.sink.close,
      cancelOnError: true,
    );
    final res = await http.Response.fromStream(await _http.send(req));
    _body(res);
  }

  // ---- groups -------------------------------------------------------------

  Future<List<ServerGroup>> listGroups() async {
    final res = await _http.get(_uri('/api/groups'), headers: _headers);
    return [
      for (final g in _body(res) as List)
        ServerGroup.fromJson(g as Map<String, dynamic>),
    ];
  }

  Future<ServerGroup> createGroup(String name) async {
    final res = await _http.post(
      _uri('/api/groups'),
      headers: _headers,
      body: jsonEncode({'name': name}),
    );
    return ServerGroup.fromJson(_body(res) as Map<String, dynamic>);
  }

  Future<void> addBookToGroup(String groupId, String bookId) async {
    final res = await _http.post(
      _uri('/api/groups/$groupId/books'),
      headers: _headers,
      body: jsonEncode({'book_id': bookId}),
    );
    _body(res);
  }

  // ---- shares -------------------------------------------------------------

  Future<List<ServerShare>> listShares() async {
    final res = await _http.get(_uri('/api/shares'), headers: _headers);
    return [
      for (final s in _body(res) as List)
        ServerShare.fromJson(s as Map<String, dynamic>),
    ];
  }

  /// Grant [granteeEmail] access at [scope] ('all' | 'group' | 'book'); pass
  /// [scopeId] for group/book scopes.
  Future<void> createShare({
    required String scope,
    String? scopeId,
    required String granteeEmail,
    String permission = 'viewer',
  }) async {
    final res = await _http.post(
      _uri('/api/shares'),
      headers: _headers,
      body: jsonEncode({
        'scope': scope,
        'scope_id': ?scopeId,
        'grantee_email': granteeEmail,
        'permission': permission,
      }),
    );
    _body(res);
  }

  Future<void> deleteShare(String id) async {
    final res = await _http.delete(_uri('/api/shares/$id'), headers: _headers);
    _body(res);
  }

  // ---- public links -------------------------------------------------------

  Future<List<ServerLink>> listLinks() async {
    final res = await _http.get(_uri('/api/share-links'), headers: _headers);
    return [
      for (final l in _body(res) as List)
        ServerLink.fromJson(l as Map<String, dynamic>),
    ];
  }

  /// Mint a public link for [bookId]; returns the shareable URL (shown once).
  Future<String> createShareLink(String bookId, {int? expiresInDays}) async {
    final res = await _http.post(
      _uri('/api/share-links'),
      headers: _headers,
      body: jsonEncode({'book_id': bookId, 'expires_in_days': ?expiresInDays}),
    );
    return (_body(res) as Map<String, dynamic>)['url'] as String;
  }

  Future<void> deleteLink(String id) async {
    final res = await _http.delete(
      _uri('/api/share-links/$id'),
      headers: _headers,
    );
    _body(res);
  }
}

/// A shareable book group on the server.
class ServerGroup {
  ServerGroup({required this.id, required this.name, required this.bookCount});
  final String id;
  final String name;
  final int bookCount;
  factory ServerGroup.fromJson(Map<String, dynamic> j) => ServerGroup(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    bookCount: j['book_count'] as int? ?? 0,
  );
}

/// A grant of access from one account to another.
class ServerShare {
  ServerShare({
    required this.id,
    required this.scope,
    required this.permission,
    required this.granteeEmail,
    this.scopeLabel,
  });
  final String id;
  final String scope;
  final String permission;
  final String granteeEmail;
  final String? scopeLabel;
  factory ServerShare.fromJson(Map<String, dynamic> j) => ServerShare(
    id: j['id'] as String,
    scope: j['scope'] as String? ?? '',
    permission: j['permission'] as String? ?? 'viewer',
    granteeEmail: j['grantee_email'] as String? ?? '',
    scopeLabel: j['scope_label'] as String?,
  );
}

/// A digital file attached to a book on the server.
class ServerFile {
  ServerFile({
    required this.id,
    required this.bookId,
    required this.format,
    required this.sizeBytes,
    required this.sha256,
  });

  final String id;
  final String bookId;
  final String format;
  final int sizeBytes;
  final String sha256;

  factory ServerFile.fromJson(Map<String, dynamic> j) => ServerFile(
    id: j['id'] as String,
    bookId: j['book_id'] as String,
    format: j['format'] as String? ?? 'bin',
    sizeBytes: j['size_bytes'] as int? ?? 0,
    sha256: j['sha256'] as String? ?? '',
  );
}

/// A public per-book link.
class ServerLink {
  ServerLink({
    required this.id,
    required this.bookTitle,
    required this.revoked,
    this.expiresAt,
  });
  final String id;
  final String bookTitle;
  final bool revoked;
  final String? expiresAt;
  factory ServerLink.fromJson(Map<String, dynamic> j) => ServerLink(
    id: j['id'] as String,
    bookTitle: j['book_title'] as String? ?? '',
    revoked: j['revoked'] as bool? ?? false,
    expiresAt: j['expires_at'] as String?,
  );
}

/// Token + user returned by register/login.
class AuthResult {
  AuthResult._(Map<String, dynamic> json)
    : token = json['token'] as String,
      user = ServerUser.fromJson(json['user'] as Map<String, dynamic>);

  final String token;
  final ServerUser user;
}
