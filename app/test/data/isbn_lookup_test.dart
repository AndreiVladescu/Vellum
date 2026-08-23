// Finding the book behind a barcode (8/23 note: "some of the books I scan are
// not found by the database of the isbns, how can I broaden it?").
//
// A book that "isn't in the database" usually is, under a different key. What
// is pinned here is that each source is asked, that the ten-digit form of the
// barcode is tried too, and that whichever one answers, the book is recorded
// under the barcode that was actually scanned.
import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vellum/data/metadata.dart';

/// A stand-in for the three catalogues, each answering only for the keys it is
/// told about. Records every URL it is asked for.
({MockClient client, List<Uri> asked}) catalogues({
  Map<String, String> openLibrarySearch = const {},
  Map<String, String> googleBooks = const {},
  Map<String, Map<String, dynamic>> openLibraryEditions = const {},
}) {
  final asked = <Uri>[];
  return (
    asked: asked,
    client: MockClient((req) async {
      asked.add(req.url);
      final path = req.url.path;
      if (path == '/search.json') {
        final query = req.url.queryParameters['q'] ?? '';
        final isbn = query.replaceFirst('isbn:', '');
        final title = openLibrarySearch[isbn];
        return http.Response(
          jsonEncode({
            'docs': [
              if (title != null)
                {'key': '/works/OL1W', 'title': title, 'isbn': [isbn]},
            ],
          }),
          200,
        );
      }
      if (path == '/books/v1/volumes') {
        final query = req.url.queryParameters['q'] ?? '';
        final isbn = query.replaceFirst('isbn:', '');
        final title = googleBooks[isbn];
        return http.Response(
          jsonEncode({
            'items': [
              if (title != null)
                {
                  'volumeInfo': {
                    'title': title,
                    'industryIdentifiers': [
                      {'type': 'ISBN_13', 'identifier': isbn},
                    ],
                  },
                },
            ],
          }),
          200,
        );
      }
      if (path == '/api/books') {
        final key = req.url.queryParameters['bibkeys'] ?? '';
        final isbn = key.replaceFirst('ISBN:', '');
        final data = openLibraryEditions[isbn];
        return http.Response(
          jsonEncode({key: ?data}),
          200,
        );
      }
      return http.Response('{}', 404);
    }),
  );
}

void main() {
  const dune13 = '9780441013593';
  const dune10 = '0441013597';

  test('the first source that knows the book answers', () async {
    final net = catalogues(openLibrarySearch: {dune13: 'Dune'});
    final found =
        await MetadataService(client: net.client).lookupByIsbn(dune13);

    expect(found?.title, 'Dune');
    expect(net.asked, hasLength(1),
        reason: 'a hit costs one request; the rest are for misses');
  });

  test('Google Books is asked when the search index has nothing', () async {
    final net = catalogues(googleBooks: {dune13: 'Dune'});
    final found =
        await MetadataService(client: net.client).lookupByIsbn(dune13);

    expect(found?.title, 'Dune');
  });

  test('the edition record is asked when neither index has it', () async {
    // The commonest reason a scan fails: the edition exists in Open Library
    // but was never folded into a work, so the search index cannot see it.
    final net = catalogues(openLibraryEditions: {
      dune13: {
        'title': 'Dune',
        'authors': [
          {'name': 'Frank Herbert'},
        ],
        'publishers': [
          {'name': 'Ace'},
        ],
        'number_of_pages': 617,
        'publish_date': 'August 1990',
        'cover': {'large': 'https://covers.openlibrary.org/b/id/1-L.jpg'},
      },
    });

    final found =
        await MetadataService(client: net.client).lookupByIsbn(dune13);

    expect(found?.title, 'Dune');
    expect(found?.authors, ['Frank Herbert']);
    expect(found?.publisher, 'Ace');
    expect(found?.pageCount, 617);
    expect(found?.firstPublishYear, 1990, reason: 'the year out of the date');
    expect(found?.largeCoverUrl.toString(), contains('covers.openlibrary.org'));
  });

  test('the ten-digit form of the barcode is tried as well', () async {
    // A record made before 2007 and never re-indexed: the 13-digit barcode
    // finds nothing, its own ISBN-10 finds the book.
    final net = catalogues(openLibrarySearch: {dune10: 'Dune'});

    final found =
        await MetadataService(client: net.client).lookupByIsbn(dune13);

    expect(found?.title, 'Dune');
    expect(net.asked.map((u) => u.toString()).join(' '), contains(dune10));
  });

  test('however it was found, the book keeps the barcode that was scanned',
      () async {
    final net = catalogues(googleBooks: {dune10: 'Dune'});
    final found =
        await MetadataService(client: net.client).lookupByIsbn(dune13);

    expect(found?.isbn, dune13,
        reason: 'the 13-digit form is what the library dedupes and searches by');
  });

  test('a 979 barcode is not asked for under a ten-digit form', () async {
    // 979 exists because the ten-digit space ran out; there is no such form.
    const music = '9791234567896';
    final net = catalogues();
    await MetadataService(client: net.client).lookupByIsbn(music);

    expect(net.asked, hasLength(3), reason: 'three sources, one form');
  });

  test('a source that is down does not fail the scan', () async {
    final asked = <Uri>[];
    final client = MockClient((req) async {
      asked.add(req.url);
      if (req.url.path == '/search.json') throw const SocketFailure();
      if (req.url.path == '/books/v1/volumes') {
        return http.Response('gateway timeout', 504);
      }
      return http.Response(
        jsonEncode({'ISBN:$dune13': {'title': 'Dune'}}),
        200,
      );
    });

    final found = await MetadataService(client: client).lookupByIsbn(dune13);

    expect(found?.title, 'Dune',
        reason: 'a catalogue being down is not an answer about the book');
  });

  test('nothing anywhere is null, not an error', () async {
    final net = catalogues();
    expect(await MetadataService(client: net.client).lookupByIsbn(dune13),
        isNull);
    expect(net.asked, hasLength(6), reason: 'three sources, two forms');
  });
}

/// A dead socket, without dragging dart:io in.
class SocketFailure implements Exception {
  const SocketFailure();
}
