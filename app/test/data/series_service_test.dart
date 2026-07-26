// Series and volume tracking (plan 5 #17). Two things matter: membership resolves
// by *name* so two devices converge on one series (the same rule authors and
// genres follow), and the gap list only claims a volume is missing when it really
// can tell — inventing gaps would make the most useful part of the feature
// untrustworthy.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/settings/shelf_sort.dart';
import 'package:vellum/shelf/shelf_filter.dart';

Future<LibraryRepository> _repo(Directory dir) async =>
    LibraryRepository.forTesting(VellumDatabase(NativeDatabase.memory()), dir);

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_series'));
  tearDown(() => dir.deleteSync(recursive: true));

  Future<LibraryRepository> withBooks(Map<String, String> titlesById) async {
    final repo = await _repo(dir);
    for (final e in titlesById.entries) {
      await repo.db.into(repo.db.books).insert(BooksCompanion.insert(
            id: e.key,
            title: e.value,
            needsPush: const Value(false),
          ));
    }
    return repo;
  }

  test('two books in the same series share one series row', () async {
    final repo = await withBooks({'b1': 'Dune', 'b2': 'Dune Messiah'});
    await repo.seriesService.setSeries('b1', 'Dune', 1);
    await repo.seriesService.setSeries('b2', 'Dune', 2);

    final rows = await repo.db.select(repo.db.series).get();
    expect(rows, hasLength(1), reason: 'resolved by name, not by a fresh id');
    expect(await repo.seriesService.nameOf('b2'), 'Dune');
  });

  test('a fractional volume is kept as given', () async {
    final repo = await withBooks({'b1': 'An Interquel'});
    await repo.seriesService.setSeries('b1', 'Dune', 1.5);
    expect((await repo.watchBook('b1').first)!.seriesIndex, 1.5);
  });

  test('a blank name clears the membership and the volume', () async {
    final repo = await withBooks({'b1': 'Dune'});
    await repo.seriesService.setSeries('b1', 'Dune', 1);
    await repo.seriesService.setSeries('b1', '  ', 1);

    final book = (await repo.watchBook('b1').first)!;
    expect(book.seriesId, isNull);
    expect(book.seriesIndex, isNull,
        reason: 'a volume number with no series is meaningless');
  });

  test('a series nobody references is swept', () async {
    final repo = await withBooks({'b1': 'Dune'});
    await repo.seriesService.setSeries('b1', 'Dune', 1);
    await repo.seriesService.setSeries('b1', 'Dune Chronicles', 1);

    final names = await repo.seriesService.watchNames().first;
    expect(names, ['Dune Chronicles'],
        reason: 'the renamed-away series must not linger in autocomplete');
  });

  test('setting a series marks the book for push — it is synced data', () async {
    final repo = await withBooks({'b1': 'Dune'});
    await repo.seriesService.setSeries('b1', 'Dune', 1);
    expect((await repo.watchBook('b1').first)!.needsPush, true);
  });

  group('gap detection', () {
    test('reports whole numbers missing between what you own', () {
      expect(SeriesService.gapsIn([1, 3, 4]), [2]);
      expect(SeriesService.gapsIn([1, 5]), [2, 3, 4]);
    });

    test('a complete run has no gaps', () {
      expect(SeriesService.gapsIn([1, 2, 3]), isEmpty);
    });

    test('fewer than two volumes cannot show a gap', () {
      // Owning only book 3 says nothing about 1 and 2 — the series might start
      // there for all we know.
      expect(SeriesService.gapsIn([3]), isEmpty);
      expect(SeriesService.gapsIn(const []), isEmpty);
    });

    test('only whole numbers are ever reported as missing', () {
      // A *fractional* volume is never claimed as a gap: a novella at 2.5 is
      // usually not something the reader meant to own, and inventing it would
      // make the feature cry wolf.
      expect(SeriesService.gapsIn([1, 2, 3, 4]), isEmpty);
      // Owning the novellas either side of volume 3, though, does imply 3 —
      // that is a whole number strictly inside the owned range.
      expect(SeriesService.gapsIn([2.5, 3.5]), [3]);
    });

    test('fractional volumes do not hide a whole-number gap', () {
      expect(SeriesService.gapsIn([1, 1.5, 3]), [2]);
    });
  });

  test('placeOf describes the book, its siblings and the gaps', () async {
    final repo =
        await withBooks({'b1': 'One', 'b2': 'Three', 'b3': 'Four', 'b4': 'Other'});
    await repo.seriesService.setSeries('b1', 'Dune', 1);
    await repo.seriesService.setSeries('b2', 'Dune', 3);
    await repo.seriesService.setSeries('b3', 'Dune', 4);

    final place =
        await repo.seriesService.placeOf((await repo.watchBook('b1').first)!);
    expect(place, isNotNull);
    expect(place!.name, 'Dune');
    expect(place.index, 1);
    expect(place.owned, [1, 3, 4]);
    expect(place.gaps, [2]);
    expect(place.hasGaps, true);

    // A book in no series has no place at all.
    expect(
      await repo.seriesService.placeOf((await repo.watchBook('b4').first)!),
      isNull,
    );
  });

  test('the shelf can sort by series, with series-less books last', () async {
    final repo = await withBooks({
      'b1': 'Second Volume',
      'b2': 'First Volume',
      'b3': 'Unrelated',
    });
    await repo.seriesService.setSeries('b1', 'Dune', 2);
    await repo.seriesService.setSeries('b2', 'Dune', 1);

    final view =
        await repo.queries.watchLibrary(sort: ShelfSort.series).first;
    expect(
      view.entries.map((e) => e.book.title),
      ['First Volume', 'Second Volume', 'Unrelated'],
    );
  });

  test('the in-memory sort agrees with the SQL one about ordering', () async {
    // `sortBooks` is used for already-fetched lists; it must not disagree with
    // the shelf about where a series-less book goes.
    final repo = await withBooks({'b1': 'Two', 'b2': 'One', 'b3': 'None'});
    await repo.seriesService.setSeries('b1', 'Dune', 2);
    await repo.seriesService.setSeries('b2', 'Dune', 1);
    final books = await repo.db.select(repo.db.books).get();

    final sorted = sortBooks(
      books: books,
      sort: ShelfSort.series,
      authorsByBook: const {},
    );
    expect(sorted.last.title, 'None');
    expect(sorted.first.title, 'One');
  });
}
