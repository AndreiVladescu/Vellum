// Finding a copy, tidying a shelf, and the shelf-label link (plan 5 #28).
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:qr/qr.dart';
import 'package:vellum/physical/labels.dart';
import 'package:vellum/physical/locate.dart';

Book _book({String title = 'Dune', String? subtitle, String? isbn}) => Book(
      id: 'b1',
      title: title,
      subtitle: subtitle,
      isbn: isbn,
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      needsPush: false,
      readerNotesNeedsPush: false,
      needsProgressPush: false,
      status: 'unread',
      readCount: 0,
    );

TidyBook _tb(
  String id, {
  required String title,
  String? author,
  String? series,
  double? index,
  double width = 0.03,
}) =>
    TidyBook(
      placementId: id,
      width: width,
      title: title,
      author: author,
      seriesName: series,
      seriesIndex: index,
    );

void main() {
  group('search', () {
    test('an empty query matches everything, so a blank field is no filter',
        () {
      expect(bookMatches(_book(), ''), isTrue);
      expect(bookMatches(_book(), '   '), isTrue);
    });

    test('matches title, subtitle, ISBN and authors, case-insensitively', () {
      final book = _book(
        title: 'Dune',
        subtitle: 'Chronicles',
        isbn: '9780441013593',
      );
      expect(bookMatches(book, 'dun'), isTrue);
      expect(bookMatches(book, 'CHRON'), isTrue);
      expect(bookMatches(book, '441013'), isTrue);
      expect(bookMatches(book, 'herbert', authors: ['Frank Herbert']), isTrue);
      expect(bookMatches(book, 'asimov', authors: ['Frank Herbert']), isFalse);
    });

    test('a partially typed word still matches', () {
      // The field filters as you type; requiring a whole word would make it
      // look broken for the first four keystrokes.
      expect(bookMatches(_book(title: 'Neuromancer'), 'neuro'), isTrue);
    });
  });

  group('tidy order', () {
    test('by author, with the author-less books last', () {
      final ordered = tidyOrder([
        _tb('1', title: 'Anon', author: null),
        _tb('2', title: 'Dune', author: 'Herbert'),
        _tb('3', title: 'Foundation', author: 'Asimov'),
      ], TidySort.author);
      expect(ordered.map((b) => b.placementId), ['3', '2', '1']);
    });

    test('by series, then volume, with volume-less companions after', () {
      final ordered = tidyOrder([
        _tb('c', title: 'Companion', series: 'Dune'),
        _tb('b', title: 'Messiah', series: 'Dune', index: 2),
        _tb('a', title: 'Dune', series: 'Dune', index: 1),
        _tb('z', title: 'Standalone'),
      ], TidySort.series);
      expect(ordered.map((b) => b.placementId), ['a', 'b', 'c', 'z']);
    });

    test('a fractional volume sits between its neighbours', () {
      final ordered = tidyOrder([
        _tb('two', title: 'Two', series: 'S', index: 2),
        _tb('novella', title: 'Novella', series: 'S', index: 1.5),
        _tb('one', title: 'One', series: 'S', index: 1),
      ], TidySort.series);
      expect(ordered.map((b) => b.placementId), ['one', 'novella', 'two']);
    });

    test('ties break on title then id, so a tidy never shuffles', () {
      final books = [
        _tb('zz', title: 'Same', author: 'A'),
        _tb('aa', title: 'Same', author: 'A'),
      ];
      final first = tidyOrder(books, TidySort.author).map((b) => b.placementId);
      final second =
          tidyOrder(books.reversed.toList(), TidySort.author)
              .map((b) => b.placementId);
      expect(first, ['aa', 'zz']);
      expect(second, ['aa', 'zz'], reason: 'order is independent of input order');
    });

    test('by title ignores case', () {
      final ordered = tidyOrder([
        _tb('1', title: 'banana'),
        _tb('2', title: 'Apple'),
      ], TidySort.title);
      expect(ordered.map((b) => b.placementId), ['2', '1']);
    });
  });

  group('tidy positions', () {
    test('packs flush from the left end, in order, with no overlaps', () {
      final books = [
        _tb('a', title: 'A', width: 0.03),
        _tb('b', title: 'B', width: 0.05),
        _tb('c', title: 'C', width: 0.02),
      ];
      final moves = tidyPositions(
        books,
        shelfLeft: 0.2,
        shelfRight: 1.2,
        currentX: const {'a': 9.0, 'b': 9.0, 'c': 9.0},
      );
      expect(moves.map((m) => m.x), [0.2, closeTo(0.23, 1e-9), 0.28]);
      // No overlap: each book starts exactly where the previous one ended.
      for (var i = 1; i < moves.length; i++) {
        expect(moves[i].x, greaterThanOrEqualTo(moves[i - 1].x));
      }
    });

    test('an already-tidy shelf writes nothing', () {
      final books = [
        _tb('a', title: 'A', width: 0.03),
        _tb('b', title: 'B', width: 0.05),
      ];
      expect(
        tidyPositions(books,
            shelfLeft: 0, shelfRight: 1, currentX: const {'a': 0, 'b': 0.03}),
        isEmpty,
      );
    });

    test('a shelf given right-to-left endpoints still packs from its left', () {
      final moves = tidyPositions(
        [_tb('a', title: 'A', width: 0.03)],
        shelfLeft: 1.5,
        shelfRight: 0.5,
        currentX: const {'a': 0},
      );
      expect(moves.single.x, 0.5);
    });

    test('books wider than the shelf overflow rather than vanishing', () {
      // Silently dropping or stacking a book because the shelf is full would be
      // much worse than one sticking out; gravity deals with it afterwards.
      final moves = tidyPositions(
        [
          _tb('a', title: 'A', width: 0.6),
          _tb('b', title: 'B', width: 0.6),
        ],
        shelfLeft: 0,
        shelfRight: 1,
        currentX: const {'a': 0.9, 'b': 0.9},
      );
      expect(moves.map((m) => m.x), [0, 0.6]);
    });

    test('an empty shelf produces no moves', () {
      expect(
        tidyPositions(const [],
            shelfLeft: 0, shelfRight: 1, currentX: const {}),
        isEmpty,
      );
    });
  });

  group('shelf links', () {
    test('round-trips an id', () {
      expect(parseShelfLink(shelfLink('abc-123')), 'abc-123');
    });

    test('tolerates whitespace and a mixed-case scheme', () {
      expect(parseShelfLink('  VELLUM://shelf/xyz  '), 'xyz');
    });

    test('rejects anything that is not a shelf link', () {
      // A book barcode, another Vellum link, and a plain URL must all be
      // ignored — the scanner sees whatever is in front of it.
      expect(parseShelfLink('9780441013593'), isNull);
      expect(parseShelfLink('vellum://book/abc'), isNull);
      expect(parseShelfLink('https://example.com/shelf/abc'), isNull);
      expect(parseShelfLink('vellum://shelf/'), isNull);
      expect(parseShelfLink('vellum://shelf/a/b'), isNull);
    });
  });

  group('label sheet', () {
    test('names every shelf and carries a scannable link for each', () {
      final html = buildLabelSheetHtml(labels: const [
        ShelfLabel(
          shelfId: 's1',
          environmentName: 'Living room',
          shelfName: 'Top shelf',
          bookCount: 12,
        ),
        ShelfLabel(shelfId: 's2', environmentName: 'Study'),
      ]);
      expect(html, contains('Top shelf'));
      expect(html, contains('Living room'));
      expect(html, contains('12 books'));
      expect(html, contains('vellum://shelf/s1'));
      // An unlabelled shelf still gets a label — you stick it on, then name it.
      expect(html, contains('Unlabelled shelf'));
      expect(html, contains('No books recorded'));
      // Two QR codes, one per label.
      expect('<svg'.allMatches(html).length, 2);
    });

    test('user text is escaped, so a name with markup cannot break the sheet',
        () {
      final html = buildLabelSheetHtml(labels: const [
        ShelfLabel(
          shelfId: 's1',
          environmentName: 'Ana & Bob',
          shelfName: '<script>alert(1)</script>',
        ),
      ]);
      expect(html, isNot(contains('<script>')));
      expect(html, contains('&lt;script&gt;'));
      expect(html, contains('Ana &amp; Bob'));
    });

    test('the QR can be turned off for a plain text sheet', () {
      final html = buildLabelSheetHtml(
        labels: const [ShelfLabel(shelfId: 's1', environmentName: 'Study')],
        includeQr: false,
      );
      expect(html, isNot(contains('<svg')));
      expect(html, contains('Study'));
    });

    test('the SVG draws the QR the right way round', () {
      // The bug this guards is invisible on screen and fatal on paper: writing
      // `M<row> <col>` instead of `M<col> <row>` transposes the code, which
      // still *looks* like a QR — finder squares in three corners and all —
      // and simply never scans. So the emitted path is parsed back into a
      // matrix and compared against the encoder's own orientation.
      const data = 'vellum://shelf/abc-123';
      final svg = qrSvgForTesting(data);
      final expected = QrImage(QrCode(
        payload: QrPayload.fromString(data),
        errorCorrectLevel: QrErrorCorrectLevel.high,
      ));

      final drawn = <(int, int)>{};
      for (final match
          in RegExp(r'M(\d+) (\d+)h1v1h-1z').allMatches(svg)) {
        drawn.add((int.parse(match.group(1)!), int.parse(match.group(2)!)));
      }
      final wanted = <(int, int)>{};
      for (var row = 0; row < expected.moduleCount; row++) {
        for (var col = 0; col < expected.moduleCount; col++) {
          if (expected.isDark(row, col)) wanted.add((col, row));
        }
      }
      expect(drawn, isNotEmpty);
      expect(drawn, wanted);

      // And the quiet zone the spec requires is really there: 4 modules of
      // white on every side, or scanners struggle to find the code at all.
      final side = expected.moduleCount + 8;
      expect(svg, contains('viewBox="0 0 $side $side"'));
      expect(svg, contains('translate(4 4)'));
    });

    test('one book is not "1 books"', () {
      final html = buildLabelSheetHtml(labels: const [
        ShelfLabel(shelfId: 's1', environmentName: 'Study', bookCount: 1),
      ]);
      expect(html, contains('1 book<'));
    });
  });
}
