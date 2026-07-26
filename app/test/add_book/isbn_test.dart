// ISBN/EAN validation for barcode scanning (plan 5 #16). The point of these is
// the *rejections*: a continuous scan points a camera at whatever is on the
// table, and firing a metadata lookup for a cereal box would make the feature
// feel broken.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/add_book/isbn.dart';

void main() {
  group('ISBN-13', () {
    test('accepts real ISBN-13s', () {
      expect(isValidIsbn13('9780441013593'), true, reason: 'Dune');
      expect(isValidIsbn13('9780262033848'), true, reason: 'CLRS');
      expect(isValidIsbn13('9791234567896'), true, reason: '979 is Bookland too');
    });

    test('rejects a wrong check digit', () {
      expect(isValidIsbn13('9780441013594'), false);
    });

    test('rejects a non-book EAN-13', () {
      // A valid EAN-13 (correct check digit) that is not in Bookland: a real
      // product barcode, the exact thing a scanner keeps finding.
      expect(isValidIsbn13('4006381333931'), false);
      expect(isValidIsbn13('0012345678905'), false);
    });

    test('rejects sheet music (ISMN, 979-0)', () {
      // 9790000000005 has a valid EAN check digit but is an ISMN, not an ISBN.
      expect(isValidIsbn13('9790000000005'), false);
    });

    test('rejects wrong lengths and non-digits', () {
      expect(isValidIsbn13('978044101359'), false);
      expect(isValidIsbn13('97804410135933'), false);
      expect(isValidIsbn13('978044101359X'), false);
      expect(isValidIsbn13(''), false);
    });
  });

  group('ISBN-10', () {
    test('accepts a valid one, including an X check digit', () {
      expect(isValidIsbn10('0441172717'), true, reason: 'Dune, ISBN-10');
      expect(isValidIsbn10('080442957X'), true);
      expect(isValidIsbn10('0-8044-2957-x'), true, reason: 'separators and case');
    });

    test('rejects a wrong check digit', () {
      expect(isValidIsbn10('0441172718'), false);
    });

    test('rejects an X anywhere but the check digit', () {
      expect(isValidIsbn10('04411X2717'), false);
    });
  });

  group('conversion', () {
    test('ISBN-10 converts to the matching ISBN-13', () {
      expect(isbn10To13('0441172717'), '9780441172719');
      expect(isbn10To13('080442957X'), '9780804429573');
    });

    test('an invalid ISBN-10 converts to null', () {
      expect(isbn10To13('0441172718'), isNull);
      expect(isbn10To13('12345'), isNull);
    });

    test('toIsbn13 accepts either form and anything a human would type', () {
      expect(toIsbn13('9780441013593'), '9780441013593');
      expect(toIsbn13('978-0-441-01359-3'), '9780441013593');
      expect(toIsbn13('  0441172717  '), '9780441172719');
      expect(toIsbn13('0-441-17271-7'), '9780441172719');
    });

    test('toIsbn13 rejects a non-book barcode', () {
      expect(toIsbn13('4006381333931'), isNull);
      expect(toIsbn13('hello'), isNull);
      expect(toIsbn13(''), isNull);
    });
  });

  test('normalizeIsbnInput keeps only digits and the X check digit', () {
    expect(normalizeIsbnInput('978-0-441 01359_3'), '9780441013593');
    expect(normalizeIsbnInput('isbn: 080442957x'), '080442957X');
    expect(normalizeIsbnInput('n/a'), '');
  });

  test('formatIsbn13 is readable and lossless', () {
    expect(formatIsbn13('9780441013593'), '978-0-4410-1359-3');
    expect(
      normalizeIsbnInput(formatIsbn13('9780441013593')),
      '9780441013593',
      reason: 'formatting must be reversible by normalisation',
    );
    expect(formatIsbn13('short'), 'short', reason: 'left alone if not 13');
  });
}
