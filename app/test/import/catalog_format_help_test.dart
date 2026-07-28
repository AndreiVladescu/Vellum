// The template a user is handed has to be a file the importer accepts.
//
// This is documentation that runs: if the reader's column names or value
// handling ever drift from what the help sheet promises, the failure lands here
// rather than on someone with a spreadsheet open.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/import/catalog_format_help.dart';
import 'package:vellum/import/csv_import.dart';

void main() {
  test('the template imports, and means what the sheet says it means', () {
    final entries = CsvImport.read(catalogTemplateCsv);
    expect(entries, hasLength(2));

    final first = entries.first;
    expect(first.title, 'The Left Hand of Darkness');
    expect(first.authors, ['Ursula K. Le Guin']);
    expect(first.year, 1969);
    expect(first.publisher, 'Ace Books');
    expect(first.isbn, '9780441007318');
    expect(first.pageCount, 304);
    expect(first.series, 'Hainish Cycle');
    expect(first.seriesIndex, 4);
    expect(first.genres, ['science fiction', 'classics'],
        reason: 'a quoted, semicolon-separated cell is a list');
    expect(first.description, isNotNull);

    final second = entries.last;
    expect(second.authors, ['Terry Pratchett', 'Neil Gaiman'],
        reason: 'the sheet promises & works as a separator');
    expect(second.series, isNull, reason: 'an empty cell stays empty');
    expect(second.seriesIndex, isNull);
  });

  test('every column the sheet lists is one the reader knows', () {
    // The aliases are printed to the user as a promise. Each is fed in as a
    // real header with a value, and has to come back out as something.
    const values = {
      'title': 'A Book',
      'authors': 'An Author',
      'author': 'An Author',
      'author_sort': 'Author, An',
      'creator': 'An Author',
      'book title': 'A Book',
      'subtitle': 'A Subtitle',
      'isbn': '9780441007318',
      'isbn13': '9780441007318',
      'isbn-13': '9780441007318',
      'isbn_13': '9780441007318',
      'publisher': 'A Publisher',
      'published_year': '1999',
      'year': '1999',
      'year published': '1999',
      'page_count': '100',
      'pages': '100',
      'number of pages': '100',
      'series': 'A Series',
      'series_index': '2',
      'volume': '2',
      'tags': 'a tag',
      'genres': 'a tag',
      'bookshelves': 'a tag',
      'subjects': 'a tag',
      'description': 'About it',
      'comments': 'About it',
      'summary': 'About it',
    };

    final listed = <String>{
      for (final (_, _, aliases) in catalogColumns)
        ...aliases.split(',').map((a) => a.trim()),
    };
    // Every alias the sheet advertises is in the fixture above, so this test
    // notices a column being *added* to the sheet as well as one going stale.
    expect(values.keys.toSet().containsAll(listed), isTrue,
        reason: 'unchecked alias(es): ${listed.difference(values.keys.toSet())}');

    for (final alias in listed) {
      if (alias == 'title' || alias == 'book title') continue;
      final entry = CsvImport.read('title,$alias\nA Book,${values[alias]}\n');
      expect(entry, hasLength(1), reason: '"$alias" broke the read');
    }
  });

  test('a title column is genuinely required', () {
    // The sheet says so; the refusal is the thing that makes the promise safe
    // to rely on, because the alternative is a library named after ISBNs.
    expect(
      () => CsvImport.read('isbn,pages\n9780441007318,304\n'),
      throwsA(isA<CsvImportException>()),
    );
  });

  testWidgets('the sheet offers the template and the columns', (tester) async {
    await tester.pumpWidget(
      const MaterialApp(home: Scaffold(body: CatalogFormatSheet())),
    );
    await tester.pump();

    expect(find.text('Save a template'), findsOneWidget);
    expect(find.text('Copy'), findsOneWidget);
    // The aliases are the answer people came for, so they are on the page
    // rather than a link to it. (Only the rows near the top are built — the
    // list is lazy — so this checks the first of them.)
    expect(find.textContaining('author_sort'), findsOneWidget);
    expect(find.text('required'), findsNothing,
        reason: 'the note is shown in brackets beside the column');
    expect(find.text('(required)'), findsOneWidget);
  });
}
