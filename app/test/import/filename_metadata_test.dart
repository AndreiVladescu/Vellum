// The file-name parser behind bulk import (plan 5 #15).
//
// The first three cases are the server's own tests from `metadata.rs` ported
// verbatim: this parser is a port, and the same file name imported in the app or
// through the console has to produce the same book. If one side's behaviour
// changes, one of these fails.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/import/filename_metadata.dart';

void main() {
  group('the download naming convention (ported from metadata.rs)', () {
    test('author - title-publisher (year)', () {
      final m = parseFilename(
          'Istvan Nagy - Complex Digital Hardware Design-CRC Press (2024)');
      expect(m.authors, ['Istvan Nagy']);
      expect(m.title, 'Complex Digital Hardware Design');
      expect(m.publisher, 'CRC Press');
      expect(m.year, 2024);
    });

    test('several comma-separated authors', () {
      final m = parseFilename(
          'Andrew S. Tanenbaum, Herbert Bos - Modern Operating Systems-Pearson (2023)');
      expect(m.authors, ['Andrew S. Tanenbaum', 'Herbert Bos']);
      expect(m.title, 'Modern Operating Systems');
      expect(m.publisher, 'Pearson');
      expect(m.year, 2023);
    });

    test('a name that fits nothing is just a title', () {
      final m = parseFilename('just_a_book_name');
      expect(m.authors, isEmpty);
      expect(m.title, 'just_a_book_name');
      expect(m.publisher, isNull);
      expect(m.year, isNull);
    });
  });

  group('real-world shapes', () {
    test('ampersand separates authors too', () {
      final m = parseFilename('Kernighan & Ritchie - The C Programming Language');
      expect(m.authors, ['Kernighan', 'Ritchie']);
      expect(m.title, 'The C Programming Language');
    });

    test('a hyphenated title without a publisher keeps the hyphen split rule', () {
      // Documents the known cost of "the last hyphen splits publisher": a
      // hyphenated title loses its tail. The dry-run table is editable exactly
      // because heuristics like this one are sometimes wrong.
      final m = parseFilename('Herbert - Dune-Messiah');
      expect(m.title, 'Dune');
      expect(m.publisher, 'Messiah');
    });

    test('a year in the middle is not treated as the year', () {
      final m = parseFilename('Someone - A History of 1969 in Pictures');
      expect(m.year, isNull);
      expect(m.title, 'A History of 1969 in Pictures');
    });

    test('a non-four-digit parenthetical is left alone', () {
      final m = parseFilename('Someone - Title (2nd ed)');
      expect(m.year, isNull);
      expect(m.title, 'Title (2nd ed)');
    });

    test('empty and whitespace-only names yield no title', () {
      expect(parseFilename('').title, isNull);
      expect(parseFilename('   ').title, isNull);
    });

    test('surrounding whitespace is trimmed everywhere', () {
      final m = parseFilename('  A. Author  -  A Title - Pub  (1999) ');
      expect(m.authors, ['A. Author']);
      expect(m.title, 'A Title');
      expect(m.publisher, 'Pub');
      expect(m.year, 1999);
    });

    test('searchQuery joins authors and title for the online lookup', () {
      final m = parseFilename('Frank Herbert - Dune-Ace (1965)');
      expect(m.searchQuery, 'Frank Herbert Dune');
    });
  });

  group('filenameStem', () {
    test('drops directories and the extension', () {
      expect(filenameStem('/home/me/books/Dune.pdf'), 'Dune');
      expect(filenameStem(r'C:\books\Dune.epub'), 'Dune');
    });

    test('keeps dots inside the name', () {
      expect(filenameStem('/b/A.B. Guthrie - The Big Sky.pdf'),
          'A.B. Guthrie - The Big Sky');
    });

    test('a dotfile keeps its whole name', () {
      expect(filenameStem('/b/.hidden'), '.hidden');
    });

    test('no extension is fine', () {
      expect(filenameStem('/b/README'), 'README');
    });
  });
}
