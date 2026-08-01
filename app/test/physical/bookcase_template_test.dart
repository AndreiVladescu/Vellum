// Bookcase templates (next features #11).
//
// The design decision under test is that a bookcase is a *generator*: it emits
// ordinary shelf and panel segments and then stops existing, so everything
// downstream — fill, tidy, stocktake, labels, the published room document —
// keeps working without knowing bookcases exist.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/physical/bookcase_template.dart';
import 'package:vellum/physical/room_measure.dart';

void main() {
  test('emits one shelf per shelf, plus two sides', () {
    final segments = bookcaseSegments(
      style: BookcaseStyle.billy,
      x: 0,
      y: 0,
    );
    final shelves = segments.where((s) => s.kind == ShelfKind.shelf).toList();
    final panels = segments.where((s) => s.kind == ShelfKind.panel).toList();
    expect(shelves, hasLength(BookcaseStyle.billy.shelves));
    expect(panels, hasLength(2));
  });

  test('the lowest shelf is at the base, not floating above it', () {
    final segments = bookcaseSegments(style: BookcaseStyle.low, x: 1.0, y: 0.3);
    final shelves = segments.where((s) => s.kind == ShelfKind.shelf).toList()
      ..sort((a, b) => a.y1.compareTo(b.y1));
    expect(shelves.first.y1, closeTo(0.3, 1e-9));
    expect(shelves.first.x1, closeTo(1.0, 1e-9));
    expect(shelves.first.x2, closeTo(1.0 + BookcaseStyle.low.width, 1e-9));
  });

  test('shelves are evenly spaced and none reaches the top of the unit', () {
    // The top of the case is not a shelf: a bookcase with six shelves has six
    // surfaces to put books on, which is what someone counting them means.
    const height = 2.0;
    final shelves = bookcaseSegments(
      style: BookcaseStyle.billy,
      x: 0,
      y: 0,
      height: height,
      shelves: 4,
    ).where((s) => s.kind == ShelfKind.shelf).toList()
      ..sort((a, b) => a.y1.compareTo(b.y1));

    expect(shelves, hasLength(4));
    for (var i = 0; i < shelves.length; i++) {
      expect(shelves[i].y1, closeTo(i * (height / 4), 1e-9));
    }
    expect(shelves.last.y1 < height, isTrue,
        reason: 'the top shelf must have headroom above it');
  });

  test('the sides are uprights, so books stop at them', () {
    // Zero width and a real vertical extent is what makes `settle` treat a
    // segment as a barrier — the same shape a divider has.
    final panels = bookcaseSegments(style: BookcaseStyle.billy, x: 2.0, y: 0)
        .where((s) => s.kind == ShelfKind.panel)
        .toList();
    for (final p in panels) {
      expect(p.x1, closeTo(p.x2, 1e-9), reason: 'a side panel is vertical');
      expect((p.y2 - p.y1).abs() > 0.5, isTrue,
          reason: 'a zero-height panel is the bug uprights used to have');
    }
    expect(
      panels.map((p) => p.x1).toList()..sort(),
      [closeTo(2.0, 1e-9), closeTo(2.0 + BookcaseStyle.billy.width, 1e-9)],
    );
  });

  test('floating shelves have no sides', () {
    final segments =
        bookcaseSegments(style: BookcaseStyle.floating, x: 0, y: 1.0);
    expect(segments.where((s) => s.kind == ShelfKind.panel), isEmpty);
    expect(segments.every((s) => s.kind == ShelfKind.shelf), isTrue);
  });

  test('only the unit is named, not every shelf in it', () {
    // "Billy 1", "Billy 2" … would be noise on the drawing and on the printed
    // shelf labels.
    final labels = bookcaseSegments(
      style: BookcaseStyle.billy,
      x: 0,
      y: 0,
      label: 'Hallway',
    ).map((s) => s.label).where((l) => l != null).toList();
    expect(labels, ['Hallway']);
  });

  test('a nonsense shelf count still produces a usable bookcase', () {
    final segments =
        bookcaseSegments(style: BookcaseStyle.billy, x: 0, y: 0, shelves: 0);
    expect(segments.where((s) => s.kind == ShelfKind.shelf), hasLength(1),
        reason: 'a bookcase with no shelves is a box, not a bookcase');
  });

  test('overriding the size moves the sides with it', () {
    final segments = bookcaseSegments(
      style: BookcaseStyle.billy,
      x: 0,
      y: 0,
      width: 1.5,
      height: 1.0,
    );
    final panels =
        segments.where((s) => s.kind == ShelfKind.panel).toList();
    expect(panels.map((p) => p.x1).toList()..sort(),
        [closeTo(0, 1e-9), closeTo(1.5, 1e-9)]);
    expect(panels.first.y2, closeTo(1.0, 1e-9));
    final shelf = segments.firstWhere((s) => s.kind == ShelfKind.shelf);
    expect(shelf.x2 - shelf.x1, closeTo(1.5, 1e-9));
  });
}
