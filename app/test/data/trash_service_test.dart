import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_queries.dart';
import 'package:vellum/data/library_repository.dart';

/// Plan 5 #52. The contract in one line: trashing hides a book without
/// deleting anything or telling the server, and only the sweep (or an explicit
/// "delete now") turns that into the real delete.
void main() {
  late Directory dir;
  late VellumDatabase db;
  late LibraryRepository repo;
  late TrashService trash;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vellum_trash_test');
    db = VellumDatabase(NativeDatabase.memory());
    repo = await LibraryRepository.forTesting(db, dir);
    trash = repo.trash;
  });
  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  /// A book with a cover file and an attached file on disk, so "the files are
  /// kept" is checked against the filesystem rather than the row.
  Future<Book> seedBook(String id, String title) async {
    await db.into(db.books).insert(BooksCompanion.insert(
          id: id,
          title: title,
          coverPath: Value('covers/$id.jpg'),
        ));
    File('${dir.path}/covers/$id.jpg').writeAsBytesSync([1, 2, 3]);
    return (await repo.watchBook(id).first)!;
  }

  test('a trashed book leaves every view but keeps its row and its files',
      () async {
    final book = await seedBook('b1', 'Dune');
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b2', title: 'A'));

    await trash.trash(book.id);

    final queries = LibraryQueries(db);
    expect([for (final b in await queries.watchAllBooks().first) b.id], ['b2'],
        reason: 'watchAllBooks hides the trashed book');
    final view = await queries.watchLibrary().first;
    expect([for (final e in view.entries) e.book.id], ['b2'],
        reason: 'the shelf view-model filters it centrally');

    expect(await db.select(db.books).get(), hasLength(2),
        reason: 'the row is still there — nothing was deleted');
    expect(File('${dir.path}/covers/b1.jpg').existsSync(), isTrue,
        reason: 'the cover file is kept for the grace period');
    expect(await db.select(db.localDeletions).get(), isEmpty,
        reason: 'no tombstone yet — the server must not hear about this');
  });

  test('restore round-trips the book back onto the shelf', () async {
    final book = await seedBook('b1', 'Dune');
    await trash.trash(book.id);
    expect(await trash.watchTrashed().first, hasLength(1));

    await trash.restore(book.id);

    expect(await trash.watchTrashed().first, isEmpty);
    final queries = LibraryQueries(db);
    expect([for (final b in await queries.watchAllBooks().first) b.id], ['b1']);
  });

  test('trashing leaves updatedAt and needsPush exactly as they were',
      () async {
    final book = await seedBook('b1', 'Dune');
    await trash.trash(book.id);

    final after = (await repo.watchBook('b1').first)!;
    expect(after.updatedAt, book.updatedAt,
        reason: 'trashing is local and reversible — not a sync-clock event');
    expect(after.needsPush, book.needsPush,
        reason: 'a restore must pick up whatever was owed before');
  });

  test('the sweep deletes only what has outlived the grace period', () async {
    final stale = await seedBook('old', 'Old');
    final fresh = await seedBook('new', 'New');

    final now = DateTime.now();
    await (db.update(db.books)..where((b) => b.id.equals(stale.id))).write(
      BooksCompanion(
        deletedAt: Value(now.subtract(TrashService.graceperiod +
            const Duration(days: 1))),
      ),
    );
    await (db.update(db.books)..where((b) => b.id.equals(fresh.id))).write(
      BooksCompanion(deletedAt: Value(now.subtract(const Duration(days: 1)))),
    );

    expect(await trash.sweep(now: now), 1);

    expect([for (final b in await db.select(db.books).get()) b.id], ['new'],
        reason: 'only the expired book was really deleted');
    expect(File('${dir.path}/covers/old.jpg').existsSync(), isFalse,
        reason: 'the real delete takes the blobs with it');
    expect(
      [for (final d in await db.select(db.localDeletions).get()) d.bookId],
      ['old'],
      reason: 'and writes the tombstone, so the deletion finally propagates',
    );
  });

  test('deleteNow skips the wait and tombstones immediately', () async {
    final book = await seedBook('b1', 'Dune');
    await trash.trash(book.id);

    await trash.deleteNow((await repo.watchBook('b1').first)!);

    expect(await db.select(db.books).get(), isEmpty);
    expect(
      [for (final d in await db.select(db.localDeletions).get()) d.bookId],
      ['b1'],
    );
  });

  test('a trashed book is not counted as work waiting to be pushed', () async {
    await seedBook('b1', 'Dune');
    final queries = LibraryQueries(db);
    expect(await queries.watchDirtyCount().first, 1,
        reason: 'needsPush defaults true, so a fresh book is dirty');

    await trash.trash('b1');
    expect(await queries.watchDirtyCount().first, 0,
        reason: 'it stops pushing until the grace period expires');
  });

  test('an all-trashed library reads as empty, not as "nothing matched"',
      () async {
    await seedBook('b1', 'Dune');
    await trash.trash('b1');
    final view = await LibraryQueries(db).watchLibrary().first;
    expect(view.scopeEmpty, isTrue);
  });
}
