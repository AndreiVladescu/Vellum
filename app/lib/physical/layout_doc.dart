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
  List<RoomProp> props = const [],
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
            // What the segment *is* (plan 5 #29). Written even for a plain
            // shelf: a viewer that drew a side panel as a shelf would let books
            // rest on it, and the omission is invisible on the publishing
            // device — where the row already exists — so only the *other*
            // device would ever see it go wrong.
            'kind': s.kind,
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
      // Ornaments (next features #10). Until this they were app-local, so a
      // room you shared arrived with its shelves and books but none of the
      // things standing between them — which reads as a bug rather than as a
      // deliberate omission, because the publishing device shows them.
      //
      // Defaulted to empty above and read as empty below, so a document from
      // before this still parses: an older room simply has no props, which is
      // exactly what it had.
      'props': [
        for (final prop in props)
          {
            'id': prop.id,
            'kind': prop.kind,
            'x': prop.x,
            'y': prop.y,
            'width_m': prop.widthM,
            'height_m': prop.heightM,
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
    this.props = const [],
  });

  final String environmentId;
  final String name;
  final List<ParsedShelf> shelves;
  final List<ParsedPlacement> placements;

  /// Empty for a document published before props were part of one.
  final List<ParsedProp> props;
}

class ParsedProp {
  const ParsedProp({
    required this.id,
    required this.kind,
    required this.x,
    required this.y,
    required this.widthM,
    required this.heightM,
  });

  final String id;

  /// A [PropKind] name. Kept as text so an unknown kind from a newer publisher
  /// still occupies its space rather than vanishing — `PropKind.parse` decides
  /// what to draw.
  final String kind;
  final double x, y, widthM, heightM;
}

class ParsedShelf {
  const ParsedShelf({
    required this.id,
    required this.x1,
    required this.y1,
    required this.x2,
    required this.y2,
    this.label,
    this.kind = 'shelf',
  });

  final String id;
  final double x1, y1, x2, y2;
  final String? label;

  /// Absent in documents written before plan 5 #29, which read as a plain
  /// shelf — the behaviour those documents were published with.
  final String kind;
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
            kind: raw['kind']?.toString() ?? 'shelf',
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
    props: [
      for (final raw in (doc['props'] as List? ?? const []))
        if (raw is Map && raw['id'] != null)
          ParsedProp(
            id: raw['id'].toString(),
            kind: raw['kind']?.toString() ?? 'boxes',
            x: _num(raw['x']),
            y: _num(raw['y']),
            widthM: _num(raw['width_m']),
            heightM: _num(raw['height_m']),
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
              kind: Value(shelf.kind),
            ),
          );
    }
    final keepShelves = {for (final s in layout.shelves) s.id};
    await (db.delete(db.physicalShelves)
          ..where((s) =>
              s.environmentId.equals(layout.environmentId) &
              s.id.isNotIn(keepShelves)))
        .go();

    // Props: upsert, then drop the ones the document no longer lists — the
    // same shape as shelves above, and for the same reason. An ornament moved
    // away on the publishing device must not linger here.
    for (final prop in layout.props) {
      await db.into(db.roomProps).insertOnConflictUpdate(
            RoomPropsCompanion.insert(
              id: prop.id,
              environmentId: layout.environmentId,
              kind: prop.kind,
              x: prop.x,
              y: prop.y,
              widthM: prop.widthM,
              heightM: prop.heightM,
            ),
          );
    }
    final keepProps = {for (final p in layout.props) p.id};
    await (db.delete(db.roomProps)
          ..where((p) =>
              p.environmentId.equals(layout.environmentId) &
              p.id.isNotIn(keepProps)))
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
      //
      // `DoNothing` on conflict, not an update: a copy that is already here is
      // the sync channel's business, not this document's. An upsert would clear
      // the `needsPush` of a copy placed locally and not yet pushed, so that
      // copy would never reach the server — and the published room would point
      // at a `copy_id` no other device can resolve.
      //
      // The insert itself sets `needsPush: false` because a *new* placeholder
      // did come from the server; pushing it straight back is the trap #17's
      // series pull hit.
      await db.into(db.physicalCopies).insert(
            PhysicalCopiesCompanion.insert(
              id: placement.copyId,
              bookId: placement.bookId,
              needsPush: const Value(false),
            ),
            onConflict: DoNothing(),
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
