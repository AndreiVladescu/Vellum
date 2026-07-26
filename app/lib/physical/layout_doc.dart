/// The `layout_doc` v1 document (plan 5 #47) — serialising a room for publish
/// and applying a fetched one.
///
/// The format itself is specified in `docs/LAYOUT_DOC.md`; this is the app's
/// half of that contract. Two properties matter and are enforced here:
///
/// - **Geometry only.** No titles, authors or covers go into the document, so a
///   viewer who may not see a book cannot learn anything about it from the room
///   — redaction is structural rather than a filter someone must remember.
/// - **Sizes are baked in.** `width_m`/`height_m` are resolved at publish time,
///   because a viewer who cannot read a book's page count still has to draw its
///   spine at the right thickness.
library;

import 'package:drift/drift.dart';

import '../data/database.dart';
import 'layout_repository.dart' show PlacedBook;
import 'physical_metrics.dart';

/// The version this app writes, and the highest it will read. A reader that
/// meets a higher one refuses: a partially understood room is a wrong room.
const int layoutDocVersion = 1;

const String layoutDocKind = 'vellum.layout';

/// Raised when a document can't be used — wrong kind, or a version from a newer
/// app. Carries a sentence fit to show a person.
class LayoutDocException implements Exception {
  const LayoutDocException(this.message);

  final String message;

  @override
  String toString() => message;
}

/// Builds the document for one environment.
///
/// [placed] and [shelves] are exactly what the editor draws, so what is
/// published is what you were looking at.
Map<String, dynamic> buildLayoutDoc({
  required PhysicalEnvironment environment,
  required List<PhysicalShelf> shelves,
  required List<PlacedBook> placed,
}) =>
    {
      'doc': layoutDocKind,
      'version': layoutDocVersion,
      'environment': {
        'id': environment.id,
        'name': environment.name,
      },
      'shelves': [
        for (final s in shelves)
          {
            'id': s.id,
            'x1': s.x1,
            'y1': s.y1,
            'x2': s.x2,
            'y2': s.y2,
            if (s.label != null && s.label!.trim().isNotEmpty) 'label': s.label,
          },
      ],
      'placements': [
        for (final pb in placed)
          {
            'id': pb.placement.id,
            'copy_id': pb.placement.copyId,
            'book_id': pb.book.id,
            'x': pb.placement.x,
            'y': pb.placement.y,
            'rotation': pb.placement.rotation,
            // Resolved here, not left to the viewer — see the library comment.
            'width_m': _thicknessOf(pb),
            'height_m': _heightOf(pb),
            if (pb.placement.format != null) 'format': pb.placement.format,
          },
      ],
    };

double _thicknessOf(PlacedBook pb) => PhysicalMetrics.thickness(
      pb.book,
      format: BookFormat.byKey(pb.placement.format),
      override: pb.placement.widthOverride,
    );

double _heightOf(PlacedBook pb) => PhysicalMetrics.height(
      pb.book,
      format: BookFormat.byKey(pb.placement.format),
      override: pb.placement.heightOverride,
    );

/// A document parsed into the pieces `applyLayoutDoc` needs.
class ParsedLayout {
  const ParsedLayout({
    required this.environmentId,
    required this.name,
    required this.shelves,
    required this.placements,
  });

  final String environmentId;
  final String name;
  final List<ParsedShelf> shelves;
  final List<ParsedPlacement> placements;
}

class ParsedShelf {
  const ParsedShelf({
    required this.id,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.label,
  });

  final String id;
  final double x1, y1, x2, y2;
  final String? label;
}

class ParsedPlacement {
  const ParsedPlacement({
    required this.id,
    required this.copyId,
    required this.bookId,
    required this.x,
    required this.y,
    required this.rotation,
    required this.widthM,
    required this.heightM,
    this.format,
  });

  final String id;
  final String copyId;
  final String bookId;
  final double x, y;
  final int rotation;
  final double widthM, heightM;
  final String? format;
}

/// Reads a document, refusing anything it doesn't fully understand.
ParsedLayout parseLayoutDoc(Map<String, dynamic> doc) {
  if (doc['doc'] != layoutDocKind) {
    throw const LayoutDocException('That is not a Vellum room document.');
  }
  final version = (doc['version'] as num?)?.toInt() ?? 0;
  if (version > layoutDocVersion) {
    throw LayoutDocException(
      'This room was published by a newer version of Vellum (format v$version). '
      'Update the app to open it.',
    );
  }
  final environment = doc['environment'];
  if (environment is! Map) {
    throw const LayoutDocException('That room document is missing its room.');
  }
  final id = environment['id']?.toString();
  if (id == null || id.isEmpty) {
    throw const LayoutDocException('That room document has no id.');
  }

  return ParsedLayout(
    environmentId: id,
    name: (environment['name'] ?? 'Room').toString(),
    shelves: [
      for (final raw in (doc['shelves'] as List? ?? const []))
        if (raw is Map)
          ParsedShelf(
            id: raw['id'].toString(),
            x1: _num(raw['x1']),
            y1: _num(raw['y1']),
            x2: _num(raw['x2']),
            y2: _num(raw['y2']),
            label: raw['label']?.toString(),
          ),
    ],
    placements: [
      for (final raw in (doc['placements'] as List? ?? const []))
        if (raw is Map && raw['copy_id'] != null && raw['book_id'] != null)
          ParsedPlacement(
            id: raw['id'].toString(),
            copyId: raw['copy_id'].toString(),
            bookId: raw['book_id'].toString(),
            x: _num(raw['x']),
            y: _num(raw['y']),
            rotation: (raw['rotation'] as num?)?.toInt() ?? 0,
            widthM: _num(raw['width_m']),
            heightM: _num(raw['height_m']),
            format: raw['format']?.toString(),
          ),
    ],
  );
}

double _num(Object? value) => (value as num?)?.toDouble() ?? 0;

/// Applies a fetched document over the local database, in one transaction.
///
/// The shape of it: **upsert by id, then delete what the document doesn't
/// mention**. That is what makes a fetch idempotent and what makes a book
/// someone else removed actually disappear here.
///
/// Two things it deliberately does *not* do:
///
/// - It never invents book rows. A placement whose `book_id` hasn't arrived
///   through the ordinary sync is skipped — the room is a *reference* to books,
///   not an inventory of them, the same semantics the editor already has.
/// - It never touches a copy's own fields. A copy minted here for a `copy_id`
///   the pull hasn't delivered yet is a placeholder that the next sync fills in.
///
/// Returns how many placements were skipped for want of a book, so the caller
/// can say "3 books aren't on this device yet" instead of quietly losing them.
Future<int> applyLayoutDoc(
  VellumDatabase db,
  ParsedLayout layout, {
  required int revision,
}) async {
  var skipped = 0;
  await db.transaction(() async {
    await db.into(db.physicalEnvironments).insertOnConflictUpdate(
          PhysicalEnvironmentsCompanion.insert(
            id: layout.environmentId,
            name: layout.name,
            serverRevision: Value(revision),
            needsPublish: const Value(false),
          ),
        );

    // Shelves: upsert, then remove the ones the document dropped.
    for (final shelf in layout.shelves) {
      await db.into(db.physicalShelves).insertOnConflictUpdate(
            PhysicalShelvesCompanion.insert(
              id: shelf.id,
              environmentId: layout.environmentId,
              x1: shelf.x1,
              y1: shelf.y1,
              x2: shelf.x2,
              y2: shelf.y2,
              label: Value(shelf.label),
            ),
          );
    }
    final keepShelves = {for (final s in layout.shelves) s.id};
    await (db.delete(db.physicalShelves)
          ..where((s) =>
              s.environmentId.equals(layout.environmentId) &
              s.id.isNotIn(keepShelves)))
        .go();

    final knownBooks = {
      for (final row in await db.select(db.books).get()) row.id,
    };

    final applied = <String>{};
    for (final placement in layout.placements) {
      if (!knownBooks.contains(placement.bookId)) {
        skipped++;
        continue;
      }
      // The copy may not have arrived through sync yet; mint a placeholder so
      // the room renders, and let the pull fill in its fields later.
      await db.into(db.physicalCopies).insertOnConflictUpdate(
            PhysicalCopiesCompanion.insert(
              id: placement.copyId,
              bookId: placement.bookId,
              // Not dirty: this row came *from* the server, and marking it for
              // push would send it straight back — the same trap #17's series
              // pull hit.
              needsPush: const Value(false),
            ),
          );
      await db.into(db.bookPlacements).insertOnConflictUpdate(
            BookPlacementsCompanion.insert(
              id: placement.id,
              environmentId: layout.environmentId,
              copyId: placement.copyId,
              x: placement.x,
              y: placement.y,
              rotation: Value(placement.rotation),
              widthOverride: Value(placement.widthM),
              heightOverride: Value(placement.heightM),
              format: Value(placement.format),
            ),
          );
      applied.add(placement.id);
    }
    await (db.delete(db.bookPlacements)
          ..where((p) =>
              p.environmentId.equals(layout.environmentId) &
              p.id.isNotIn(applied)))
        .go();
  });
  return skipped;
}
