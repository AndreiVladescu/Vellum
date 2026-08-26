// Where you are in each *file* of a book (8/25 request: "if I have an epub and
// pdf, how can I open each, and how do they sync with each other on page
// count?").
//
// Page 214 of a PDF is not page 214 of a translation, so each file keeps its
// own place. The rule worth pinning is that the carry-over is *offered* and
// never applied: a percentage is a guess about where the same passage falls,
// which is a fine thing to offer and a terrible thing to do silently.
import 'dart:io';

import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';

void main() {
  late Directory dir;
  late VellumDatabase db;
  late LibraryRepository repo;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vellum_file_pos');
    db = VellumDatabase(NativeDatabase.memory());
    repo = await LibraryRepository.forTesting(db, dir);
    await db.into(db.books).insert(BooksCompanion.insert(
          id: 'b1',
          title: 'Dune',
          pageCount: const Value(560),
        ));
    for (final (id, format) in [('f-pdf', 'pdf'), ('f-epub', 'epub')]) {
      await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
            id: id,
            bookId: 'b1',
            format: format,
            path: 'files/$id',
            sizeBytes: 1,
            sha256: id,
          ));
    }
  });

  tearDown(() async {
    await db.close();
    dir.deleteSync(recursive: true);
  });

  test('each file keeps its own place', () async {
    final positions = repo.readingPositions;
    await positions.saveFilePosition(
        fileId: 'f-pdf', bookId: 'b1', progress: 0.38, page: 214);
    await positions.saveFilePosition(
        fileId: 'f-epub', bookId: 'b1', progress: 0.11, page: 3);

    expect((await positions.positionOf('f-pdf'))?.lastReadPage, 214);
    expect((await positions.positionOf('f-epub'))?.lastReadPage, 3,
        reason: 'chapter three, not page 214');
  });

  test('a file never opened has no place, rather than page one', () async {
    expect(await repo.readingPositions.positionOf('f-epub'), isNull);
  });

  test('re-reading a file replaces its place rather than adding one', () async {
    final positions = repo.readingPositions;
    await positions.saveFilePosition(
        fileId: 'f-pdf', bookId: 'b1', progress: 0.1, page: 56);
    await positions.saveFilePosition(
        fileId: 'f-pdf', bookId: 'b1', progress: 0.5, page: 280);

    final all = await positions.positionsForBook('b1');
    expect(all, hasLength(1));
    expect(all.single.lastReadPage, 280);
  });

  group('opening the other file', () {
    test('offers the place you got to in the first', () async {
      final positions = repo.readingPositions;
      await positions.saveFilePosition(
          fileId: 'f-pdf', bookId: 'b1', progress: 0.38, page: 214);

      final offer = await positions.offerFromAnotherFile(
        bookId: 'b1',
        openingFileId: 'f-epub',
        pageCount: 24,
      );

      expect(offer, isNotNull);
      expect(offer!.progress, closeTo(0.38, 1e-9));
      expect(offer.page, 9, reason: '38% of twenty-four chapters');
      expect(offer.fromFileId, 'f-pdf');
    });

    test('says nothing when this file already has a place', () async {
      final positions = repo.readingPositions;
      await positions.saveFilePosition(
          fileId: 'f-pdf', bookId: 'b1', progress: 0.38, page: 214);
      await positions.saveFilePosition(
          fileId: 'f-epub', bookId: 'b1', progress: 0.11, page: 3);

      expect(
        await positions.offerFromAnotherFile(
            bookId: 'b1', openingFileId: 'f-epub', pageCount: 24),
        isNull,
        reason: 'where you actually are beats a translated percentage',
      );
    });

    test('says nothing about a file barely started', () async {
      // Two pages in is not a place worth carrying anywhere.
      await repo.readingPositions.saveFilePosition(
          fileId: 'f-pdf', bookId: 'b1', progress: 0.004, page: 2);

      expect(
        await repo.readingPositions.offerFromAnotherFile(
            bookId: 'b1', openingFileId: 'f-epub', pageCount: 24),
        isNull,
      );
    });

    test('nor about one you finished', () async {
      await repo.readingPositions.saveFilePosition(
          fileId: 'f-pdf', bookId: 'b1', progress: 1, page: 560);

      expect(
        await repo.readingPositions.offerFromAnotherFile(
            bookId: 'b1', openingFileId: 'f-epub', pageCount: 24),
        isNull,
        reason: 'opening the other one is starting it, not resuming',
      );
    });

    test('the offer never lands past the end', () async {
      await repo.readingPositions.saveFilePosition(
          fileId: 'f-pdf', bookId: 'b1', progress: 0.99, page: 554);

      final offer = await repo.readingPositions.offerFromAnotherFile(
          bookId: 'b1', openingFileId: 'f-epub', pageCount: 24);

      expect(offer!.page, lessThanOrEqualTo(24));
      expect(offer.page, greaterThanOrEqualTo(1));
    });

    test('a book of one file has nothing to offer', () async {
      await repo.readingPositions.saveFilePosition(
          fileId: 'f-pdf', bookId: 'b1', progress: 0.38, page: 214);

      expect(
        await repo.readingPositions.offerFromAnotherFile(
            bookId: 'b1', openingFileId: 'f-pdf', pageCount: 560),
        isNull,
      );
    });

    test('a file of unknown length is not guessed at', () async {
      await repo.readingPositions.saveFilePosition(
          fileId: 'f-pdf', bookId: 'b1', progress: 0.38, page: 214);

      expect(
        await repo.readingPositions.offerFromAnotherFile(
            bookId: 'b1', openingFileId: 'f-epub', pageCount: 0),
        isNull,
      );
    });
  });
}
