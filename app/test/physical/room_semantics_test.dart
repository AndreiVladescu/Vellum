// The room's accessible summary (plan 5 #42). A drag-and-drop canvas has no
// traversal order, so this is the representation a screen reader actually gets
// — which makes "does it describe the room correctly" a correctness question,
// not a cosmetic one.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/physical/layout_repository.dart';
import 'package:vellum/physical/room_semantics.dart';

PhysicalShelf shelf(
  String id, {
  required double y,
  double x1 = 0,
  double x2 = 2,
  String? label,
}) =>
    PhysicalShelf(
      id: id,
      environmentId: 'env',
      x1: x1,
      y1: y,
      x2: x2,
      y2: y,
      label: label,
      kind: 'shelf',
      createdAt: DateTime(2026),
    );

PlacedBook placed(String id, String title, {required double x, double y = 1.0}) =>
    (
      placement: BookPlacement(
        id: id,
        environmentId: 'env',
        copyId: 'c$id',
        x: x,
        y: y,
        rotation: 0,
        createdAt: DateTime(2026),
      ),
      book: Book(
        id: 'b$id',
        title: title,
        needsPush: true,
        readerNotesNeedsPush: false,
        needsProgressPush: false,
        status: 'unread',
        readCount: 0,
        createdAt: DateTime(2026),
        updatedAt: DateTime(2026),
      ),
    );

void main() {
  test('books are grouped onto the shelf they stand on, left to right', () {
    final shelves = [shelf('s1', y: 1.0, label: 'Top')];
    final books = [
      placed('p3', 'Solaris', x: 1.5),
      placed('p1', 'Dune', x: 0.2),
      placed('p2', 'Neuromancer', x: 0.9),
    ];

    final summary = summarizeRoom(shelves: shelves, placed: books);
    expect(summary, hasLength(1));
    expect(summary.single.name, 'Top');
    expect(summary.single.titles, ['Dune', 'Neuromancer', 'Solaris']);
    expect(summary.single.spoken,
        'Top: 3 books — Dune, Neuromancer, Solaris');
  });

  test('shelves read top to bottom, and unlabelled ones are numbered that way',
      () {
    // Created bottom-first on purpose: the numbering must follow the room, not
    // the insertion order.
    final shelves = [
      shelf('low', y: 0.5),
      shelf('high', y: 2.0),
    ];
    final summary = summarizeRoom(shelves: shelves, placed: const []);
    expect([for (final s in summary) s.name], ['Shelf 1', 'Shelf 2']);
    expect(summary.first.spoken, 'Shelf 1: empty');
  });

  test('a label wins over the positional name', () {
    final summary = summarizeRoom(
      shelves: [shelf('a', y: 2.0, label: 'Cookbooks'), shelf('b', y: 1.0)],
      placed: const [],
    );
    expect([for (final s in summary) s.name], ['Cookbooks', 'Shelf 2']);
  });

  test('a book on no shelf is reported, not dropped', () {
    // Floating well above the only shelf — the canvas draws it, so the summary
    // has to mention it or the two disagree.
    final summary = summarizeRoom(
      shelves: [shelf('s1', y: 0.5)],
      placed: [placed('p1', 'Adrift', x: 0.5, y: 3.0)],
    );
    expect(summary, hasLength(2));
    expect(summary.last.name, 'Not on a shelf');
    expect(summary.last.titles, ['Adrift']);
  });

  test('a book that overlaps no shelf horizontally is loose, not guessed onto '
      'the nearest one', () {
    final summary = summarizeRoom(
      shelves: [shelf('s1', y: 1.0, x1: 0, x2: 1)],
      placed: [placed('p1', 'Off to one side', x: 5.0)],
    );
    expect(summary.last.name, 'Not on a shelf');
  });

  test('the summary and the canvas agree on what "standing on" means', () {
    // Same rule, one implementation: the summary must not re-derive it.
    final shelves = [shelf('s1', y: 1.0, label: 'Top')];
    final book = placed('p1', 'Dune', x: 0.5);
    expect(
      LayoutRepository.nearestShelf(
        placement: book.placement,
        shelves: shelves,
      )?.id,
      's1',
    );
    expect(
      summarizeRoom(shelves: shelves, placed: [book]).single.titles,
      ['Dune'],
    );
  });

  group('roomSemanticLabel', () {
    test('an empty room says what to do rather than nothing', () {
      expect(roomSemanticLabel(const []),
          'Empty room. Add a shelf, then place books.');
    });

    test('joins the shelves into one utterance', () {
      final summary = summarizeRoom(
        shelves: [shelf('s1', y: 2.0, label: 'Top'), shelf('s2', y: 1.0)],
        placed: [placed('p1', 'Dune', x: 0.5, y: 2.0)],
      );
      expect(
        roomSemanticLabel(summary),
        'Top: 1 book — Dune. Shelf 2: empty',
      );
    });
  });
}
