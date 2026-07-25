import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/book_write_service.dart';
import 'package:vellum/data/cover_service.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/metadata.dart';

BookWriteService _writes(VellumDatabase db, Directory dir) =>
    BookWriteService(db, dir, MetadataService(), CoverService(db, dir));

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_writes_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('saveEpubPosition stores and round-trips the global reading fraction',
      () async {
    final db = VellumDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final writes = _writes(db, dir);
    await db.into(db.books).insert(BooksCompanion.insert(id: 'e1', title: 'E'));

    // Chapter 2 of 4 (index 1), halfway scrolled → (1 + 0.5) / 4 = 0.375.
    await writes.saveEpubPosition('e1',
        chapterIndex: 1, chapterCount: 4, scrollFraction: 0.5);
    final book = await writes.watchBook('e1').first;
    expect(book!.lastReadPage, 2, reason: '1-based chapter, like PDF pages');
    expect(book.readingProgress, closeTo(0.375, 1e-9));

    // The reader recovers the in-chapter fraction as progress*count - chapter.
    final within = (book.readingProgress! * 4) - 1;
    expect(within, closeTo(0.5, 1e-9));
  });

  test('re-tagging and deleting sweep orphaned author rows', () async {
    final db = VellumDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final writes = _writes(db, dir);
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'A'));
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b2', title: 'B'));

    await writes.setAuthors('b1', ['Shared', 'Only One']);
    await writes.setAuthors('b2', ['Shared']);
    expect((await db.select(db.authors).get()).length, 2);

    // Re-tag b1 to drop "Only One" — it's now referenced by nothing.
    await writes.setAuthors('b1', ['Shared']);
    final names = [for (final a in await db.select(db.authors).get()) a.name];
    expect(names, ['Shared'], reason: 'orphaned author swept');

    // Deleting the last book referencing "Shared" removes it too.
    await writes.deleteBook(await writes.watchBook('b1').first as Book);
    await writes.deleteBook(await writes.watchBook('b2').first as Book);
    expect(await db.select(db.authors).get(), isEmpty);
  });

  test('canonicalGenreName trims, collapses spaces, and Title Cases', () {
    expect(canonicalGenreName('computer security'), 'Computer Security');
    expect(canonicalGenreName('Computer Security'), 'Computer Security');
    expect(canonicalGenreName('  COMPUTER   SECURITY  '), 'Computer Security');
    expect(canonicalGenreName(''), '');
    expect(canonicalGenreName('   '), '');
  });

  test('addGenre/removeGenre tag a book, canonicalize, and dedup', () async {
    final db = VellumDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final writes = _writes(db, dir);
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'X'));

    Future<List<String>> genres() => writes.watchGenresOf('b1').first;

    await writes.addGenre('b1', 'engineering');
    await writes.addGenre('b1', 'Engineering'); // same canonical -> no-op
    await writes.addGenre('b1', '  '); // blank -> ignored
    expect(await genres(), ['Engineering'], reason: 'canonicalized, deduped');

    await writes.addGenre('b1', 'fiction');
    expect(await genres(), ['Engineering', 'Fiction'],
        reason: 'ordered by name');
    expect(await writes.watchAllGenreNames().first, ['Engineering', 'Fiction']);

    await writes.removeGenre('b1', 'ENGINEERING'); // case-insensitive removal
    expect(await genres(), ['Fiction']);
    // Removing the last book with "Engineering" swept the orphaned genre.
    expect(await writes.watchAllGenreNames().first, ['Fiction']);
  });

  test('setGenres canonicalizes and dedups case/spacing variants', () async {
    final db = VellumDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final writes = _writes(db, dir);
    await db.into(db.books).insert(BooksCompanion.insert(id: 'b1', title: 'X'));

    // Variants that all canonicalize to the same genre must yield one row.
    await writes.setGenres('b1', ['computer security', 'Computer Security', '  ']);

    final genres = [for (final g in await db.select(db.genres).get()) g.name];
    expect(genres, ['Computer Security'],
        reason: 'one canonical genre, empties dropped');
    expect((await db.select(db.bookGenres).get()).length, 1,
        reason: 'book tagged with it exactly once');
  });
}
