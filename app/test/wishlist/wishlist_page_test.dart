// The wishlist screen (plan 5 #21a). The service tests pin the semantics; this
// covers the screen's own promises — that a wanted book is listed, that "I own
// this now" moves it into the library, and that removing it goes through the
// trash rather than deleting outright.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/wishlist/wishlist_page.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_wishlist_ui'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> settle(WidgetTester tester, {int rounds = 8}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// The wishlist page ends each test by unmounting, for the same reason the
  /// trash page's tests do: cancelling a live drift `.watch()` schedules a
  /// zero-duration timer that would otherwise trip the pending-timer check.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
  }

  Future<LibraryRepository> pumpWishlist(
    WidgetTester tester, {
    bool seed = true,
  }) async {
    late LibraryRepository repo;
    await tester.runAsync(() async {
      repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()),
        dir,
      );
      if (seed) {
        await repo.wishlist.add(
          title: 'Piranesi',
          note: 'Recommended at book club',
        );
      }
    });
    await tester.pumpWidget(MaterialApp(home: WishlistPage(repository: repo)));
    await settle(tester);
    return repo;
  }

  testWidgets('lists a wanted book with the note you gave it', (tester) async {
    await pumpWishlist(tester);
    expect(find.text('Piranesi'), findsOneWidget);
    expect(find.text('Recommended at book club'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('an empty wishlist explains what it is for', (tester) async {
    await pumpWishlist(tester, seed: false);
    expect(find.text('Nothing on your wishlist'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('"I own this now" moves it into the library', (tester) async {
    final repo = await pumpWishlist(tester);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('I own this now'));
    await settle(tester);

    await tester.runAsync(() async {
      expect(await repo.wishlist.watchWishlist().first, isEmpty);
      expect(
        [for (final b in await repo.watchAllBooks().first) b.title],
        ['Piranesi'],
      );
    });
    expect(find.text('Nothing on your wishlist'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('removing goes to the trash, not straight to a delete',
      (tester) async {
    final repo = await pumpWishlist(tester);
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pumpAndSettle();
    await tester.tap(find.text('Remove from wishlist'));
    await settle(tester);

    await tester.runAsync(() async {
      expect(await repo.wishlist.watchWishlist().first, isEmpty);
      expect(await repo.trash.watchTrashed().first, hasLength(1),
          reason: 'recoverable — a wishlist entry can be a mis-tap too');
      expect(await repo.db.select(repo.db.localDeletions).get(), isEmpty,
          reason: 'and nothing was told to the server');
    });
    await unmount(tester);
  });
}
