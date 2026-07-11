import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

part 'database.g.dart';

// Mirrors server/migrations/0001_init.sql — keep the two in sync (DESIGN.md).

class Books extends Table {
  TextColumn get id => text()();
  TextColumn get title => text()();
  TextColumn get subtitle => text().nullable()();
  TextColumn get description => text().nullable()();
  TextColumn get isbn => text().nullable()();
  TextColumn get publisher => text().nullable()();
  IntColumn get publishedYear => integer().nullable()();
  IntColumn get pageCount => integer().nullable()();
  TextColumn get coverPath => text().nullable()();
  TextColumn get spineStyle => text().nullable()(); // JSON: generated spine params
  // Reading state (null progress = never opened).
  RealColumn get readingProgress => real().nullable()(); // 0..1
  IntColumn get lastReadPage => integer().nullable()();
  DateTimeColumn get lastReadAt => dateTime().nullable()();
  // Personal reader notes. Local-only — never pushed to or pulled from a server.
  TextColumn get readerNotes => text().nullable()();
  // JSON snapshot of the official library metadata this book was imported with,
  // so edits can be reverted to the source. Null for custom (manual) books.
  TextColumn get sourceMetadata => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  // Sync bookkeeping — app-local only, never mirrored on the server (like
  // reading state / readerNotes). `needsPush` marks a book whose synced
  // metadata, authors/genres, cover, or files changed since the last successful
  // push; it defaults true so every pre-existing row pushes once after upgrade.
  // `coverEtag` is the server ETag of the cover we last downloaded, for
  // conditional cover pulls (see IMPROVEMENT_PLAN_2 §D24).
  BoolColumn get needsPush => boolean().withDefault(const Constant(true))();
  TextColumn get coverEtag => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

class Authors extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();

  @override
  Set<Column> get primaryKey => {id};
}

class BookAuthors extends Table {
  TextColumn get bookId => text().references(Books, #id)();
  TextColumn get authorId => text().references(Authors, #id)();
  IntColumn get position => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {bookId, authorId};
}

class Genres extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Canonical display form for a genre name: trimmed, internal whitespace
/// collapsed to single spaces, and Title Cased. So spacing/case variants like
/// "computer  security" and "Computer Security" collapse to one canonical
/// "Computer Security", keeping the genre set small and tidy. Applied on every
/// write and by the v8 data migration that merges pre-existing duplicates.
String canonicalGenreName(String raw) => raw
    .trim()
    .split(RegExp(r'\s+'))
    .where((w) => w.isNotEmpty)
    .map((w) => w[0].toUpperCase() + w.substring(1).toLowerCase())
    .join(' ');

class BookGenres extends Table {
  TextColumn get bookId => text().references(Books, #id)();
  TextColumn get genreId => text().references(Genres, #id)();

  @override
  Set<Column> get primaryKey => {bookId, genreId};
}

/// Digital files attached to a book (0..n): a book may be physical-only,
/// digital-only, or both, possibly in several formats.
class BookFiles extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text().references(Books, #id)();
  TextColumn get format => text()(); // 'pdf', 'epub', ...
  TextColumn get path => text()();
  IntColumn get sizeBytes => integer()();
  TextColumn get sha256 => text()();
  DateTimeColumn get addedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

@DataClassName('PhysicalCopy')
class PhysicalCopies extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text().references(Books, #id)();
  TextColumn get location => text().nullable()(); // e.g. "living room, shelf 3"
  TextColumn get condition => text().nullable()();
  TextColumn get notes => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Loan history per physical copy; the active loan is the row with
/// returnedAt == null.
class Loans extends Table {
  TextColumn get id => text()();
  TextColumn get copyId => text().references(PhysicalCopies, #id)();
  TextColumn get borrower => text()();
  DateTimeColumn get loanedAt => dateTime().withDefault(currentDateAndTime)();
  DateTimeColumn get returnedAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Manual collections/panes, independent of genres, with explicit ordering.
@DataClassName('Shelf')
class Shelves extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

class ShelfBooks extends Table {
  TextColumn get shelfId => text().references(Shelves, #id)();
  TextColumn get bookId => text().references(Books, #id)();
  IntColumn get position => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {shelfId, bookId};
}

// ---------------------------------------------------------------------------
// Physical bookshelf layouts. These three tables are **app-local only** — a
// personal, per-device arrangement of physical copies in a to-scale room — and
// are deliberately NOT part of the server schema or sync payloads. All lengths
// are stored in metres; a front-elevation view (X right, Y up) renders them.
// ---------------------------------------------------------------------------

/// One physical space ("library") holding shelves and placed books.
@DataClassName('PhysicalEnvironment')
class PhysicalEnvironments extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// A flat resting surface, defined by two points in metres (a book sits on the
/// segment). Horizontal in practice, but both endpoints are stored so a shelf
/// can later be angled.
@DataClassName('PhysicalShelf')
class PhysicalShelves extends Table {
  TextColumn get id => text()();
  TextColumn get environmentId => text().references(PhysicalEnvironments, #id)();
  RealColumn get x1 => real()();
  RealColumn get y1 => real()();
  RealColumn get x2 => real()();
  RealColumn get y2 => real()();
  TextColumn get label => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// A single physical copy placed in an environment. `(x, y)` is the bottom-left
/// of its footprint in metres; `rotation` is 0 (spine up) or 90 (lying flat).
/// The width (thickness) and height default from the book's page count but can
/// be overridden per placement.
@DataClassName('BookPlacement')
class BookPlacements extends Table {
  TextColumn get id => text()();
  TextColumn get environmentId => text().references(PhysicalEnvironments, #id)();
  TextColumn get copyId => text().references(PhysicalCopies, #id)();
  RealColumn get x => real()();
  RealColumn get y => real()();
  IntColumn get rotation => integer().withDefault(const Constant(0))();
  RealColumn get widthOverride => real().nullable()();
  RealColumn get heightOverride => real().nullable()();
  // Optional size preset key (see physical_metrics.dart) that drives the
  // default thickness/height from the page count; overrides above still win.
  TextColumn get format => text().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// Books deleted on this device, remembered until the deletion has been pushed
/// to the server (rows are tiny; in standalone mode they simply linger). This
/// is app-local bookkeeping and is intentionally NOT mirrored in the server
/// schema — the server has its own `deletion` table with its own semantics.
@DataClassName('LocalDeletion')
class LocalDeletions extends Table {
  TextColumn get bookId => text()();
  DateTimeColumn get deletedAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {bookId};
}

@DriftDatabase(tables: [
  Books,
  Authors,
  BookAuthors,
  Genres,
  BookGenres,
  BookFiles,
  PhysicalCopies,
  Loans,
  Shelves,
  ShelfBooks,
  PhysicalEnvironments,
  PhysicalShelves,
  BookPlacements,
  LocalDeletions,
])
class VellumDatabase extends _$VellumDatabase {
  VellumDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 8;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          // Idempotent by design. `createTable` builds a table from the *latest*
          // schema, so a later `addColumn` for a column that table already has
          // (e.g. bookPlacements.format) would throw "duplicate column" — and a
          // partial migration that then aborts leaves objects created while
          // user_version lags, so the next open re-runs `createTable` and throws
          // "already exists". Guarding every step on what's actually present
          // makes upgrades safe to retry and self-heal such a stuck database.
          Future<Set<String>> tableNames() async => {
                for (final row in await customSelect(
                        "SELECT name FROM sqlite_master WHERE type='table'")
                    .get())
                  row.read<String>('name'),
              };
          Future<Set<String>> columnsOf(String table) async => {
                for (final row
                    in await customSelect('PRAGMA table_info($table)').get())
                  row.read<String>('name'),
              };

          final tables = await tableNames();
          final bookCols = await columnsOf('books');

          Future<void> addBookColumn(String name, GeneratedColumn column) async {
            if (!bookCols.contains(name)) await m.addColumn(books, column);
          }

          if (from < 2) {
            await addBookColumn('reading_progress', books.readingProgress);
            await addBookColumn('last_read_page', books.lastReadPage);
            await addBookColumn('last_read_at', books.lastReadAt);
          }
          if (from < 3) {
            await addBookColumn('reader_notes', books.readerNotes);
            await addBookColumn('source_metadata', books.sourceMetadata);
          }
          if (from < 4) {
            if (!tables.contains('physical_environments')) {
              await m.createTable(physicalEnvironments);
            }
            if (!tables.contains('physical_shelves')) {
              await m.createTable(physicalShelves);
            }
            if (!tables.contains('book_placements')) {
              await m.createTable(bookPlacements);
            }
          }
          if (from < 5) {
            if (!(await columnsOf('book_placements')).contains('format')) {
              await m.addColumn(bookPlacements, bookPlacements.format);
            }
          }
          if (from < 6) {
            if (!tables.contains('local_deletions')) {
              await m.createTable(localDeletions);
            }
          }
          if (from < 7) {
            await addBookColumn('needs_push', books.needsPush);
            await addBookColumn('cover_etag', books.coverEtag);
          }
          if (from < 8) {
            // Data-only: no schema change, so no matching server migration.
            await _mergeDuplicateGenres();
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// One-time cleanup: collapse genres that differ only by case/spacing into a
  /// single canonical row (e.g. "computer security" + "Computer Security" ->
  /// "Computer Security"). Duplicates are deleted *before* the keeper is renamed
  /// so the `UNIQUE(name)` constraint can't fire, and book_genres rows are
  /// repointed with OR IGNORE so a book tagged with both variants keeps one.
  Future<void> _mergeDuplicateGenres() async {
    // Defensive, like the rest of onUpgrade: a partially-built database may not
    // have these tables yet — nothing to merge if so.
    final present = {
      for (final r in await customSelect(
              "SELECT name FROM sqlite_master WHERE type='table' "
              "AND name IN ('genres', 'book_genres')")
          .get())
        r.read<String>('name'),
    };
    if (!present.contains('genres') || !present.contains('book_genres')) return;

    final rows = await customSelect('SELECT id, name FROM genres').get();
    final groups = <String, List<String>>{}; // canonical name -> genre ids
    final nameById = <String, String>{};
    for (final r in rows) {
      final id = r.read<String>('id');
      final name = r.read<String>('name');
      nameById[id] = name;
      (groups[canonicalGenreName(name)] ??= []).add(id);
    }
    for (final entry in groups.entries) {
      final canon = entry.key;
      final ids = entry.value;
      final keeper = ids.first;
      for (final dup in ids.skip(1)) {
        await customStatement(
          'UPDATE OR IGNORE book_genres SET genre_id = ? WHERE genre_id = ?',
          [keeper, dup],
        );
        await customStatement(
          'DELETE FROM book_genres WHERE genre_id = ?',
          [dup],
        );
        await customStatement('DELETE FROM genres WHERE id = ?', [dup]);
      }
      if (nameById[keeper] != canon) {
        await customStatement(
          'UPDATE genres SET name = ? WHERE id = ?',
          [canon, keeper],
        );
      }
    }
  }

  /// All books, alphabetically — reactive: the shelf UI rebuilds on changes.
  Stream<List<Book>> watchAllBooks() =>
      (select(books)..orderBy([(b) => OrderingTerm.asc(b.title)])).watch();

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'vellum');
  }
}
