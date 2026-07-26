import 'package:drift/drift.dart';
import 'package:drift_flutter/drift_flutter.dart';

import 'search_index.dart';

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
  // Series membership (plan 5 #17), synced. `seriesIndex` is REAL so a novella
  // can be 1.5 — an integer would force it to lie about where it sits.
  TextColumn get seriesId => text().nullable().references(Series, #id)();
  RealColumn get seriesIndex => real().nullable()();
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
  // Whether this book's *reading position* still needs publishing to the
  // optional cross-device channel (plan 5 #5). Separate from `needsPush` on
  // purpose: reading state is not part of the book upsert and must never ride
  // along with it. Defaults **false**, unlike `needsPush` — the channel is
  // opt-in, so "never switched on" has to mean "nothing was ever published".
  // Enabling the setting marks the already-read books dirty explicitly.
  BoolColumn get needsProgressPush =>
      boolean().withDefault(const Constant(false))();
  // ---- Reading status and judgements (plan 5 #18) -------------------------
  // App-local **for now**, and written to be promotable: these are additive
  // nullable/defaulted columns, so moving them onto the synced payload later is
  // one server migration plus a parity update, with no data conversion. They are
  // *judgements* (what you thought, what you mean to read) rather than reading
  // mechanics, so users will eventually expect them on every device — see the
  // locality note in plan 5 #18.
  //
  // 'unread' | 'reading' | 'finished' | 'abandoned' | 'reference'.
  TextColumn get status =>
      text().withDefault(const Constant('unread'))();
  /// 1–5, or null for unrated.
  IntColumn get rating => integer().nullable()();
  DateTimeColumn get startedAt => dateTime().nullable()();
  DateTimeColumn get finishedAt => dateTime().nullable()();
  /// How many times this book has been finished, for re-reads.
  IntColumn get readCount => integer().withDefault(const Constant(0))();

  @override
  Set<Column> get primaryKey => {id};
}

/// A named book series (plan 5 #17). Mirrors `server/migrations/0012_series.sql`
/// — this one **is** synced, unlike the app-local tables further down: series
/// membership is catalogue metadata the metadata sources supply.
class Series extends Table {
  TextColumn get id => text()();
  TextColumn get name => text().unique()();

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
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  // Sync bookkeeping since plan 5 #4 (second of three), same convention as
  // Shelves.needsPush: set at creation, cleared once a push succeeds. There
  // is no edit UI for a copy's fields yet, so this only ever goes true once.
  BoolColumn get needsPush => boolean().withDefault(const Constant(true))();

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
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  // Sync bookkeeping since plan 5 #4 (third of three), same convention as
  // PhysicalCopies.needsPush: set at creation and by returnLoan (an update,
  // so this must be bumped explicitly -- column defaults don't re-run),
  // cleared once a push succeeds.
  BoolColumn get needsPush => boolean().withDefault(const Constant(true))();
  // Due dates, contacts and notes (plan 5 #27). Synced, because `loan` has been
  // a synced table since plan 5 #4 — mirrors server migration 0014.
  //
  // `dueAt` is nullable and that is a real state, not missing data: "borrow it
  // as long as you like" is a normal arrangement, and forcing a date would make
  // the app describe an agreement nobody made.
  DateTimeColumn get dueAt => dateTime().nullable()();
  /// Free text — a phone number, an email, "Ana from book club".
  TextColumn get borrowerContact => text().nullable()();
  TextColumn get notes => text().nullable()();
  /// When a due reminder was last raised, so it isn't raised twice.
  DateTimeColumn get reminderSentAt => dateTime().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Photographs of a physical copy's condition (plan 5 #51).
///
/// The point is the loan argument: `physicalCopy.condition` is one word, and
/// "there was already a tear on page 40" is not something a word settles. A
/// photo taken as a copy goes out — and another when it comes back — is.
///
/// **App-local, deliberately and permanently.** Copies and loans sync
/// (plan 5 #4), but photo *blobs* are exactly the sync weight that channel
/// shouldn't quietly acquire: one condition photo outweighs the entire
/// catalogue payload for a mid-sized library. Only [path] is stored here; the
/// bytes live under `photos/` in the data dir and ride backups.
@DataClassName('CopyPhoto')
class CopyPhotos extends Table {
  TextColumn get id => text()();
  TextColumn get copyId => text().references(PhysicalCopies, #id)();

  /// Relative to the data dir, like `BookFiles.path` — `photos/<id>.jpg`.
  TextColumn get path => text()();
  DateTimeColumn get takenAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get caption => text().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

/// Manual collections/panes, independent of genres, with explicit ordering.
@DataClassName('Shelf')
class Shelves extends Table {
  TextColumn get id => text()();
  TextColumn get name => text()();
  IntColumn get sortOrder => integer().withDefault(const Constant(0))();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  // Sync bookkeeping, same convention as Books.needsPush: set on every write
  // (rename, reorder, or a membership change via ShelfBooks), cleared once a
  // push succeeds. Membership itself dirties the parent shelf; ShelfBooks
  // carries no sync columns of its own.
  BoolColumn get needsPush => boolean().withDefault(const Constant(true))();

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
  // 'book', 'shelf', or 'copy' (plan 5 #4) — which server endpoint the next
  // push tells about this id. Named to match the server's `deletion.kind`.
  TextColumn get kind => text().withDefault(const Constant('book'))();

  @override
  Set<Column> get primaryKey => {bookId};
}

/// Other devices' reading positions for a book, mirrored from the server's
/// `reading_progress` table (plan 5 #5) so "you were on page 214 on desktop —
/// jump there?" works offline and without a round trip when opening a book.
///
/// App-local by construction and NOT a counterpart of the server table: this
/// device's own position stays on the book row, and only *remote* rows land
/// here. Nothing in here is authoritative — it is a cache of what the server
/// last said, cleared when the feature is switched off.
@DataClassName('RemoteReadingPosition')
class RemoteReadingPositions extends Table {
  TextColumn get bookId => text()();
  TextColumn get deviceId => text()();
  /// Human label for the prompt ("desktop", "Pixel 8"); may be absent if the
  /// writing device didn't send one.
  TextColumn get deviceLabel => text().nullable()();
  RealColumn get progress => real().nullable()();
  IntColumn get page => integer().nullable()();
  /// What [page] counts: 'page' (PDF) or 'chapter' (EPUB). A remote device may
  /// have read a different format of the same book, so the unit travels with
  /// the row instead of being inferred locally.
  TextColumn get unit => text().nullable()();
  RealColumn get scroll => real().nullable()();
  DateTimeColumn get updatedAt => dateTime()();

  @override
  Set<Column> get primaryKey => {bookId, deviceId};
}

/// Bookmarks, highlights and notes made while reading (plan 5 #22).
///
/// One table for all three kinds, discriminated by [kind], because they differ
/// only in which fields they carry: a bookmark is a location, a highlight is a
/// location plus quoted text, a note is either plus the user's own words.
///
/// **App-local, like `readerNotes`.** These are personal marginalia, not
/// catalogue data. If they ever sync they get their own table and endpoint
/// (the shape #5 established), never a column on the book row.
@DataClassName('Annotation')
class Annotations extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text().references(Books, #id)();
  /// 'bookmark' | 'highlight' | 'note'.
  TextColumn get kind => text()();
  /// Coarse location, kept as columns (not only inside [locator]) so the panel
  /// can order and group without parsing JSON: the PDF page or the EPUB chapter.
  IntColumn get page => integer().nullable()();
  IntColumn get chapter => integer().nullable()();
  /// Fine location as versioned JSON — see `annotation_locator.dart`. Versioned
  /// because the EPUB offsets depend on this app's own text extraction, so a
  /// parser change must be able to migrate them rather than orphan them.
  TextColumn get locator => text().nullable()();
  TextColumn get quotedText => text().nullable()();
  TextColumn get note => text().nullable()();
  /// Highlight colour as an ARGB int, or null for the default.
  IntColumn get color => integer().nullable()();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// One stretch of reading (plan 5 #19).
///
/// The app already knows every page turn — `saveReadingPosition` writes on each
/// one — and throws all of it away except the latest position. This table keeps
/// the shape of it: one row per *session*, not per page turn, so a long evening
/// costs one write rather than four hundred.
///
/// **Local-only, permanently.** This is behavioural data: when you read and for
/// how long. It rides backups (they snapshot the database file) and can be wiped
/// from Preferences, but it has no sync channel and should never get one.
@DataClassName('ReadingSession')
class ReadingSessions extends Table {
  TextColumn get id => text()();
  TextColumn get bookId => text().references(Books, #id)();
  DateTimeColumn get startedAt => dateTime()();
  DateTimeColumn get endedAt => dateTime()();
  IntColumn get startPage => integer().nullable()();
  IntColumn get endPage => integer().nullable()();

  @override
  Set<Column> get primaryKey => {id};
}

@DriftDatabase(tables: [
  Books,
  Series,
  Authors,
  BookAuthors,
  Genres,
  BookGenres,
  BookFiles,
  PhysicalCopies,
  Loans,
  CopyPhotos,
  Shelves,
  ShelfBooks,
  PhysicalEnvironments,
  PhysicalShelves,
  BookPlacements,
  LocalDeletions,
  RemoteReadingPositions,
  Annotations,
  ReadingSessions,
])
class VellumDatabase extends _$VellumDatabase {
  VellumDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 19;

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
          if (from < 9) {
            // App-local: no server migration (search_index.dart's doc
            // comment). Also guarded from beforeOpen below, so a fresh
            // install (which never runs onUpgrade) still gets it.
            await _ensureSearchIndex();
          }
          if (from < 10) {
            // Shelves start syncing (plan 5 #4); needsPush defaults true so
            // every pre-existing shelf pushes once, same as books at v7.
            // Guarded like `physical_environments` etc. above: a database
            // stuck partway through a much older migration (recovery test)
            // may not have `shelves`/`local_deletions` yet either.
            if (!tables.contains('shelves')) {
              await m.createTable(shelves);
            } else {
              final shelfCols = await columnsOf('shelves');
              if (!shelfCols.contains('updated_at')) {
                await m.addColumn(shelves, shelves.updatedAt);
              }
              if (!shelfCols.contains('needs_push')) {
                await m.addColumn(shelves, shelves.needsPush);
              }
            }
            // Live check, not the `tables` snapshot from the top of this
            // function: from < 6 above may have just created this table in
            // this same run, which the stale snapshot wouldn't reflect.
            if (!(await tableNames()).contains('local_deletions')) {
              await m.createTable(localDeletions);
            } else if (!(await columnsOf('local_deletions')).contains('kind')) {
              await m.addColumn(localDeletions, localDeletions.kind);
            }
          }
          if (from < 11) {
            // Physical copies start syncing (plan 5 #4, second of three);
            // needsPush defaults true so every pre-existing copy pushes once,
            // same reasoning as shelves at v10. Guarded the same way: a
            // database stuck partway through an older migration may not have
            // `physical_copies` at all yet.
            if (!tables.contains('physical_copies')) {
              await m.createTable(physicalCopies);
            } else {
              final copyCols = await columnsOf('physical_copies');
              if (!copyCols.contains('updated_at')) {
                await m.addColumn(physicalCopies, physicalCopies.updatedAt);
              }
              if (!copyCols.contains('needs_push')) {
                await m.addColumn(physicalCopies, physicalCopies.needsPush);
              }
            }
          }
          if (from < 12) {
            // Loans start syncing (plan 5 #4, third and last); needsPush
            // defaults true so every pre-existing loan pushes once, same
            // reasoning as shelves/copies before it. Guarded the same way.
            if (!tables.contains('loans')) {
              await m.createTable(loans);
            } else {
              final loanCols = await columnsOf('loans');
              if (!loanCols.contains('updated_at')) {
                await m.addColumn(loans, loans.updatedAt);
              }
              if (!loanCols.contains('needs_push')) {
                await m.addColumn(loans, loans.needsPush);
              }
            }
          }
          if (from < 13) {
            // Optional cross-device reading position (plan 5 #5). Both parts
            // are app-local: `needs_progress_push` defaults *false* (unlike
            // every needsPush before it) because the channel is opt-in, and
            // `remote_reading_positions` only ever caches other devices' rows.
            await addBookColumn(
              'needs_progress_push',
              books.needsProgressPush,
            );
            if (!(await tableNames()).contains('remote_reading_positions')) {
              await m.createTable(remoteReadingPositions);
            }
          }
          if (from < 14) {
            // Annotations (plan 5 #22): app-local, so no server migration.
            if (!(await tableNames()).contains('annotations')) {
              await m.createTable(annotations);
            }
          }
          if (from < 15) {
            // Reading status, rating and dates (plan 5 #18). App-local for now
            // (see the column comments), so no server migration; every column
            // is nullable or defaulted, so existing rows need no backfill
            // beyond the status default.
            await addBookColumn('status', books.status);
            await addBookColumn('rating', books.rating);
            await addBookColumn('started_at', books.startedAt);
            await addBookColumn('finished_at', books.finishedAt);
            await addBookColumn('read_count', books.readCount);
          }
          if (from < 16) {
            // Reading sessions (plan 5 #19): local-only behavioural data, so no
            // server migration — and deliberately never one.
            if (!(await tableNames()).contains('reading_sessions')) {
              await m.createTable(readingSessions);
            }
          }
          if (from < 17) {
            // Series (plan 5 #17) — synced, so this has a matching server
            // migration (0012) and an entry in schema_parity.rs.
            if (!(await tableNames()).contains('series')) {
              await m.createTable(series);
            }
            await addBookColumn('series_id', books.seriesId);
            await addBookColumn('series_index', books.seriesIndex);
          }
          if (from < 18) {
            // Loan due dates (plan 5 #27) — synced, matching server 0014.
            final loanCols = await columnsOf('loans');
            if (!loanCols.contains('due_at')) {
              await m.addColumn(loans, loans.dueAt);
            }
            if (!loanCols.contains('borrower_contact')) {
              await m.addColumn(loans, loans.borrowerContact);
            }
            if (!loanCols.contains('notes')) {
              await m.addColumn(loans, loans.notes);
            }
            if (!loanCols.contains('reminder_sent_at')) {
              await m.addColumn(loans, loans.reminderSentAt);
            }
          }
          if (from < 19) {
            // Condition photos (plan 5 #51): app-local, so no server migration
            // — and deliberately never one, see the table's doc comment.
            if (!(await tableNames()).contains('copy_photos')) {
              await m.createTable(copyPhotos);
            }
          }
        },
        beforeOpen: (details) async {
          await customStatement('PRAGMA foreign_keys = ON');
          await _ensureSearchIndex();
        },
      );

  /// Creates `book_search` and its triggers if missing, then backfills —
  /// idempotent, like the rest of `onUpgrade`. Runs from `beforeOpen` (every
  /// open, cheap once the table exists) so a fresh install is covered too,
  /// not just an upgrade from an older `schemaVersion`.
  ///
  /// Bails out if `book_authors`/`authors`/`book_genres`/`genres` aren't
  /// present yet: the triggers reference them, and (like
  /// `_mergeDuplicateGenres`) a partially-migrated database can reach here
  /// without them — this runs from `beforeOpen`, on every launch, so a throw
  /// here would brick the app rather than just miss the search index.
  Future<void> _ensureSearchIndex() async {
    final present = await customSelect(
      "SELECT name FROM sqlite_master WHERE type IN ('table', 'trigger')",
    ).get();
    final names = {for (final row in present) row.read<String>('name')};
    const required = {'book_authors', 'authors', 'book_genres', 'genres'};
    if (!required.every(names.contains)) return;

    if (!names.contains('book_search')) {
      await customStatement(createBookSearchTable);
    }
    for (final entry in bookSearchTriggers.entries) {
      if (!names.contains(entry.key)) await customStatement(entry.value);
    }
    if (!names.contains('book_search')) {
      // Only on first creation — an existing table already has its rows
      // (kept current by the triggers above).
      await customStatement(backfillBookSearch);
    }
  }

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
