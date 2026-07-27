// CSV/JSON catalogue import (plan 5 #21c). The promise that matters is the
// round trip: what the server console exports, this reads back.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/import/csv_import.dart';

void main() {
  group('parseCsv', () {
    test('quoted fields keep their commas and newlines', () {
      final rows = parseCsv('a,"b,c","d\ne"\n1,2,3\n');
      expect(rows, [
        ['a', 'b,c', 'd\ne'],
        ['1', '2', '3'],
      ]);
    });

    test('doubled quotes are one quote', () {
      expect(parseCsv('"say ""hi""",x').first, ['say "hi"', 'x']);
    });

    test('a file with no trailing newline still yields its last row', () {
      expect(parseCsv('a,b\n1,2'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('CRLF is one row break, not two', () {
      expect(parseCsv('a,b\r\n1,2\r\n'), [
        ['a', 'b'],
        ['1', '2'],
      ]);
    });

    test('empty fields are preserved, not collapsed', () {
      expect(parseCsv('a,,c').first, ['a', '', 'c']);
    });
  });

  group('the console export round-trips', () {
    // Exactly the header `exportCSV()` writes in server/web/console.js.
    const consoleCsv = 'title,subtitle,authors,published_year,publisher,isbn,'
        'page_count,file_count,has_cover,tags,created_at\n'
        'Dune,,"Frank Herbert",1965,Chilton Books,9780441013593,412,1,yes,'
        '"Science Fiction; Classics",2026-01-01\n'
        '"Gödel, Escher, Bach",An Eternal Golden Braid,'
        '"Douglas Hofstadter",1979,Basic Books,9780465026562,777,1,yes,'
        'Philosophy,2026-01-02\n';

    test('every column the console writes is read back', () {
      final entries = CsvImport.read(consoleCsv);
      expect(entries, hasLength(2));

      final dune = entries.first;
      expect(dune.title, 'Dune');
      expect(dune.authors, ['Frank Herbert']);
      expect(dune.year, 1965);
      expect(dune.publisher, 'Chilton Books');
      expect(dune.isbn, '9780441013593');
      expect(dune.pageCount, 412);
      expect(dune.genres, ['Science Fiction', 'Classics']);
    });

    test('a title containing a comma survives the round trip', () {
      final entries = CsvImport.read(consoleCsv);
      expect(entries.last.title, 'Gödel, Escher, Bach');
      expect(entries.last.subtitle, 'An Eternal Golden Braid');
    });

    test('no entry claims to bring a file', () {
      // A catalogue export describes books whose bytes are elsewhere.
      for (final e in CsvImport.read(consoleCsv)) {
        expect(e.filePath, isNull);
        expect(e.coverPath, isNull);
      }
    });
  });

  group('JSON', () {
    test('reads the console\'s /api/books shape', () {
      final entries = CsvImport.read('''
        [{"id":"x","title":"Dune","authors":["Frank Herbert"],
          "published_year":1965,"isbn":"978-0-441-01359-3","page_count":412}]
      ''');
      expect(entries.single.title, 'Dune');
      expect(entries.single.authors, ['Frank Herbert']);
      expect(entries.single.isbn, '9780441013593',
          reason: 'punctuation is stripped');
    });

    test('an object wrapping a books list is accepted too', () {
      final entries =
          CsvImport.read('{"books":[{"title":"Solaris"}],"total":1}');
      expect(entries.single.title, 'Solaris');
    });

    test('format is decided by content, not by extension', () {
      // A .csv holding JSON is still JSON.
      expect(CsvImport.read('  [{"title":"Dune"}]').single.title, 'Dune');
    });
  });

  group('other exporters land on their feet', () {
    test('a Goodreads-shaped export maps onto the same fields', () {
      final entries = CsvImport.read(
        'Title,Author,ISBN13,Original Publication Year,Publisher,'
        'Number of Pages,Bookshelves\n'
        'Dune,Frank Herbert,="9780441013593",1965,Chilton,412,'
        '"sci-fi, favourites"\n',
      );
      final dune = entries.single;
      expect(dune.title, 'Dune');
      expect(dune.authors, ['Frank Herbert']);
      expect(dune.isbn, '9780441013593',
          reason: "Goodreads' Excel escape is stripped");
      expect(dune.year, 1965);
      expect(dune.genres, ['sci-fi', 'favourites']);
    });
  });

  group('bad input is refused, not half-imported', () {
    test('a file with no title column is rejected', () {
      expect(
        () => CsvImport.read('isbn,pages\n123,400\n'),
        throwsA(isA<CsvImportException>()),
      );
    });

    test('an empty file is rejected', () {
      expect(() => CsvImport.read(''), throwsA(isA<CsvImportException>()));
    });

    test('rows without a title are dropped, not imported as blanks', () {
      final entries = CsvImport.read('title,isbn\nDune,1\n,2\n   ,3\n');
      expect([for (final e in entries) e.title], ['Dune']);
    });

    test('unparseable JSON says so rather than being read as CSV', () {
      expect(
        () => CsvImport.read('[{"title": '),
        throwsA(isA<CsvImportException>()),
      );
    });

    test('a nonsense ISBN is dropped rather than stored', () {
      expect(CsvImport.read('title,isbn\nDune,not-an-isbn\n').single.isbn,
          isNull);
    });
  });
}
