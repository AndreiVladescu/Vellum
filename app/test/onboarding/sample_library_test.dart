// The bundled sample books: they import through the ordinary pipeline, pressing
// twice adds nothing, they stay off the sync server, and they can be removed
// without touching anything the user owns.
//
// Plain `test`, not `testWidgets`: drift and EPUB work under the widget tester's
// fake-async zone can hang rather than fail, and nothing here needs a widget.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/onboarding/sample_library.dart';
import 'package:vellum/reader/epub_book.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory dataDir;
  late LibraryRepository repo;
  late SampleLibrary samples;

  setUp(() async {
    dataDir = Directory.systemTemp.createTempSync('vellum_samples_data');
    repo = await LibraryRepository.forTesting(
        VellumDatabase(NativeDatabase.memory()), dataDir);
    samples = SampleLibrary(repo);
  });
  tearDown(() async {
    await repo.db.close();
    dataDir.deleteSync(recursive: true);
  });

  Future<List<Book>> allBooks() => repo.db.select(repo.db.books).get();
  final count = SampleLibrary.books.length;

  test('adds every sample with metadata, a cover, and the Samples shelf',
      () async {
    final result = await samples.add();
    expect(result.added, count);

    final books = await allBooks();
    expect(books.map((b) => b.title),
        unorderedEquals([for (final b in SampleLibrary.books) b.title]));
    final frankenstein = books.firstWhere((b) => b.title == 'Frankenstein');
    expect(frankenstein.publishedYear, 1818);
    for (final b in books) {
      expect(b.coverPath, isNotNull, reason: '${b.title} has an embedded cover');
    }
    final files = await repo.db.select(repo.db.bookFiles).get();
    expect(files, hasLength(count));
    expect(files.every((f) => f.format == 'epub'), isTrue);

    final shelves = await repo.db.select(repo.db.shelves).get();
    expect(shelves.single.name, SampleLibrary.shelfName);
    expect(await repo.db.select(repo.db.shelfBooks).get(), hasLength(count));
  });

  test("each bundled file opens in the app's own EPUB reader", () async {
    for (final b in SampleLibrary.books) {
      final book = await EpubBook.open(File(b.asset));
      expect(book.chapters, isNotEmpty, reason: b.asset);
    }
  });

  test('pressing it twice adds nothing', () async {
    await samples.add();
    final again = await samples.add();

    expect(again.added, 0);
    expect(again.alreadyThere, count);
    expect(await allBooks(), hasLength(count));
    expect(await repo.db.select(repo.db.bookFiles).get(), hasLength(count));
    expect(await repo.db.select(repo.db.shelves).get(), hasLength(1));
  });

  test('samples are device-only and the shelf is not queued for a push',
      () async {
    await samples.add();

    expect((await allBooks()).every((b) => b.syncExcluded), isTrue);
    final shelf = (await repo.db.select(repo.db.shelves).get()).single;
    expect(shelf.needsPush, isFalse);
  });

  test('a book the user already has is not duplicated', () async {
    await repo.createCustomBook(title: 'Frankenstein', author: 'Mary Shelley');

    final result = await samples.add();

    expect(result.added, count - 1);
    expect(result.alreadyThere, 1);
    expect((await allBooks()).where((b) => b.title == 'Frankenstein'),
        hasLength(1));
  });

  test('remove deletes the samples and their shelf, and only those', () async {
    final mine = await repo.createCustomBook(title: 'My Own Book');
    await samples.add();
    expect(await samples.watchCount().first, count);

    final removed = await samples.remove();

    expect(removed, count);
    expect((await allBooks()).single.id, mine);
    expect(await repo.db.select(repo.db.bookFiles).get(), isEmpty);
    expect(await repo.db.select(repo.db.shelves).get(), isEmpty);
    expect(await samples.watchCount().first, 0);

    // And they can come back.
    expect((await samples.add()).added, count);
  });

  test('remove keeps a Samples shelf the user has put their own book on',
      () async {
    final mine = await repo.createCustomBook(title: 'My Own Book');
    await samples.add();
    final shelf = (await repo.db.select(repo.db.shelves).get()).single;
    await repo.addToShelf(mine, shelf.id);

    await samples.remove();

    expect(await repo.db.select(repo.db.shelves).get(), hasLength(1));
    expect((await allBooks()).single.id, mine);
  });
}
