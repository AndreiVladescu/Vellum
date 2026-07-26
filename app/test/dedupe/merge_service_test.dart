// Merging two books (plan 5 #21b). A merge is destructive and irreversible, so
// what these pin is that *nothing is lost*: every file, copy, placement, loan,
// shelf membership, author and genre has to arrive on the keeper, and the loser
// has to leave a tombstone so the merge reaches the server instead of the
// duplicate coming back on the next pull.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/dedupe/merge_service.dart';

Future<LibraryRepository> _repo(Directory dir) async =>
    LibraryRepository.forTesting(VellumDatabase(NativeDatabase.memory()), dir);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_merge_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<void> seedBook(
    VellumDatabase db,
    String id,
    String title, {
    String? isbn,
    String? publisher,
    int? year,
    int? pages,
    String? description,
    String? coverPath,
    double? progress,
    int? page,
  }) =>
      db.into(db.books).insert(BooksCompanion.insert(
            id: id,
            title: title,
            isbn: Value(isbn),
            publisher: Value(publisher),
            publishedYear: Value(year),
            pageCount: Value(pages),
            description: Value(description),
            coverPath: Value(coverPath),
            readingProgress: Value(progress),
            lastReadPage: Value(page),
            needsPush: const Value(false),
          ));

  Future<void> attachRow(
    VellumDatabase db,
    String bookId,
    String fileId,
    String hash,
  ) =>
      db.into(db.bookFiles).insert(BookFilesCompanion.insert(
            id: fileId,
            bookId: bookId,
            format: 'pdf',
            path: p.join('files', '$fileId.pdf'),
            sizeBytes: 10,
            sha256: hash,
          ));

  test('files, copies, placements and loans all move to the keeper', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await seedBook(db, 'keep', 'Dune');
    await seedBook(db, 'dupe', 'Dune');
    await attachRow(db, 'keep', 'f1', 'hash-1');
    await attachRow(db, 'dupe', 'f2', 'hash-2');
    // The duplicate is the one with the physical copy, its placement and a loan.
    final copyId = await repo.addPhysicalCopy('dupe');
    await repo.lendCopy(copyId, 'Alice');
    final envId = await repo.layout.createEnvironment('Study');
    await repo.layout.placeBook(envId, 'dupe', x: 1, y: 2);

    final log = await MergeService(repo).merge(keeperId: 'keep', loserId: 'dupe');

    final files = await db.select(db.bookFiles).get();
    expect(files, hasLength(2));
    expect({for (final f in files) f.bookId}, {'keep'});

    final copies = await db.select(db.physicalCopies).get();
    expect(copies.map((c) => c.bookId).toSet(), {'keep'});
    expect(copies, hasLength(2), reason: 'addPhysicalCopy + placeBook each mint one');
    // Placements and loans are keyed by copy, so they follow without touching.
    expect(await db.select(db.bookPlacements).get(), hasLength(1));
    final loans = await db.select(db.loans).get();
    expect(loans, hasLength(1));
    expect(loans.single.borrower, 'Alice');

    expect(log.entries.join('\n'), contains('moved 1 file'));
    expect(log.entries.join('\n'), contains('physical copy'));
  });

  test('the loser is deleted and tombstoned so the merge syncs', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await seedBook(db, 'keep', 'Dune');
    await seedBook(db, 'dupe', 'Dune');

    await MergeService(repo).merge(keeperId: 'keep', loserId: 'dupe');

    expect(await repo.watchBook('dupe').first, isNull);
    final tombstones = await db.select(db.localDeletions).get();
    expect(tombstones.map((t) => t.bookId), contains('dupe'));
    // And the survivor is dirty, since its metadata may have changed.
    expect((await repo.watchBook('keep').first)?.needsPush, true);
  });

  test('blank fields on the keeper are filled from the duplicate', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await seedBook(db, 'keep', 'Dune');
    await seedBook(
      db,
      'dupe',
      'Dune',
      isbn: '9780441013593',
      publisher: 'Ace',
      year: 1965,
      pages: 412,
      description: 'A desert planet.',
    );

    await MergeService(repo).merge(keeperId: 'keep', loserId: 'dupe');

    final kept = (await repo.watchBook('keep').first)!;
    expect(kept.isbn, '9780441013593');
    expect(kept.publisher, 'Ace');
    expect(kept.publishedYear, 1965);
    expect(kept.pageCount, 412);
    expect(kept.description, 'A desert planet.');
  });

  test('a value the keeper already has is not overwritten', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await seedBook(db, 'keep', 'Dune', publisher: 'Gollancz', year: 1966);
    await seedBook(db, 'dupe', 'Dune', publisher: 'Ace', year: 1965);

    await MergeService(repo).merge(keeperId: 'keep', loserId: 'dupe');

    final kept = (await repo.watchBook('keep').first)!;
    expect(kept.publisher, 'Gollancz');
    expect(kept.publishedYear, 1966);
  });

  test('conflicts are reported per field and resolvable either way', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await seedBook(db, 'keep', 'Dune', publisher: 'Gollancz', year: 1966);
    await seedBook(db, 'dupe', 'Dune: A Novel', publisher: 'Ace', year: 1965);
    final service = MergeService(repo);

    final keeper = (await repo.watchBook('keep').first)!;
    final loser = (await repo.watchBook('dupe').first)!;
    final conflicts = await service.conflictsBetween(keeper, loser);
    expect(
      conflicts.map((c) => c.field).toSet(),
      {'title', 'publisher', 'publishedYear'},
    );
    final title = conflicts.firstWhere((c) => c.field == 'title');
    expect(title.keeperValue, 'Dune');
    expect(title.loserValue, 'Dune: A Novel');

    await service.merge(
      keeperId: 'keep',
      loserId: 'dupe',
      choices: {
        'title': MergeChoice.loser,
        'publishedYear': MergeChoice.loser,
        // publisher deliberately unspecified: the keeper's value stands.
      },
    );

    final kept = (await repo.watchBook('keep').first)!;
    expect(kept.title, 'Dune: A Novel');
    expect(kept.publishedYear, 1965);
    expect(kept.publisher, 'Gollancz');
  });

  test('shelf memberships move, and a shared shelf does not collide', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await seedBook(db, 'keep', 'Dune');
    await seedBook(db, 'dupe', 'Dune');
    final shared = await repo.createShelf('Favourites');
    final only = await repo.createShelf('Sci-fi');
    await repo.addToShelf('keep', shared);
    await repo.addToShelf('dupe', shared); // both on this one
    await repo.addToShelf('dupe', only); // only the duplicate on this one

    await MergeService(repo).merge(keeperId: 'keep', loserId: 'dupe');

    final rows = await db.select(db.shelfBooks).get();
    expect(rows.map((r) => r.bookId).toSet(), {'keep'});
    expect(
      rows.map((r) => r.shelfId).toSet(),
      {shared, only},
      reason: 'the shelf only the duplicate was on must not be lost',
    );
    expect(rows, hasLength(2), reason: 'the shared shelf keeps one row');
    // The shelves changed membership, so they are queued for push.
    for (final shelf in await db.select(db.shelves).get()) {
      expect(shelf.needsPush, true);
    }
  });

  test('authors and genres are unioned, not replaced', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await seedBook(db, 'keep', 'Dune');
    await seedBook(db, 'dupe', 'Dune');
    await repo.setAuthors('keep', ['Frank Herbert']);
    await repo.setAuthors('dupe', ['Frank Herbert', 'Brian Herbert']);
    await repo.setGenres('keep', ['Science Fiction']);
    await repo.setGenres('dupe', ['Classics']);

    await MergeService(repo).merge(keeperId: 'keep', loserId: 'dupe');

    final details = await repo.detailsFor('keep');
    expect(details.authors, ['Frank Herbert', 'Brian Herbert'],
        reason: 'keeper order first, then the duplicate’s extras');
    expect(details.genres.toSet(), {'Science Fiction', 'Classics'});
  });

  test('the further-along reading position survives', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await seedBook(db, 'keep', 'Dune', progress: 0.1, page: 40);
    await seedBook(db, 'dupe', 'Dune', progress: 0.8, page: 320);

    await MergeService(repo).merge(keeperId: 'keep', loserId: 'dupe');

    final kept = (await repo.watchBook('keep').first)!;
    expect(kept.readingProgress, 0.8);
    expect(kept.lastReadPage, 320);
  });

  test('a keeper that is further along keeps its own position', () async {
    final repo = await _repo(dir);
    final db = repo.db;
    await seedBook(db, 'keep', 'Dune', progress: 0.9, page: 380);
    await seedBook(db, 'dupe', 'Dune', progress: 0.2, page: 60);

    await MergeService(repo).merge(keeperId: 'keep', loserId: 'dupe');

    expect((await repo.watchBook('keep').first)?.lastReadPage, 380);
  });

  test('merging a book into itself is refused', () async {
    final repo = await _repo(dir);
    await seedBook(repo.db, 'keep', 'Dune');
    expect(
      () => MergeService(repo).merge(keeperId: 'keep', loserId: 'keep'),
      throwsArgumentError,
    );
  });

  test('a missing book is refused before anything is written', () async {
    final repo = await _repo(dir);
    await seedBook(repo.db, 'keep', 'Dune');
    await expectLater(
      () => MergeService(repo).merge(keeperId: 'keep', loserId: 'ghost'),
      throwsStateError,
    );
    // The survivor is untouched — in particular still not dirty.
    expect((await repo.watchBook('keep').first)?.needsPush, false);
  });
}
