import 'dart:io';

import 'package:drift/drift.dart' show Value, Variable;
import 'package:drift/native.dart';
import 'package:drift_dev/api/migrations_native.dart' as verify;
import 'package:flutter_test/flutter_test.dart';
// ignore: depend_on_referenced_packages — transitive via drift, test-only fixture
import 'package:sqlite3/sqlite3.dart' as raw;
import 'package:vellum/data/database.dart';
import 'package:vellum/data/search_index.dart';

import 'generated/drift_schema_versions/schema.dart' as versions;

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

  test('v9 creates book_search and backfills existing books', () async {
    final dir = Directory.systemTemp.createTempSync('vellum_fts_migration_test');
    final file = File('${dir.path}/vellum.sqlite');

    // A book with an author and a genre, written the normal way (so
    // book_search is populated by the triggers as a side effect) — then
    // simulate "this database predates the search index" by dropping it and
    // rewinding user_version, so the next open must recreate it from scratch
    // via the backfill, not the triggers.
    final setup = VellumDatabase(NativeDatabase(file));
    await setup.into(setup.books).insert(
        BooksCompanion.insert(id: 'b1', title: 'Dune', subtitle: const Value('A Novel')));
    await setup
        .into(setup.authors)
        .insert(AuthorsCompanion.insert(id: 'a1', name: 'Frank Herbert'));
    await setup.into(setup.bookAuthors).insert(
        BookAuthorsCompanion.insert(bookId: 'b1', authorId: 'a1'));
    await setup
        .into(setup.genres)
        .insert(GenresCompanion.insert(id: 'g1', name: 'Science Fiction'));
    await setup.into(setup.bookGenres).insert(
        BookGenresCompanion.insert(bookId: 'b1', genreId: 'g1'));

    await setup.customStatement('DROP TABLE book_search');
    for (final name in bookSearchTriggers.keys) {
      await setup.customStatement('DROP TRIGGER $name');
    }
    await setup.customStatement('PRAGMA user_version = 8');
    await setup.close();

    final vellum = VellumDatabase(NativeDatabase(file));
    final byTitle = await vellum
        .customSelect(
          'SELECT book_id FROM book_search WHERE book_search MATCH ?',
          variables: [Variable.withString('"dune"*')],
        )
        .get();
    expect(byTitle.map((r) => r.read<String>('book_id')), ['b1']);

    final byAuthor = await vellum
        .customSelect(
          'SELECT book_id FROM book_search WHERE book_search MATCH ?',
          variables: [Variable.withString('"herbert"*')],
        )
        .get();
    expect(byAuthor.map((r) => r.read<String>('book_id')), ['b1'],
        reason: 'backfill computed the authors column, not just title');

    final byGenre = await vellum
        .customSelect(
          'SELECT book_id FROM book_search WHERE book_search MATCH ?',
          variables: [Variable.withString('genres:"science"*')],
        )
        .get();
    expect(byGenre.map((r) => r.read<String>('book_id')), ['b1'],
        reason: 'backfill computed the genres column too');

    await vellum.close();
    dir.deleteSync(recursive: true);
  });

  // Snapshots in test/drift_schemas/ (one per schemaVersion ever shipped,
  // dumped with `dart run drift_dev schema dump` from the historical commit
  // that introduced each version) plus the generated verifier in
  // test/generated/drift_schema_versions/ (`dart run drift_dev schema
  // generate`) let every one of them be replayed here, not just the ones a
  // handwritten fixture happens to cover. This is what an early user who
  // hasn't opened the app since v1 actually does on upgrade: the case above
  // (v3-stuck-with-v4-objects) is a *recovery* from a corrupted intermediate
  // state that no clean schemaAt(N) snapshot can reproduce, so it stays as
  // its own test rather than folding into this group.
  //
  // To add a version: bump schemaVersion, write the migration, then run
  //   dart run drift_dev schema dump lib/data/database.dart test/drift_schemas
  //   dart run drift_dev schema generate test/drift_schemas \
  //     test/generated/drift_schema_versions
  //
  // Do NOT pass --data-classes / --companions. The verifier only ever asks a
  // snapshot to *create* its tables and then diffs `sqlite_schema`; it never
  // calls `map()`, so those flags add a data class and a companion per table
  // per version — 84k lines of dead code across 20 snapshots — and regenerate
  // every existing file in the process, burying the one real change. This
  // comment said otherwise until 2026-07-27, and the churn duly happened.
  group('every historical schema version migrates cleanly to the latest', () {
    final verifier = verify.SchemaVerifier(versions.GeneratedHelper());
    final latest = versions.GeneratedHelper.versions.last;

    for (final version in versions.GeneratedHelper.versions) {
      test('v$version -> v$latest', () async {
        final connection = await verifier.startAt(version);
        final db = VellumDatabase(connection);
        addTearDown(db.close);
        // Runs the real VellumDatabase.migration strategy (the same
        // onUpgrade/beforeOpen a real app launch would run) and compares the
        // resulting sqlite_schema against what v$latest's tables declare.
        await verifier.migrateAndValidate(db, latest);
      });
    }
  });
}
