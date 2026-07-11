import 'dart:io';

import 'package:drift/drift.dart' show Variable;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages — transitive via drift, test-only fixture
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:vellum/data/database.dart';

/// Recreates the corrupted state seen in the wild: a database whose
/// `user_version` is stuck at 3 while the v4/v5 objects (the physical tables,
/// and `book_placements.format`) already exist — the result of a previously
/// aborted migration. Opening it must NOT throw and must finish the upgrade.
void main() {
  test('upgrade recovers a database stuck at v3 with v4/v5 objects present', () async {
    final dir = Directory.systemTemp.createTempSync('vellum_migration_test');
    final file = File('${dir.path}/vellum.sqlite');

    // Build the stuck-at-3 schema by hand with a raw sqlite connection.
    final db = raw.sqlite3.open(file.path);
    db.execute('''
      CREATE TABLE books (
        id TEXT NOT NULL PRIMARY KEY, title TEXT NOT NULL, subtitle TEXT,
        description TEXT, isbn TEXT, publisher TEXT, published_year INTEGER,
        page_count INTEGER, cover_path TEXT, spine_style TEXT,
        reading_progress REAL, last_read_page INTEGER, last_read_at INTEGER,
        reader_notes TEXT, source_metadata TEXT,
        created_at INTEGER NOT NULL, updated_at INTEGER NOT NULL);
      CREATE TABLE physical_environments (
        id TEXT NOT NULL PRIMARY KEY, name TEXT NOT NULL,
        sort_order INTEGER NOT NULL DEFAULT 0, created_at INTEGER NOT NULL);
      CREATE TABLE physical_shelves (
        id TEXT NOT NULL PRIMARY KEY, environment_id TEXT NOT NULL,
        x1 REAL NOT NULL, y1 REAL NOT NULL, x2 REAL NOT NULL, y2 REAL NOT NULL,
        label TEXT, created_at INTEGER NOT NULL);
      CREATE TABLE book_placements (
        id TEXT NOT NULL PRIMARY KEY, environment_id TEXT NOT NULL,
        copy_id TEXT NOT NULL, x REAL NOT NULL, y REAL NOT NULL,
        rotation INTEGER NOT NULL DEFAULT 0, width_override REAL,
        height_override REAL, format TEXT, created_at INTEGER NOT NULL);
    ''');
    // A real book that must survive the upgrade.
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    db.execute(
      "INSERT INTO books (id, title, created_at, updated_at) VALUES ('b1', 'Dune', $now, $now)",
    );
    db.execute('PRAGMA user_version = 3');
    db.close();

    // Open through drift — this triggers onUpgrade(3 -> 7).
    final vellum = VellumDatabase(NativeDatabase(file));
    // Forcing a query runs the migration; it must not throw "already exists".
    final books = await vellum.select(vellum.books).get();
    expect(books.map((b) => b.title), ['Dune'], reason: 'existing data preserved');

    // The v6 table now exists and is usable...
    await vellum
        .into(vellum.localDeletions)
        .insert(LocalDeletionsCompanion.insert(bookId: 'b1'));
    expect((await vellum.select(vellum.localDeletions).get()).length, 1);

    await vellum.close();
    dir.deleteSync(recursive: true);
  });

  test('v8 merges genres that differ only by case into one canonical row',
      () async {
    final dir = Directory.systemTemp.createTempSync('vellum_genre_merge_test');
    final file = File('${dir.path}/vellum.sqlite');

    // Seed two genres that differ only by case, both tagging the same book —
    // raw inserts bypass the write-path canonicalization so we recreate the
    // pre-v8 state exactly.
    final setup = VellumDatabase(NativeDatabase(file));
    final now = DateTime.now().millisecondsSinceEpoch ~/ 1000;
    await setup.customStatement(
      "INSERT INTO books (id, title, created_at, updated_at) "
      "VALUES ('b1', 'Dune', $now, $now)",
    );
    await setup.customStatement(
      "INSERT INTO genres (id, name) VALUES ('g1', 'computer security')",
    );
    await setup.customStatement(
      "INSERT INTO genres (id, name) VALUES ('g2', 'Computer Security')",
    );
    await setup.customStatement(
      "INSERT INTO book_genres (book_id, genre_id) VALUES ('b1', 'g1')",
    );
    await setup.customStatement(
      "INSERT INTO book_genres (book_id, genre_id) VALUES ('b1', 'g2')",
    );
    // Rewind user_version so opening again re-runs the v8 data migration.
    await setup.customStatement('PRAGMA user_version = 7');
    await setup.close();

    final vellum = VellumDatabase(NativeDatabase(file));
    final genres =
        await vellum.customSelect('SELECT name FROM genres').get();
    expect(
      genres.map((r) => r.read<String>('name')),
      ['Computer Security'],
      reason: 'the two case variants collapse into one canonical genre',
    );
    final links = await vellum.customSelect(
      'SELECT genre_id FROM book_genres WHERE book_id = ?',
      variables: [Variable.withString('b1')],
    ).get();
    expect(links.length, 1, reason: 'the book keeps the genre exactly once');

    await vellum.close();
    dir.deleteSync(recursive: true);
  });
}
