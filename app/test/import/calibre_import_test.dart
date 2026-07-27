// Reading a Calibre library (plan 5 #21c), against a real metadata.db built
// with Calibre's own schema — the parts of it this reader touches. A fixture
// rather than a mock, because the whole risk in this feature is that someone
// else's schema isn't what you assumed.
import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
// ignore: depend_on_referenced_packages — transitive via drift, test-only fixture
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:vellum/import/calibre_import.dart';

/// Builds a Calibre library on disk: metadata.db plus the per-book folders
/// Calibre lays out as `<Author>/<Title> (<id>)/<name>.<ext>`.
Directory buildLibrary(
  Directory root, {
  bool withIdentifiers = true,
  bool withCover = true,
}) {
  final db = raw.sqlite3.open(p.join(root.path, 'metadata.db'));
  db.execute('''
    CREATE TABLE books (
      id INTEGER PRIMARY KEY, title TEXT NOT NULL, sort TEXT, pubdate TIMESTAMP,
      series_index REAL NOT NULL DEFAULT 1.0, path TEXT NOT NULL DEFAULT '',
      has_cover BOOL DEFAULT 0);
    CREATE TABLE authors (id INTEGER PRIMARY KEY, name TEXT NOT NULL, sort TEXT);
    CREATE TABLE books_authors_link (
      id INTEGER PRIMARY KEY, book INTEGER NOT NULL, author INTEGER NOT NULL);
    CREATE TABLE publishers (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
    CREATE TABLE books_publishers_link (
      id INTEGER PRIMARY KEY, book INTEGER NOT NULL, publisher INTEGER NOT NULL);
    CREATE TABLE series (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
    CREATE TABLE books_series_link (
      id INTEGER PRIMARY KEY, book INTEGER NOT NULL, series INTEGER NOT NULL);
    CREATE TABLE tags (id INTEGER PRIMARY KEY, name TEXT NOT NULL);
    CREATE TABLE books_tags_link (
      id INTEGER PRIMARY KEY, book INTEGER NOT NULL, tag INTEGER NOT NULL);
    CREATE TABLE comments (
      id INTEGER PRIMARY KEY, book INTEGER NOT NULL, text TEXT NOT NULL);
    CREATE TABLE data (
      id INTEGER PRIMARY KEY, book INTEGER NOT NULL, format TEXT NOT NULL,
      uncompressed_size INTEGER, name TEXT NOT NULL);
  ''');
  if (withIdentifiers) {
    db.execute('''
      CREATE TABLE identifiers (
        id INTEGER PRIMARY KEY, book INTEGER NOT NULL, type TEXT NOT NULL,
        val TEXT NOT NULL);
    ''');
  }

  // Book 1: everything filled in, two formats.
  db.execute(
    "INSERT INTO books (id, title, sort, pubdate, series_index, path, has_cover) "
    "VALUES (1, 'Dune', 'Dune', '1965-08-01 00:00:00+00:00', 1.0, "
    "'Frank Herbert/Dune (1)', ${withCover ? 1 : 0})",
  );
  db.execute("INSERT INTO authors (id, name) VALUES (1, 'Frank Herbert')");
  db.execute("INSERT INTO books_authors_link (book, author) VALUES (1, 1)");
  db.execute("INSERT INTO publishers (id, name) VALUES (1, 'Chilton Books')");
  db.execute("INSERT INTO books_publishers_link (book, publisher) VALUES (1, 1)");
  db.execute("INSERT INTO series (id, name) VALUES (1, 'Dune Chronicles')");
  db.execute("INSERT INTO books_series_link (book, series) VALUES (1, 1)");
  db.execute("INSERT INTO tags (id, name) VALUES (1, 'Science Fiction')");
  db.execute("INSERT INTO tags (id, name) VALUES (2, 'Classics')");
  db.execute("INSERT INTO books_tags_link (book, tag) VALUES (1, 1)");
  db.execute("INSERT INTO books_tags_link (book, tag) VALUES (1, 2)");
  db.execute(
    "INSERT INTO comments (book, text) VALUES "
    "(1, '<div><p>A desert planet.</p><p>Spice &amp; politics.</p></div>')",
  );
  db.execute("INSERT INTO data (book, format, name) VALUES (1, 'EPUB', 'Dune')");
  db.execute("INSERT INTO data (book, format, name) VALUES (1, 'PDF', 'Dune')");
  db.execute("INSERT INTO data (book, format, name) VALUES (1, 'MOBI', 'Dune')");
  if (withIdentifiers) {
    db.execute(
      "INSERT INTO identifiers (book, type, val) "
      "VALUES (1, 'isbn', '9780441013593')",
    );
    db.execute(
      "INSERT INTO identifiers (book, type, val) VALUES (1, 'goodreads', '234225')",
    );
  }

  // Book 2: bare minimum — no author, no series, no files, unset pubdate.
  db.execute(
    "INSERT INTO books (id, title, sort, pubdate, series_index, path) "
    "VALUES (2, 'Untitled Notes', 'Untitled Notes', "
    "'0101-01-01 00:00:00+00:00', 1.0, 'Unknown/Untitled Notes (2)')",
  );
  db.close();

  final bookDir = Directory(p.join(root.path, 'Frank Herbert', 'Dune (1)'))
    ..createSync(recursive: true);
  File(p.join(bookDir.path, 'Dune.epub')).writeAsBytesSync([1, 2, 3]);
  File(p.join(bookDir.path, 'Dune.pdf')).writeAsBytesSync([4, 5, 6]);
  if (withCover) {
    File(p.join(bookDir.path, 'cover.jpg')).writeAsBytesSync([7, 8, 9]);
  }
  return root;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_calibre'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('reads the catalogue as Calibre states it', () async {
    final entries = await CalibreImport.read(buildLibrary(dir));

    final dune = entries.firstWhere((e) => e.title == 'Dune');
    expect(dune.authors, ['Frank Herbert']);
    expect(dune.publisher, 'Chilton Books');
    expect(dune.series, 'Dune Chronicles');
    expect(dune.seriesIndex, 1.0);
    expect(dune.year, 1965);
    expect(dune.isbn, '9780441013593');
    expect(dune.genres, ['Classics', 'Science Fiction']);
    expect(dune.description, 'A desert planet.\n\nSpice & politics.',
        reason: 'HTML comments become plain text');
  });

  test('resolves file paths through Calibre\'s own layout', () async {
    final entries = await CalibreImport.read(buildLibrary(dir));
    final dune = entries.where((e) => e.title == 'Dune').toList();

    expect(dune, hasLength(2), reason: 'one row per importable format');
    final paths = [for (final e in dune) e.filePath];
    expect(paths, containsAll([
      p.join(dir.path, 'Frank Herbert/Dune (1)', 'Dune.epub'),
      p.join(dir.path, 'Frank Herbert/Dune (1)', 'Dune.pdf'),
    ]));
    for (final path in paths) {
      expect(File(path!).existsSync(), isTrue);
    }
  });

  test('formats the app cannot open are left behind', () async {
    final entries = await CalibreImport.read(buildLibrary(dir));
    expect(
      [for (final e in entries) e.filePath].where((f) => f?.endsWith('.mobi') ?? false),
      isEmpty,
      reason: 'a book whose file nothing can read is worse than no book',
    );
  });

  test('a cover is picked up when Calibre says there is one', () async {
    final entries = await CalibreImport.read(buildLibrary(dir));
    final dune = entries.firstWhere((e) => e.title == 'Dune');
    expect(dune.coverPath, p.join(dir.path, 'Frank Herbert/Dune (1)', 'cover.jpg'));
    expect(File(dune.coverPath!).existsSync(), isTrue);

    // A second library needs its own folder: metadata.db is created, not
    // migrated, so building twice into one directory would fail on CREATE.
    final other = Directory(p.join(dir.path, 'other'))..createSync();
    final noCover =
        await CalibreImport.read(buildLibrary(other, withCover: false));
    expect(noCover.firstWhere((e) => e.title == 'Dune').coverPath, isNull);
  });

  test('a sparse book still imports, with nothing invented', () async {
    final entries = await CalibreImport.read(buildLibrary(dir));
    final notes = entries.firstWhere((e) => e.title == 'Untitled Notes');
    expect(notes.authors, isEmpty);
    expect(notes.series, isNull);
    expect(notes.filePath, isNull, reason: 'metadata-only is a valid row');
    expect(notes.year, isNull,
        reason: "Calibre's year-101 sentinel is not a publication date");
  });

  test('an old library with no identifiers table still reads', () async {
    // Calibre's schema has grown for fifteen years; one missing optional table
    // must not fail the whole catalogue.
    final other = Directory(p.join(dir.path, 'old'))..createSync();
    final entries =
        await CalibreImport.read(buildLibrary(other, withIdentifiers: false));
    expect(entries, isNotEmpty);
    expect(entries.first.isbn, isNull);
  });

  test('the user\'s metadata.db is never opened directly', () async {
    final library = buildLibrary(dir);
    final metadata = File(p.join(library.path, 'metadata.db'));
    final before = await metadata.lastModified();
    final bytesBefore = await metadata.readAsBytes();

    await CalibreImport.read(library);

    expect(await metadata.lastModified(), before);
    expect(await metadata.readAsBytes(), bytesBefore,
        reason: 'read from a copy, so a running Calibre is never disturbed');
  });

  test('a folder that is not a Calibre library says so', () async {
    final empty = Directory(p.join(dir.path, 'empty'))..createSync();
    expect(await CalibreImport.looksLikeLibrary(empty), isFalse);
    await expectLater(
      CalibreImport.read(empty),
      throwsA(isA<CalibreImportException>()),
    );
    expect(await CalibreImport.looksLikeLibrary(buildLibrary(dir)), isTrue);
  });
}
