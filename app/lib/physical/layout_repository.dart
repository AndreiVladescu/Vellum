import 'dart:ui' show Offset;

import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../data/database.dart';
import '../data/physical_service.dart';
import 'locate.dart';
import 'bookcase_template.dart';
import 'room_prop.dart';
import 'room_measure.dart';

/// A placement joined with the book it shows, for rendering an environment.
typedef PlacedBook = ({BookPlacement placement, Book book});

/// CRUD for the app-local physical-layout model: environments, their shelves,
/// and the placements of books onto them (each placement owns a physical copy
/// so the same title can sit in several spots). Split out of
/// [LibraryRepository] to keep that class focused on the digital library and
/// sync; this holds no state beyond the shared [db] handle. The
/// environment/shelf/placement tables themselves are never synced — see
/// database.dart — but the copy a placement mints is a real physical object,
/// so (plan 5 #4) it syncs like any other copy; deletion goes through
/// [PhysicalService.deletePhysicalCopy] so that stays true when a placement
/// is removed.
/// A copy's real location, derived from its placement (plan 5 #50).
class CopyLocation {
  const CopyLocation({
    required this.environmentId,
    required this.environmentName,
    this.shelfLabel,
  });

  final String environmentId;
  final String environmentName;

  /// The label of the shelf it stands on, when that shelf has one.
  final String? shelfLabel;

  /// "Living room · Shelf 2", or just the room when the shelf is unlabelled.
  String get display =>
      shelfLabel == null ? environmentName : '$environmentName · $shelfLabel';
}

class LayoutRepository {
  LayoutRepository(this.db, this._physical);

  final VellumDatabase db;
  final PhysicalService _physical;
  final _uuid = const Uuid();

  Stream<List<PhysicalEnvironment>> watchEnvironments() =>
      (db.select(db.physicalEnvironments)
            ..orderBy([
              (e) => OrderingTerm.asc(e.sortOrder),
              (e) => OrderingTerm.asc(e.createdAt),
            ]))
          .watch();

  Future<String> createEnvironment(String name) async {
    final id = _uuid.v4();
    final existing = await db.select(db.physicalEnvironments).get();
    await db
        .into(db.physicalEnvironments)
        .insert(
          PhysicalEnvironmentsCompanion.insert(
            id: id,
            name: name.trim(),
            sortOrder: Value(existing.length),
          ),
        );
    return id;
  }

  /// Marks a room as changed since its last publish (plan 5 #47).
  ///
  /// Set **here**, inside every mutator, rather than at the fifteen call sites
  /// in the editor — a flag that has to be remembered is a flag that gets
  /// forgotten, and this one decides whether the Publish badge is honest.
  ///
  /// The by-placement and by-shelf variants resolve the room in the same
  /// statement, so marking a room dirty never costs a second round trip during
  /// a gravity pass that touches every book on a shelf.
  Future<void> markDirty(String environmentId) =>
      (db.update(db.physicalEnvironments)
            ..where((e) => e.id.equals(environmentId)))
          .write(const PhysicalEnvironmentsCompanion(
        needsPublish: Value(true),
      ));

  /// Records a successful publish/fetch: this device is now level with the
  /// server at [revision].
  Future<void> markPublished(String environmentId, int revision) =>
      (db.update(db.physicalEnvironments)
            ..where((e) => e.id.equals(environmentId)))
          .write(PhysicalEnvironmentsCompanion(
        serverRevision: Value(revision),
        needsPublish: const Value(false),
      ));

  Future<void> _dirtyByPlacement(String placementId) => db.customStatement(
        'UPDATE physical_environments SET needs_publish = 1 WHERE id = '
        '(SELECT environment_id FROM book_placements WHERE id = ?)',
        [placementId],
      );

  Future<void> _dirtyByShelf(String shelfId) => db.customStatement(
        'UPDATE physical_environments SET needs_publish = 1 WHERE id = '
        '(SELECT environment_id FROM physical_shelves WHERE id = ?)',
        [shelfId],
      );

  /// The room's backdrop photo and how it is placed (plan 5 #29). Any argument
  /// left null is untouched; pass `Value(null)` for [backdropPath] to remove
  /// the photo.
  Future<void> updateBackdrop(
    String environmentId, {
    Value<String?>? backdropPath,
    double? opacity,
    Value<double?>? scale,
    double? offsetX,
    double? offsetY,
  }) async {
    await (db.update(db.physicalEnvironments)
          ..where((e) => e.id.equals(environmentId)))
        .write(PhysicalEnvironmentsCompanion(
      backdropPath: backdropPath ?? const Value.absent(),
      backdropOpacity:
          opacity == null ? const Value.absent() : Value(opacity.clamp(0, 1)),
      backdropScale: scale ?? const Value.absent(),
      backdropOffsetX:
          offsetX == null ? const Value.absent() : Value(offsetX),
      backdropOffsetY:
          offsetY == null ? const Value.absent() : Value(offsetY),
    ));
    // Deliberately *not* markDirty: the backdrop is app-local and never
    // published (#47's document is geometry only), so it must not make a room
    // look like it has unpublished changes.
  }

  /// The room's wall/floor colours and whether its surfaces are drawn
  /// (next features #10). App-local, like the backdrop — so deliberately *not*
  /// `markDirty`: how a room is decorated is not part of where the books are,
  /// and it must not make a room look like it has unpublished changes.
  Future<void> updateRoomLook(
    String environmentId, {
    Value<int?>? wallColor,
    Value<int?>? floorColor,
    bool? surfaces,
  }) async {
    await (db.update(db.physicalEnvironments)
          ..where((e) => e.id.equals(environmentId)))
        .write(PhysicalEnvironmentsCompanion(
      wallColor: wallColor ?? const Value.absent(),
      floorColor: floorColor ?? const Value.absent(),
      roomSurfaces: surfaces == null ? const Value.absent() : Value(surfaces),
    ));
  }

  Future<PhysicalEnvironment?> environment(String id) =>
      (db.select(db.physicalEnvironments)..where((e) => e.id.equals(id)))
          .getSingleOrNull();

  Future<void> renameEnvironment(String id, String name) async {
    await (db.update(db.physicalEnvironments)..where((e) => e.id.equals(id)))
        .write(PhysicalEnvironmentsCompanion(name: Value(name.trim())));
  }

  /// Removes an environment along with its shelves, placements, and the copies
  /// those placements created.
  Future<void> deleteEnvironment(String id) async {
    await db.transaction(() async {
      final placements = await (db.select(
        db.bookPlacements,
      )..where((p) => p.environmentId.equals(id))).get();
      await (db.delete(db.bookPlacements)
            ..where((p) => p.environmentId.equals(id)))
          .go();
      for (final placement in placements) {
        await _deleteCopy(placement.copyId);
      }
      await (db.delete(db.physicalShelves)
            ..where((s) => s.environmentId.equals(id)))
          .go();
      // Props reference the room with no ON DELETE cascade, and foreign keys
      // are enforced — exactly the trap copy photos fell into, where deleting a
      // photographed book aborted on the constraint.
      await (db.delete(db.roomProps)..where((p) => p.environmentId.equals(id)))
          .go();
      await (db.delete(db.physicalEnvironments)..where((e) => e.id.equals(id)))
          .go();
    });
  }

  Stream<List<PhysicalShelf>> watchShelves(String environmentId) =>
      (db.select(db.physicalShelves)
            ..where((s) => s.environmentId.equals(environmentId)))
          .watch();

  Future<void> addShelf(
    String environmentId, {
    required double x1,
    required double y1,
    required double x2,
    required double y2,
    String? label,
    ShelfKind kind = ShelfKind.shelf,
  }) async {
    await db
        .into(db.physicalShelves)
        .insert(
          PhysicalShelvesCompanion.insert(
            id: _uuid.v4(),
            environmentId: environmentId,
            x1: x1,
            y1: y1,
            x2: x2,
            y2: y2,
            label: Value(label),
            kind: Value(kind.key),
          ),
        );
    await markDirty(environmentId);
  }

  Future<void> updateShelf(
    String id, {
    double? x1,
    double? y1,
    double? x2,
    double? y2,
    Value<String?>? label,
    ShelfKind? kind,
  }) async {
    await (db.update(db.physicalShelves)..where((s) => s.id.equals(id))).write(
      PhysicalShelvesCompanion(
        x1: x1 == null ? const Value.absent() : Value(x1),
        y1: y1 == null ? const Value.absent() : Value(y1),
        x2: x2 == null ? const Value.absent() : Value(x2),
        y2: y2 == null ? const Value.absent() : Value(y2),
        label: label ?? const Value.absent(),
        kind: kind == null ? const Value.absent() : Value(kind.key),
      ),
    );
    await _dirtyByShelf(id);
  }

  Future<void> deleteShelf(String id) async {
    // Dirty *before* the delete, while the shelf still names its room.
    await _dirtyByShelf(id);
    await (db.delete(db.physicalShelves)..where((s) => s.id.equals(id))).go();
  }

  /// Where a copy actually sits, derived from its placement (plan 5 #50).
  ///
  /// `physical_copy.location` is free text typed once when the copy was added,
  /// while a *placement* records where the book was last dragged to. They drift
  /// apart the first time the shelf is rearranged, and the detail page used to
  /// show the stale string. So the placement wins when there is one — and the
  /// derived string is **never written back** into the column: derived data stays
  /// derived, the same rule spine colours follow.
  ///
  /// Returns null when the copy has no placement, in which case the free-text
  /// note is all there is.
  Stream<CopyLocation?> watchLocationOf(String copyId) {
    final query = db.select(db.bookPlacements).join([
      innerJoin(
        db.physicalEnvironments,
        db.physicalEnvironments.id.equalsExp(db.bookPlacements.environmentId),
      ),
    ])
      ..where(db.bookPlacements.copyId.equals(copyId))
      ..limit(1);
    return query.watch().asyncMap((rows) async {
      if (rows.isEmpty) return null;
      final placement = rows.first.readTable(db.bookPlacements);
      final environment = rows.first.readTable(db.physicalEnvironments);
      final shelves = await (db.select(db.physicalShelves)
            ..where((s) => s.environmentId.equals(placement.environmentId)))
          .get();
      return CopyLocation(
        environmentId: environment.id,
        environmentName: environment.name,
        shelfLabel: nearestShelfLabel(placement: placement, shelves: shelves),
      );
    });
  }

  /// The label of the shelf a placement is standing on, or null.
  ///
  /// "Standing on" means the nearest shelf *below or at* the book's baseline and
  /// horizontally overlapping it — a book floating above a shelf it doesn't
  /// overlap belongs to no shelf, and guessing would put it on the wrong one.
  static String? nearestShelfLabel({
    required BookPlacement placement,
    required List<PhysicalShelf> shelves,
  }) {
    final shelf = nearestShelf(placement: placement, shelves: shelves);
    final label = shelf?.label?.trim();
    return (label == null || label.isEmpty) ? null : label;
  }

  /// The shelf a placement is standing on, or null — see [nearestShelfLabel]
  /// for what "standing on" means. Exposed separately from the label because
  /// grouping a room's books by shelf (the accessible room summary, plan 5
  /// #42) needs the shelf itself, and an unlabelled shelf is still a shelf.
  static PhysicalShelf? nearestShelf({
    required BookPlacement placement,
    required List<PhysicalShelf> shelves,
  }) {
    PhysicalShelf? best;
    var bestDistance = double.infinity;
    for (final shelf in shelves) {
      final left = shelf.x1 < shelf.x2 ? shelf.x1 : shelf.x2;
      final right = shelf.x1 < shelf.x2 ? shelf.x2 : shelf.x1;
      if (placement.x < left || placement.x > right) continue;
      // Shelf tops are y; a book sits with its base at (or just above) one.
      final surface = (shelf.y1 + shelf.y2) / 2;
      final distance = surface - placement.y;
      if (distance < -0.02) continue; // the shelf is above the book
      if (distance < bestDistance) {
        bestDistance = distance;
        best = shelf;
      }
    }
    return best;
  }

  /// Every place a copy of [bookId] physically stands (plan 5 #28).
  ///
  /// Across *all* environments, because "which library is it in?" is the
  /// question once you have more than one room — and a book with two copies in
  /// two rooms is the case that makes picking the first row silently wrong.
  /// Ordered by room, then by position along the shelf, so the list reads the
  /// way the shelf does.
  Future<List<BookSighting>> sightingsOf(String bookId) async {
    final rows = await (db.select(db.bookPlacements).join([
      innerJoin(
        db.physicalCopies,
        db.physicalCopies.id.equalsExp(db.bookPlacements.copyId),
      ),
      innerJoin(
        db.physicalEnvironments,
        db.physicalEnvironments.id.equalsExp(db.bookPlacements.environmentId),
      ),
    ])
          ..where(db.physicalCopies.bookId.equals(bookId)))
        .get();
    if (rows.isEmpty) return const [];

    // Shelves are fetched once per environment rather than per placement: a
    // wall of books in one room would otherwise be one query each.
    final shelvesByEnv = <String, List<PhysicalShelf>>{};
    final sightings = <BookSighting>[];
    for (final row in rows) {
      final placement = row.readTable(db.bookPlacements);
      final environment = row.readTable(db.physicalEnvironments);
      final shelves = shelvesByEnv[environment.id] ??= await (db.select(
        db.physicalShelves,
      )..where((s) => s.environmentId.equals(environment.id)))
          .get();
      sightings.add(BookSighting(
        placementId: placement.id,
        copyId: placement.copyId,
        environmentId: environment.id,
        environmentName: environment.name,
        x: placement.x,
        y: placement.y,
        shelfLabel: nearestShelfLabel(placement: placement, shelves: shelves),
      ));
    }
    sightings.sort((a, b) {
      final byRoom = a.environmentName.compareTo(b.environmentName);
      if (byRoom != 0) return byRoom;
      final byHeight = b.y.compareTo(a.y); // top shelf first, as you'd look
      if (byHeight != 0) return byHeight;
      return a.x.compareTo(b.x);
    });
    return sightings;
  }

  /// The environment a shelf belongs to, for opening a scanned shelf label.
  /// Null when the shelf no longer exists (a label outlived its shelf).
  Future<PhysicalEnvironment?> environmentOfShelf(String shelfId) async {
    final rows = await (db.select(db.physicalShelves).join([
      innerJoin(
        db.physicalEnvironments,
        db.physicalEnvironments.id.equalsExp(db.physicalShelves.environmentId),
      ),
    ])
          ..where(db.physicalShelves.id.equals(shelfId))
          ..limit(1))
        .get();
    return rows.isEmpty
        ? null
        : rows.first.readTable(db.physicalEnvironments);
  }

  /// Placements joined with their books, for rendering.
  Stream<List<PlacedBook>> watchPlacedBooks(String environmentId) {
    final query =
        db.select(db.bookPlacements).join([
            innerJoin(
              db.physicalCopies,
              db.physicalCopies.id.equalsExp(db.bookPlacements.copyId),
            ),
            innerJoin(
              db.books,
              db.books.id.equalsExp(db.physicalCopies.bookId),
            ),
          ])
          ..where(db.bookPlacements.environmentId.equals(environmentId));
    return query.watch().map(
      (rows) => [
        for (final r in rows)
          (
            placement: r.readTable(db.bookPlacements),
            book: r.readTable(db.books),
          ),
      ],
    );
  }

  /// Drops a book into an environment: creates a fresh physical copy (so the
  /// same title can be placed several times) and a placement at `(x, y)`.
  Future<void> placeBook(
    String environmentId,
    String bookId, {
    required double x,
    required double y,
  }) async {
    await db.transaction(() async {
      final copyId = _uuid.v4();
      await db
          .into(db.physicalCopies)
          .insert(
            PhysicalCopiesCompanion.insert(id: copyId, bookId: bookId),
          );
      await db
          .into(db.bookPlacements)
          .insert(
            BookPlacementsCompanion.insert(
              id: _uuid.v4(),
              environmentId: environmentId,
              copyId: copyId,
              x: x,
              y: y,
            ),
          );
    });
    await markDirty(environmentId);
  }

  /// Writes a whole bookcase — its shelves and its side panels — in one
  /// transaction (next features #11).
  ///
  /// A generator, not a container: what lands in the database is ordinary
  /// segments, so fill, tidy, stocktake, labels and the published room document
  /// keep working without knowing bookcases exist. Returns how many segments
  /// were written.
  /// Returns the group id the bookcase was written under, so the caller can
  /// select it straight away.
  Future<String> addBookcase(
    String environmentId,
    List<TemplateSegment> parts, {
    String? groupId,
  }) async {
    final group = groupId ?? _uuid.v4();
    if (parts.isEmpty) return group;
    await db.transaction(() async {
      for (final part in parts) {
        await db.into(db.physicalShelves).insert(
              PhysicalShelvesCompanion.insert(
                id: _uuid.v4(),
                environmentId: environmentId,
                x1: part.x1,
                y1: part.y1,
                x2: part.x2,
                y2: part.y2,
                label: Value(part.label),
                kind: Value(part.kind.key),
                groupId: Value(group),
              ),
            );
      }
    });
    await markDirty(environmentId);
    return group;
  }

  /// Every segment of one bookcase.
  Future<List<PhysicalShelf>> shelvesInGroup(String groupId) =>
      (db.select(db.physicalShelves)..where((s) => s.groupId.equals(groupId)))
          .get();

  /// Moves a whole bookcase by [delta] metres, in one transaction so it can
  /// never end up half-moved.
  Future<void> moveGroup(String groupId, Offset delta) async {
    final parts = await shelvesInGroup(groupId);
    if (parts.isEmpty) return;
    await db.transaction(() async {
      for (final part in parts) {
        await (db.update(db.physicalShelves)..where((s) => s.id.equals(part.id)))
            .write(PhysicalShelvesCompanion(
          x1: Value(part.x1 + delta.dx),
          y1: Value(part.y1 + delta.dy),
          x2: Value(part.x2 + delta.dx),
          y2: Value(part.y2 + delta.dy),
        ));
      }
    });
    await markDirty(parts.first.environmentId);
  }

  /// Breaks a bookcase back into loose segments. Nothing moves — the geometry
  /// was never nested, only tagged — so this is genuinely just forgetting the
  /// tag, and the shelves stay exactly where they are.
  Future<void> ungroup(String groupId) async {
    final parts = await shelvesInGroup(groupId);
    if (parts.isEmpty) return;
    await (db.update(db.physicalShelves)
          ..where((s) => s.groupId.equals(groupId)))
        .write(const PhysicalShelvesCompanion(groupId: Value(null)));
    await markDirty(parts.first.environmentId);
  }

  /// Tags a hand-picked set of segments as one bookcase.
  Future<String> groupShelves(String environmentId, Iterable<String> ids) async {
    final group = _uuid.v4();
    await db.transaction(() async {
      for (final id in ids) {
        await (db.update(db.physicalShelves)..where((s) => s.id.equals(id)))
            .write(PhysicalShelvesCompanion(groupId: Value(group)));
      }
    });
    await markDirty(environmentId);
    return group;
  }

  /// Deletes a whole bookcase.
  Future<void> deleteGroup(String groupId) async {
    final parts = await shelvesInGroup(groupId);
    if (parts.isEmpty) return;
    await (db.delete(db.physicalShelves)
          ..where((s) => s.groupId.equals(groupId)))
        .go();
    await markDirty(parts.first.environmentId);
  }

  /// Places several books at once, each with its own position (the bulk-add
  /// flow). Every copy and placement is written in **one** transaction, so a
  /// batch of forty either lands whole or not at all — and the room is marked
  /// dirty once rather than forty times, which is what a per-book loop would
  /// have cost in sync churn.
  ///
  /// Returns the number of books placed.
  Future<int> placeBooks(
    String environmentId,
    List<({String bookId, double x, double y})> books,
  ) async {
    if (books.isEmpty) return 0;
    await db.transaction(() async {
      for (final b in books) {
        final copyId = _uuid.v4();
        await db.into(db.physicalCopies).insert(
              PhysicalCopiesCompanion.insert(id: copyId, bookId: b.bookId),
            );
        await db.into(db.bookPlacements).insert(
              BookPlacementsCompanion.insert(
                id: _uuid.v4(),
                environmentId: environmentId,
                copyId: copyId,
                x: b.x,
                y: b.y,
              ),
            );
      }
    });
    await markDirty(environmentId);
    return books.length;
  }

  // ---- props (next features #10) -------------------------------------------

  Stream<List<RoomProp>> watchProps(String environmentId) =>
      (db.select(db.roomProps)
            ..where((p) => p.environmentId.equals(environmentId)))
          .watch();

  /// Stands a prop in the room at ([x], [y]) — its bottom-left corner, like a
  /// book placement, so the same settling code puts it on a shelf.
  Future<String> addProp(
    String environmentId, {
    required PropKind kind,
    required double x,
    required double y,
    double? width,
    double? height,
  }) async {
    final id = _uuid.v4();
    await db.into(db.roomProps).insert(
          RoomPropsCompanion.insert(
            id: id,
            environmentId: environmentId,
            kind: kind.name,
            x: x,
            y: y,
            widthM: width ?? kind.width,
            heightM: height ?? kind.height,
          ),
        );
    await markDirty(environmentId);
    return id;
  }

  Future<void> moveProp(String id, {required double x, required double y}) async {
    await (db.update(db.roomProps)..where((p) => p.id.equals(id)))
        .write(RoomPropsCompanion(x: Value(x), y: Value(y)));
    await db.customStatement(
      'UPDATE physical_environments SET needs_publish = 1 WHERE id = '
      '(SELECT environment_id FROM room_props WHERE id = ?)',
      [id],
    );
  }

  Future<void> deleteProp(String id) async {
    await db.customStatement(
      'UPDATE physical_environments SET needs_publish = 1 WHERE id = '
      '(SELECT environment_id FROM room_props WHERE id = ?)',
      [id],
    );
    await (db.delete(db.roomProps)..where((p) => p.id.equals(id))).go();
  }

  /// Partial update of a placement; omitted arguments are left unchanged.
  /// Pass a `Value(null)` for a size override to clear it back to the default.
  Future<void> updatePlacement(
    String id, {
    double? x,
    double? y,
    int? rotation,
    Value<double?>? widthOverride,
    Value<double?>? heightOverride,
    Value<String?>? format,
  }) async {
    await (db.update(db.bookPlacements)..where((p) => p.id.equals(id))).write(
      BookPlacementsCompanion(
        x: x == null ? const Value.absent() : Value(x),
        y: y == null ? const Value.absent() : Value(y),
        rotation: rotation == null ? const Value.absent() : Value(rotation),
        widthOverride: widthOverride ?? const Value.absent(),
        heightOverride: heightOverride ?? const Value.absent(),
        format: format ?? const Value.absent(),
      ),
    );
    await _dirtyByPlacement(id);
  }

  /// Removes a placement and the copy it created.
  Future<void> removePlacement(BookPlacement placement) async {
    await markDirty(placement.environmentId);
    await db.transaction(() async {
      await (db.delete(db.bookPlacements)
            ..where((p) => p.id.equals(placement.id)))
          .go();
      await _deleteCopy(placement.copyId);
    });
  }

  Future<void> _deleteCopy(String copyId) => _physical.deletePhysicalCopy(copyId);
}
