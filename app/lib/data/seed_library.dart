import 'dart:math';

import 'package:drift/drift.dart';

import 'database.dart';

/// Deterministic, reasonably realistic synthetic library data for profiling
/// the shelf/search/sort query paths (see `docs/PERFORMANCE.md`) without a
/// real collection on hand. Populates books, authors, genres and shelves —
/// the tables §A's queries actually touch; physical layouts aren't.
///
/// Runs in batches so a large [count] doesn't hold one giant transaction in
/// memory, and reports progress via [onProgress] (`done` out of `total`).
Future<void> seedLibrary(
  VellumDatabase db, {
  required int count,
  int seed = 1,
  int shelfCount = 12,
  void Function(int done, int total)? onProgress,
}) async {
  final rng = Random(seed);
  final authorPoolSize = max(20, count ~/ 8);
  final authorIds = List.generate(authorPoolSize, (i) => 'seed-author-$i');
  final authorNames = _uniqueNames(authorPoolSize);
  final genreIds = List.generate(_genrePool.length, (i) => 'seed-genre-$i');
  final shelfIds = List.generate(shelfCount, (i) => 'seed-shelf-$i');

  await db.batch((b) {
    b.insertAll(db.authors, [
      for (var i = 0; i < authorPoolSize; i++)
        AuthorsCompanion.insert(id: authorIds[i], name: authorNames[i]),
    ]);
    b.insertAll(db.genres, [
      for (var i = 0; i < _genrePool.length; i++)
        GenresCompanion.insert(id: genreIds[i], name: _genrePool[i]),
    ]);
    b.insertAll(db.shelves, [
      for (var i = 0; i < shelfCount; i++)
        ShelvesCompanion.insert(
          id: shelfIds[i],
          name: '${_shelfAdjectives[i % _shelfAdjectives.length]} Shelf',
          sortOrder: Value(i),
        ),
    ]);
  });

  final shelfPositions = <String, int>{};
  const chunkSize = 500;
  for (var start = 0; start < count; start += chunkSize) {
    final end = min(start + chunkSize, count);
    final bookRows = <BooksCompanion>[];
    final authorRows = <BookAuthorsCompanion>[];
    final genreRows = <BookGenresCompanion>[];
    final shelfRows = <ShelfBooksCompanion>[];

    for (var i = start; i < end; i++) {
      final id = 'seed-book-$i';
      bookRows.add(BooksCompanion.insert(
        id: id,
        title: _titleFor(rng),
        subtitle: Value(rng.nextInt(4) == 0 ? _subtitleFor(rng) : null),
        isbn: Value(_isbnFor(rng)),
        publisher: Value(_publishers[rng.nextInt(_publishers.length)]),
        publishedYear: Value(1960 + rng.nextInt(66)),
        pageCount: Value(80 + rng.nextInt(700)),
      ));

      final authorCount = 1 + rng.nextInt(3);
      final pickedAuthors = <int>{
        for (var a = 0; a < authorCount; a++) rng.nextInt(authorPoolSize),
      };
      var pos = 0;
      for (final ai in pickedAuthors) {
        authorRows.add(BookAuthorsCompanion.insert(
          bookId: id,
          authorId: authorIds[ai],
          position: Value(pos++),
        ));
      }

      final pickedGenres = <int>{
        for (var g = 0; g < rng.nextInt(4); g++) rng.nextInt(_genrePool.length),
      };
      for (final gi in pickedGenres) {
        genreRows.add(
          BookGenresCompanion.insert(bookId: id, genreId: genreIds[gi]),
        );
      }

      // ~30% of books land on a shelf.
      if (rng.nextInt(10) < 3) {
        final shelfId = shelfIds[rng.nextInt(shelfCount)];
        final position = shelfPositions.update(
          shelfId,
          (p) => p + 1,
          ifAbsent: () => 0,
        );
        shelfRows.add(ShelfBooksCompanion.insert(
          shelfId: shelfId,
          bookId: id,
          position: Value(position),
        ));
      }
    }

    await db.batch((b) {
      b.insertAll(db.books, bookRows);
      b.insertAll(db.bookAuthors, authorRows);
      b.insertAll(db.bookGenres, genreRows);
      b.insertAll(db.shelfBooks, shelfRows);
    });
    onProgress?.call(end, count);
  }
}

/// First+last name combinations, appending a numeric disambiguator once the
/// pool of combinations is exhausted so `authors.name` (UNIQUE) never clashes.
List<String> _uniqueNames(int n) {
  final combos = _firstNames.length * _lastNames.length;
  return [
    for (var i = 0; i < n; i++)
      if (i < combos)
        '${_firstNames[i % _firstNames.length]} '
            '${_lastNames[i ~/ _firstNames.length]}'
      else
        '${_firstNames[i % _firstNames.length]} '
            '${_lastNames[(i ~/ _firstNames.length) % _lastNames.length]} '
            '${i ~/ combos + 1}',
  ];
}

String _titleFor(Random rng) {
  final adj = _adjectives[rng.nextInt(_adjectives.length)];
  final noun = _nouns[rng.nextInt(_nouns.length)];
  switch (rng.nextInt(4)) {
    case 0:
      return 'The $adj $noun';
    case 1:
      final noun2 = _nouns[rng.nextInt(_nouns.length)];
      return '$noun of the $noun2';
    case 2:
      return '$adj $noun';
    default:
      final noun2 = _nouns[rng.nextInt(_nouns.length)];
      return 'The $noun and the $adj $noun2';
  }
}

String _subtitleFor(Random rng) {
  final noun = _nouns[rng.nextInt(_nouns.length)];
  return 'A History of the $noun';
}

String _isbnFor(Random rng) =>
    '978${List.generate(10, (_) => rng.nextInt(10)).join()}';

const _firstNames = [
  'Ada', 'Baran', 'Chidi', 'Delia', 'Elin', 'Farid', 'Greta', 'Hiro',
  'Ines', 'Jorge', 'Kaya', 'Lior', 'Mira', 'Noor', 'Otto', 'Priya',
  'Quinn', 'Rosa', 'Saoirse', 'Taro', 'Uma', 'Viktor', 'Wren', 'Xiu',
  'Yara', 'Zane', 'Amara', 'Bo', 'Celia', 'Dov',
];

const _lastNames = [
  'Adeyemi', 'Bergman', 'Castellanos', 'Dubois', 'Eriksson', 'Farrow',
  'Girard', 'Haddad', 'Ivanov', 'Jansen', 'Kowalski', 'Larsson', 'Mercer',
  'Nakamura', 'Okafor', 'Petrov', 'Quintero', 'Reyes', 'Sato', 'Thorne',
  'Ulfsson', 'Vance', 'Webb', 'Xander', 'Yilmaz', 'Zamora', 'Abernathy',
  'Byrne', 'Castillo', 'Drummond',
];

const _adjectives = [
  'Silent', 'Hidden', 'Last', 'Broken', 'Golden', 'Forgotten', 'Distant',
  'Quiet', 'Endless', 'Crimson', 'Wandering', 'Lost', 'Secret', 'Frozen',
  'Burning',
];

const _nouns = [
  'Garden', 'River', 'Kingdom', 'Shadow', 'Library', 'Mountain', 'City',
  'Ocean', 'Forest', 'Star', 'Clock', 'Letter', 'Bridge', 'Storm', 'Door',
];

const _publishers = [
  'Northwind Press', 'Harborlight Books', 'Cinder & Sage', 'Meridian House',
  'Thistle Editions', 'Antler Books', 'Greywolf Studio', 'Cobalt & Co.',
];

const _shelfAdjectives = [
  'Favourite', 'Read Next', 'Reference', 'Loaned Out', 'Rare', 'Classics',
  'Signed Copies', 'To Reread', 'Travel', 'Gifts', 'Course Reading', 'Boxed',
];

const _genrePool = [
  'Science Fiction', 'Fantasy', 'Mystery', 'Thriller', 'Romance',
  'Historical Fiction', 'Literary Fiction', 'Horror', 'Biography', 'Memoir',
  'Poetry', 'Philosophy', 'History', 'Science', 'Mathematics',
  'Computer Science', 'Self-Help', 'Business', 'Travel', 'True Crime',
  'Young Adult', 'Graphic Novel', 'Classics', 'Essays',
];
