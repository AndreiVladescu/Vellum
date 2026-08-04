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
  group('personal columns from a reading tracker', () {
    // A Goodreads or StoryGraph export is mostly not catalogue data — it is
    // years of ratings, shelves and reviews. Dropping those silently is the
    // failure that looks like success.

    test('a Goodreads row keeps rating, shelf, date and review', () {
      // The real header, in Goodreads' own order and spelling.
      const csv = 'Book Id,Title,Author,Additional Authors,ISBN13,'
          'My Rating,Number of Pages,Original Publication Year,Date Read,'
          'Bookshelves,Exclusive Shelf,My Review,Read Count\n'
          '1,Dune,Frank Herbert,Brian Herbert,9780441013593,'
          '5,412,1965,2019/03/14,'
          'sci-fi,read,"Still the best of them.",2';
      final entry = CsvImport.read(csv).single;

      expect(entry.title, 'Dune');
      expect(entry.authors, ['Frank Herbert', 'Brian Herbert']);
      expect(entry.rating, 5);
      expect(entry.status, 'finished');
      expect(entry.finishedAt, DateTime(2019, 3, 14));
      expect(entry.readCount, 2);
      expect(entry.review, 'Still the best of them.');
    });

    test('a StoryGraph row is read the same way', () {
      const csv = 'Title,Authors,Contributors,ISBN/UID,Read Status,'
          'Star Rating,Last Date Read,Read Count,Review,Tags\n'
          'Piranesi,Susanna Clarke,,9781526622426,read,'
          '4.5,2021-07-02,1,"Odd and lovely.",fantasy';
      final entry = CsvImport.read(csv).single;

      expect(entry.status, 'finished');
      // Half stars round up: 4.5 is nearer the person's meaning at 5 than 4.
      expect(entry.rating, 5);
      expect(entry.finishedAt, DateTime(2021, 7, 2));
      expect(entry.review, 'Odd and lovely.');
    });

    test('to-read becomes the wishlist, not an unread shelf book', () {
      const csv = 'Title,Exclusive Shelf\nThe Dispossessed,to-read';
      // The point of the whole mapping: a want-to-read pile is books you do
      // not own, and four hundred of them on the shelf would bury the ones
      // you do.
      expect(CsvImport.read(csv).single.status, 'wishlist');
    });

    test('every shelf name either maps or is left alone', () {
      expect(readingStatusFromExport('currently-reading'), 'reading');
      expect(readingStatusFromExport('did-not-finish'), 'abandoned');
      expect(readingStatusFromExport('dnf'), 'abandoned');
      expect(readingStatusFromExport('Read'), 'finished');
      // Not a guess: an unknown shelf leaves the status alone.
      expect(readingStatusFromExport('borrowed-from-mum'), isNull);
      expect(readingStatusFromExport(''), isNull);
      expect(readingStatusFromExport(null), isNull);
    });

    test('an unrated book is null, not zero stars', () {
      // Goodreads writes 0 for "not rated", which is not a rating of nought.
      expect(ratingFromExport(0), isNull);
      expect(ratingFromExport(null), isNull);
      expect(ratingFromExport(3), 3);
      expect(ratingFromExport(4.5), 5);
      expect(ratingFromExport(9), 5, reason: 'clamped, not trusted');
    });

    test('a date that is not a date is null rather than a guess', () {
      expect(dateFromExport('2019/03/14'), DateTime(2019, 3, 14));
      expect(dateFromExport('2019-03-14'), DateTime(2019, 3, 14));
      expect(dateFromExport('not a date'), isNull);
      expect(dateFromExport(''), isNull);
      // DateTime would roll this into March; the export never said March.
      expect(dateFromExport('2019-02-31'), isNull);
    });

    test('a plain catalogue with none of these columns is unaffected', () {
      const csv = 'title,authors,year\nSolaris,Stanislaw Lem,1961';
      final entry = CsvImport.read(csv).single;
      expect(entry.title, 'Solaris');
      expect(entry.status, isNull);
      expect(entry.rating, isNull);
      expect(entry.review, isNull);
    });
  });
}
