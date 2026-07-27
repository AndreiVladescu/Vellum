// The scanning flow (plan 5 #16), driven by an injected barcode stream instead
// of a camera: what happens on a good ISBN, a non-book barcode, a repeat, a
// duplicate of a book already owned, an undo, and a lookup that finds nothing.
//
// The metadata lookup is a MockClient, so no test here touches the network.
import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:http/http.dart' as http;
import 'package:http/testing.dart';
import 'package:vellum/add_book/scan_page.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/data/metadata.dart';

/// An Open Library search response for one work, keyed by the ISBN queried.
/// [known] maps `isbn:<n>` queries to a title; anything else answers empty, the
/// "no online match" case.
MockClient _metadataServer(Map<String, String> known) =>
    MockClient((req) async {
      if (req.url.host == 'openlibrary.org' && req.url.path == '/search.json') {
        final q = req.url.queryParameters['q'] ?? '';
        final isbn = q.startsWith('isbn:') ? q.substring(5) : '';
        final title = known[isbn];
        return http.Response(
          jsonEncode({
            'docs': [
              if (title != null)
                {
                  'key': '/works/OL1W',
                  'title': title,
                  'author_name': ['Frank Herbert'],
                  'first_publish_year': 1965,
                  'isbn': [isbn],
                },
            ],
          }),
          200,
        );
      }
      // Google Books fallback, and the work-description fetch: both empty.
      return http.Response('{}', 200);
    });

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_scan_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Pumps enough interleaved real-async/fake-async rounds for the lookup and
  /// the database writes to land (see folder_import_page_test.dart).
  Future<void> settle(WidgetTester tester, {int rounds = 25}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Builds the page over a repository whose metadata service is mocked.
  Future<({Widget app, LibraryRepository repo, StreamController<String> codes})>
      build(
    WidgetTester tester, {
    Map<String, String> known = const {'9780441013593': 'Dune'},
    bool initialWishlist = false,
  }) async {
    late LibraryRepository repo;
    late StreamController<String> codes;
    late Widget app;
    await tester.runAsync(() async {
      final client = _metadataServer(known);
      repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dir,
        metadata: MetadataService(client: client),
      );
      codes = StreamController<String>();
      app = MaterialApp(
        home: ScanPage(
          repository: repo,
          barcodes: codes.stream,
          cameraAvailable: false,
          initialWishlist: initialWishlist,
        ),
      );
    });
    addTearDown(codes.close);
    return (app: app, repo: repo, codes: codes);
  }

  testWidgets('a scanned ISBN adds a book and lists it', (tester) async {
    final t = await build(tester);
    await tester.pumpWidget(t.app);
    await settle(tester);

    t.codes.add('9780441013593');
    await settle(tester);

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('1 added'), findsOneWidget);
    final books = await t.repo.db.select(t.repo.db.books).get();
    expect(books.single.title, 'Dune');
    expect(books.single.isbn, '9780441013593');
  });

  testWidgets('a non-book barcode is rejected without a lookup', (tester) async {
    final t = await build(tester);
    await tester.pumpWidget(t.app);
    await settle(tester);

    t.codes.add('4006381333931'); // valid EAN-13, not Bookland
    await settle(tester);

    expect(find.textContaining('isn’t a book'), findsOneWidget);
    expect(await t.repo.db.select(t.repo.db.books).get(), isEmpty);
    expect(find.text('1 added'), findsNothing);
  });

  testWidgets('the same barcode in the frame twice adds one book',
      (tester) async {
    // The camera re-reads a held-still book many times a second; without this
    // guard a shelf of 40 books would become hundreds of rows.
    final t = await build(tester);
    await tester.pumpWidget(t.app);
    await settle(tester);

    t.codes.add('9780441013593');
    await settle(tester);
    t.codes.add('9780441013593');
    await settle(tester);

    expect(await t.repo.db.select(t.repo.db.books).get(), hasLength(1));
    expect(find.text('1 added'), findsOneWidget);
  });

  testWidgets('a book already in the library is added but flagged',
      (tester) async {
    final t = await build(tester);
    await tester.runAsync(() async {
      final db = t.repo.db;
      await db.into(db.books).insert(BooksCompanion.insert(
            id: 'existing',
            title: 'Dune',
            isbn: const Value('9780441013593'),
          ));
    });
    await tester.pumpWidget(t.app);
    await settle(tester);

    t.codes.add('9780441013593');
    await settle(tester);

    expect(find.textContaining('Possible duplicate'), findsOneWidget);
    expect(await t.repo.db.select(t.repo.db.books).get(), hasLength(2),
        reason: 'owning two copies is legitimate — flag, never block');
  });

  testWidgets('undo removes the book it added', (tester) async {
    final t = await build(tester);
    await tester.pumpWidget(t.app);
    await settle(tester);
    t.codes.add('9780441013593');
    await settle(tester);
    expect(await t.repo.db.select(t.repo.db.books).get(), hasLength(1));

    await tester.tap(find.text('Undo'));
    await settle(tester);

    expect(await t.repo.db.select(t.repo.db.books).get(), isEmpty);
    expect(find.text('Dune'), findsNothing);
  });

  testWidgets('an ISBN with no online match says so instead of adding nothing '
      'silently', (tester) async {
    final t = await build(tester, known: const {});
    await tester.pumpWidget(t.app);
    await settle(tester);

    t.codes.add('9780441013593');
    await settle(tester);

    expect(find.textContaining('No online match'), findsOneWidget);
    expect(find.textContaining('978-0-4410-1359-3'), findsOneWidget,
        reason: 'the ISBN is shown so it can be typed into the manual form');
    expect(await t.repo.db.select(t.repo.db.books).get(), isEmpty);
  });

  testWidgets('the manual field drives the same path as the camera',
      (tester) async {
    // The permission-denied / desktop fallback: no camera, typed ISBN-10.
    final t = await build(tester);
    await tester.pumpWidget(t.app);
    await settle(tester);

    await tester.enterText(find.byType(TextField), '0-441-01359-7');
    await tester.tap(find.text('Add'));
    await settle(tester);

    expect(find.text('Dune'), findsOneWidget);
    expect(await t.repo.db.select(t.repo.db.books).get(), hasLength(1));
  });

  testWidgets('a typed non-ISBN is refused with a message', (tester) async {
    final t = await build(tester);
    await tester.pumpWidget(t.app);
    await settle(tester);

    await tester.enterText(find.byType(TextField), 'not an isbn');
    await tester.tap(find.text('Add'));
    await settle(tester, rounds: 3);

    expect(find.textContaining('doesn’t look like an ISBN'), findsOneWidget);
    expect(await t.repo.db.select(t.repo.db.books).get(), isEmpty);
  });

  testWidgets('in wishlist mode a scan is wanted, not owned', (tester) async {
    // The bookshop case (plan 5 #21a): you scan what you're holding to remember
    // it, and it must not turn up on the shelf as though you'd bought it.
    final t = await build(tester, initialWishlist: true);
    await tester.pumpWidget(t.app);
    await settle(tester);

    t.codes.add('9780441013593');
    await settle(tester);

    expect(find.text('Dune'), findsOneWidget);
    await tester.runAsync(() async {
      final wanted = await t.repo.wishlist.watchWishlist().first;
      expect([for (final b in wanted) b.title], ['Dune']);
      expect(await t.repo.watchAllBooks().first, isEmpty,
          reason: 'and it is not in the library');
    });
  });

  testWidgets('the toggle switches where the next scan goes', (tester) async {
    final t = await build(tester, known: const {
      '9780441013593': 'Dune',
      '9780575081581': 'Neuromancer',
    });
    await tester.pumpWidget(t.app);
    await settle(tester);

    t.codes.add('9780441013593');
    await settle(tester);
    await tester.runAsync(() async {
      expect(await t.repo.watchAllBooks().first, hasLength(1));
    });

    await tester.tap(find.text('I want it'));
    await settle(tester);
    t.codes.add('9780575081581');
    await settle(tester);

    await tester.runAsync(() async {
      expect(await t.repo.wishlist.watchWishlist().first, hasLength(1),
          reason: 'the second scan followed the toggle');
    });
  });
}
