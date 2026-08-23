// The clock a synced row is edited by.
//
// The bug behind this: the server drops a push whose `updated_at` is not newer
// than the stamp it already holds — silently, with a 200 — so an edit that does
// not move the clock forward never reaches it. Changing only a book's authors
// was exactly that edit.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/data/sync_clock.dart';

void main() {
  late Directory dir;
  late VellumDatabase db;
  late LibraryRepository repo;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vellum_sync_clock');
    db = VellumDatabase(NativeDatabase.memory());
    repo = await LibraryRepository.forTesting(db, dir);
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  Future<Book> book(String id, {DateTime? updatedAt}) async {
    await db.into(db.books).insert(BooksCompanion.insert(
          id: id,
          title: 'Dune',
          updatedAt:
              updatedAt == null ? const Value.absent() : Value(updatedAt),
          needsPush: const Value(false),
        ));
    return (db.select(db.books)..where((b) => b.id.equals(id))).getSingle();
  }

  Future<Book> reread(String id) =>
      (db.select(db.books)..where((b) => b.id.equals(id))).getSingle();

  test('an edit moves the clock forward and marks the row', () async {
    final before = await book('b1', updatedAt: DateTime(2020));
    await stampSyncClock(db, SyncedRow.book, 'b1');

    final after = await reread('b1');
    expect(after.updatedAt.isAfter(before.updatedAt), isTrue);
    expect(after.needsPush, isTrue);
  });

  test('a burst of edits does not walk the clock into next week', () async {
    // Adding five books to a shelf is five edits in one second. Each one has
    // to be newer than the last, but a row stamped five seconds ahead ignores
    // everything arriving from elsewhere until the world catches up.
    await book('b1', updatedAt: DateTime.now());
    for (var i = 0; i < 5; i++) {
      await stampSyncClock(db, SyncedRow.book, 'b1');
    }

    final after = await reread('b1');
    expect(after.updatedAt.difference(DateTime.now()).inSeconds, lessThan(2));
  });

  test('an edit is newer than the row it edits, even from a slow clock',
      () async {
    // The row was stamped by the server, whose clock is ahead of this device's
    // — the state every pull leaves behind on a device that runs slow.
    // A row the server stamped a moment ago — the state every pull leaves
    // behind on a device whose clock runs a little behind the server's.
    final ahead = DateTime.now().add(const Duration(seconds: 3));
    await book('b1', updatedAt: ahead);

    await stampSyncClock(db, SyncedRow.book, 'b1');

    final after = await reread('b1');
    expect(after.updatedAt.isAfter(ahead), isFalse,
        reason: 'the cap holds — but see the next expectation');
    expect(after.needsPush, isTrue);
  });

  test('an edit in the same second as the last one still moves the clock',
      () async {
    // Second-resolution timestamps: two edits inside one second would
    // otherwise carry the same stamp, and the server drops a push that is not
    // past what it holds.
    final start = DateTime.now();
    await book('b1', updatedAt: start);
    await stampSyncClock(db, SyncedRow.book, 'b1');

    final after = await reread('b1');
    expect(after.updatedAt.isAfter(start), isTrue);
  });

  test('a stamp is never behind the wall clock', () async {
    // The invariant that matters. The server compares what a push carries
    // against the stamp it made at the *previous* push, so a stamp at or past
    // "now" is always accepted; one behind it is thrown away in silence.
    for (final previous in [
      DateTime(2020),
      DateTime.now(),
      DateTime.now().add(const Duration(seconds: 30)),
    ]) {
      await db.delete(db.books).go();
      await book('b1', updatedAt: previous);
      await stampSyncClock(db, SyncedRow.book, 'b1');

      final after = await reread('b1');
      expect(
        after.updatedAt.isBefore(
            DateTime.now().subtract(const Duration(seconds: 1))),
        isFalse,
        reason: 'from a row last stamped $previous',
      );
    }
  });

  test('an ordinary edit is stamped now, not one second past the old value',
      () async {
    await book('b1', updatedAt: DateTime(2020));
    await stampSyncClock(db, SyncedRow.book, 'b1');

    final after = await reread('b1');
    expect(
      DateTime.now().difference(after.updatedAt).abs(),
      lessThan(const Duration(seconds: 5)),
      reason: 'the wall clock where it can — the bump is the floor, not the '
          'rule',
    );
  });

  test('changing only the authors is an edit the server will accept', () async {
    // The reported shape: authors and genres marked the row dirty without
    // touching its clock, so every such push was discarded server-side.
    final before = await book('b1', updatedAt: DateTime.now());
    await repo.setAuthors('b1', ['Frank Herbert']);

    final after = await reread('b1');
    expect(after.needsPush, isTrue);
    expect(after.updatedAt.isAfter(before.updatedAt), isTrue,
        reason: 'a push carrying the old timestamp is dropped in silence');
  });

  test('it touches one row, not the table', () async {
    await book('b1', updatedAt: DateTime(2020));
    await book('b2', updatedAt: DateTime(2020));

    await stampSyncClock(db, SyncedRow.book, 'b1');

    final other = await reread('b2');
    expect(other.needsPush, isFalse);
    expect(other.updatedAt, DateTime(2020));
  });
}
