import 'package:drift/drift.dart';
import 'package:uuid/uuid.dart';

import '../data/database.dart';
import '../data/physical_service.dart';

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
          ),
        );
  }

  Future<void> updateShelf(
    String id, {
    double? x1,
    double? y1,
    double? x2,
    double? y2,
    Value<String?>? label,
  }) async {
    await (db.update(db.physicalShelves)..where((s) => s.id.equals(id))).write(
      PhysicalShelvesCompanion(
        x1: x1 == null ? const Value.absent() : Value(x1),
        y1: y1 == null ? const Value.absent() : Value(y1),
        x2: x2 == null ? const Value.absent() : Value(x2),
        y2: y2 == null ? const Value.absent() : Value(y2),
        label: label ?? const Value.absent(),
      ),
    );
  }

  Future<void> deleteShelf(String id) async {
    await (db.delete(db.physicalShelves)..where((s) => s.id.equals(id))).go();
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
  }

  /// Removes a placement and the copy it created.
  Future<void> removePlacement(BookPlacement placement) async {
    await db.transaction(() async {
      await (db.delete(db.bookPlacements)
            ..where((p) => p.id.equals(placement.id)))
          .go();
      await _deleteCopy(placement.copyId);
    });
  }

  Future<void> _deleteCopy(String copyId) => _physical.deletePhysicalCopy(copyId);
}
