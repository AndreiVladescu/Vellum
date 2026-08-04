import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/shelf/series_page.dart';

/// Seeing every series at once, and what is missing from each.
///
/// Gap detection itself is plan 5 #17 and already tested per book; what is new
/// is asking the question library-wide, which is the direction a reader
/// actually asks it in.
void main() {
  late Directory dir;
  late VellumDatabase db;
  late LibraryRepository repo;

  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_series_page'));
  tearDown(() => dir.deleteSync(recursive: true));

  /// Lets drift's real async finish between pumps.
  ///
  /// A widget test's clock is fake and `NativeDatabase` answers on a real
  /// background isolate, so pumping alone never delivers a `.watch()` result —
  /// the page would sit on its spinner for ever, and the spinner's animation
  /// then trips the pending-timer check with a message about timers rather
  /// than about the data never arriving. Same helper the wishlist and trash
  /// page tests use, for the same reason.
  Future<void> settle(WidgetTester tester, {int rounds = 8}) async {
    for (var i = 0; i < rounds; i++) {
      await tester.runAsync(() async {
        await Future<void>.delayed(const Duration(milliseconds: 5));
      });
      await tester.pump(const Duration(milliseconds: 20));
    }
  }

  /// Cancelling a live `.watch()` schedules a zero-duration timer, which the
  /// pending-timer check would otherwise trip. Unmounting first drains it.
  Future<void> unmount(WidgetTester tester) async {
    await tester.pumpWidget(const SizedBox.shrink());
    await settle(tester);
    await db.close();
  }

  Future<void> addVolume(
    String id,
    String series,
    double index, {
    bool wishlist = false,
  }) async {
    await db.into(db.books).insert(BooksCompanion.insert(
          id: id,
          title: '$series $index',
          status: Value(wishlist ? 'wishlist' : 'unread'),
        ));
    await repo.seriesService.setSeries(id, series, index);
  }

  /// Builds the database, seeds it, and pumps the page — all the drift work
  /// inside `runAsync` so it actually runs.
  Future<void> pumpWith(
    WidgetTester tester,
    Future<void> Function() seed,
  ) async {
    await tester.runAsync(() async {
      db = VellumDatabase(NativeDatabase.memory());
      repo = await LibraryRepository.forTesting(db, dir);
      await seed();
    });
    await tester.pumpWidget(MaterialApp(home: SeriesPage(repository: repo)));
    await settle(tester);
  }

  testWidgets('a series with a hole says which volume is missing',
      (tester) async {
    await pumpWith(tester, () async {
      await addVolume('b1', 'Dune', 1);
      await addVolume('b2', 'Dune', 2);
      await addVolume('b4', 'Dune', 4);
    });

    expect(find.text('Dune'), findsOneWidget);
    expect(find.text('You have 1, 2, 4'), findsOneWidget);
    // The useful sentence: not "you own 1, 2, 4" but "you're missing 3".
    expect(find.text('3'), findsOneWidget);
    await unmount(tester);
  });

  testWidgets('a complete series is listed without alarm', (tester) async {
    await pumpWith(tester, () async {
      await addVolume('b1', 'Earthsea', 1);
      await addVolume('b2', 'Earthsea', 2);
    });

    expect(find.text('Earthsea'), findsOneWidget);
    expect(find.text('Missing'), findsNothing);
    await unmount(tester);
  });

  testWidgets('series with gaps sort above complete ones', (tester) async {
    await pumpWith(tester, () async {
      // Alphabetically "Amber" precedes "Zelazny"; the ordering must ignore
      // that and put the one needing attention first, since that is why you
      // opened the screen.
      await addVolume('a1', 'Amber', 1);
      await addVolume('a2', 'Amber', 2);
      await addVolume('z1', 'Zelazny', 1);
      await addVolume('z3', 'Zelazny', 3);
    });

    final tiles = tester.widgetList<ListTile>(find.byType(ListTile)).toList();
    expect((tiles.first.title! as Text).data, 'Zelazny');
    await unmount(tester);
  });

  testWidgets('a gap already on the wishlist is not offered again',
      (tester) async {
    await pumpWith(tester, () async {
      await addVolume('b1', 'Dune', 1);
      await addVolume('b3', 'Dune', 3);
      await addVolume('b2', 'Dune', 2, wishlist: true);
    });

    // Shown as a decision already taken, not as a button to take it again.
    expect(find.text('2 · wanted'), findsOneWidget);
    expect(find.widgetWithText(ActionChip, '2'), findsNothing);
    await unmount(tester);
  });

  testWidgets('tapping a gap adds that volume to the wishlist', (tester) async {
    await pumpWith(tester, () async {
      await addVolume('b1', 'Dune', 1);
      await addVolume('b3', 'Dune', 3);
    });

    await tester.tap(find.widgetWithText(ActionChip, '2'));
    await settle(tester);

    late List<Book> wanted;
    await tester.runAsync(() async {
      wanted = await repo.wishlist.watchWishlist().first;
    });
    expect(wanted.map((b) => b.title), contains('Dune vol. 2'));
    await unmount(tester);
  });

  testWidgets('no series at all explains how to get one', (tester) async {
    await pumpWith(tester, () async {});
    expect(find.text('No series yet'), findsOneWidget);
    await unmount(tester);
  });
}
