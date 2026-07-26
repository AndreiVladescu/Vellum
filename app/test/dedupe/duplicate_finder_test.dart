// Duplicate detection (plan 5 #21b). Same asymmetry as the import classifier: a
// missed duplicate costs a tidy-up, a false one offers to destroy a book the user
// wanted. So the certain signals are separated from the fuzzy one, and the fuzzy
// one always needs the authors to agree.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/dedupe/duplicate_finder.dart';
import 'package:vellum/import/import_plan.dart';

LibraryFingerprint _book(
  String id,
  String title, {
  String? isbn,
  List<String> authors = const [],
  Set<String> hashes = const {},
}) =>
    LibraryFingerprint(
      bookId: id,
      title: title,
      isbn: isbn,
      authors: authors,
      fileHashes: hashes,
    );

void main() {
  test('an identical file hash is reported as certain', () {
    final pairs = findDuplicates([
      _book('a', 'Dune', hashes: {'h1'}),
      _book('b', 'dune (copy)', hashes: {'h1'}),
    ]);
    expect(pairs, hasLength(1));
    expect(pairs.single.reason, DuplicateReason.sameFile);
    expect(pairs.single.reason.isCertain, true);
    expect(pairs.single.involves('a'), true);
    expect(pairs.single.involves('b'), true);
  });

  test('an equal ISBN matches regardless of hyphens', () {
    final pairs = findDuplicates([
      _book('a', 'Dune', isbn: '978-0-441-01359-3'),
      _book('b', 'Dune: A Novel', isbn: '9780441013593'),
    ]);
    expect(pairs.single.reason, DuplicateReason.sameIsbn);
  });

  test('a near-identical title with a shared author is a suggestion', () {
    final pairs = findDuplicates([
      _book('a', 'The Dispossessed', authors: ['Ursula K. Le Guin']),
      _book('b', 'Dispossessed', authors: ['Ursula K Le Guin']),
    ]);
    expect(pairs.single.reason, DuplicateReason.similarTitle);
    expect(pairs.single.reason.isCertain, false,
        reason: 'fuzzy matches are offered, never assumed');
  });

  test('the same title by different authors is not a duplicate', () {
    expect(
      findDuplicates([
        _book('a', 'Physics', authors: ['Alice']),
        _book('b', 'Physics', authors: ['Bob']),
      ]),
      isEmpty,
    );
  });

  test('unrelated titles are not duplicates', () {
    expect(
      findDuplicates([
        _book('a', 'Dune', authors: ['Frank Herbert']),
        _book('b', 'Neuromancer', authors: ['William Gibson']),
        _book('c', 'Hyperion'),
      ]),
      isEmpty,
    );
  });

  test('the strongest reason wins for a pair that matches several ways', () {
    final pairs = findDuplicates([
      _book('a', 'Dune', isbn: '9780441013593', authors: ['Frank Herbert'], hashes: {'h1'}),
      _book('b', 'Dune', isbn: '9780441013593', authors: ['Frank Herbert'], hashes: {'h1'}),
    ]);
    expect(pairs, hasLength(1), reason: 'one pair, not three');
    expect(pairs.single.reason, DuplicateReason.sameFile);
  });

  test('each pair is reported once, not in both orders', () {
    final pairs = findDuplicates([
      _book('a', 'Dune', hashes: {'h1'}),
      _book('b', 'Dune copy', hashes: {'h1'}),
      _book('c', 'Dune again', hashes: {'h1'}),
    ]);
    // Three books sharing one hash: a-b, a-c, b-c.
    expect(pairs, hasLength(3));
  });

  test('certain pairs sort before fuzzy ones', () {
    final pairs = findDuplicates([
      _book('a', 'Foundation', authors: ['Isaac Asimov']),
      _book('b', 'Foundation!', authors: ['Isaac Asimov']),
      _book('c', 'Dune', hashes: {'h1'}),
      _book('d', 'Dune copy', hashes: {'h1'}),
    ]);
    expect(pairs.first.reason, DuplicateReason.sameFile);
    expect(pairs.last.reason, DuplicateReason.similarTitle);
  });

  test('a book with no title is never matched fuzzily', () {
    expect(findDuplicates([_book('a', ''), _book('b', '')]), isEmpty);
  });

  group('supporting pieces', () {
    test('comparableTitle is word-order independent', () {
      expect(comparableTitle('The Left Hand of Darkness'),
          comparableTitle('darkness left of hand'));
    });

    test('boundedEditDistance measures small edits and bails on big ones', () {
      expect(boundedEditDistance('dune', 'dune'), 0);
      expect(boundedEditDistance('dune', 'dunes'), 1);
      expect(boundedEditDistance('dune', 'dun'), 1);
      expect(boundedEditDistance('dune', 'dume'), 1);
      expect(boundedEditDistance('kitten', 'sitting'), 3);
      // Past the limit the exact value doesn't matter, only that it exceeds it.
      expect(boundedEditDistance('dune', 'neuromancer', limit: 3),
          greaterThan(3));
    });

    test('boundedEditDistance is symmetric', () {
      expect(boundedEditDistance('abcd', 'abd'), boundedEditDistance('abd', 'abcd'));
    });
  });
}
