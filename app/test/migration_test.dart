import 'dart:io';

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

    // Open through drift — this triggers onUpgrade(3 -> 6).
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
}
