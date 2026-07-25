import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// Raised when the server returns a non-2xx response; [message] is the server's
/// `{"error": ...}` text when present, otherwise a generic status line.
/// [statusCode] lets callers special-case e.g. a 401 (expired session).
class ServerException implements Exception {
  ServerException(this.message, {this.statusCode});
  final String message;
  final int? statusCode;

  /// True when the session is no longer valid and the user must log in again.
  bool get isUnauthorized => statusCode == 401;

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
    this.files = const [],
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

  /// The book's files from the list enrichment, so a pull/push needn't do a
  /// `GET .../files` per book. Empty when the server predates carrying them.
  final List<ServerFile> files;

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
    files: j['files'] is List
        ? [
            for (final f in j['files'] as List)
              ServerFile.fromJson(f as Map<String, dynamic>),
          ]
        : const [],
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
    throw ServerException(message, statusCode: res.statusCode);
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

  /// Unauthenticated — a client needs to know what a server supports before
  /// it has (or instead of) a session. Throws [ServerException] on a server
  /// old enough to predate this endpoint (404); callers treat that as "no
  /// capability info available" rather than a hard failure.
  Future<Capabilities> capabilities() async {
    final res = await _http.get(_uri('/api/capabilities'));
    return Capabilities.fromJson(_body(res) as Map<String, dynamic>);
  }

  /// Invalidates the current session server-side. Best-effort: the caller still
  /// clears local credentials even if this fails (e.g. offline).
  Future<void> logout() async {
    final res = await _http.post(_uri('/api/auth/logout'), headers: _headers);
    _body(res);
  }

  /// The visible library (owned + shared) plus the server's clock, as the
  /// delta-pull envelope `{ server_now, books }`. Always sends `cursor` (empty
  /// for a first/full pull) so the server includes `server_now`; a non-empty
  /// [cursor] asks for only rows changed since it. Falls back gracefully to a
  /// bare array (server_now null) from a server that predates the cursor.
  Future<({String? serverNow, List<ServerBook> books})> listBooks({
    String? cursor,
  }) async {
    final uri = _uri(
      '/api/books',
    ).replace(queryParameters: {'cursor': cursor ?? ''});
    final res = await _http.get(uri, headers: _headers);
    final body = _body(res);
    final list = (body is Map ? body['books'] as List? : body as List?) ?? const [];
    return (
      serverNow: body is Map ? body['server_now'] as String? : null,
      books: [
        for (final b in list) ServerBook.fromJson(b as Map<String, dynamic>),
      ],
    );
  }

  /// The book's cover bytes and its ETag. Pass the previously stored [etag] to
  /// let the server answer `304 Not Modified` for an unchanged cover — then
  /// [bytes] is null and the caller keeps what it has. [bytes] is also null when
  /// the book has no cover (404). Throws on other errors.
  Future<({Uint8List? bytes, String? etag})> downloadCover(
    String bookId, {
    String? etag,
  }) async {
    final headers = {
      ..._headers,
      'if-none-match': ?etag,
    };
    final res = await _http.get(
      _uri('/api/books/$bookId/cover'),
      headers: headers,
    );
    if (res.statusCode == 304) return (bytes: null, etag: etag);
    if (res.statusCode == 404) return (bytes: null, etag: null);
    if (res.statusCode >= 200 && res.statusCode < 300) {
      return (bytes: res.bodyBytes, etag: res.headers['etag']);
    }
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

  /// Ids the server has tombstoned, so a pull can delete them locally. A
  /// non-empty [since] cursor narrows to tombstones at or after it; [kind]
  /// ('book', 'shelf', ...) narrows to just that entity type — omitted, this
  /// returns every kind (what a server predating [kind] always did; this
  /// client just reads `book_id` regardless, see plan 5 #4's deletion.kind).
  Future<List<String>> listDeletions({String? since, String? kind}) async {
    final params = {
      if (since != null && since.isNotEmpty) 'since': since,
      'kind': ?kind,
    };
    final uri = params.isEmpty
        ? _uri('/api/deletions')
        : _uri('/api/deletions').replace(queryParameters: params);
    final res = await _http.get(uri, headers: _headers);
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
  /// file in memory. If [dest] already holds a partial download, resumes from
  /// where it left off with a `Range` request; the server answers `206` (append)
  /// or `200` (start over). Book files are content-addressed and immutable, so a
  /// resume can't stitch together bytes from two different files.
  Future<void> downloadFileTo(String fileId, File dest) async {
    final existing = await dest.exists() ? await dest.length() : 0;
    final req = http.Request('GET', _uri('/api/files/$fileId'));
    final auth = _bearer;
    if (auth != null) req.headers['authorization'] = auth;
    if (existing > 0) req.headers['range'] = 'bytes=$existing-';
    final res = await _http.send(req);
    if (res.statusCode < 200 || res.statusCode >= 300) {
      throw ServerException('File download failed (HTTP ${res.statusCode})');
    }
    // 206 continues the existing file; anything else (200) is a full body, so
    // overwrite from the start.
    final sink = res.statusCode == 206
        ? dest.openWrite(mode: FileMode.append)
        : dest.openWrite();
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

  // ---- shelves (plan 5 #4) -------------------------------------------------

  /// The visible shelves (owned + all-scope shared) plus the server's clock,
  /// as the delta-pull envelope `{ server_now, shelves }` — same cursor
  /// convention as [listBooks], minus that method's bare-array fallback:
  /// `/api/shelves` has no pre-cursor history to be backward compatible with,
  /// so a server that has this endpoint at all always sends the envelope.
  Future<({String? serverNow, List<ServerShelf> shelves})> listShelves({
    String? cursor,
  }) async {
    final uri = _uri(
      '/api/shelves',
    ).replace(queryParameters: {'cursor': cursor ?? ''});
    final res = await _http.get(uri, headers: _headers);
    final map = _body(res) as Map<String, dynamic>;
    return (
      serverNow: map['server_now'] as String?,
      shelves: [
        for (final s in map['shelves'] as List)
          ServerShelf.fromJson(s as Map<String, dynamic>),
      ],
    );
  }

  /// Upsert a shelf at [id] (create or update), replacing its membership
  /// wholesale with [bookIds] in that exact order — same LWW convention as
  /// [pushBook].
  Future<void> pushShelf({
    required String id,
    required String name,
    required int sortOrder,
    required List<String> bookIds,
    DateTime? updatedAt,
  }) async {
    final res = await _http.put(
      _uri('/api/shelves/$id'),
      headers: _headers,
      body: jsonEncode({
        'name': name,
        'sort_order': sortOrder,
        'book_ids': bookIds,
        'updated_at': ?formatServerTime(updatedAt),
      }),
    );
    _body(res);
  }

  /// Delete a shelf on the server (used to propagate a local delete up).
  Future<void> deleteShelf(String id) async {
    final res = await _http.delete(_uri('/api/shelves/$id'), headers: _headers);
    _body(res);
  }

  // ---- physical copies (plan 5 #4) -----------------------------------------

  /// The visible copies (of owned + shared books) plus the server's clock, as
  /// the delta-pull envelope `{ server_now, copies }` — same cursor
  /// convention as [listShelves]: no pre-cursor history, so always the
  /// envelope shape.
  Future<({String? serverNow, List<ServerCopy> copies})> listCopies({
    String? cursor,
  }) async {
    final uri = _uri(
      '/api/copies',
    ).replace(queryParameters: {'cursor': cursor ?? ''});
    final res = await _http.get(uri, headers: _headers);
    final map = _body(res) as Map<String, dynamic>;
    return (
      serverNow: map['server_now'] as String?,
      copies: [
        for (final c in map['copies'] as List)
          ServerCopy.fromJson(c as Map<String, dynamic>),
      ],
    );
  }

  /// Upsert a copy at [id] (create or update) — same LWW convention as
  /// [pushBook]/[pushShelf]. [bookId] is only meaningful at creation; the
  /// server rejects a push that tries to move an existing copy to a
  /// different book.
  Future<void> pushCopy({
    required String id,
    required String bookId,
    String? location,
    String? condition,
    String? notes,
    DateTime? updatedAt,
  }) async {
    final res = await _http.put(
      _uri('/api/copies/$id'),
      headers: _headers,
      body: jsonEncode({
        'book_id': bookId,
        'location': location,
        'condition': condition,
        'notes': notes,
        'updated_at': ?formatServerTime(updatedAt),
      }),
    );
    _body(res);
  }

  /// Delete a copy on the server (used to propagate a local delete up).
  Future<void> deleteCopy(String id) async {
    final res = await _http.delete(_uri('/api/copies/$id'), headers: _headers);
    _body(res);
  }

  // ---- loans (plan 5 #4) ----------------------------------------------------

  /// The visible loans (of owned + shared copies) plus the server's clock, as
  /// the delta-pull envelope `{ server_now, loans }` — same cursor convention
  /// as [listCopies].
  Future<({String? serverNow, List<ServerLoan> loans})> listLoans({
    String? cursor,
  }) async {
    final uri = _uri(
      '/api/loans',
    ).replace(queryParameters: {'cursor': cursor ?? ''});
    final res = await _http.get(uri, headers: _headers);
    final map = _body(res) as Map<String, dynamic>;
    return (
      serverNow: map['server_now'] as String?,
      loans: [
        for (final l in map['loans'] as List)
          ServerLoan.fromJson(l as Map<String, dynamic>),
      ],
    );
  }

  /// Upsert a loan at [id] (create or update) — same LWW convention as
  /// [pushCopy]. [copyId]/[loanedAt] are only meaningful at creation; the
  /// server rejects a push that tries to move an existing loan to a
  /// different copy.
  Future<void> pushLoan({
    required String id,
    required String copyId,
    required String borrower,
    required DateTime loanedAt,
    DateTime? returnedAt,
    DateTime? updatedAt,
  }) async {
    final res = await _http.put(
      _uri('/api/loans/$id'),
      headers: _headers,
      body: jsonEncode({
        'copy_id': copyId,
        'borrower': borrower,
        'loaned_at': formatServerTime(loanedAt),
        'returned_at': ?formatServerTime(returnedAt),
        'updated_at': ?formatServerTime(updatedAt),
      }),
    );
    _body(res);
  }

  /// Delete a loan on the server. No app code path calls this today (a loan
  /// is removed only via its copy's cascade), but it's exposed for parity
  /// with the other synced entities' `delete*` methods.
  Future<void> deleteLoan(String id) async {
    final res = await _http.delete(_uri('/api/loans/$id'), headers: _headers);
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

/// A custom shelf from the server (plan 5 #4): metadata plus its membership
/// in explicit order.
class ServerShelf {
  ServerShelf({
    required this.id,
    required this.name,
    required this.sortOrder,
    required this.bookIds,
    this.updatedAt,
  });

  final String id;
  final String name;
  final int sortOrder;
  final List<String> bookIds;
  final DateTime? updatedAt;

  factory ServerShelf.fromJson(Map<String, dynamic> j) => ServerShelf(
    id: j['id'] as String,
    name: j['name'] as String? ?? '',
    sortOrder: j['sort_order'] as int? ?? 0,
    bookIds: [for (final id in (j['book_ids'] as List? ?? const [])) id as String],
    updatedAt: ServerBook._parseServerTime(j['updated_at'] as String?),
  );
}

/// A physical copy from the server (plan 5 #4). No owner of its own — access
/// derives from [bookId]'s book.
class ServerCopy {
  ServerCopy({
    required this.id,
    required this.bookId,
    this.location,
    this.condition,
    this.notes,
    this.updatedAt,
  });

  final String id;
  final String bookId;
  final String? location;
  final String? condition;
  final String? notes;
  final DateTime? updatedAt;

  factory ServerCopy.fromJson(Map<String, dynamic> j) => ServerCopy(
    id: j['id'] as String,
    bookId: j['book_id'] as String,
    location: j['location'] as String?,
    condition: j['condition'] as String?,
    notes: j['notes'] as String?,
    updatedAt: ServerBook._parseServerTime(j['updated_at'] as String?),
  );
}

/// A loan from the server (plan 5 #4). No owner of its own — access derives
/// from its copy's book.
class ServerLoan {
  ServerLoan({
    required this.id,
    required this.copyId,
    required this.borrower,
    required this.loanedAt,
    this.returnedAt,
    this.updatedAt,
  });

  final String id;
  final String copyId;
  final String borrower;
  final DateTime loanedAt;
  final DateTime? returnedAt;
  final DateTime? updatedAt;

  factory ServerLoan.fromJson(Map<String, dynamic> j) => ServerLoan(
    id: j['id'] as String,
    copyId: j['copy_id'] as String,
    borrower: j['borrower'] as String? ?? '',
    loanedAt: ServerBook._parseServerTime(j['loaned_at'] as String?) ?? DateTime.now(),
    returnedAt: ServerBook._parseServerTime(j['returned_at'] as String?),
    updatedAt: ServerBook._parseServerTime(j['updated_at'] as String?),
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

/// The `sync_protocol` this app build understands (plan 5 #6). Bump only when
/// adopting a breaking server response-shape change; compared against
/// [Capabilities.syncProtocol] to show "this server is newer than the app"
/// instead of failing sync opaquely partway through.
const kKnownSyncProtocol = 1;

/// The server's `GET /api/capabilities` response: version info plus which
/// optional sync features it actually supports. Fetched once per connect and
/// cached on [ServerConnection] — see `connection_store.dart`.
class Capabilities {
  Capabilities({
    required this.serverVersion,
    required this.syncProtocol,
    required this.features,
  });

  final String serverVersion;
  final int syncProtocol;
  final List<String> features;

  bool hasFeature(String name) => features.contains(name);

  /// Whether this server speaks a newer sync protocol than this app build
  /// understands — the one case the app should say something about, rather
  /// than silently missing whatever changed.
  bool get isNewerThanApp => syncProtocol > kKnownSyncProtocol;

  factory Capabilities.fromJson(Map<String, dynamic> j) => Capabilities(
    serverVersion: j['server_version'] as String? ?? '',
    syncProtocol: j['sync_protocol'] as int? ?? 1,
    features: [
      for (final f in (j['features'] as List? ?? const [])) f.toString(),
    ],
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
