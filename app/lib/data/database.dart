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
  int get schemaVersion => 6;

  @override
  MigrationStrategy get migration => MigrationStrategy(
        onUpgrade: (m, from, to) async {
          if (from < 2) {
            await m.addColumn(books, books.readingProgress);
            await m.addColumn(books, books.lastReadPage);
            await m.addColumn(books, books.lastReadAt);
          }
          if (from < 3) {
            await m.addColumn(books, books.readerNotes);
            await m.addColumn(books, books.sourceMetadata);
          }
          if (from < 4) {
            await m.createTable(physicalEnvironments);
            await m.createTable(physicalShelves);
            await m.createTable(bookPlacements);
          }
          if (from < 5) {
            await m.addColumn(bookPlacements, bookPlacements.format);
          }
          if (from < 6) {
            await m.createTable(localDeletions);
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
        },
      );

  /// All books, alphabetically — reactive: the shelf UI rebuilds on changes.
  Stream<List<Book>> watchAllBooks() =>
      (select(books)..orderBy([(b) => OrderingTerm.asc(b.title)])).watch();

  static QueryExecutor _openConnection() {
    return driftDatabase(name: 'vellum');
  }
}
