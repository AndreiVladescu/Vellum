import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

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

  /// The one book behind a scanned barcode, or null if neither source knows it
  /// (plan 5 #16).
  ///
  /// Same Open-Library-then-Google order as [search], but ISBN-qualified on both
  /// sides and reduced to a single result: a barcode identifies one edition, so
  /// presenting a list of twenty would just be a worse confirm step. Returns
  /// null rather than throwing when nothing matches — "not found" is an ordinary
  /// outcome that the caller answers with the manual form.
  Future<BookSearchResult?> lookupByIsbn(String isbn13) async {
    List<BookSearchResult> results = const [];
    try {
      results = await _openLibrary.searchByIsbn(isbn13);
    } catch (_) {
      // Fall through to Google Books.
    }
    if (results.isEmpty) {
      try {
        results = await _googleBooks.searchByIsbn(isbn13);
      } catch (_) {
        return null;
      }
    }
    return results.firstOrNull;
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
