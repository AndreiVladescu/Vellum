// Reading status, ratings and finish dates (plan 5 #18).
//
// The invariant worth protecting: **the app never decides for you**. Exactly one
// transition is automatic (opening an unread book), reaching the end only
// *offers* to finish, and the dates can't contradict the status.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/data/reading_status.dart' show StatusState, mergeStatus;
import 'package:vellum/settings/shelf_sort.dart';

Future<LibraryRepository> _repo(Directory dir) async =>
    LibraryRepository.forTesting(VellumDatabase(NativeDatabase.memory()), dir);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_status'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<LibraryRepository> seeded({
    double? progress,
    String status = 'unread',
  }) async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'b1',
          title: 'Dune',
          readingProgress: Value(progress),
          status: Value(status),
          needsPush: const Value(false),
          readerNotesNeedsPush: const Value(false),
        ));
    return repo;
  }

  test('a new book is unread, unrated, undated', () async {
    final repo = await seeded();
    final book = (await repo.watchBook('b1').first)!;
    expect(ReadingStatus.parse(book.status), ReadingStatus.unread);
    expect(book.rating, isNull);
    expect(book.startedAt, isNull);
    expect(book.finishedAt, isNull);
    expect(book.readCount, 0);
  });

  test('opening an unread book marks it reading and stamps the start', () async {
    final repo = await seeded();
    await repo.readingStatus.noteOpened('b1');
    final book = (await repo.watchBook('b1').first)!;
    expect(ReadingStatus.parse(book.status), ReadingStatus.reading);
    expect(book.startedAt, isNotNull);
  });

  test('opening does not reclassify a book you already judged', () async {
    // Re-opening something marked abandoned (or kept as reference) must not
    // quietly drag it back to "reading".
    for (final status in ['abandoned', 'reference', 'finished']) {
      final repo = await seeded(status: status);
      await repo.readingStatus.noteOpened('b1');
      final book = (await repo.watchBook('b1').first)!;
      expect(book.status, status, reason: '$status must be left alone');
    }
  });

  test('finishing a book at the end is offered, never applied', () async {
    final repo = await seeded(progress: 0.99, status: 'reading');
    final book = (await repo.watchBook('b1').first)!;
    expect(ReadingStatusService.shouldOfferFinished(book), true);
    expect(book.status, 'reading',
        reason: 'reaching the end changes nothing on its own');

    await repo.readingStatus.setStatus('b1', ReadingStatus.finished);
    final after = (await repo.watchBook('b1').first)!;
    expect(after.status, 'finished');
    expect(after.finishedAt, isNotNull);
    expect(after.readCount, 1);
  });

  test('finishing is not offered mid-book, or once resolved', () async {
    Book book(String status, double progress) => Book(
          id: 'b',
          title: 't',
          status: status,
          readingProgress: progress,
          readCount: 0,
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
          needsPush: false, syncExcluded: false,
          readerNotesNeedsPush: false,
      statusNeedsPush: false,
      statusInferred: false,
          needsProgressPush: false,
        );

    expect(ReadingStatusService.shouldOfferFinished(book('reading', 0.5)), false);
    expect(
        ReadingStatusService.shouldOfferFinished(book('finished', 1.0)), false);
    expect(
        ReadingStatusService.shouldOfferFinished(book('abandoned', 1.0)), false);
    expect(
        ReadingStatusService.shouldOfferFinished(book('reference', 1.0)), false);
    expect(ReadingStatusService.shouldOfferFinished(book('unread', 0.99)), true,
        reason: 'a book read elsewhere then synced can still be finished here');
  });

  test('re-finishing counts a re-read', () async {
    final repo = await seeded(status: 'reading');
    await repo.readingStatus.setStatus('b1', ReadingStatus.finished);
    await repo.readingStatus.setStatus('b1', ReadingStatus.reading);
    await repo.readingStatus.setStatus('b1', ReadingStatus.finished);
    final book = (await repo.watchBook('b1').first)!;
    expect(book.readCount, 2);
  });

  test('leaving finished clears the finish date, so the two agree', () async {
    final repo = await seeded(status: 'reading');
    await repo.readingStatus.setStatus('b1', ReadingStatus.finished);
    expect((await repo.watchBook('b1').first)!.finishedAt, isNotNull);

    await repo.readingStatus.setStatus('b1', ReadingStatus.abandoned);
    final book = (await repo.watchBook('b1').first)!;
    expect(book.status, 'abandoned');
    expect(book.finishedAt, isNull, reason: 'a date that no longer applies');
  });

  test('setting the same status again is a no-op', () async {
    final repo = await seeded(status: 'finished');
    await repo.readingStatus.setStatus('b1', ReadingStatus.finished);
    expect((await repo.watchBook('b1').first)!.readCount, 0,
        reason: 'must not count a re-read for a redundant tap');
  });

  test('a rating clamps to 1–5 and can be cleared', () async {
    final repo = await seeded();
    await repo.readingStatus.setRating('b1', 9);
    expect((await repo.watchBook('b1').first)!.rating, 5);
    await repo.readingStatus.setRating('b1', 0);
    expect((await repo.watchBook('b1').first)!.rating, 1);
    await repo.readingStatus.setRating('b1', null);
    expect((await repo.watchBook('b1').first)!.rating, isNull);
  });

  test("status and rating never touch the book's sync clock", () async {
    // They are personal judgements; putting them on the book's LWW clock would
    // publish them on the shared row and make a rating tap win over a genuine
    // metadata edit from the server.
    final repo = await seeded();
    final before = (await repo.watchBook('b1').first)!;
    await repo.readingStatus.setStatus('b1', ReadingStatus.reading);
    await repo.readingStatus.setRating('b1', 4);
    final after = (await repo.watchBook('b1').first)!;
    expect(after.updatedAt, before.updatedAt);
    expect(after.needsPush, false);
  });

  test('a rating has its own clock, and is queued for the other devices',
      () async {
    final repo = await seeded();
    await repo.readingStatus.setRating('b1', 4);
    final rated = (await repo.watchBook('b1').first)!;
    expect(rated.statusNeedsPush, isTrue);
    expect(rated.ratingUpdatedAt, isNotNull);
    expect(rated.statusUpdatedAt, isNull,
        reason: 'rating a book is not choosing its status: a stale "unread" '
            'here must not become the newest status everywhere');

    // The same rating again is not an edit, and must not move the clock past
    // another device's real change.
    await (repo.db.update(repo.db.books)..where((b) => b.id.equals('b1')))
        .write(BooksCompanion(
      statusNeedsPush: const Value(false),
      ratingUpdatedAt: Value(DateTime(2020)),
    ));
    await repo.readingStatus.setRating('b1', 4);
    final again = (await repo.watchBook('b1').first)!;
    expect(again.statusNeedsPush, isFalse);
    expect(again.ratingUpdatedAt, DateTime(2020));
  });

  test('opening a book is a guess; choosing a status is not', () async {
    final repo = await seeded();
    await repo.readingStatus.noteOpened('b1');
    final opened = (await repo.watchBook('b1').first)!;
    expect(opened.status, 'reading');
    expect(opened.statusInferred, isTrue,
        reason: 'this device only thinks the book was unread');
    expect(opened.statusNeedsPush, isTrue);

    await repo.readingStatus.setStatus('b1', ReadingStatus.finished);
    final chosen = (await repo.watchBook('b1').first)!;
    expect(chosen.statusInferred, isFalse);
  });

  group('mergeStatus', () {
    final t1 = DateTime.utc(2026, 8, 20, 22);
    final t2 = DateTime.utc(2026, 8, 21, 8);

    test('between two choices, the newer wins, dates and all', () {
      final merged = mergeStatus(
        StatusState(status: 'reading', startedAt: t1, updatedAt: t1),
        StatusState(status: 'finished', finishedAt: t2, updatedAt: t2),
      );
      expect(merged.status, 'finished');
      expect(merged.finishedAt, t2);
      expect(merged.startedAt, isNull, reason: 'the dates move with the status');
      expect(merged.updatedAt, t2);
    });

    test('status and rating each win on their own clock', () {
      // The tablet missed the phone's finish and its rating, then rated it.
      final phone = StatusState(
          status: 'finished', updatedAt: t1, rating: 5, ratingUpdatedAt: t1);
      final tablet = StatusState(
          status: 'unread', updatedAt: null, rating: 3, ratingUpdatedAt: t2);
      final merged = mergeStatus(phone, tablet);
      expect(merged.status, 'finished', reason: 'rating did not unfinish it');
      expect(merged.rating, 3, reason: 'the newer rating');
      // And a status change from a device that never rated says nothing
      // about the rating.
      final unrated = mergeStatus(
          merged, StatusState(status: 'abandoned', updatedAt: t2));
      expect(unrated.status, 'abandoned');
      expect(unrated.rating, 3);
    });

    test('a rating taken away is a dated null, and travels', () {
      final merged = mergeStatus(
        StatusState(status: 'finished', rating: 4, ratingUpdatedAt: t1),
        StatusState(status: 'finished', rating: null, ratingUpdatedAt: t2),
      );
      expect(merged.rating, isNull);
      expect(merged.ratingUpdatedAt, t2);
    });

    test('a newer guess does not replace an older choice', () {
      final finished = StatusState(
          status: 'finished', finishedAt: t1, readCount: 1, updatedAt: t1);
      final guess =
          StatusState(status: 'reading', inferred: true, updatedAt: t2);
      for (final merged in [
        mergeStatus(finished, guess),
        mergeStatus(guess, finished),
      ]) {
        expect(merged.status, 'finished', reason: 'whichever arrives first');
        expect(merged.inferred, isFalse);
        expect(merged.readCount, 1);
        expect(merged.updatedAt, t2, reason: 'the later clock, either way');
      }
    });

    test('a guess after a chosen "unread" is newer news, not a stale one', () {
      final merged = mergeStatus(
        StatusState(status: 'unread', updatedAt: t1),
        StatusState(status: 'reading', inferred: true, updatedAt: t2),
      );
      expect(merged.status, 'reading');
    });

    test('the read count keeps the larger, not the newer', () {
      final merged = mergeStatus(
        StatusState(status: 'finished', readCount: 2, updatedAt: t1),
        StatusState(status: 'abandoned', readCount: 1, updatedAt: t2),
      );
      expect(merged.status, 'abandoned');
      expect(merged.readCount, 2);
    });

    test('an undated rating is filled in by any dated one', () {
      final merged = mergeStatus(
        StatusState(status: 'finished', updatedAt: t2),
        StatusState(
            status: 'reading', updatedAt: t1, rating: 5, ratingUpdatedAt: t1),
      );
      expect(merged.rating, 5);
      expect(merged.status, 'finished');
      // And a dated one is not replaced by an older one.
      expect(
        mergeStatus(
          StatusState(status: 'finished', rating: 2, ratingUpdatedAt: t2),
          StatusState(status: 'finished', rating: 5, ratingUpdatedAt: t1),
        ).rating,
        2,
      );
    });
  });

  test('an unknown status string reads as unread rather than throwing', () {
    expect(ReadingStatus.parse('who-knows'), ReadingStatus.unread);
    expect(ReadingStatus.parse(null), ReadingStatus.unread);
  });

  test('the shelf can be filtered to one status', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    for (final (id, title, status) in [
      ('a', 'Reading now', 'reading'),
      ('b', 'Done', 'finished'),
      ('c', 'Someday', 'unread'),
    ]) {
      await db.into(db.books).insert(BooksCompanion.insert(
            id: id,
            title: title,
            status: Value(status),
          ));
    }

    final finished = await repo.queries
        .watchLibrary(status: 'finished', sort: ShelfSort.title)
        .first;
    expect(finished.entries.map((e) => e.book.title), ['Done']);

    // No facet = everything, as before.
    final all = await repo.queries.watchLibrary(sort: ShelfSort.title).first;
    expect(all.entries, hasLength(3));
  });

  test('the status facet stacks with a search', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(
        id: 'a', title: 'Dune', status: const Value('finished')));
    await db.into(db.books).insert(BooksCompanion.insert(
        id: 'b', title: 'Dune Messiah', status: const Value('unread')));

    final view = await repo.queries
        .watchLibrary(query: 'dune', status: 'finished')
        .first;
    expect(view.entries.map((e) => e.book.title), ['Dune']);
  });

  test('watchByStatus lists a status, most recently read first', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'a',
          title: 'Older',
          status: const Value('reading'),
          lastReadAt: Value(DateTime(2026, 1, 1)),
        ));
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'b',
          title: 'Newer',
          status: const Value('reading'),
          lastReadAt: Value(DateTime(2026, 6, 1)),
        ));

    final reading =
        await repo.readingStatus.watchByStatus(ReadingStatus.reading).first;
    expect(reading.map((b) => b.title), ['Newer', 'Older']);
  });
}
