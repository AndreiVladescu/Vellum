import 'dart:convert';

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/demo_pdf.dart';

void main() {
  DemoPdfBook book({int paragraphs = 60}) => DemoPdfBook(
        title: 'The Art of War',
        author: 'Sun Tzu',
        translator: 'Lionel Giles',
        colophon: 'Typeset for a test.',
        chapters: [
          for (var c = 1; c <= 3; c++)
            DemoPdfChapter(
              title: 'Chapter $c — “Laying Plans”',
              paragraphs: [
                for (var i = 0; i < paragraphs; i++)
                  'Sun Tzu said: The art of war is of vital importance to the '
                      'State (paragraph $i), a matter of life and death.',
              ],
            ),
        ],
      );

  test('every xref offset points at its object', () {
    final pdf = typesetDemoPdf(book());
    final text = latin1.decode(pdf.bytes);
    expect(text, startsWith('%PDF-1.4'));
    expect(text.trimRight(), endsWith('%%EOF'));

    final startxref = int.parse(
      RegExp(r'startxref\n(\d+)').firstMatch(text)!.group(1)!,
    );
    expect(text.substring(startxref), startsWith('xref'));
    final entries = RegExp(r'(\d{10}) 00000 n ').allMatches(text).toList();
    expect(entries, isNotEmpty);
    for (var i = 0; i < entries.length; i++) {
      final offset = int.parse(entries[i].group(1)!);
      expect(text.substring(offset), startsWith('${i + 1} 0 obj'));
    }
  });

  test('long chapters run onto further pages, one page tree for all', () {
    final short = typesetDemoPdf(book(paragraphs: 2));
    final long = typesetDemoPdf(book(paragraphs: 120));
    // A title page and one page a chapter, at the least.
    expect(short.pages, 4);
    expect(long.pages, greaterThan(short.pages + 6));
    final text = latin1.decode(long.bytes);
    expect(text, contains('/Count ${long.pages}'));
  });

  test('the same book gives the same bytes', () {
    expect(typesetDemoPdf(book()).bytes, typesetDemoPdf(book()).bytes);
  });
}
