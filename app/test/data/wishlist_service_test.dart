// Wishlist (plan 5 #21a). The contract: a wanted book is a real book row that
// is nowhere in the library, and it graduates the moment you actually have it —
// which is when a file or a copy shows up, not when you remember to tick a box.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_queries.dart';
import 'package:vellum/data/library_repository.dart';

void main() {
  late Directory dir;
  late VellumDatabase db;
  late LibraryRepository repo;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vellum_wishlist_test');
    db = VellumDatabase(NativeDatabase.memory());
    repo = await LibraryRepository.forTesting(db, dir);
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('a wanted book is out of every library view but still a book', () async {
    await repo.createCustomBook(title: 'Owned');
    final wantedId = await repo.wishlist.add(title: 'Wanted', author: 'A. N.');

    final queries = LibraryQueries(db);
    expect([for (final b in await queries.watchAllBooks().first) b.title],
        ['Owned']);
    final view = await queries.watchLibrary().first;
    expect([for (final e in view.entries) e.book.title], ['Owned']);

    expect(
      [for (final b in await repo.wishlist.watchWishlist().first) b.title],
      ['Wanted'],
    );
    // Still a full book row: the author went in, so buying it needs no re-entry.
    final details = await repo.detailsFor(wantedId);
    expect(details.authors, ['A. N.']);
  });

  test('an all-wishlist library still reads as empty', () async {
    await repo.wishlist.add(title: 'Wanted');
    final view = await LibraryQueries(db).watchLibrary().first;
    expect(view.scopeEmpty, isTrue);
  });

  test('the status facet can still ask for the wishlist explicitly', () async {
    await repo.createCustomBook(title: 'Owned');
    await repo.wishlist.add(title: 'Wanted');
    final view =
        await LibraryQueries(db).watchLibrary(status: 'wishlist').first;
    expect([for (final e in view.entries) e.book.title], ['Wanted']);
  });

  test('attaching a file graduates a wanted book automatically', () async {
    final id = await repo.wishlist.add(title: 'Wanted');
    final source = File('${dir.path}/wanted.epub')..writeAsBytesSync([1, 2, 3]);

    await repo.attachFile(id, source.path);

    final book = (await repo.watchBook(id).first)!;
    expect(WishlistService.isWanted(book), isFalse);
    expect(book.status, 'unread');
    expect(await repo.wishlist.watchWishlist().first, isEmpty);
  });

  test('adding a physical copy graduates a wanted book too', () async {
    final id = await repo.wishlist.add(title: 'Wanted');
    await repo.addPhysicalCopy(id, location: 'Shelf 3');
    expect(await repo.wishlist.watchWishlist().first, isEmpty);
  });

  test('acquiring an already-owned book changes nothing', () async {
    final id = await repo.createCustomBook(title: 'Owned');
    await repo.readingStatus.setStatus(id, ReadingStatus.reading);
    await repo.addPhysicalCopy(id);
    final book = (await repo.watchBook(id).first)!;
    expect(book.status, 'reading',
        reason: 'noteAcquired must not reset a real reading state');
  });

  test('wishing a book clears reading state it has no business claiming',
      () async {
    final id = await repo.createCustomBook(title: 'Lent and lost');
    await repo.saveReadingPosition(id, 40, 100);
    await repo.wishlist.markWanted(id);

    final book = (await repo.watchBook(id).first)!;
    expect(book.readingProgress, isNull);
    expect(book.lastReadPage, isNull);
  });

  test('markOwned puts it back on the shelf as unread', () async {
    final id = await repo.wishlist.add(title: 'Wanted');
    await repo.wishlist.markOwned(id);
    expect([for (final b in await repo.watchAllBooks().first) b.id], [id]);
    expect((await repo.watchBook(id).first)!.status, 'unread');
  });

  group('series gaps feed the wishlist', () {
    /// Volumes 1 and 3 of one series, so 2 is a gap.
    Future<Book> seedSeries() async {
      final one = await repo.createCustomBook(title: 'Empire I');
      final three = await repo.createCustomBook(title: 'Empire III');
      await repo.seriesService.setSeries(one, 'Empire', 1);
      await repo.seriesService.setSeries(three, 'Empire', 3);
      return (await repo.watchBook(one).first)!;
    }

    test('a gap is offered until it is wished for', () async {
      final book = await seedSeries();
      var place = (await repo.seriesService.placeOf(book))!;
      expect(place.gaps, [2]);
      expect(place.openGaps, [2]);

      await repo.wishlist
          .addSeriesGap(seriesName: 'Empire', volume: 2, author: 'A. N.');

      place = (await repo.seriesService.placeOf(book))!;
      expect(place.gaps, [2], reason: 'wishing for it does not fill the gap');
      expect(place.openGaps, isEmpty,
          reason: 'but it is no longer worth offering again');
      expect(place.owned, [1, 3],
          reason: 'a wanted volume is not one you own');
    });

    test('the wished volume lands in the series, numbered', () async {
      await seedSeries();
      await repo.wishlist.addSeriesGap(seriesName: 'Empire', volume: 2);

      final wanted = (await repo.wishlist.watchWishlist().first).single;
      expect(wanted.title, 'Empire vol. 2');
      expect(wanted.seriesIndex, 2);
      expect(await repo.seriesService.nameOf(wanted.id), 'Empire');
    });

    test('a trashed sibling stops counting as a volume you own', () async {
      final book = await seedSeries();
      final siblings = await db.select(db.books).get();
      final volumeThree =
          siblings.firstWhere((b) => b.title == 'Empire III');
      await repo.trashBook(volumeThree.id);

      final place = (await repo.seriesService.placeOf(book))!;
      expect(place.owned, [1]);
      expect(place.gaps, isEmpty, reason: 'one volume can have no gaps');
    });
  });

  test('a wanted book still syncs like any other row', () async {
    // Wishlist entries are ordinary book rows and do push — this pins that
    // #21a's exclusions stopped at the *views*, unlike #52's trash, which
    // deliberately suppresses the push as well.
    await repo.wishlist.add(title: 'Wanted');
    expect(await LibraryQueries(db).watchDirtyCount().first, 1);
  });

  test('a trashed wishlist entry leaves the wishlist too', () async {
    final id = await repo.wishlist.add(title: 'Wanted');
    await repo.trashBook(id);
    expect(await repo.wishlist.watchWishlist().first, isEmpty);
    await repo.restoreBook(id);
    expect(await repo.wishlist.watchWishlist().first, hasLength(1));
  });

  test('ownedStates leaves wishlist out of the reading-status menu', () {
    expect(ReadingStatus.ownedStates, isNot(contains(ReadingStatus.wishlist)));
    expect(ReadingStatus.ownedStates, hasLength(ReadingStatus.values.length - 1));
    expect(ReadingStatus.parse('wishlist'), ReadingStatus.wishlist);
  });

  test('a wishlist book keeps its note', () async {
    final id = await repo.wishlist.add(
      title: 'Wanted',
      note: 'Saw it in the window on Grand St',
    );
    final book = (await repo.watchBook(id).first)!;
    expect(book.readerNotes, 'Saw it in the window on Grand St');

    // …and loses it on graduating, since the note was about wanting it.
    await repo.wishlist.markOwned(id);
    expect((await repo.watchBook(id).first)!.readerNotes, isNull);
  });

  test('a seeded wishlist row can be written directly, for fixtures', () async {
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'w1',
          title: 'Direct',
          status: const Value('wishlist'),
        ));
    expect([for (final b in await repo.wishlist.watchWishlist().first) b.id],
        ['w1']);
  });
}
