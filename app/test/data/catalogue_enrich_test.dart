// Filling in a book that arrived with almost nothing (8/23 requests: ISBN
// lookup from the wishlist, and a cover for a book with no file to take one
// from).
//
// Two rules are pinned here. Only the blanks are filled — a lookup that
// overwrote a corrected title would be the "fetch metadata undoes my edit" bug
// wearing a new coat. And a title search only accepts a real match: quietly
// attaching the cover of a *companion book* to your copy of Dune is worse than
// leaving it blank.
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vellum/data/catalogue_enrich.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/data/metadata.dart';

void main() {
  late Directory dir;
  late VellumDatabase db;
  late LibraryRepository repo;
  late List<String> coveredBooks;

  /// A catalogue that knows one book, by ISBN and by title.
  MockClient catalogue({
    Map<String, dynamic>? volume,
    List<Uri>? asked,
  }) =>
      MockClient((req) async {
        asked?.add(req.url);
        if (req.url.host.contains('covers')) {
          return http.Response.bytes(
            Uint8List.fromList([0x89, 0x50, 0x4E, 0x47, 0, 0, 0, 0]),
            200,
          );
        }
        if (req.url.path == '/search.json') {
          return http.Response(
            jsonEncode({'docs': [?volume]}),
            200,
          );
        }
        return http.Response(jsonEncode({'docs': [], 'items': []}), 200);
      });

  const dune = {
    'key': '/works/OL1W',
    'title': 'Dune',
    'author_name': ['Frank Herbert'],
    'first_publish_year': 1965,
    'publisher': ['Ace'],
    'number_of_pages_median': 617,
    'isbn': ['9780441013593'],
    'cover_i': 42,
  };

  Future<CatalogueEnrich> enrich({
    Map<String, dynamic>? volume = dune,
    List<Uri>? asked,
  }) async {
    coveredBooks = [];
    return CatalogueEnrich(
      db,
      MetadataService(client: catalogue(volume: volume, asked: asked)),
      (bookId, bytes) async => coveredBooks.add(bookId),
    );
  }

  Future<Book> book(String id, BooksCompanion values) async {
    await db.into(db.books).insert(values);
    return (db.select(db.books)..where((b) => b.id.equals(id))).getSingle();
  }

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vellum_enrich');
    db = VellumDatabase(NativeDatabase.memory());
    repo = await LibraryRepository.forTesting(db, dir);
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('a bare wishlist entry gets its details and a cover', () async {
    final row = await book(
      'b1',
      BooksCompanion.insert(id: 'b1', title: 'Dune'),
    );

    final outcome = await (await enrich()).fill(row);

    expect(outcome, EnrichOutcome.filled);
    final after = await (db.select(db.books)..where((b) => b.id.equals('b1')))
        .getSingle();
    expect(after.publishedYear, 1965);
    expect(after.publisher, 'Ace');
    expect(after.pageCount, 617);
    expect(coveredBooks, ['b1'], reason: 'the point of the request');
    final authors = await repo.detailsFor('b1');
    expect(authors.authors, ['Frank Herbert']);
  });

  test('what the reader typed is left alone', () async {
    final row = await book(
      'b1',
      BooksCompanion.insert(
        id: 'b1',
        title: 'Dune',
        publisher: const Value('My own edition'),
        publishedYear: const Value(1999),
        coverPath: const Value('covers/b1.jpg'),
      ),
    );

    await (await enrich()).fill(row);

    final after = await (db.select(db.books)..where((b) => b.id.equals('b1')))
        .getSingle();
    expect(after.publisher, 'My own edition');
    expect(after.publishedYear, 1999);
    expect(coveredBooks, isEmpty, reason: 'it already had a cover');
  });

  test('an ISBN is the key it looks up by', () async {
    final asked = <Uri>[];
    final row = await book('b1', BooksCompanion.insert(id: 'b1', title: 'Dune'));

    await (await enrich(asked: asked)).fill(row, isbn: '9780441013593');

    expect(asked.map((u) => u.toString()).join(' '), contains('9780441013593'));
    final after = await (db.select(db.books)..where((b) => b.id.equals('b1')))
        .getSingle();
    expect(after.isbn, '9780441013593',
        reason: 'and the book keeps the number it was found by');
  });

  test('the ten-digit form is accepted, and stored as thirteen', () async {
    final row = await book('b1', BooksCompanion.insert(id: 'b1', title: 'Dune'));

    await (await enrich()).fill(row, isbn: '0441013597');

    final after = await (db.select(db.books)..where((b) => b.id.equals('b1')))
        .getSingle();
    expect(after.isbn, '9780441013593');
  });

  test('a title that only nearly matches is refused', () async {
    // The failure this prevents: attaching "The Dune Encyclopedia" to Dune.
    final row = await book(
      'b1',
      BooksCompanion.insert(id: 'b1', title: 'Dune'),
    );

    final outcome = await (await enrich(volume: {
      'key': '/works/OL9W',
      'title': 'The Dune Encyclopedia',
      'author_name': ['Willis McNelly'],
      'cover_i': 9,
    }))
        .fill(row);

    expect(outcome, EnrichOutcome.notFound);
    expect(coveredBooks, isEmpty);
  });

  test('an article and a comma do not make it a different book', () async {
    final row = await book(
      'b1',
      BooksCompanion.insert(id: 'b1', title: 'The Dispossessed'),
    );

    final outcome = await (await enrich(volume: {
      'key': '/works/OL2W',
      'title': 'Dispossessed',
      'author_name': ['Ursula K. Le Guin'],
      'cover_i': 7,
    }))
        .fill(row);

    expect(outcome, EnrichOutcome.filled);
    expect(coveredBooks, ['b1']);
  });

  test('nothing online is an outcome, not an error', () async {
    final row = await book('b1', BooksCompanion.insert(id: 'b1', title: 'Dune'));

    expect(await (await enrich(volume: null)).fill(row),
        EnrichOutcome.notFound);
  });

  test('a book that already knows everything is left as it is', () async {
    final row = await book(
      'b1',
      BooksCompanion.insert(
        id: 'b1',
        title: 'Dune',
        subtitle: const Value('A novel'),
        description: const Value('Sand.'),
        isbn: const Value('9780441013593'),
        publisher: const Value('Ace'),
        publishedYear: const Value(1965),
        pageCount: const Value(617),
        coverPath: const Value('covers/b1.jpg'),
      ),
    );
    await repo.setAuthors('b1', ['Frank Herbert']);

    expect(await (await enrich()).fill(row), EnrichOutcome.alreadyComplete);
  });

  test('filling a book marks it for the next sync', () async {
    final row = await book('b1', BooksCompanion.insert(id: 'b1', title: 'Dune'));
    await (db.update(db.books)..where((b) => b.id.equals('b1')))
        .write(const BooksCompanion(needsPush: Value(false)));

    await (await enrich()).fill(row);

    final after = await (db.select(db.books)..where((b) => b.id.equals('b1')))
        .getSingle();
    expect(after.needsPush, isTrue,
        reason: 'the details it gained are catalogue data, and they travel');
  });
}
