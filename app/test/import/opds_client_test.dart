// The OPDS client (plan 5 #21c), against feeds shaped like the ones real
// servers publish — including Vellum's own, since pointing one Vellum at
// another is the case that must work.
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vellum/import/opds_client.dart';

const _acquisitionFeed = '''
<?xml version="1.0" encoding="UTF-8"?>
<feed xmlns="http://www.w3.org/2005/Atom"
      xmlns:dc="http://purl.org/dc/terms/">
  <title>All books</title>
  <link rel="self" href="/opds/books" type="application/atom+xml"/>
  <link rel="next" href="/opds/books?page=2" type="application/atom+xml"/>
  <link rel="search" href="/opds/search.xml"
        type="application/opensearchdescription+xml"/>
  <entry>
    <title>Dune</title>
    <id>urn:uuid:1</id>
    <author><name>Frank Herbert</name></author>
    <dc:publisher>Chilton Books</dc:publisher>
    <dc:issued>1965-08-01</dc:issued>
    <dc:identifier>urn:isbn:9780441013593</dc:identifier>
    <category term="sf" label="Science Fiction"/>
    <category term="classics"/>
    <summary>A desert planet.</summary>
    <link rel="http://opds-spec.org/acquisition"
          href="/opds/books/1/file.epub" type="application/epub+zip"/>
    <link rel="http://opds-spec.org/acquisition"
          href="/opds/books/1/file.mobi" type="application/x-mobipocket-ebook"/>
    <link rel="http://opds-spec.org/image" href="/opds/books/1/cover.jpg"
          type="image/jpeg"/>
    <link rel="http://opds-spec.org/image/thumbnail"
          href="/opds/books/1/thumb.jpg" type="image/jpeg"/>
  </entry>
  <entry>
    <title>A folder, not a book</title>
    <id>urn:uuid:2</id>
    <link href="/opds/shelf/2" type="application/atom+xml;profile=opds-catalog;kind=navigation"/>
  </entry>
</feed>
''';

void main() {
  final base = Uri.parse('https://books.example.com/opds/books');

  group('parsing', () {
    test('reads an acquisition entry as a book', () {
      final feed = OpdsClient.parseFeed(_acquisitionFeed, base: base);
      expect(feed.title, 'All books');
      expect(feed.books, hasLength(1));

      final dune = feed.books.single;
      expect(dune.title, 'Dune');
      expect(dune.authors, ['Frank Herbert']);
      expect(dune.summary, 'A desert planet.');
      expect(dune.publisher, 'Chilton Books');
      expect(dune.categories, ['Science Fiction', 'classics'],
          reason: 'label wins over term, but term is used when there is no label');
    });

    test('only formats the app can open count as acquisitions', () {
      final dune = OpdsClient.parseFeed(_acquisitionFeed, base: base).books.single;
      expect([for (final a in dune.acquisitions) a.format], ['epub'],
          reason: 'the mobi link is listed by the server but unusable here');
    });

    test('relative hrefs resolve against the feed they came from', () {
      // The mistake this prevents is navigating to the wrong host.
      final feed = OpdsClient.parseFeed(_acquisitionFeed, base: base);
      expect(feed.books.single.acquisitions.single.href,
          'https://books.example.com/opds/books/1/file.epub');
      expect(feed.nextHref, 'https://books.example.com/opds/books?page=2');
      expect(feed.searchHref, 'https://books.example.com/opds/search.xml');
    });

    test('a full-size cover is preferred over the thumbnail', () {
      final dune = OpdsClient.parseFeed(_acquisitionFeed, base: base).books.single;
      expect(dune.coverHref, 'https://books.example.com/opds/books/1/cover.jpg');
    });

    test('an entry with no acquisition is a folder to browse into', () {
      final feed = OpdsClient.parseFeed(_acquisitionFeed, base: base);
      expect(feed.folders, hasLength(1));
      expect(feed.folders.single.navigationHref,
          'https://books.example.com/opds/shelf/2');
      expect(feed.folders.single.isBook, isFalse);
    });

    test('an entry becomes an import row with its metadata intact', () {
      final entry =
          OpdsClient.parseFeed(_acquisitionFeed, base: base).books.single;
      final catalog = entry.toCatalogEntry();
      expect(catalog.title, 'Dune');
      expect(catalog.authors, ['Frank Herbert']);
      expect(catalog.isbn, '9780441013593',
          reason: 'dug out of the urn: identifier');
      expect(catalog.year, 1965);
      expect(catalog.genres, ['Science Fiction', 'classics']);
      expect(catalog.filePath, isNull,
          reason: 'the file is fetched separately, only if the user wants it');
    });

    test('dc:creator is read as an author too', () {
      final feed = OpdsClient.parseFeed('''
        <feed xmlns="http://www.w3.org/2005/Atom"
              xmlns:dc="http://purl.org/dc/terms/">
          <title>t</title>
          <entry><title>X</title><id>1</id>
            <dc:creator>Someone Else</dc:creator>
            <link rel="http://opds-spec.org/acquisition" href="/x.epub"
                  type="application/epub+zip"/>
          </entry>
        </feed>
      ''', base: base);
      expect(feed.books.single.authors, ['Someone Else']);
    });

    test('an HTML page is refused, not parsed into an empty catalogue', () {
      expect(
        () => OpdsClient.parseFeed('<html><body>Nope</body></html>', base: base),
        throwsA(isA<OpdsException>()),
      );
      expect(
        () => OpdsClient.parseFeed('not xml at all', base: base),
        throwsA(isA<OpdsException>()),
      );
    });
  });

  group('fetching', () {
    OpdsClient clientFor(Future<http.Response> Function(http.Request) handler) =>
        OpdsClient(httpClient: MockClient(handler));

    test('a feed is fetched and parsed', () async {
      final client = clientFor((req) async {
        expect(req.headers['Accept'], contains('atom'));
        return http.Response(_acquisitionFeed, 200);
      });
      final feed = await client.fetch(base);
      expect(feed.books.single.title, 'Dune');
    });

    test('an auth-protected catalogue says so plainly', () async {
      final client = clientFor((_) async => http.Response('', 401));
      await expectLater(
        client.fetch(base),
        throwsA(isA<OpdsException>().having(
          (e) => e.message,
          'message',
          contains('credentials'),
        )),
      );
    });

    test('a server error is reported with its status', () async {
      final client = clientFor((_) async => http.Response('', 503));
      await expectLater(
        client.fetch(base),
        throwsA(isA<OpdsException>()
            .having((e) => e.message, 'message', contains('503'))),
      );
    });

    test('an unreachable host is an OpdsException, not a raw socket error',
        () async {
      final client = clientFor((_) async => throw const SocketishError());
      await expectLater(client.fetch(base), throwsA(isA<OpdsException>()));
    });

    test('an implausibly large feed is refused before parsing', () async {
      final huge = 'x' * (OpdsClient.maxFeedBytes + 1);
      final client = clientFor((_) async => http.Response(huge, 200));
      await expectLater(client.fetch(base), throwsA(isA<OpdsException>()));
    });

    test('download returns the bytes', () async {
      final client = clientFor((_) async => http.Response.bytes([1, 2, 3], 200));
      expect(await client.download(base), [1, 2, 3]);
    });
  });
}

class SocketishError implements Exception {
  const SocketishError();
}
