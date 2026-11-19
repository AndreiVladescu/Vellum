// The Audiobooks facet (v1.5.2): watchLibrary(audioOnly:) keeps books with an
// audio part, whether or not they also have text, and every entry says how long
// its audio is so the shelf can size the spine and badge it.
import 'package:drift/drift.dart' show Value;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_queries.dart';
import 'package:vellum/settings/shelf_sort.dart';

Future<VellumDatabase> _seeded() async {
  final db = VellumDatabase(NativeDatabase.memory());

  Future<void> book(String id, String title) =>
      db.into(db.books).insert(BooksCompanion.insert(id: id, title: title));

  Future<void> file(String bookId, String format,
      {int? ms, int track = 1, String? suffix}) {
    final id = '$bookId-$format${suffix ?? ''}';
    return db.into(db.bookFiles).insert(BookFilesCompanion.insert(
          id: id,
          bookId: bookId,
          format: format,
          path: 'files/$id.$format',
          sizeBytes: 1,
          sha256: id,
          durationMs: Value(ms),
          track: Value(format == 'pdf' || format == 'epub' ? null : track),
        ));
  }

  await book('text', 'Only text');
  await book('audio', 'Only audio');
  await book('both', 'Text and audio');
  await book('none', 'Paper only');
  await book('unmeasured', 'Audio without durations');
  await book('multi', 'Two parts');

  await file('text', 'epub');
  await file('audio', 'm4b', ms: 3600000);
  await file('both', 'epub');
  await file('both', 'mp3', ms: 7200000);
  await file('unmeasured', 'mp3');
  await file('multi', 'mp3', ms: 1800000, track: 1);
  await file('multi', 'mp3', ms: 900000, track: 2, suffix: '-2');
  return db;
}

List<String> _ids(LibraryView v) => [for (final e in v.entries) e.book.id];

void main() {
  test('audioOnly keeps every book with an audio part, text or not', () async {
    final db = await _seeded();
    addTearDown(db.close);
    final q = LibraryQueries(db);

    final all = await q.watchLibrary(sort: ShelfSort.title).first;
    expect(_ids(all).length, 6);

    final audio =
        await q.watchLibrary(audioOnly: true, sort: ShelfSort.title).first;
    expect(_ids(audio), ['unmeasured', 'audio', 'both', 'multi']);
  });

  test('it combines with the other facets and with sorting', () async {
    final db = await _seeded();
    addTearDown(db.close);
    await db.into(db.genres).insert(GenresCompanion.insert(id: 'g', name: 'SF'));
    await db
        .into(db.bookGenres)
        .insert(BookGenresCompanion.insert(bookId: 'both', genreId: 'g'));
    await db
        .into(db.bookGenres)
        .insert(BookGenresCompanion.insert(bookId: 'text', genreId: 'g'));

    final view = await LibraryQueries(db)
        .watchLibrary(audioOnly: true, genre: 'SF')
        .first;
    expect(_ids(view), ['both'], reason: 'SF and has audio, not just SF');

    final searched = await LibraryQueries(db)
        .watchLibrary(audioOnly: true, query: 'text')
        .first;
    expect(_ids(searched), ['both'], reason: 'the text-only book is out');
  });

  test('entries carry the audio length: summed, zero if unknown, else null',
      () async {
    final db = await _seeded();
    addTearDown(db.close);
    final view = await LibraryQueries(db).watchLibrary().first;
    final ms = {for (final e in view.entries) e.book.id: e.audioMs};
    expect(ms['audio'], 3600000);
    expect(ms['both'], 7200000, reason: 'the epub adds nothing');
    expect(ms['multi'], 2700000, reason: 'parts are summed');
    expect(ms['unmeasured'], 0, reason: 'audio, length not known');
    expect(ms['text'], isNull);
    expect(ms['none'], isNull);
    final byId = {for (final e in view.entries) e.book.id: e};
    expect(byId['unmeasured']!.hasAudio, isTrue);
    expect(byId['text']!.hasAudio, isFalse);
  });

  test('watchHasAudio follows the library', () async {
    final db = VellumDatabase(NativeDatabase.memory());
    addTearDown(db.close);
    final q = LibraryQueries(db);
    await db
        .into(db.books)
        .insert(BooksCompanion.insert(id: 'b', title: 'Book'));
    expect(await q.watchHasAudio().first, isFalse);
    await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
          id: 'f',
          bookId: 'b',
          format: 'epub',
          path: 'f.epub',
          sizeBytes: 1,
          sha256: 'x',
        ));
    expect(await q.watchHasAudio().first, isFalse, reason: 'text is not audio');
    await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
          id: 'g',
          bookId: 'b',
          format: 'm4b',
          path: 'g.m4b',
          sizeBytes: 1,
          sha256: 'y',
          durationMs: const Value(1000),
          track: const Value(1),
        ));
    expect(await q.watchHasAudio().first, isTrue);
  });
}
