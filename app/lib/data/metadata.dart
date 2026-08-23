import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

import '../add_book/isbn.dart';

/// One edition/work found by an online metadata search. The same shape is
/// produced by every source (Open Library, Google Books), so the rest of the
/// app doesn't care where a result came from.
class BookSearchResult {
  const BookSearchResult({
    required this.workKey,
    required this.title,
    this.subtitle,
    this.authors = const [],
    this.firstPublishYear,
    this.isbn,
    this.coverId,
    this.coverUrl,
    this.description,
    this.subjects = const [],
    this.publisher,
    this.pageCount,
  });

  /// Open Library work key, e.g. "/works/OL45883W". Empty for other sources;
  /// used to fetch the full description lazily (see [OpenLibraryClient]).
  final String workKey;
  final String title;
  final String? subtitle;
  final List<String> authors;
  final int? firstPublishYear;
  final String? isbn;

  /// Open Library cover id (its covers are addressed by numeric id).
  final int? coverId;

  /// A ready-made cover image URL, used by sources that hand back a link
  /// rather than an id (Google Books). Takes precedence over [coverId].
  final Uri? coverUrl;

  /// Description, when the source returns it inline (Google Books does;
  /// Open Library needs a second request — see [MetadataService.descriptionOf]).
  final String? description;

  final List<String> subjects;
  final String? publisher;
  final int? pageCount;

  String get authorLine => authors.isEmpty ? 'Unknown author' : authors.join(', ');

  /// Small cover for search result lists.
  Uri? get thumbnailUrl {
    if (coverId != null) {
      return Uri.parse('https://covers.openlibrary.org/b/id/$coverId-M.jpg');
    }
    return coverUrl;
  }

  /// Full-size cover to store with the book, or null if none is known.
  Uri? get largeCoverUrl {
    if (coverId != null) {
      return Uri.parse('https://covers.openlibrary.org/b/id/$coverId-L.jpg');
    }
    return coverUrl;
  }

  /// Open Library's *books* API (`/api/books?jscmd=data`), which answers from
  /// the edition records rather than the search index — see
  /// [OpenLibraryClient.lookupEdition] for why that is a different question.
  /// The same result under the barcode that was scanned. A lookup may have
  /// succeeded against the ISBN-10 form, but the book is stored under the
  /// 13-digit one — that is the key duplicate detection and search use.
  BookSearchResult withIsbn(String isbn13) => BookSearchResult(
        workKey: workKey,
        title: title,
        subtitle: subtitle,
        authors: authors,
        firstPublishYear: firstPublishYear,
        isbn: isbn13,
        coverId: coverId,
        coverUrl: coverUrl,
        description: description,
        subjects: subjects,
        publisher: publisher,
        pageCount: pageCount,
      );

  factory BookSearchResult.fromOpenLibraryData(
    Map<String, dynamic> data, {
    required String isbn,
  }) {
    List<String> names(dynamic v) => v is List
        ? [
            for (final e in v)
              if (e is Map && e['name'] is String) e['name'] as String,
          ]
        : const [];
    final cover = data['cover'];
    final coverUrl = cover is Map ? (cover['large'] ?? cover['medium']) : null;
    // "1990" or "March 1990" or "1990-03-01": the year is the part every one
    // of those has, and the only part this app shows.
    final year = RegExp(r'\d{4}').firstMatch('${data['publish_date'] ?? ''}');
    return BookSearchResult(
      workKey: '',
      title: (data['title'] as String?) ?? '',
      subtitle: data['subtitle'] as String?,
      authors: names(data['authors']),
      firstPublishYear: year == null ? null : int.tryParse(year.group(0)!),
      isbn: isbn,
      coverUrl: coverUrl is String ? Uri.tryParse(coverUrl) : null,
      subjects: names(data['subjects']),
      publisher: names(data['publishers']).firstOrNull,
      pageCount: (data['number_of_pages'] as num?)?.toInt(),
    );
  }

  factory BookSearchResult.fromOpenLibraryDoc(Map<String, dynamic> doc) {
    List<String> strings(dynamic v) =>
        v is List ? v.whereType<String>().toList() : const [];
    return BookSearchResult(
      workKey: doc['key'] as String? ?? '',
      title: doc['title'] as String? ?? '',
      subtitle: doc['subtitle'] as String?,
      authors: strings(doc['author_name']),
      firstPublishYear: doc['first_publish_year'] as int?,
      isbn: strings(doc['isbn']).firstOrNull,
      coverId: doc['cover_i'] as int?,
      subjects: strings(doc['subject']),
      publisher: strings(doc['publisher']).firstOrNull,
      pageCount: doc['number_of_pages_median'] as int?,
    );
  }

  factory BookSearchResult.fromGoogleVolume(Map<String, dynamic> volume) {
    final info =
        volume['volumeInfo'] as Map<String, dynamic>? ?? const {};
    List<String> strings(dynamic v) =>
        v is List ? v.whereType<String>().toList() : const [];

    // Published date is "2003", "2003-05" or "2003-05-17"; take the year.
    int? year;
    final published = info['publishedDate'] as String?;
    if (published != null && published.length >= 4) {
      year = int.tryParse(published.substring(0, 4));
    }

    // Prefer an ISBN-13, else whatever identifier is present.
    String? isbn;
    final ids = info['industryIdentifiers'] as List? ?? const [];
    for (final id in ids.whereType<Map<String, dynamic>>()) {
      final value = id['identifier'] as String?;
      if (value == null) continue;
      isbn ??= value;
      if (id['type'] == 'ISBN_13') {
        isbn = value;
        break;
      }
    }

    final links = info['imageLinks'] as Map<String, dynamic>? ?? const {};
    final thumb = (links['thumbnail'] ?? links['smallThumbnail']) as String?;

    return BookSearchResult(
      workKey: '',
      title: info['title'] as String? ?? '',
      subtitle: info['subtitle'] as String?,
      authors: strings(info['authors']),
      firstPublishYear: year,
      isbn: isbn,
      // Google serves covers over http by default; force https for the CSP.
      coverUrl: thumb == null
          ? null
          : Uri.parse(thumb.replaceFirst('http://', 'https://')),
      description: info['description'] as String?,
      subjects: strings(info['categories']),
      publisher: info['publisher'] as String?,
      pageCount: info['pageCount'] as int?,
    );
  }
}

/// Client for the Open Library APIs (https://openlibrary.org/developers/api).
/// Free, no API key.
class OpenLibraryClient {
  OpenLibraryClient([http.Client? client]) : _http = client ?? http.Client();

  final http.Client _http;

  /// Searches works by free text (title, author, or ISBN all work).
  Future<List<BookSearchResult>> search(String query) async {
    final uri = Uri.https('openlibrary.org', '/search.json', {
      'q': query,
      'fields': 'key,title,subtitle,author_name,first_publish_year,isbn,'
          'cover_i,subject,publisher,number_of_pages_median',
      'limit': '20',
    });
    final res = await _http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Open Library search failed (HTTP ${res.statusCode})');
    }
    final docs = (jsonDecode(res.body)['docs'] as List? ?? const [])
        .whereType<Map<String, dynamic>>();
    return [
      for (final doc in docs)
        if ((doc['title'] as String?)?.isNotEmpty ?? false)
          BookSearchResult.fromOpenLibraryDoc(doc),
    ];
  }

  /// Looks a book up by its ISBN specifically (plan 5 #16).
  ///
  /// `isbn:<n>` rather than the bare number as free text: a plain numeric query
  /// also matches works that merely *mention* the digits, which for a barcode
  /// scan means confidently attaching the wrong book.
  Future<List<BookSearchResult>> searchByIsbn(String isbn13) =>
      search('isbn:$isbn13');

  /// One edition, straight from the edition record.
  ///
  /// A different question from [searchByIsbn], and that is the point: the
  /// search index only knows editions that made it into a *work*, while this
  /// answers from the edition itself. A book catalogued by a library or added
  /// by an importer — which is most of the ones a barcode finds nothing for —
  /// is often present here and absent there.
  Future<BookSearchResult?> lookupEdition(String isbn) async {
    final uri = Uri.https('openlibrary.org', '/api/books', {
      'bibkeys': 'ISBN:$isbn',
      'format': 'json',
      'jscmd': 'data',
    });
    final res = await _http.get(uri);
    if (res.statusCode != 200) return null;
    final body = jsonDecode(res.body);
    if (body is! Map) return null;
    final data = body['ISBN:$isbn'];
    if (data is! Map<String, dynamic>) return null;
    final result = BookSearchResult.fromOpenLibraryData(data, isbn: isbn);
    return result.title.isEmpty ? null : result;
  }

  /// The work's description is not in search results; fetch it separately.
  Future<String?> fetchDescription(String workKey) async {
    if (workKey.isEmpty) return null;
    final res = await _http.get(Uri.https('openlibrary.org', '$workKey.json'));
    if (res.statusCode != 200) return null;
    final desc = (jsonDecode(res.body) as Map<String, dynamic>)['description'];
    if (desc is String) return desc;
    if (desc is Map && desc['value'] is String) return desc['value'] as String;
    return null;
  }
}

/// Client for the Google Books API (https://developers.google.com/books).
/// Free for public volume search, no API key required for basic queries.
class GoogleBooksClient {
  GoogleBooksClient([http.Client? client]) : _http = client ?? http.Client();

  final http.Client _http;

  /// Google Books' own ISBN-qualified search — the fallback for a scan when
  /// Open Library doesn't have the edition.
  Future<List<BookSearchResult>> searchByIsbn(String isbn13) =>
      search('isbn:$isbn13');

  Future<List<BookSearchResult>> search(String query) async {
    final uri = Uri.https('www.googleapis.com', '/books/v1/volumes', {
      'q': query,
      'maxResults': '20',
      'printType': 'books',
    });
    final res = await _http.get(uri);
    if (res.statusCode != 200) {
      throw Exception('Google Books search failed (HTTP ${res.statusCode})');
    }
    final items = (jsonDecode(res.body)['items'] as List? ?? const [])
        .whereType<Map<String, dynamic>>();
    return [
      for (final item in items)
        if ((((item['volumeInfo'] as Map?)?['title']) as String?)?.isNotEmpty ??
            false)
          BookSearchResult.fromGoogleVolume(item),
    ];
  }
}

/// Combines the metadata sources per DESIGN.md: query Open Library first
/// (free, no key), fall back to Google Books when it has nothing (or is down).
/// Downloading covers and resolving descriptions is source-agnostic.
class MetadataService {
  MetadataService({
    OpenLibraryClient? openLibrary,
    GoogleBooksClient? googleBooks,
    http.Client? client,
  })  : _openLibrary = openLibrary ?? OpenLibraryClient(client),
        _googleBooks = googleBooks ?? GoogleBooksClient(client),
        _http = client ?? http.Client();

  final OpenLibraryClient _openLibrary;
  final GoogleBooksClient _googleBooks;
  final http.Client _http;

  /// Open Library first; Google Books only if Open Library returns nothing or
  /// errors out — so a working primary source is never blocked by the fallback.
  Future<List<BookSearchResult>> search(String query) async {
    List<BookSearchResult> openLibraryResults = const [];
    try {
      openLibraryResults = await _openLibrary.search(query);
    } catch (_) {
      // Fall through to Google Books below.
    }
    if (openLibraryResults.isNotEmpty) return openLibraryResults;
    return _googleBooks.search(query);
  }

  /// The one book behind a scanned barcode, or null if nothing knows it
  /// (plan 5 #16).
  ///
  /// Reduced to a single result: a barcode identifies one edition, so a list of
  /// twenty would only be a worse confirm step. Returns null rather than
  /// throwing when nothing matches — "not found" is an ordinary outcome the
  /// caller answers with the manual form.
  ///
  /// **Why it asks so many times.** A book that "isn't in the database" usually
  /// is, under a different key. Each of these finds books the others don't:
  ///
  ///  * Open Library's *search* index — good coverage, but only editions that
  ///    were folded into a work.
  ///  * Google Books — a different catalogue entirely, and better on recent and
  ///    non-English printings.
  ///  * Open Library's *edition* record — the same library, a different index;
  ///    imported and library-catalogued editions live here and nowhere else.
  ///  * All three again against the **ISBN-10** form. Records made before 2007
  ///    are keyed by it, and plenty were never re-indexed, so the ten-digit
  ///    form of the barcode on the back of the book finds what the barcode
  ///    itself does not.
  ///
  /// The order is cheapest-and-likeliest first, and it stops at the first hit,
  /// so the common case is still one request.
  Future<BookSearchResult?> lookupByIsbn(String isbn13) async {
    final forms = <String>[isbn13, ?isbn13To10(isbn13)];
    for (final isbn in forms) {
      for (final attempt in <Future<List<BookSearchResult>> Function()>[
        () => _openLibrary.searchByIsbn(isbn),
        () => _googleBooks.searchByIsbn(isbn),
        () async {
          final edition = await _openLibrary.lookupEdition(isbn);
          return edition == null ? const [] : [edition];
        },
      ]) {
        try {
          // A source that hangs must not hold the scanner: six catalogues with
          // no deadline is a scan that never comes back.
          final results = await attempt().timeout(const Duration(seconds: 8));
          // Whatever the source was asked about, record the *barcode* on the
          // book: it is the key the rest of the app dedupes and searches by.
          final hit = results.firstOrNull;
          if (hit != null) return hit.withIsbn(isbn13);
        } catch (_) {
          // A source that is down or rate-limiting is not an answer; ask the
          // next one rather than failing the scan.
        }
      }
    }
    return null;
  }

  /// The description for a chosen result: inline when the source supplied one
  /// (Google Books), otherwise fetched from Open Library by its work key.
  Future<String?> descriptionOf(BookSearchResult result) async {
    if (result.description != null) return result.description;
    return _openLibrary.fetchDescription(result.workKey);
  }

  /// Downloads the full-size cover for a result, or null if there is none /
  /// it fails.
  Future<Uint8List?> downloadCover(BookSearchResult result) async {
    final url = result.largeCoverUrl;
    if (url == null) return null;
    final res = await _http.get(url);
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    return res.bodyBytes;
  }
}
