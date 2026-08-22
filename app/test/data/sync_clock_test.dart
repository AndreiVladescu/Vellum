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

  test('an edit is newer than the row it edits, even from a slow clock',
      () async {
    // The row was stamped by the server, whose clock is ahead of this device's
    // — the state every pull leaves behind on a device that runs slow.
    final future = DateTime.now().add(const Duration(hours: 2));
    await book('b1', updatedAt: future);

    await stampSyncClock(db, SyncedRow.book, 'b1');

    final after = await reread('b1');
    expect(after.updatedAt.isAfter(future), isTrue,
        reason: 'otherwise the server drops the edit as older than what it '
            'holds, says 200, and the next pull overwrites it here');
  });

  test('two edits in the same second still advance', () async {
    await book('b1', updatedAt: DateTime.now());
    await stampSyncClock(db, SyncedRow.book, 'b1');
    final first = await reread('b1');
    await stampSyncClock(db, SyncedRow.book, 'b1');
    final second = await reread('b1');

    expect(second.updatedAt.isAfter(first.updatedAt), isTrue,
        reason: 'server timestamps have one-second resolution, and a second '
            'edit inside that second must not look like the first');
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
