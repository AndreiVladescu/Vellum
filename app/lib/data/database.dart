import 'dart:io';

import 'package:drift/drift.dart';
import 'package:flutter/foundation.dart' show visibleForTesting;
import 'package:drift_flutter/drift_flutter.dart';
import 'package:path/path.dart' as p;
import 'package:path_provider/path_provider.dart';

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

  /// The private note's own clock and outbox flag.
  ///
  /// Separate from the book's `updatedAt`/`needsPush` because the note does not
  /// travel with the book: it goes to `/api/notes`, a per-user table, so that a
  /// library shared with someone else does not hand them your notes. Editing a
  /// note must therefore not look like editing the catalogue entry.
  DateTimeColumn get readerNotesUpdatedAt => dateTime().nullable()();
  BoolColumn get readerNotesNeedsPush =>
      boolean().withDefault(const Constant(false))();
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

  /// When the status above was last changed, and whether that change is still
  /// waiting to be published.
  ///
  /// Its own pair rather than the book's `updatedAt`/`needsPush`, for the same
  /// reason [readerNotesUpdatedAt] has its own: reading status is **personal**.
  /// It travels on the per-user channel (`book_status`, server migration 0034),
  /// so a shared library holds each reader's own "finished" instead of
  /// publishing one person's to everyone. Putting it on the book row is what
  /// server migration 0006 undid deliberately.
  ///
  /// Null means "never changed here": a book that has sat at `unread` since it
  /// was added has nothing to say about its status, and saying it anyway would
  /// let a device that has never opened the book overwrite one that finished it.
  DateTimeColumn get statusUpdatedAt => dateTime().nullable()();
  BoolColumn get statusNeedsPush =>
      boolean().withDefault(const Constant(false))();
  // ---- Trash (plan 5 #52) --------------------------------------------------
  /// When this book was moved to the trash, or null for a live book.
  ///
  /// **App-local, and deliberately so.** A trashed book is not deleted — no
  /// tombstone is written, its files stay on disk, and the server is told
  /// nothing — it is only hidden here until the grace period expires and the
  /// real delete runs. Mirroring the column would make one device's second
  /// thoughts another device's deletion, which is the opposite of the point.
  ///
  /// Everything that reads the library filters on `deleted_at IS NULL`;
  /// [LibraryQueries] does it centrally for the shelf, and the push side
  /// skips trashed rows so a book on its way out never reaches the server.
  DateTimeColumn get deletedAt => dateTime().nullable()();
  // ---- Per-book sync opt-out ------------------------------------------------
  /// Keep this book on this device only: no push, no pull, no covers or files
  /// either way.
  ///
  /// **App-local, and deliberately so** — like [deletedAt] above. It is a
  /// statement about *this* device's appetite, not about the book: mirroring it
  /// would let one device decide what another one is allowed to see, and a
  /// shared library would inherit one person's shyness about a title.
  ///
  /// Excluding a book that was already pushed does **not** take it off the
  /// server. Deleting it there removes it for everyone the library is shared
  /// with, which is a different intent with its own button; this one only stops
  /// the traffic from here.
  BoolColumn get syncExcluded => boolean().withDefault(const Constant(false))();

  /// Who added this book, as the server names them — their display name, or
  /// their email if they never set one.
  ///
  /// **App-local, and derived rather than owned.** The server holds the truth
  /// (`book.owner_id`); this is the readable form of it, cached at pull time so
  /// a book's page can say "Added by Ana" without a lookup per book. Never
  /// pushed: it is the server's answer, and a client asserting it would be
  /// claiming to know something it was told. Null for a book added here, on a
  /// library with no server, or by an account since removed.
  TextColumn get addedBy => text().nullable()();

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
/// Photos of a physical copy.
///
/// Library data rather than personal (plan 6 #4): a photo hangs off a copy,
/// copies sync, and it is visible to whoever the book is shared with — like its
/// covers. That is why these carry the same `updatedAt`/`needsPush` pair as
/// every other synced row, and not the per-user channel `readerNotes` uses.
class CopyPhotos extends Table {
  TextColumn get id => text()();
  TextColumn get copyId => text().references(PhysicalCopies, #id)();

  /// Relative to the data dir, like `BookFiles.path` — `photos/<id>.jpg`.
  TextColumn get path => text()();
  DateTimeColumn get takenAt => dateTime().withDefault(currentDateAndTime)();
  TextColumn get caption => text().nullable()();
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();
  BoolColumn get needsPush => boolean().withDefault(const Constant(true))();

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
  /// A shelf its owner keeps to themselves. Synced — it is theirs on every
  /// device they use — but the server withholds it from shares (migration
  /// 0029), so it never appears in anyone else's chip row.
  BoolColumn get isPersonal => boolean().withDefault(const Constant(false))();
  /// Who made it, as the server knows them. Null for a shelf made on this
  /// device, or on a library with no server: "mine" is the useful reading of
  /// null, and it is what the shelf was before any of this existed.
  TextColumn get ownerId => text().nullable()();
  /// Whether this device shows a shelf somebody else made. **App-local only**,
  /// and deliberately: it says what this reader wants to see, not anything
  /// about the shelf, so pushing it would let one person's "no thanks" hide a
  /// shelf for everyone.
  ///
  /// Null means undecided, which is not the same as yes: an undecided shelf
  /// follows the `acceptSharedShelves` preference, and a decided one keeps the
  /// answer you gave it even if you later flip that preference. Without the
  /// third state, "accept new shelves by default: off" and "I declined this
  /// one" would be the same value, and turning the default back on would undo
  /// every individual no.
  BoolColumn get accepted => boolean().nullable()();
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
  // Publishing bookkeeping (plan 5 #47). **App-local by construction**: the
  // server stores a `layout` *document*, not a mirror of this table, so these
  // two columns have no server counterpart and must never gain one.
  //
  // `serverRevision` is the revision this device last published or fetched —
  // sent back as `base_revision` so a publish that raced another device is
  // refused with a 409 rather than silently overwriting their arrangement.
  // Null means "never published".
  IntColumn get serverRevision => integer().nullable()();
  // Set whenever the room is edited locally; cleared on a successful publish or
  // fetch. Defaults **false**, unlike the sync tables' `needsPush`: publishing
  // is a deliberate act, and a room that was never published should not start
  // life asking to be.
  BoolColumn get needsPublish =>
      boolean().withDefault(const Constant(false))();
  // ---- Room realism (plan 5 #29) ------------------------------------------
  // A photo of the actual wall, traced over at true scale. **App-local**: the
  // published layout document (#47) is geometry only and must stay that way —
  // a backdrop is a photo of someone's home, which is exactly the sort of
  // thing that must not ride a share link.
  //
  // Relative to the data dir, like every other blob path.
  // ---- The room's own surfaces (next features #10) -------------------------
  // Wall and floor colours, as ARGB ints. **App-local**, for the same reason
  // the backdrop is: the published document is geometry, and how someone has
  // decorated their study is not part of "where the books are". Null means the
  // theme picks, which is what every existing room does.
  IntColumn get wallColor => integer().nullable()();
  IntColumn get floorColor => integer().nullable()();
  /// Whether to draw the floor line, its skirting board, and a soft shadow
  /// under each shelf. On by default — an empty room drawn without them looks
  /// like graph paper.
  BoolColumn get roomSurfaces =>
      boolean().withDefault(const Constant(true))();

  TextColumn get backdropPath => text().nullable()();
  RealColumn get backdropOpacity =>
      real().withDefault(const Constant(0.5))();
  /// Metres per backdrop pixel, from the two-point calibration. Null means the
  /// photo has never been calibrated, so it is drawn but not trusted for scale.
  RealColumn get backdropScale => real().nullable()();
  /// Where the photo's top-left sits in world metres.
  RealColumn get backdropOffsetX => real().withDefault(const Constant(0))();
  RealColumn get backdropOffsetY => real().withDefault(const Constant(0))();

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
  /// What this segment *is* (plan 5 #29): 'shelf' (books rest on it),
  /// 'panel' (a bookcase side — structure, nothing rests on it), 'divider'
  /// (a vertical separator), or 'label' (a text marker).
  ///
  /// A `kind` column rather than a second table, because a side panel is
  /// geometrically a shelf that books don't sit on — the only difference is
  /// whether `settle` may land something on it, which is one predicate.
  TextColumn get kind => text().withDefault(const Constant('shelf'))();

  /// Which bookcase this segment belongs to, or null when it stands alone.
  ///
  /// **A tag, not a hierarchy.** A bookcase is still just its segments — this
  /// only says which ones move, resize and delete together. Making bookcases a
  /// parent table would have broken every query that reasons about a flat list
  /// of segments (fill, tidy, stocktake, labels, the published document), and
  /// would have had to answer "what happens when I drag one shelf out of a
  /// bookcase". With a tag the answer is easy: it keeps the tag until you
  /// ungroup, and ungrouping is one UPDATE.
  TextColumn get groupId => text().nullable()();

  /// Whether this segment refuses to be dragged.
  ///
  /// **Anchored by default, deliberately.** A room is arranged once and then
  /// looked at hundreds of times, so the common gesture on a shelf is not
  /// "move it" — and a left-click that shifts a bookcase you were only trying
  /// to look at is a mistake you have to notice before you can undo it.
  /// Unanchoring is a right-click (or long-press) away, and is remembered, so
  /// rearranging stays a two-step act you opted into.
  BoolColumn get anchored => boolean().withDefault(const Constant(true))();
  DateTimeColumn get createdAt => dateTime().withDefault(currentDateAndTime)();

  @override
  Set<Column> get primaryKey => {id};
}

/// A decorative object standing in a room (next features #10).
///
/// **App-local, like the backdrop and the room's colours.** The published
/// document is geometry — where the books are — and a statuette is not that.
/// Nothing here syncs, which is also why it costs no server migration.
///
/// `(x, y)` is the bottom-left corner in world metres, exactly like a book
/// placement, so a prop settles onto a shelf through the same code books do.
@DataClassName('RoomProp')
class RoomProps extends Table {
  TextColumn get id => text()();
  TextColumn get environmentId => text().references(PhysicalEnvironments, #id)();

  /// A [PropKind] name. Text rather than an int so a database read by an older
  /// build shows an unknown prop rather than the wrong one.
  TextColumn get kind => text()();
  RealColumn get x => real()();
  RealColumn get y => real()();

  /// Its footprint in metres. Stored per prop rather than taken from the kind,
  /// so one can be made bigger or smaller without every other one changing.
  RealColumn get widthM => real()();
  RealColumn get heightM => real()();

  /// Whether this prop is drawn in front of the books rather than behind them.
  ///
  /// Behind is the default and the ordinary case — an ornament pushed to the
  /// back of a shelf, with the spines readable in front of it. In front is for
  /// the things that really do stand at the edge: a photo frame, a plant whose
  /// leaves fall across the books. Per prop, because a room usually wants both.
  BoolColumn get inFront => boolean().withDefault(const Constant(false))();
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

  /// Last-write-wins key, and what a delta pull compares against. Bumped on
  /// every edit — recolouring a highlight or rewriting a note both count.
  DateTimeColumn get updatedAt => dateTime().withDefault(currentDateAndTime)();

  /// Waiting to be pushed. Same convention as every other synced table: set on
  /// local write, cleared once the server has it.
  BoolColumn get needsPush => boolean().withDefault(const Constant(true))();

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

  /// Which device this sitting happened on, so statistics can still answer
  /// "where do I actually read" once they span three of them.
  TextColumn get deviceId => text().nullable()();
  TextColumn get deviceLabel => text().nullable()();

  /// Waiting to be pushed. A session is an immutable fact, so this is only ever
  /// set once — there is no edit to re-push and no conflict to resolve.
  BoolColumn get needsPush => boolean().withDefault(const Constant(true))();

  @override
  Set<Column> get primaryKey => {id};
}

/// Extraction state for one book file's text, for the local content index.
///
/// **App-local by design, like `sourceMetadata` and `deletedAt`** — do *not*
/// add this to the server schema or to any sync payload. The server has its own
/// `book_text` (migration 0016) built the same way for the same purpose; the
/// two indexes are independent, each derived from files their own side holds,
/// and neither is ever pushed. Everything here can be dropped and rebuilt from
/// the files on disk, so it carries no `updatedAt`/`needsPush` pair.
///
/// **The queue is the table**, copied from the server's design: a row with
/// `status = 'pending'` *is* the work item, so an app killed mid-extraction
/// resumes exactly where it stopped with no job state held in memory.
@DataClassName('BookText')
class BookTexts extends Table {
  @override
  String get tableName => 'book_text';

  TextColumn get fileId => text().references(BookFiles, #id)();
  TextColumn get bookId => text().references(Books, #id)();

  /// How many page/section rows were indexed, or null until extraction runs.
  IntColumn get pages => integer().nullable()();
  DateTimeColumn get extractedAt =>
      dateTime().withDefault(currentDateAndTime)();

  /// 'pending' | 'ok' | 'no_text' | 'failed' | 'skipped'.
  ///
  /// `no_text` is a scanned PDF — a real outcome rather than a failure, and
  /// the same position the server takes: there is no OCR here either.
  TextColumn get status => text()();

  @override
  Set<Column> get primaryKey => {fileId};
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
  RoomProps,
  LocalDeletions,
  RemoteReadingPositions,
  Annotations,
  ReadingSessions,
  BookTexts,
])
class VellumDatabase extends _$VellumDatabase {
  VellumDatabase([QueryExecutor? executor])
      : super(executor ?? _openConnection());

  @override
  int get schemaVersion => 34;

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
          if (from < 20) {
            // Layout publishing bookkeeping (plan 5 #47). App-local: the server
            // stores a document, not a mirror of these tables, so there is no
            // matching server migration.
            final envCols = await columnsOf('physical_environments');
            if (!envCols.contains('server_revision')) {
              await m.addColumn(
                physicalEnvironments,
                physicalEnvironments.serverRevision,
              );
            }
            if (!envCols.contains('needs_publish')) {
              await m.addColumn(
                physicalEnvironments,
                physicalEnvironments.needsPublish,
              );
            }
          }
          if (from < 21) {
            // Trash (plan 5 #52). App-local: a trashed book is still a book
            // everywhere else, so there is no server migration — and never
            // one, see the column's doc comment.
            await addBookColumn('deleted_at', books.deletedAt);
          }
          if (from < 22) {
            // Room realism (plan 5 #29): a backdrop photo per room and a kind
            // per shelf segment. App-local — the published layout document
            // (#47) carries geometry only, and a photo of someone's wall must
            // never ride a share link.
            final envCols = await columnsOf('physical_environments');
            for (final (name, column) in [
              ('backdrop_path', physicalEnvironments.backdropPath),
              ('backdrop_opacity', physicalEnvironments.backdropOpacity),
              ('backdrop_scale', physicalEnvironments.backdropScale),
              ('backdrop_offset_x', physicalEnvironments.backdropOffsetX),
              ('backdrop_offset_y', physicalEnvironments.backdropOffsetY),
            ]) {
              if (!envCols.contains(name)) {
                await m.addColumn(physicalEnvironments, column);
              }
            }
            if (!(await columnsOf('physical_shelves')).contains('kind')) {
              await m.addColumn(physicalShelves, physicalShelves.kind);
            }
          }
          if (from < 23) {
            // Personal data reaches the server (annotations, sittings, private
            // notes, profile). These columns are what makes it syncable:
            // `updated_at` for last-write-wins, `needs_push` for the outbox.
            //
            // Existing rows default to needs_push = true, which is right — they
            // predate the server knowing about them, so the first sync after
            // this upgrade is what publishes a library's back catalogue of
            // highlights rather than silently leaving it behind.
            final annotationCols = await columnsOf('annotations');
            for (final (name, column) in [
              ('updated_at', annotations.updatedAt),
              ('needs_push', annotations.needsPush),
            ]) {
              if (!annotationCols.contains(name)) {
                await m.addColumn(annotations, column);
              }
            }
            final bookCols = await columnsOf('books');
            for (final (name, column) in [
              ('reader_notes_updated_at', books.readerNotesUpdatedAt),
              ('reader_notes_needs_push', books.readerNotesNeedsPush),
            ]) {
              if (!bookCols.contains(name)) {
                await m.addColumn(books, column);
              }
            }
            final sessionCols = await columnsOf('reading_sessions');
            for (final (name, column) in [
              ('device_id', readingSessions.deviceId),
              ('device_label', readingSessions.deviceLabel),
              ('needs_push', readingSessions.needsPush),
            ]) {
              if (!sessionCols.contains(name)) {
                await m.addColumn(readingSessions, column);
              }
            }
          }
          if (from < 24) {
            // Copy photos start syncing (plan 6 #4). Existing rows default to
            // needs_push = true so the first sync after upgrading publishes the
            // photos already taken, rather than stranding them.
            final photoCols = await columnsOf('copy_photos');
            for (final (name, column) in [
              ('updated_at', copyPhotos.updatedAt),
              ('needs_push', copyPhotos.needsPush),
            ]) {
              if (!photoCols.contains(name)) {
                await m.addColumn(copyPhotos, column);
              }
            }
          }
          if (from < 34) {
            // Reading status becomes personal data that syncs (v1.1.5 bug: a
            // wishlist book arrived on the tablet as one you own). The columns
            // are the note's pattern — its own clock, its own dirty flag.
            final bookCols = await columnsOf('books');
            if (!bookCols.contains('status_updated_at')) {
              await m.addColumn(books, books.statusUpdatedAt);
            }
            if (!bookCols.contains('status_needs_push')) {
              await m.addColumn(books, books.statusNeedsPush);
              // Publish what this device already knows, once — but only where
              // the status says something. A library of `unread` books would
              // otherwise open with one request per book to announce that
              // nothing has happened to any of them.
              // Dated from whatever the row already knows about when this
              // happened, and only from those columns — a status with no date
              // behind it gets the moment of the upgrade, which is still older
              // than any change made after it.
              await customStatement(
                "UPDATE books SET status_needs_push = 1, "
                "status_updated_at = COALESCE(finished_at, started_at, "
                "last_read_at, strftime('%s', 'now')) "
                "WHERE status IS NOT NULL AND status != 'unread'",
              );
            }
          }
          if (from < 33) {
            // Props can stand in front of the books (issue #10 item 4).
            // Defaulted to false, which is where every existing prop already
            // is — the choice is something you go and make, never something an
            // upgrade makes for you. App-local, like the rest of the room, so
            // there is no server migration.
            // `room_props` itself only arrived at v27, and these steps run
            // newest-first — so on an older database the table does not exist
            // yet when this runs. The v27 step below creates it from the
            // *current* schema, which already has the column.
            if ((await tableNames()).contains('room_props') &&
                !(await columnsOf('room_props')).contains('in_front')) {
              await m.addColumn(roomProps, roomProps.inFront);
            }
          }
          if (from < 32) {
            // Who added a book, cached from the server for display. Nothing to
            // backfill: it arrives with the next pull of each book, and until
            // then "unknown" is the honest answer rather than a guess.
            if (!(await columnsOf('books')).contains('added_by')) {
              await m.addColumn(books, books.addedBy);
            }
          }
          if (from < 31) {
            // Personal shelves, and whether this device shows other people's.
            // Every existing shelf stays public and accepted: they were made
            // when public was the only kind, and an upgrade that quietly hid
            // shelves from the people who can already see them would be a
            // change nobody asked for.
            final cols = await columnsOf('shelves');
            if (!cols.contains('is_personal')) {
              await m.addColumn(shelves, shelves.isPersonal);
            }
            if (!cols.contains('owner_id')) {
              await m.addColumn(shelves, shelves.ownerId);
            }
            if (!cols.contains('accepted')) {
              await m.addColumn(shelves, shelves.accepted);
            }
          }
          if (from < 30) {
            // The local content index. App-local and fully derivable from the
            // files on disk, so there is no server migration and nothing to
            // backfill — every existing file is simply unindexed until the
            // extractor reaches it, which is what an empty table already means.
            if (!(await tableNames()).contains('book_text')) {
              await m.createTable(bookTexts);
            }
          }
          if (from < 29) {
            // Per-book sync opt-out. Defaulted to false, so every existing book
            // keeps syncing exactly as it did — the switch is something you go
            // and flip, never something an upgrade flips for you.
            if (!(await columnsOf('books')).contains('sync_excluded')) {
              await m.addColumn(books, books.syncExcluded);
            }
          }
          if (from < 28) {
            // Shelves become anchored by default (next features #11 follow-up).
            // Existing shelves are anchored too: someone who has arranged a
            // room already wants it to stay arranged.
            final cols = await columnsOf('physical_shelves');
            if (!cols.contains('anchored')) {
              await m.addColumn(physicalShelves, physicalShelves.anchored);
            }
          }
          if (from < 27) {
            // Room props (next features #10). App-local, so no server
            // migration; guarded like every other step.
            if (!(await tableNames()).contains('room_props')) {
              await m.createTable(roomProps);
            }
          }
          if (from < 26) {
            // Bookcase grouping (next features #11). A tag on the existing
            // segments; every row made before this stays ungrouped, which is
            // exactly right — they were drawn one at a time.
            final shelfCols = await columnsOf('physical_shelves');
            if (!shelfCols.contains('group_id')) {
              await m.addColumn(physicalShelves, physicalShelves.groupId);
            }
          }
          if (from < 25) {
            // The room's own surfaces (next features #10). App-local, like the
            // backdrop, so there is no matching server migration. Guarded like
            // every other step: a database stuck partway through an older
            // upgrade may already have them.
            final envCols = await columnsOf('physical_environments');
            for (final (name, column) in [
              ('wall_color', physicalEnvironments.wallColor),
              ('floor_color', physicalEnvironments.floorColor),
              ('room_surfaces', physicalEnvironments.roomSurfaces),
            ]) {
              if (!envCols.contains(name)) {
                await m.addColumn(physicalEnvironments, column);
              }
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

    // The content index's virtual table and sweeper. No backfill: its source is
    // files on disk rather than a table, so it fills as the extractor runs.
    // Guarded on `book_text` existing because this runs from `beforeOpen`, and
    // a database still mid-upgrade may not have reached v29 yet.
    if (names.contains('book_text')) {
      if (!names.contains('book_text_fts')) {
        await customStatement(createBookTextFtsTable);
      }
      for (final entry in bookTextTriggers.entries) {
        if (!names.contains(entry.key)) await customStatement(entry.value);
      }
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

  /// Every book you own, alphabetically — reactive: the shelf UI rebuilds on
  /// changes. Trashed books (plan 5 #52) and wishlist entries (plan 5 #21a) are
  /// both excluded here rather than at each call site, so nothing that asks for
  /// "the library" has to remember that neither is in it.
  Stream<List<Book>> watchAllBooks() => (select(books)
        ..where((b) =>
            b.deletedAt.isNull() & b.status.equals('wishlist').not())
        ..orderBy([(b) => OrderingTerm.asc(b.title)]))
      .watch();

  /// The database lives beside the covers, book files and settings, in the
  /// application-support directory.
  ///
  /// `driftDatabase` defaults to the *documents* directory, which on Linux is
  /// the user's own `~/Documents` — so the catalogue used to sit among their
  /// papers while everything else it describes lived in `~/.local/share`. One
  /// library in one place is easier to back up, easier to move between
  /// machines, and easier to reason about than a catalogue and its contents
  /// kept apart.
  static QueryExecutor _openConnection() {
    return driftDatabase(
      name: 'vellum',
      native: DriftNativeOptions(
        databaseDirectory: () async {
          final dir = await getApplicationSupportDirectory();
          await _relocateLegacyDatabase(dir);
          return dir;
        },
      ),
    );
  }

  /// Moves a database left in the documents directory by an earlier version.
  ///
  /// Without this, changing the directory would present every existing
  /// installation with an empty library while its real one sat untouched a
  /// directory away — the catalogue is the one thing whose loss is not
  /// recoverable from the files on disk.
  ///
  /// Runs before the file is opened, and only when the destination does not
  /// exist, so it cannot overwrite a newer database with an older one. The
  /// `-wal` and `-shm` companions move too: leaving a stale write-ahead log
  /// beside a moved database is how a "successful" move loses the last
  /// transactions committed before it.
  @visibleForTesting
  static Future<void> relocateLegacyDatabaseForTesting(Directory target) =>
      _relocateLegacyDatabase(target);

  static Future<void> _relocateLegacyDatabase(Directory target) async {
    final destination = File(p.join(target.path, 'vellum.sqlite'));
    if (destination.existsSync()) return;
    final Directory documents;
    try {
      documents = await getApplicationDocumentsDirectory();
    } catch (_) {
      return; // No documents directory on this platform; nothing to move.
    }
    if (p.equals(documents.path, target.path)) return;

    final legacy = File(p.join(documents.path, 'vellum.sqlite'));
    if (!legacy.existsSync()) return;
    try {
      await target.create(recursive: true);
      for (final suffix in ['', '-wal', '-shm']) {
        final from = File('${legacy.path}$suffix');
        if (from.existsSync()) {
          await from.rename('${destination.path}$suffix');
        }
      }
    } catch (_) {
      // A rename across filesystems, or a locked file: leave the original
      // where it is rather than half-move it. The app then opens an empty
      // database, which is visibly wrong and recoverable, instead of a
      // partially copied one, which is neither.
    }
  }
}
