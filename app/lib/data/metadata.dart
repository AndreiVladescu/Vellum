import 'dart:convert';
import 'dart:typed_data';

import 'package:http/http.dart' as http;

/// One edition/work found by an online metadata search.
class BookSearchResult {
  const BookSearchResult({
    required this.workKey,
    required this.title,
    this.subtitle,
    this.authors = const [],
    this.firstPublishYear,
    this.isbn,
    this.coverId,
    this.subjects = const [],
    this.publisher,
    this.pageCount,
  });

  /// Open Library work key, e.g. "/works/OL45883W".
  final String workKey;
  final String title;
  final String? subtitle;
  final List<String> authors;
  final int? firstPublishYear;
  final String? isbn;
  final int? coverId;
  final List<String> subjects;
  final String? publisher;
  final int? pageCount;

  String get authorLine => authors.isEmpty ? 'Unknown author' : authors.join(', ');

  /// Small cover for search result lists.
  Uri? get thumbnailUrl => coverId == null
      ? null
      : Uri.parse('https://covers.openlibrary.org/b/id/$coverId-M.jpg');

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
}

/// Client for the Open Library APIs (https://openlibrary.org/developers/api).
/// Free, no API key. Google Books can be added later as a fallback source.
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

  /// Downloads the large cover image, or null if there is none / it fails.
  Future<Uint8List?> downloadCover(int? coverId) async {
    if (coverId == null) return null;
    final res = await _http
        .get(Uri.parse('https://covers.openlibrary.org/b/id/$coverId-L.jpg'));
    if (res.statusCode != 200 || res.bodyBytes.isEmpty) return null;
    return res.bodyBytes;
  }
}
