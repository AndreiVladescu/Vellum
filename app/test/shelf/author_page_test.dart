import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/shelf/author_page.dart';

/// Everything you hold by one author.
///
/// Genres have been tappable from a book's page for a while and authors were
/// not, which is backwards — "what else of theirs do I have" is the commoner
/// thought. These pin what the page counts as "theirs".
void main() {
  late Directory dir;
  late VellumDatabase db;
  late LibraryRepository repo;

  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_author_page'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Drift answers on a real isolate while the widget clock is fake — see the
  /// same helper in `series_page_test.dart`.
  Future<void> settle(WidgetTester tester, {int rounds = 8}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await db.close();
  }

  Future<void> addBook(
    String id,
    String title,
    List<String> authors, {
    String status = 'unread',
    bool trashed = false,
  }) async {
    await db.into(db.books).insert(BooksCompanion.insert(
          id: id,
          title: title,
          status: Value(status),
          deletedAt: Value(trashed ? DateTime.now() : null),
        ));
    await repo.setAuthors(id, authors);
  }

  Future<void> pumpAuthor(
    WidgetTester tester,
    String author,
    Future<void> Function() seed,
  ) async {
    await tester.runAsync(() async {
      db = VellumDatabase(NativeDatabase.memory());
      repo = await LibraryRepository.forTesting(db, dir);
      await seed();
    });
    await tester.pumpWidget(MaterialApp(
      home: AuthorPage(author: author, repository: repo),
    ));
    await settle(tester);
  }

  testWidgets('lists every book by that author and nobody else’s',
      (tester) async {
    await pumpAuthor(tester, 'Ursula K. Le Guin', () async {
      await addBook('b1', 'The Dispossessed', ['Ursula K. Le Guin']);
      await addBook('b2', 'A Wizard of Earthsea', ['Ursula K. Le Guin']);
      await addBook('b3', 'Dune', ['Frank Herbert']);
    });

    expect(find.text('The Dispossessed'), findsOneWidget);
    expect(find.text('A Wizard of Earthsea'), findsOneWidget);
    expect(find.text('Dune'), findsNothing);
    await unmount(tester);
  });

  testWidgets('a co-authored book counts for both authors', (tester) async {
    await pumpAuthor(tester, 'Terry Pratchett', () async {
      await addBook('b1', 'Good Omens', ['Neil Gaiman', 'Terry Pratchett']);
    });

    // Second-listed author, so this fails if the query only reads position 0.
    expect(find.text('Good Omens'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('wishlist books are shown, marked as wanted', (tester) async {
    await pumpAuthor(tester, 'Ursula K. Le Guin', () async {
      await addBook('b1', 'The Dispossessed', ['Ursula K. Le Guin']);
      await addBook('b2', 'The Lathe of Heaven', ['Ursula K. Le Guin'],
          status: 'wishlist');
    });

    // Half the point of looking an author up is spotting the ones you have
    // already decided to get, so these belong here — labelled, not hidden.
    expect(find.text('The Lathe of Heaven'), findsOneWidget);
    expect(find.text('On your wishlist'), findsOneWidget);
    expect(find.text('1 on your shelf · 1 on the wishlist'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a trashed book is not listed', (tester) async {
    await pumpAuthor(tester, 'Frank Herbert', () async {
      await addBook('b1', 'Dune', ['Frank Herbert']);
      await addBook('b2', 'Dune Messiah', ['Frank Herbert'], trashed: true);
    });

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('Dune Messiah'), findsNothing);
    await unmount(tester);
  });

  testWidgets('an author with nothing says so rather than showing a blank',
      (tester) async {
    await pumpAuthor(tester, 'Nobody At All', () async {});
    expect(find.text('No books by this author.'), findsOneWidget);
    await unmount(tester);
  });
}
