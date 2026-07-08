import 'dart:convert';
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

  /// Server-relative cover path; non-null means a cover is available to fetch.
  final String? coverPath;

  bool get hasCover => coverPath != null && coverPath!.isNotEmpty;

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
  );
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
      }),
    );
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

  /// Downloads a book file's bytes by its server id.
  Future<Uint8List> downloadFile(String fileId) async {
    final res = await _http.get(_uri('/api/files/$fileId'), headers: _headers);
    if (res.statusCode >= 200 && res.statusCode < 300) return res.bodyBytes;
    throw ServerException('File download failed (HTTP ${res.statusCode})');
  }

  /// Uploads a book file. [format] (e.g. 'pdf') sets the stored extension.
  Future<void> uploadFile(
    String bookId,
    Uint8List bytes, {
    required String format,
  }) async {
    final mime = switch (format) {
      'pdf' => 'application/pdf',
      'epub' => 'application/epub+zip',
      _ => 'application/octet-stream',
    };
    final filename = Uri.encodeQueryComponent('book.$format');
    final res = await _http.post(
      _uri('/api/books/$bookId/files?filename=$filename'),
      headers: {'content-type': mime, 'authorization': ?_bearer},
      body: bytes,
    );
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
