import 'package:http/http.dart' as http;
import 'package:xml/xml.dart';

import 'catalog_entry.dart';

/// A minimal OPDS 1.x client (plan 5 #21c).
///
/// Vellum already *serves* OPDS (plan 5 #34); this makes it a citizen of that
/// ecosystem rather than only a supplier to it — including pointing one Vellum
/// at another. OPDS 1.x is Atom, so this is an XML walk rather than a protocol
/// implementation, which is exactly why it is worth having: a few hundred lines
/// buys interoperability with Calibre-Web, Kavita, Komga, Standard Ebooks and
/// every other catalogue in the ecosystem.
///
/// Deliberately **1.x only**. OPDS 2.0 is a different (JSON) format with far
/// less deployment; the 1.x feed is what servers actually publish, and adding
/// 2.0 before anyone asks would be building for a hypothesis.

/// A link off a feed or an entry.
class OpdsLink {
  const OpdsLink({required this.href, this.rel, this.type, this.title});

  final String href;
  final String? rel;
  final String? type;
  final String? title;

  /// Whether this link downloads the book itself, as opposed to navigating.
  bool get isAcquisition =>
      rel != null && rel!.contains('http://opds-spec.org/acquisition');

  bool get isImage =>
      rel != null &&
      rel!.contains('http://opds-spec.org/image') &&
      !rel!.contains('thumbnail');

  bool get isThumbnail =>
      rel != null && rel!.contains('http://opds-spec.org/image/thumbnail');

  /// The file extension this link's media type implies, or null when it is not
  /// something the app can open.
  String? get format => switch (type) {
        final String t when t.startsWith('application/epub') => 'epub',
        final String t when t.startsWith('application/pdf') => 'pdf',
        _ => null,
      };
}

/// One `<entry>`: either a book to acquire or a sub-feed to browse into.
class OpdsEntry {
  const OpdsEntry({
    required this.id,
    required this.title,
    required this.links,
    this.authors = const [],
    this.summary,
    this.publisher,
    this.language,
    this.categories = const [],
    this.issued,
    this.identifier,
  });

  final String id;
  final String title;
  final List<String> authors;
  final String? summary;
  final String? publisher;
  final String? language;
  final List<String> categories;
  final String? issued;
  final String? identifier;
  final List<OpdsLink> links;

  /// Downloadable files the app can actually open.
  List<OpdsLink> get acquisitions =>
      [for (final l in links) if (l.isAcquisition && l.format != null) l];

  /// A navigation link, for an entry that is a sub-catalogue rather than a
  /// book. An entry with no acquisition and one plain link is a folder.
  String? get navigationHref {
    if (acquisitions.isNotEmpty) return null;
    for (final l in links) {
      if (l.type?.contains('type=feed') ?? false) return l.href;
      if (l.rel == 'subsection' || l.rel == 'http://opds-spec.org/sort/new') {
        return l.href;
      }
    }
    // A lone link with no acquisition rel is, in practice, a sub-feed.
    return links.length == 1 && !links.first.isAcquisition
        ? links.first.href
        : null;
  }

  String? get coverHref {
    for (final l in links) {
      if (l.isImage) return l.href;
    }
    for (final l in links) {
      if (l.isThumbnail) return l.href;
    }
    return null;
  }

  bool get isBook => acquisitions.isNotEmpty;

  /// This entry as an import row. Metadata only — the file, if the user wants
  /// it, is fetched separately by [OpdsClient.download].
  CatalogEntry toCatalogEntry() => CatalogEntry(
        title: title,
        authors: authors,
        description: summary,
        publisher: publisher,
        isbn: _isbnOf(identifier),
        year: _yearOf(issued),
        genres: categories,
        sourceId: id,
      );

  static String? _isbnOf(String? identifier) {
    if (identifier == null) return null;
    final digits =
        identifier.replaceAll(RegExp(r'[^0-9Xx]'), '').toUpperCase();
    return (digits.length == 10 || digits.length == 13) ? digits : null;
  }

  static int? _yearOf(String? issued) {
    if (issued == null || issued.isEmpty) return null;
    final match = RegExp(r'\b(\d{4})\b').firstMatch(issued);
    final year = match == null ? null : int.tryParse(match.group(1)!);
    return (year == null || year < 500) ? null : year;
  }
}

/// One page of a catalogue.
class OpdsFeed {
  const OpdsFeed({
    required this.title,
    required this.entries,
    this.nextHref,
    this.searchHref,
  });

  final String title;
  final List<OpdsEntry> entries;

  /// `rel="next"`, for a paged catalogue. Following it is the caller's choice —
  /// a catalogue can be very large, and fetching it all to show a list would
  /// be the wrong default.
  final String? nextHref;

  /// An OpenSearch description, when the catalogue advertises one.
  final String? searchHref;

  List<OpdsEntry> get books => [for (final e in entries) if (e.isBook) e];
  List<OpdsEntry> get folders =>
      [for (final e in entries) if (!e.isBook) e];
}

class OpdsException implements Exception {
  const OpdsException(this.message);

  final String message;

  @override
  String toString() => message;
}

class OpdsClient {
  OpdsClient({http.Client? httpClient}) : _http = httpClient ?? http.Client();

  final http.Client _http;

  /// A cap on a feed body. A catalogue is XML describing books; anything this
  /// large is either a mistake or hostile, and parsing it would take the app
  /// down with it.
  static const maxFeedBytes = 8 * 1024 * 1024;

  void close() => _http.close();

  /// Fetches and parses the feed at [url].
  Future<OpdsFeed> fetch(Uri url) async {
    final http.Response response;
    try {
      response = await _http.get(url, headers: const {
        'Accept': 'application/atom+xml, application/xml;q=0.8, */*;q=0.5',
      });
    } catch (e) {
      throw OpdsException('Could not reach that catalogue: $e');
    }
    if (response.statusCode == 401 || response.statusCode == 403) {
      throw const OpdsException(
        'That catalogue needs credentials this app cannot supply yet.',
      );
    }
    if (response.statusCode != 200) {
      throw OpdsException('The catalogue answered ${response.statusCode}.');
    }
    if (response.bodyBytes.length > maxFeedBytes) {
      throw const OpdsException('That feed is implausibly large; refusing it.');
    }
    return parseFeed(response.body, base: url);
  }

  /// Downloads one acquisition link's bytes.
  Future<List<int>> download(Uri url) async {
    final response = await _http.get(url);
    if (response.statusCode != 200) {
      throw OpdsException('Download failed (${response.statusCode}).');
    }
    return response.bodyBytes;
  }

  /// Parses an Atom/OPDS document.
  ///
  /// Relative hrefs are resolved against [base] here rather than at use, so a
  /// caller never has to remember which feed a link came from — that is the
  /// mistake that makes a browser navigate to the wrong host.
  static OpdsFeed parseFeed(String xml, {required Uri base}) {
    final XmlDocument document;
    try {
      document = XmlDocument.parse(xml);
    } catch (e) {
      throw OpdsException('That is not a valid OPDS feed: $e');
    }
    final feed = document.rootElement;
    if (feed.localName != 'feed') {
      throw const OpdsException(
        'That URL is not an OPDS catalogue (no <feed> element).',
      );
    }

    String? resolve(String? href) =>
        href == null ? null : base.resolve(href).toString();

    final feedLinks = [
      for (final l in feed.childElements.where((e) => e.localName == 'link'))
        OpdsLink(
          href: resolve(l.getAttribute('href')) ?? '',
          rel: l.getAttribute('rel'),
          type: l.getAttribute('type'),
          title: l.getAttribute('title'),
        ),
    ];

    return OpdsFeed(
      title: _text(feed, 'title') ?? base.toString(),
      nextHref: feedLinks.where((l) => l.rel == 'next').firstOrNull?.href,
      searchHref: feedLinks
          .where((l) =>
              l.rel == 'search' &&
              (l.type?.contains('opensearchdescription') ?? false))
          .firstOrNull
          ?.href,
      entries: [
        for (final e in feed.childElements.where((e) => e.localName == 'entry'))
          _parseEntry(e, resolve),
      ],
    );
  }

  static OpdsEntry _parseEntry(
    XmlElement element,
    String? Function(String?) resolve,
  ) {
    return OpdsEntry(
      id: _text(element, 'id') ?? _text(element, 'title') ?? '',
      title: (_text(element, 'title') ?? '').trim(),
      // Atom nests the name inside <author>; Dublin Core sometimes uses
      // <dc:creator> instead. Both appear in the wild.
      authors: [
        for (final a in element.childElements.where((e) => e.localName == 'author'))
          ?_text(a, 'name'),
        for (final c in element.childElements
            .where((e) => e.localName == 'creator'))
          c.innerText.trim(),
      ].where((a) => a.trim().isNotEmpty).toList(),
      // `content` is the richer field and `summary` the fallback; a catalogue
      // usually has one or the other.
      summary: _text(element, 'content') ?? _text(element, 'summary'),
      publisher: _text(element, 'publisher'),
      language: _text(element, 'language'),
      issued: _text(element, 'issued') ?? _text(element, 'published'),
      identifier: _text(element, 'identifier'),
      categories: [
        for (final c in element.childElements
            .where((e) => e.localName == 'category'))
          if ((c.getAttribute('label') ?? c.getAttribute('term'))?.trim()
              case final String label when label.isNotEmpty)
            label,
      ],
      links: [
        for (final l in element.childElements.where((e) => e.localName == 'link'))
          OpdsLink(
            href: resolve(l.getAttribute('href')) ?? '',
            rel: l.getAttribute('rel'),
            type: l.getAttribute('type'),
            title: l.getAttribute('title'),
          ),
      ],
    );
  }

  /// First child element with [name] (namespace-insensitive), trimmed.
  static String? _text(XmlElement parent, String name) {
    for (final child in parent.childElements) {
      if (child.localName != name) continue;
      final text = child.innerText.trim();
      if (text.isNotEmpty) return text;
    }
    return null;
  }
}
