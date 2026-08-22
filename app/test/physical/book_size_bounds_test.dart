import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/physical/physical_metrics.dart';

/// How big a book is, and how big it is allowed to get (issue #10 item 6).
///
/// Two separate things were wrong. The spine curve was calibrated against one
/// book and has been recalibrated against another — 40 mm for 720 pages — and
/// nothing bounded a size somebody typed in: `thickness` returned an override
/// *before* its clamp and `height` never clamped at all, so the resize dialog
/// could produce a book several times the size of the bookcase it stood in.
Book book({int? pages}) => Book(
      id: 'b1',
      title: 'A book',
      pageCount: pages,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      needsPush: false,
      syncExcluded: false,
      readerNotesNeedsPush: false,
      statusNeedsPush: false,
      needsProgressPush: false,
      status: 'unread',
      readCount: 0,
    );

void main() {
  group('the spine curve', () {
    test('720 pages is 40 mm, the book it was measured from', () {
      final mm = PhysicalMetrics.thickness(book(pages: 720)) * 1000;
      expect(mm, closeTo(40, 0.001));
    });

    test('and it is linear in the page count', () {
      final half = PhysicalMetrics.thickness(book(pages: 360)) * 1000;
      final double_ = PhysicalMetrics.thickness(book(pages: 1440)) * 1000;
      expect(half, closeTo(20, 0.001));
      expect(double_, closeTo(80, 0.001));
    });

    test('a hardcover adds its boards on top', () {
      final hard = BookFormat.byKey('hardcover');
      final mm = PhysicalMetrics.thickness(book(pages: 720), format: hard) *
          1000;
      expect(mm, closeTo(45, 0.001), reason: '40 mm of paper plus 5 mm boards');
    });

    test('a book with no page count still gets a size', () {
      expect(PhysicalMetrics.thickness(book()), greaterThan(0));
    });
  });

  group('nothing is bigger than A3', () {
    test('an absurd typed thickness is brought back to the ceiling', () {
      // The screenshot in the issue: a book wider than its bookcase.
      expect(
        PhysicalMetrics.thickness(book(), override: 5.0),
        PhysicalMetrics.maxThickness,
      );
    });

    test('and an absurd typed height', () {
      expect(
        PhysicalMetrics.height(book(), override: 5.0),
        PhysicalMetrics.maxHeight,
      );
    });

    test('A3 itself is allowed — the limit is generous, not tight', () {
      // An atlas or a folio really is this big; a limit that refused real
      // books would be its own bug.
      expect(PhysicalMetrics.height(book(), override: 0.420), 0.420);
      expect(PhysicalMetrics.thickness(book(), override: 0.297), 0.297);
    });

    test('an enormous page count cannot outgrow it either', () {
      expect(
        PhysicalMetrics.thickness(book(pages: 100000)),
        PhysicalMetrics.maxThickness,
      );
    });

    test('and nothing collapses to nothing', () {
      expect(PhysicalMetrics.height(book(), override: 0.0),
          PhysicalMetrics.minHeight);
      expect(PhysicalMetrics.thickness(book(), override: 0.0),
          greaterThan(0));
    });
  });

  test('an ordinary book is unaffected by any of this', () {
    // The bounds must not reshape a normal shelf: a 300-page paperback comes
    // out at its trim height and about 17 mm.
    final trade = BookFormat.byKey('trade');
    expect(PhysicalMetrics.height(book(pages: 300), format: trade), 0.203);
    expect(
      PhysicalMetrics.thickness(book(pages: 300), format: trade) * 1000,
      closeTo(16.7, 0.1),
    );
  });
}
