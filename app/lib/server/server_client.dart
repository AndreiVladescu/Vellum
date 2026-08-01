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
    this.series,
    this.seriesIndex,
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

  /// Series name and volume number (plan 5 #17), null when the book is in none.
  final String? series;
  final double? seriesIndex;

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
    series: j['series'] as String?,
    seriesIndex: (j['series_index'] as num?)?.toDouble(),
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

/// One book's push payload for [VellumServerClient.pushBooksBatch] — the same
/// fields [VellumServerClient.pushBook] takes, plus the id (a batch request
/// has no per-item URL to carry it).
class BookPushItem {
  BookPushItem({
    required this.id,
    required this.title,
    this.subtitle,
    this.description,
    this.isbn,
    this.publisher,
    this.publishedYear,
    this.pageCount,
    this.spineStyle,
    this.updatedAt,
    this.authors,
    this.genres,
    this.series,
    this.seriesIndex,
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
  final DateTime? updatedAt;
  final List<String>? authors;
  final List<String>? genres;
  final String? series;
  final double? seriesIndex;
}

/// One book's outcome from [VellumServerClient.pushBooksBatch] — mirrors the
/// server's per-item `status` (`'updated'`, `'skipped_older'`, or `'error'`).
class BatchPushResult {
  BatchPushResult({required this.status, this.message});

  final String status;
  final String? message;

  bool get isError => status == 'error';

  factory BatchPushResult.fromJson(Map<String, dynamic> j) => BatchPushResult(
    status: j['status'] as String? ?? 'error',
    message: j['message'] as String?,
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

  /// Borrow requests (plan 5 #49). [direction] is 'incoming' (to answer) or
  /// 'outgoing' (asked for).
  Future<List<BorrowRequest>> listBorrowRequests({
    String direction = 'incoming',
    String? status,
  }) async {
    final query = {'direction': direction};
    if (status != null) query['status'] = status;
    final uri = _uri('/api/borrow-requests').replace(queryParameters: query);
    final res = await _http.get(uri, headers: _headers);
    final body = _body(res) as List? ?? const [];
    return [
      for (final r in body) BorrowRequest.fromJson(r as Map<String, dynamic>),
    ];
  }

  Future<BorrowRequest> requestToBorrow({
    required String bookId,
    String? copyId,
    String? note,
  }) async {
    final res = await _http.post(
      _uri('/api/borrow-requests'),
      headers: {..._headers, 'content-type': 'application/json'},
      body: jsonEncode({
        'book_id': bookId,
        'copy_id': ?copyId,
        if (note != null && note.isNotEmpty) 'note': note,
      }),
    );
    return BorrowRequest.fromJson(_body(res) as Map<String, dynamic>);
  }

  /// Approve, decline or cancel. An approval creates the loan server-side.
  Future<BorrowRequest> decideBorrowRequest(
    String id, {
    required String status,
    String? reply,
    DateTime? dueAt,
  }) async {
    final res = await _http.post(
      _uri('/api/borrow-requests/$id/decide'),
      headers: {..._headers, 'content-type': 'application/json'},
      body: jsonEncode({
        'status': status,
        if (reply != null && reply.isNotEmpty) 'reply': reply,
        if (dueAt != null)
          'due_at': '${dueAt.year}-${dueAt.month.toString().padLeft(2, '0')}-'
              '${dueAt.day.toString().padLeft(2, '0')} 00:00:00',
      }),
    );
    return BorrowRequest.fromJson(_body(res) as Map<String, dynamic>);
  }

  /// Rooms this account can see: its own, plus any shared with it (plan 5 #47).
  Future<List<ServerLayout>> listLayouts() async {
    final res = await _http.get(_uri('/api/layouts'), headers: _headers);
    final body = _body(res) as List? ?? const [];
    return [
      for (final l in body) ServerLayout.fromJson(l as Map<String, dynamic>),
    ];
  }

  /// One room, document included.
  Future<ServerLayout> fetchLayout(String id) async {
    final res = await _http.get(_uri('/api/layouts/$id'), headers: _headers);
    return ServerLayout.fromJson(_body(res) as Map<String, dynamic>);
  }

  /// Titles for the books a published room mentions (next features #9).
  ///
  /// The room document is geometry only — deliberately, so publishing a room
  /// doesn't publish your catalogue — so a viewer that wants to label the
  /// spines has to ask. Returns `{book_id: title}`; ids the caller can't see
  /// are simply absent, which the viewer draws as an unnamed book rather than
  /// a gap.
  Future<Map<String, String>> fetchLayoutBookTitles(String id) async {
    final res = await _http.get(
      _uri('/api/layouts/$id/books'),
      headers: _headers,
    );
    final body = _body(res) as List? ?? const [];
    return {
      for (final b in body)
        if (b is Map && b['book_id'] is String)
          b['book_id'] as String: (b['title'] as String?) ?? 'Untitled',
    };
  }

  /// Publishes a room whole.
  ///
  /// [baseRevision] is the revision this device last saw; the server answers
  /// **409** if someone else published since, which surfaces as a
  /// [ServerException] with `statusCode == 409` for the caller to turn into a
  /// question rather than an overwrite.
  Future<ServerLayout> publishLayout({
    required String id,
    required String name,
    required int baseRevision,
    required Map<String, dynamic> doc,
  }) async {
    final res = await _http.put(
      _uri('/api/layouts/$id'),
      headers: {..._headers, 'content-type': 'application/json'},
      body: jsonEncode({
        'name': name,
        'base_revision': baseRevision,
        'doc': doc,
      }),
    );
    return ServerLayout.fromJson(_body(res) as Map<String, dynamic>);
  }

  Future<void> deleteLayout(String id) async {
    final res = await _http.delete(_uri('/api/layouts/$id'), headers: _headers);
    _body(res);
  }

  /// Starts a password reset (plan 5 #31).
  ///
  /// Unauthenticated, and the server answers the same whether or not the
  /// address exists — so the app must not phrase the result as confirmation
  /// that an account was found.
  Future<void> forgotPassword(String email) async {
    final res = await _http.post(
      _uri('/api/auth/forgot'),
      headers: const {'content-type': 'application/json'},
      body: jsonEncode({'email': email}),
    );
    _body(res);
  }

  /// Searches inside book *contents* (plan 5 #32).
  ///
  /// Only meaningful when the server advertises `content_search`; without the
  /// index it answers 400, which surfaces as a [ServerException] the caller
  /// turns into "this server doesn't do that" rather than an error.
  Future<List<ContentHit>> searchContents(String query, {int limit = 30}) async {
    final uri = _uri('/api/search').replace(
      queryParameters: {'q': query, 'limit': '$limit'},
    );
    final res = await _http.get(uri, headers: _headers);
    final body = _body(res);
    final hits = (body is Map ? body['hits'] as List? : null) ?? const [];
    return [
      for (final h in hits) ContentHit.fromJson(h as Map<String, dynamic>),
    ];
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

  /// The JSON body [pushBook] and [pushBooksBatch] both send for one book —
  /// factored out so the two can't drift on field names/shape.
  Map<String, dynamic> _bookPushJson({
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
    String? series,
    double? seriesIndex,
  }) => {
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
    // Series by *name* (plan 5 #17), same convention: omitted means "nothing to
    // say"; an empty string clears the membership.
    'series': ?series,
    'series_index': ?seriesIndex,
  };

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
    String? series,
    double? seriesIndex,
  }) async {
    final res = await _http.put(
      _uri('/api/books/$id'),
      headers: _headers,
      body: jsonEncode(_bookPushJson(
        title: title,
        subtitle: subtitle,
        description: description,
        isbn: isbn,
        publisher: publisher,
        publishedYear: publishedYear,
        pageCount: pageCount,
        spineStyle: spineStyle,
        updatedAt: updatedAt,
        authors: authors,
        genres: genres,
        series: series,
        seriesIndex: seriesIndex,
      )),
    );
    _body(res);
  }

  /// Batch sibling of [pushBook] (plan 5 #7): several books' metadata in one
  /// request, each with its own outcome, so a first sync of a large library
  /// isn't one HTTPS round trip per book. Only call this when the server
  /// advertises `batch_push` (see [Capabilities.hasFeature]) — an older
  /// server 404s on this route, and the caller should fall back to
  /// per-book [pushBook] instead of treating that as this batch's failure.
  Future<Map<String, BatchPushResult>> pushBooksBatch(
    List<BookPushItem> items,
  ) async {
    final res = await _http.post(
      _uri('/api/books:batch'),
      headers: _headers,
      body: jsonEncode({
        'books': [
          for (final it in items)
            {
              'id': it.id,
              ..._bookPushJson(
                title: it.title,
                subtitle: it.subtitle,
                description: it.description,
                isbn: it.isbn,
                publisher: it.publisher,
                publishedYear: it.publishedYear,
                pageCount: it.pageCount,
                spineStyle: it.spineStyle,
                updatedAt: it.updatedAt,
                authors: it.authors,
                genres: it.genres,
                series: it.series,
                seriesIndex: it.seriesIndex,
              ),
            },
        ],
      }),
    );
    final body = _body(res) as Map<String, dynamic>;
    return {
      for (final r in body['results'] as List)
        (r as Map<String, dynamic>)['id'] as String: BatchPushResult.fromJson(r),
    };
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

  /// Opens the live change-hint stream (plan 5 #8), decoded to lines.
  ///
  /// Takes the [http.Client] rather than using the shared one: an SSE response
  /// is held open indefinitely, and closing it is how the caller cancels — a
  /// shared client would have to stay alive for every other request too.
  Future<Stream<String>> openEventStream(http.Client httpClient) async {
    final request = http.Request('GET', _uri('/api/events'))
      ..headers.addAll({..._headers, 'accept': 'text/event-stream'});
    final response = await httpClient.send(request);
    if (response.statusCode != 200) {
      throw ServerException(
        'event stream unavailable (${response.statusCode})',
        statusCode: response.statusCode,
      );
    }
    return response.stream.transform(utf8.decoder).transform(const LineSplitter());
  }

  // ---- send to a device (plan 5 #53) --------------------------------------

  /// The caller's saved destination addresses.
  Future<List<SendTarget>> sendTargets() async {
    final res = await _http.get(_uri('/api/send-targets'), headers: _headers);
    return [
      for (final t in _body(res) as List)
        SendTarget.fromJson(t as Map<String, dynamic>),
    ];
  }

  /// Replaces the whole saved list.
  Future<List<SendTarget>> setSendTargets(List<SendTarget> targets) async {
    final res = await _http.put(
      _uri('/api/send-targets'),
      headers: {..._headers, 'content-type': 'application/json'},
      body: jsonEncode([for (final t in targets) t.toJson()]),
    );
    return [
      for (final t in _body(res) as List)
        SendTarget.fromJson(t as Map<String, dynamic>),
    ];
  }

  /// Emails one of a book's files to an e-reader. [to] is a literal address;
  /// [label] picks one of the saved targets instead.
  Future<String> sendBookToDevice(
    String bookId, {
    required String fileId,
    String? to,
    String? label,
  }) async {
    final res = await _http.post(
      _uri('/api/books/$bookId/send'),
      headers: {..._headers, 'content-type': 'application/json'},
      body: jsonEncode({
        'file_id': fileId,
        // Null-aware values: an absent field lets the server fall back to the
        // other way of naming the destination.
        'to': ?to,
        'label': ?label,
      }),
    );
    final body = _body(res) as Map<String, dynamic>;
    return body['sent_to'] as String? ?? '';
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
    DateTime? dueAt,
    String? borrowerContact,
    String? notes,
    DateTime? reminderSentAt,
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
        // Due dates, contacts and notes (plan 5 #27). Sent as explicit nulls,
        // not omitted: clearing a due date is a real edit, and omitting the
        // field would leave a stale date on the server forever.
        'due_at': formatServerTime(dueAt),
        'borrower_contact': borrowerContact,
        'notes': notes,
        'reminder_sent_at': formatServerTime(reminderSentAt),
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

  // ---- copy photos (plan 6 #4) --------------------------------------------
  //
  // Library data, so the split is the same as a book and its file: a row with
  // the caption, and the bytes separately. A metadata push then doesn't carry
  // megabytes, and a failed transfer doesn't lose the caption.

  Future<({String? serverNow, List<ServerCopyPhoto> entries})> listCopyPhotos({
    String? cursor,
  }) async {
    final uri = _uri('/api/copy-photos')
        .replace(queryParameters: {'cursor': cursor ?? ''});
    final map = _body(await _http.get(uri, headers: _headers))
        as Map<String, dynamic>;
    return (
      serverNow: map['server_now'] as String?,
      entries: [
        for (final e in (map['photos'] as List? ?? []))
          ServerCopyPhoto.fromJson(e as Map<String, dynamic>),
      ],
    );
  }

  Future<void> pushCopyPhoto({
    required String id,
    required String copyId,
    String? caption,
    DateTime? takenAt,
    DateTime? updatedAt,
  }) async {
    _body(await _http.put(
      _uri('/api/copy-photos/$id'),
      headers: _headers,
      body: jsonEncode({
        'copy_id': copyId,
        'caption': caption,
        'taken_at': formatServerTime(takenAt),
        'updated_at': formatServerTime(updatedAt),
      }),
    ));
  }

  Future<void> deleteCopyPhoto(String id) async {
    _body(await _http.delete(_uri('/api/copy-photos/$id'), headers: _headers));
  }

  Future<void> uploadCopyPhotoImage(String id, Uint8List bytes) async {
    _body(await _http.put(
      _uri('/api/copy-photos/$id/image'),
      headers: {..._headers, 'content-type': 'application/octet-stream'},
      body: bytes,
    ));
  }

  /// The photo's bytes, or null when the server has the row but not the image
  /// yet — the two are uploaded separately, so that gap is normal.
  Future<Uint8List?> downloadCopyPhotoImage(String id) async {
    final res =
        await _http.get(_uri('/api/copy-photos/$id/image'), headers: _headers);
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 400) _body(res);
    return res.bodyBytes;
  }

  // ---- personal data ------------------------------------------------------
  //
  // Annotations, sittings, private notes and the profile. Every one of these is
  // scoped server-side to the caller's account, so none of them takes a user
  // id: asking for someone else's is not something the API allows a client to
  // express.

  Future<({String? serverNow, List<ServerAnnotation> entries})> listAnnotations({
    String? cursor,
  }) async {
    final uri = _uri('/api/annotations')
        .replace(queryParameters: {'cursor': cursor ?? ''});
    final map = _body(await _http.get(uri, headers: _headers))
        as Map<String, dynamic>;
    return (
      serverNow: map['server_now'] as String?,
      entries: [
        for (final e in (map['entries'] as List? ?? []))
          ServerAnnotation.fromJson(e as Map<String, dynamic>),
      ],
    );
  }

  /// Annotation ids this account deleted, so a device stops showing them
  /// instead of pushing them back. Its own endpoint rather than the shared
  /// `/deletions` list — see `personal.rs`.
  Future<({String? serverNow, List<({String id, DateTime? deletedAt})> entries})>
      listAnnotationDeletions({String? cursor}) async {
    final uri = _uri('/api/annotations/deletions')
        .replace(queryParameters: {'cursor': cursor ?? ''});
    final map = _body(await _http.get(uri, headers: _headers))
        as Map<String, dynamic>;
    return (
      serverNow: map['server_now'] as String?,
      entries: [
        for (final e in (map['entries'] as List? ?? []))
          (
            id: (e as Map<String, dynamic>)['id'] as String,
            deletedAt: ServerBook._parseServerTime(e['deleted_at'] as String?),
          ),
      ],
    );
  }

  Future<void> pushAnnotation({
    required String id,
    required String bookId,
    required String kind,
    int? page,
    int? chapter,
    String? locator,
    String? quotedText,
    String? note,
    int? color,
    DateTime? createdAt,
    DateTime? updatedAt,
  }) async {
    final res = await _http.put(
      _uri('/api/annotations/$id'),
      headers: _headers,
      body: jsonEncode({
        'book_id': bookId,
        'kind': kind,
        // Explicit nulls, not omissions: clearing a note or a colour is a real
        // edit, and an omitted field would leave the old value on the server.
        'page': page,
        'chapter': chapter,
        'locator': locator,
        'quoted_text': quotedText,
        'note': note,
        'color': color,
        'created_at': formatServerTime(createdAt),
        'updated_at': formatServerTime(updatedAt),
      }),
    );
    _body(res);
  }

  Future<void> deleteAnnotation(String id) async {
    _body(await _http.delete(_uri('/api/annotations/$id'), headers: _headers));
  }

  Future<({String? serverNow, List<ServerSession> entries})> listSessions({
    String? cursor,
  }) async {
    final uri =
        _uri('/api/sessions').replace(queryParameters: {'cursor': cursor ?? ''});
    final map = _body(await _http.get(uri, headers: _headers))
        as Map<String, dynamic>;
    return (
      serverNow: map['server_now'] as String?,
      entries: [
        for (final e in (map['entries'] as List? ?? []))
          ServerSession.fromJson(e as Map<String, dynamic>),
      ],
    );
  }

  Future<void> pushSession({
    required String id,
    required String bookId,
    required DateTime startedAt,
    required DateTime endedAt,
    int? startPage,
    int? endPage,
    String? deviceId,
    String? deviceLabel,
  }) async {
    final res = await _http.put(
      _uri('/api/sessions/$id'),
      headers: _headers,
      body: jsonEncode({
        'book_id': bookId,
        'started_at': formatServerTime(startedAt),
        'ended_at': formatServerTime(endedAt),
        'start_page': startPage,
        'end_page': endPage,
        'device_id': deviceId,
        'device_label': deviceLabel,
      }),
    );
    _body(res);
  }

  Future<({String? serverNow, List<({String bookId, String note, DateTime? updatedAt})> entries})>
      listBookNotes({String? cursor}) async {
    final uri =
        _uri('/api/notes').replace(queryParameters: {'cursor': cursor ?? ''});
    final map = _body(await _http.get(uri, headers: _headers))
        as Map<String, dynamic>;
    return (
      serverNow: map['server_now'] as String?,
      entries: [
        for (final e in (map['entries'] as List? ?? []))
          (
            bookId: (e as Map<String, dynamic>)['book_id'] as String,
            note: e['note'] as String? ?? '',
            updatedAt: ServerBook._parseServerTime(e['updated_at'] as String?),
          ),
      ],
    );
  }

  Future<void> pushBookNote({
    required String bookId,
    required String note,
    DateTime? updatedAt,
  }) async {
    final res = await _http.put(
      _uri('/api/notes/$bookId'),
      headers: _headers,
      body: jsonEncode({
        'note': note,
        'updated_at': formatServerTime(updatedAt),
      }),
    );
    _body(res);
  }

  // ---- profile -------------------------------------------------------------

  Future<({String displayName, bool hasAvatar, DateTime? updatedAt})>
      fetchProfile() async {
    final map = _body(await _http.get(_uri('/api/profile'), headers: _headers))
        as Map<String, dynamic>;
    return (
      displayName: map['display_name'] as String? ?? '',
      hasAvatar: map['has_avatar'] == true || map['has_avatar'] == 1,
      updatedAt: ServerBook._parseServerTime(map['profile_updated_at'] as String?),
    );
  }

  Future<void> pushDisplayName(String displayName) async {
    _body(await _http.put(
      _uri('/api/profile'),
      headers: _headers,
      body: jsonEncode({'display_name': displayName}),
    ));
  }

  /// The avatar bytes, or null when the account has none.
  Future<Uint8List?> fetchAvatar() async {
    final res = await _http.get(_uri('/api/profile/avatar'), headers: _headers);
    if (res.statusCode == 404) return null;
    if (res.statusCode >= 400) _body(res);
    return res.bodyBytes;
  }

  Future<void> pushAvatar(Uint8List bytes) async {
    final res = await _http.put(
      _uri('/api/profile/avatar'),
      headers: {..._headers, 'content-type': 'application/octet-stream'},
      body: bytes,
    );
    _body(res);
  }

  Future<void> deleteAvatar() async {
    _body(await _http.delete(_uri('/api/profile/avatar'), headers: _headers));
  }

  // ---- reading position (plan 5 #5) ----------------------------------------

  /// This account's reading positions across all its devices, as the delta-pull
  /// envelope `{ server_now, entries }` — same cursor convention as
  /// [listShelves]. The server only ever returns the caller's own rows.
  Future<({String? serverNow, List<ServerReadingPosition> entries})>
      listReadingPositions({String? cursor}) async {
    final uri = _uri(
      '/api/reading-progress',
    ).replace(queryParameters: {'cursor': cursor ?? ''});
    final res = await _http.get(uri, headers: _headers);
    final map = _body(res) as Map<String, dynamic>;
    return (
      serverNow: map['server_now'] as String?,
      entries: [
        for (final e in map['entries'] as List)
          ServerReadingPosition.fromJson(e as Map<String, dynamic>),
      ],
    );
  }

  /// Publish this device's position in [bookId]. Not an LWW push: the row is
  /// keyed by device, so this only ever overwrites what *this* device last
  /// said. [unit] must be `'page'` or `'chapter'` — what [page] counts.
  Future<void> pushReadingPosition(
    String bookId, {
    required String deviceId,
    String? deviceLabel,
    double? progress,
    int? page,
    String? unit,
    double? scroll,
    DateTime? updatedAt,
  }) async {
    final res = await _http.put(
      _uri('/api/reading-progress/$bookId'),
      headers: _headers,
      body: jsonEncode({
        'device_id': deviceId,
        'device_label': deviceLabel,
        'progress': progress,
        'page': page,
        'unit': unit,
        'scroll': scroll,
        'updated_at': ?formatServerTime(updatedAt),
      }),
    );
    _body(res);
  }

  /// Un-publish every position this device ever sent, for this account only.
  /// What the "Sync reading position" switch calls on its way off, so turning
  /// the feature off removes what turning it on published.
  Future<void> forgetReadingPositions(String deviceId) async {
    final uri = _uri(
      '/api/reading-progress',
    ).replace(queryParameters: {'device_id': deviceId});
    final res = await _http.delete(uri, headers: _headers);
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

/// One device's reading position in one book (plan 5 #5). Always this
/// account's own — the server never returns another user's row, so there is no
/// user field to carry.
/// A photo of a physical copy, as the server holds it.
class ServerCopyPhoto {
  ServerCopyPhoto({
    required this.id,
    required this.copyId,
    this.caption,
    this.takenAt,
    this.updatedAt,
  });

  factory ServerCopyPhoto.fromJson(Map<String, dynamic> json) => ServerCopyPhoto(
        id: json['id'] as String,
        copyId: json['copy_id'] as String,
        caption: json['caption'] as String?,
        takenAt: ServerBook._parseServerTime(json['taken_at'] as String?),
        updatedAt: ServerBook._parseServerTime(json['updated_at'] as String?),
      );

  final String id;
  final String copyId;
  final String? caption;
  final DateTime? takenAt;
  final DateTime? updatedAt;
}

/// One of the caller's annotations as the server holds it.
class ServerAnnotation {
  ServerAnnotation({
    required this.id,
    required this.bookId,
    required this.kind,
    this.page,
    this.chapter,
    this.locator,
    this.quotedText,
    this.note,
    this.color,
    this.createdAt,
    this.updatedAt,
  });

  factory ServerAnnotation.fromJson(Map<String, dynamic> json) =>
      ServerAnnotation(
        id: json['id'] as String,
        bookId: json['book_id'] as String,
        kind: json['kind'] as String,
        page: (json['page'] as num?)?.toInt(),
        chapter: (json['chapter'] as num?)?.toInt(),
        locator: json['locator'] as String?,
        quotedText: json['quoted_text'] as String?,
        note: json['note'] as String?,
        color: (json['color'] as num?)?.toInt(),
        createdAt: ServerBook._parseServerTime(json['created_at'] as String?),
        updatedAt: ServerBook._parseServerTime(json['updated_at'] as String?),
      );

  final String id;
  final String bookId;
  final String kind;
  final int? page;
  final int? chapter;
  final String? locator;
  final String? quotedText;
  final String? note;
  final int? color;
  final DateTime? createdAt;
  final DateTime? updatedAt;
}

/// One reading sitting as the server holds it. Immutable, so there is no
/// `updatedAt` to compare — only the id decides whether it is already known.
class ServerSession {
  ServerSession({
    required this.id,
    required this.bookId,
    required this.startedAt,
    required this.endedAt,
    this.startPage,
    this.endPage,
    this.deviceId,
    this.deviceLabel,
  });

  factory ServerSession.fromJson(Map<String, dynamic> json) => ServerSession(
        id: json['id'] as String,
        bookId: json['book_id'] as String,
        startedAt: ServerBook._parseServerTime(json['started_at'] as String?) ?? DateTime.now(),
        endedAt: ServerBook._parseServerTime(json['ended_at'] as String?) ?? DateTime.now(),
        startPage: (json['start_page'] as num?)?.toInt(),
        endPage: (json['end_page'] as num?)?.toInt(),
        deviceId: json['device_id'] as String?,
        deviceLabel: json['device_label'] as String?,
      );

  final String id;
  final String bookId;
  final DateTime startedAt;
  final DateTime endedAt;
  final int? startPage;
  final int? endPage;
  final String? deviceId;
  final String? deviceLabel;
}

class ServerReadingPosition {
  ServerReadingPosition({
    required this.bookId,
    required this.deviceId,
    this.deviceLabel,
    this.progress,
    this.page,
    this.unit,
    this.scroll,
    this.updatedAt,
  });

  final String bookId;
  final String deviceId;
  final String? deviceLabel;
  final double? progress;
  final int? page;

  /// What [page] counts: `'page'` (PDF) or `'chapter'` (EPUB). Travels with the
  /// row because another device may have read a different format.
  final String? unit;
  final double? scroll;
  final DateTime? updatedAt;

  factory ServerReadingPosition.fromJson(Map<String, dynamic> j) =>
      ServerReadingPosition(
        bookId: j['book_id'] as String,
        deviceId: j['device_id'] as String,
        deviceLabel: j['device_label'] as String?,
        progress: (j['progress'] as num?)?.toDouble(),
        page: (j['page'] as num?)?.toInt(),
        unit: j['unit'] as String?,
        scroll: (j['scroll'] as num?)?.toDouble(),
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
    this.dueAt,
    this.borrowerContact,
    this.notes,
    this.reminderSentAt,
  });

  final String id;
  final String copyId;
  final String borrower;
  final DateTime loanedAt;
  final DateTime? returnedAt;
  final DateTime? updatedAt;

  /// Due date, contact and notes (plan 5 #27).
  final DateTime? dueAt;
  final String? borrowerContact;
  final String? notes;
  final DateTime? reminderSentAt;

  factory ServerLoan.fromJson(Map<String, dynamic> j) => ServerLoan(
    id: j['id'] as String,
    copyId: j['copy_id'] as String,
    borrower: j['borrower'] as String? ?? '',
    loanedAt: ServerBook._parseServerTime(j['loaned_at'] as String?) ?? DateTime.now(),
    returnedAt: ServerBook._parseServerTime(j['returned_at'] as String?),
    dueAt: ServerBook._parseServerTime(j['due_at'] as String?),
    borrowerContact: j['borrower_contact'] as String?,
    notes: j['notes'] as String?,
    reminderSentAt: ServerBook._parseServerTime(j['reminder_sent_at'] as String?),
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

/// Someone asking to borrow a book (plan 5 #49).
class BorrowRequest {
  const BorrowRequest({
    required this.id,
    required this.bookId,
    required this.bookTitle,
    required this.requesterEmail,
    required this.status,
    required this.createdAt,
    this.note,
    this.reply,
    this.copyId,
  });

  final String id;
  final String bookId;
  final String bookTitle;
  final String requesterEmail;

  /// 'pending' | 'approved' | 'declined' | 'cancelled'.
  final String status;
  final String createdAt;
  final String? note;
  final String? reply;
  final String? copyId;

  bool get isPending => status == 'pending';

  factory BorrowRequest.fromJson(Map<String, dynamic> j) => BorrowRequest(
        id: j['id'] as String,
        bookId: j['book_id'] as String,
        bookTitle: (j['book_title'] as String?) ?? 'A book',
        requesterEmail: (j['requester_email'] as String?) ?? 'someone',
        status: (j['status'] as String?) ?? 'pending',
        createdAt: (j['created_at'] as String?) ?? '',
        note: j['note'] as String?,
        reply: j['reply'] as String?,
        copyId: j['copy_id'] as String?,
      );
}

/// A published room (plan 5 #47), with its document when fetched singly.
class ServerLayout {
  const ServerLayout({
    required this.id,
    required this.name,
    required this.revision,
    required this.publishedAt,
    required this.mine,
    this.doc,
  });

  final String id;
  final String name;
  final int revision;
  final String publishedAt;

  /// Whether this account owns it — a shared room can be fetched but not
  /// published over.
  final bool mine;

  /// The `layout_doc` JSON. Null in a list response, which carries only the
  /// summary.
  final Map<String, dynamic>? doc;

  factory ServerLayout.fromJson(Map<String, dynamic> j) => ServerLayout(
        id: j['id'] as String,
        name: (j['name'] as String?) ?? 'Room',
        revision: (j['revision'] as num?)?.toInt() ?? 0,
        publishedAt: (j['published_at'] as String?) ?? '',
        mine: j['mine'] == true,
        doc: j['doc'] is Map ? (j['doc'] as Map).cast<String, dynamic>() : null,
      );
}

/// One hit from `GET /api/search` (plan 5 #32): where in which book, and the
/// surrounding text with the match marked.
class ContentHit {
  const ContentHit({
    required this.bookId,
    required this.title,
    required this.fileId,
    required this.page,
    required this.snippet,
  });

  final String bookId;
  final String title;
  final String fileId;

  /// The PDF page, or — for an EPUB, which has no pages — the 1-based spine
  /// section. The app labels it accordingly rather than claiming a page number
  /// a reflowable book doesn't have.
  final int page;

  /// Text around the match, with the matched words wrapped in `[` and `]` by
  /// FTS5's `snippet()`.
  final String snippet;

  factory ContentHit.fromJson(Map<String, dynamic> j) => ContentHit(
        bookId: j['book_id'] as String,
        title: (j['title'] as String?) ?? 'Untitled',
        fileId: (j['file_id'] as String?) ?? '',
        page: (j['page'] as num?)?.toInt() ?? 1,
        snippet: (j['snippet'] as String?) ?? '',
      );
}

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

/// A saved send-to-device address (plan 5 #53) — "My Kindle".
class SendTarget {
  const SendTarget({required this.label, required this.address});

  factory SendTarget.fromJson(Map<String, dynamic> json) => SendTarget(
        label: json['label'] as String? ?? '',
        address: json['address'] as String? ?? '',
      );

  final String label;
  final String address;

  Map<String, dynamic> toJson() => {'label': label, 'address': address};
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
