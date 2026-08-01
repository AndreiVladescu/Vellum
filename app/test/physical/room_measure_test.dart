// Room realism: calibration maths, shelf kinds, and the fill estimate
// (plan 5 #29).
//
// These are the parts that are wrong silently. A bad calibration doesn't throw,
// it just draws the room at the wrong size and looks authoritative doing it;
// a fill estimate that disagrees with the drawing is worse than no estimate.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/physical/room_measure.dart';

PhysicalShelf _shelf({
  double x1 = 0,
  double x2 = 0.9,
  double y = 1.0,
  String kind = 'shelf',
  String id = 's1',
  String? label,
}) =>
    PhysicalShelf(
      id: id,
      label: label,
      environmentId: 'e1',
      x1: x1,
      y1: y,
      x2: x2,
      y2: y,
      kind: kind,
      anchored: true,
      createdAt: DateTime(2026),
    );

Book _book({String id = 'b1', int pages = 220}) => Book(
      id: id,
      title: 'Book $id',
      pageCount: pages,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      needsPush: false,
      readerNotesNeedsPush: false,
      needsProgressPush: false,
      status: 'unread',
      readCount: 0,
    );

({BookPlacement placement, Book book}) _placed({
  String id = 'p1',
  required double x,
  double y = 1.0,
  int rotation = 0,
  double? width,
  double? height,
  Book? book,
}) =>
    (
      placement: BookPlacement(
        id: id,
        environmentId: 'e1',
        copyId: 'c$id',
        x: x,
        y: y,
        rotation: rotation,
        widthOverride: width,
        heightOverride: height,
        createdAt: DateTime(2026),
      ),
      book: book ?? _book(),
    );

void main() {
  group('shelf kinds', () {
    test('only a shelf holds books', () {
      expect(ShelfKind.shelf.holdsBooks, isTrue);
      expect(ShelfKind.panel.holdsBooks, isFalse);
      expect(ShelfKind.divider.holdsBooks, isFalse);
      expect(ShelfKind.marker.holdsBooks, isFalse);
    });

    test('an unknown kind reads as a shelf, not as furniture', () {
      // A row written by a newer version must still hold up the books resting
      // on it; treating it as furniture would drop them to the floor.
      expect(ShelfKind.parse('shelf'), ShelfKind.shelf);
      expect(ShelfKind.parse('panel'), ShelfKind.panel);
      expect(ShelfKind.parse('label'), ShelfKind.marker);
      expect(ShelfKind.parse('something-new'), ShelfKind.shelf);
      expect(ShelfKind.parse(null), ShelfKind.shelf);
    });
  });

  group('backdrop calibration', () {
    test('metres per pixel is the ratio', () {
      const c = BackdropCalibration(pixelDistance: 1000, realMetres: 2.0);
      expect(c.metresPerPixel, closeTo(0.002, 1e-12));
    });

    test('degenerate input yields no scale rather than a wrong one', () {
      // Rejected, not clamped: a scale of zero or infinity makes the whole room
      // the wrong size while looking like a calibrated photo.
      expect(
        const BackdropCalibration(pixelDistance: 0, realMetres: 2)
            .metresPerPixel,
        isNull,
      );
      expect(
        const BackdropCalibration(pixelDistance: 1000, realMetres: 0)
            .metresPerPixel,
        isNull,
      );
      expect(
        const BackdropCalibration(pixelDistance: -5, realMetres: 2)
            .metresPerPixel,
        isNull,
      );
      expect(
        BackdropCalibration(pixelDistance: double.nan, realMetres: 2)
            .metresPerPixel,
        isNull,
      );
    });

    test('a round trip through the scale recovers the real length', () {
      const c = BackdropCalibration(pixelDistance: 1500, realMetres: 2.1);
      expect(1500 * c.metresPerPixel!, closeTo(2.1, 1e-12));
    });

    test('pixel distance is Euclidean', () {
      expect(pixelDistanceBetween(0, 0, 3, 4), closeTo(5, 1e-12));
      expect(pixelDistanceBetween(10, 10, 10, 10), 0);
    });
  });

  group('distance formatting', () {
    test('centimetres below a metre, metres above', () {
      expect(formatDistance(0.42), '42 cm');
      expect(formatDistance(0.005), '1 cm'); // rounds, doesn't claim 0.5 cm
      expect(formatDistance(1.0), '1.00 m');
      expect(formatDistance(2.375), '2.38 m');
    });

    test('a negative distance reads as a length, not a direction', () {
      expect(formatDistance(-0.42), '42 cm');
    });
  });

  group('shelf fill', () {
    test('sums the spines resting on the shelf', () {
      // A 220-page book is ~12.6 mm on the default curve; three of them is a
      // few centimetres of a 90 cm shelf.
      final fill = fillOf(
        shelf: _shelf(),
        placed: [
          _placed(id: 'a', x: 0.0),
          _placed(id: 'b', x: 0.1),
          _placed(id: 'c', x: 0.2),
        ],
      );
      expect(fill.bookCount, 3);
      expect(fill.lengthM, closeTo(0.9, 1e-12));
      expect(fill.usedM, greaterThan(0.03));
      expect(fill.usedM, lessThan(0.05));
      expect(fill.fraction, lessThan(0.1));
      expect(fill.isOverfull, isFalse);
      expect(fill.describe(), contains('of 90 cm used'));
    });

    test('a book on another shelf is not counted', () {
      final fill = fillOf(
        shelf: _shelf(y: 1.0),
        placed: [
          _placed(id: 'here', x: 0.1, y: 1.0),
          _placed(id: 'above', x: 0.1, y: 1.4),
          _placed(id: 'beside', x: 5.0, y: 1.0),
        ],
      );
      expect(fill.bookCount, 1);
    });

    test('a book lying flat takes its height along the shelf', () {
      // The bug this prevents: counting a flat book by its spine thickness
      // makes a shelf of laid-down art books look almost empty.
      final upright = fillOf(
        shelf: _shelf(),
        placed: [_placed(x: 0, height: 0.25, width: 0.02)],
      );
      final flat = fillOf(
        shelf: _shelf(),
        placed: [_placed(x: 0, rotation: 90, height: 0.25, width: 0.02)],
      );
      expect(upright.usedM, closeTo(0.02, 1e-12));
      expect(flat.usedM, closeTo(0.25, 1e-12));
    });

    test('an overfull shelf says so instead of showing a full bar', () {
      final fill = fillOf(
        shelf: _shelf(x1: 0, x2: 0.1),
        placed: [
          _placed(id: 'a', x: 0, width: 0.06),
          _placed(id: 'b', x: 0.06, width: 0.06),
        ],
      );
      expect(fill.isOverfull, isTrue);
      expect(fill.fraction, 1.0, reason: 'clamped so the bar renders');
      expect(fill.freeM, 0);
      expect(fill.describe(), contains('overfull'));
    });

    test('an empty shelf is all free', () {
      final fill = fillOf(shelf: _shelf(), placed: const []);
      expect(fill.bookCount, 0);
      expect(fill.usedM, 0);
      expect(fill.freeM, closeTo(0.9, 1e-12));
      expect(fill.fraction, 0);
    });

    test('a zero-length shelf does not divide by zero', () {
      final fill = fillOf(shelf: _shelf(x1: 1, x2: 1), placed: const []);
      expect(fill.fraction, 0);
      expect(fill.describe(), 'No length');
    });

    test('fits allows for a millimetre of slack', () {
      // Shelves are measured by hand; a "fits" that is true by 0.2 mm is a lie
      // in the only place it matters — standing at the bookcase.
      final fill = fillOf(
        shelf: _shelf(x1: 0, x2: 0.1),
        placed: [_placed(x: 0, width: 0.09)],
      );
      expect(fill.freeM, closeTo(0.01, 1e-12));
      expect(fitsOn(fill, 0.005), isTrue);
      expect(fitsOn(fill, 0.0089), isTrue, reason: '8.9 mm + 1 mm slack fits');
      // 9.9 mm needs 10.9 mm with the slack, and only 10 mm is free — so no.
      expect(fitsOn(fill, 0.0099), isFalse);
      expect(fitsOn(fill, 0.01), isFalse, reason: 'exactly flush is not a fit');
      expect(fitsOn(fill, 0.02), isFalse);
    });
  });

  group('shelfName', () {
    test('uses the label when there is one', () {
      final s = _shelf(label: 'Cookbooks');
      expect(shelfName(s, [s]), 'Cookbooks');
    });

    test('falls back to the height, so a chooser can tell them apart', () {
      // Three rows all reading "Unlabelled shelf" is a list you cannot use.
      final low = _shelf(id: 'a', y: 0.4);
      final high = _shelf(id: 'b', y: 1.45);
      expect(shelfName(low, [low, high]), 'Shelf at 40 cm');
      expect(shelfName(high, [low, high]), 'Shelf at 1.45 m');
    });

    test('disambiguates two shelves sharing a label', () {
      final a = _shelf(id: 'a', y: 0.4, label: 'Cookbooks');
      final b = _shelf(id: 'b', y: 1.2, label: 'Cookbooks');
      expect(shelfName(a, [a, b]), 'Cookbooks (40 cm)');
      expect(shelfName(b, [a, b]), 'Cookbooks (1.20 m)');
    });

    test('a blank label counts as no label', () {
      final s = _shelf(label: '   ', y: 1.0);
      expect(shelfName(s, [s]), 'Shelf at 1.00 m');
    });
  });
}
