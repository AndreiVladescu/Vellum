// Duplicate classification for bulk import (plan 5 #15). The stakes here are
// asymmetric: a false "new" costs the user a duplicate they can delete, while a
// false "duplicate" silently loses a book they wanted. So the certain signal
// (identical hash) is the only one that decides anything on its own, and the
// heuristics only ever *suggest* — they deselect a row that stays visible and
// re-selectable.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/import/import_plan.dart';

const _dune = LibraryFingerprint(
  bookId: 'b1',
  title: 'Dune',
  isbn: '978-0-441-01359-3',
  authors: ['Frank Herbert'],
  fileHashes: {'hash-dune-pdf'},
);

ImportCandidate _classify(
  String path, {
  String? sha256 = 'fresh-hash',
  List<LibraryFingerprint> library = const [_dune],
  String? isbn,
  String? error,
}) =>
    classify(
      path: path,
      sizeBytes: 1234,
      format: 'pdf',
      sha256: sha256,
      library: library,
      isbn: isbn,
      error: error,
    );

void main() {
  test('an unknown file is new', () {
    final c = _classify('/books/Someone - A Brand New Book.pdf');
    expect(c.status, ImportStatus.newBook);
    expect(c.selectedByDefault, true);
    expect(c.meta.title, 'A Brand New Book');
  });

  test('an identical hash is a duplicate file, whatever it is called', () {
    final c = _classify('/books/renamed-entirely.pdf', sha256: 'hash-dune-pdf');
    expect(c.status, ImportStatus.duplicateFile);
    expect(c.matchedBookId, 'b1');
    expect(c.matchedTitle, 'Dune');
    expect(c.selectedByDefault, false);
  });

  test('the hash wins over the heuristics', () {
    // Same bytes as Dune but named like something else: still certainly the
    // same file, so the certain answer is the one reported.
    final c = _classify('/books/Someone Else - Another Title.pdf',
        sha256: 'hash-dune-pdf');
    expect(c.status, ImportStatus.duplicateFile);
  });

  test('same title and author is a probable duplicate', () {
    final c = _classify('/books/Frank Herbert - Dune.epub');
    expect(c.status, ImportStatus.probableDuplicate);
    expect(c.matchedBookId, 'b1');
    expect(c.selectedByDefault, false,
        reason: 'shown but not imported unless the user says so');
  });

  test('title matching ignores case, punctuation and articles', () {
    const library = [
      LibraryFingerprint(
        bookId: 'b2',
        title: 'The Left Hand of Darkness',
        authors: ['Ursula K. Le Guin'],
      ),
    ];
    final c = _classify(
      '/books/Ursula K Le Guin - left hand of darkness.pdf',
      library: library,
    );
    expect(c.status, ImportStatus.probableDuplicate);
  });

  test('the same title by a different author is NOT a duplicate', () {
    // The case that makes title-only matching unsafe: two unrelated books can
    // share a generic title.
    const library = [
      LibraryFingerprint(bookId: 'b3', title: 'Physics', authors: ['Alice']),
    ];
    final c = _classify('/books/Bob - Physics.pdf', library: library);
    expect(c.status, ImportStatus.newBook);
  });

  test('a matching ISBN is a probable duplicate even with a different title', () {
    final c = _classify(
      '/books/completely different name.pdf',
      isbn: '9780441013593',
    );
    expect(c.status, ImportStatus.probableDuplicate,
        reason: 'hyphenation must not defeat the ISBN compare');
    expect(c.matchedBookId, 'b1');
  });

  test('an unreadable file is skipped with its reason kept', () {
    final c = _classify('/books/locked.pdf', sha256: null, error: 'permission denied');
    expect(c.status, ImportStatus.skip);
    expect(c.error, 'permission denied');
    expect(c.selectedByDefault, false);
  });

  test('an empty library makes everything new', () {
    expect(
      _classify('/books/Frank Herbert - Dune.pdf', library: const []).status,
      ImportStatus.newBook,
    );
  });

  test('a title-only file matches a title-only book', () {
    const library = [LibraryFingerprint(bookId: 'b4', title: 'Anonymous Work')];
    expect(
      _classify('/books/Anonymous Work.pdf', library: library).status,
      ImportStatus.probableDuplicate,
    );
    // ...but a file that names an author does not match an author-less book,
    // since there is nothing to corroborate the title with.
    expect(
      _classify('/books/Someone - Anonymous Work.pdf', library: library).status,
      ImportStatus.newBook,
    );
  });

  test('normalizeIsbn keeps the X check digit and drops the rest', () {
    expect(normalizeIsbn('0-8044-2957-x'), '080442957X');
    expect(normalizeIsbn('  '), isNull);
    expect(normalizeIsbn(null), isNull);
  });

  test('summarize counts every status, including the zeroes', () {
    final counts = summarize([
      _classify('/b/new one.pdf'),
      _classify('/b/other.pdf', sha256: 'hash-dune-pdf'),
      _classify('/b/Frank Herbert - Dune.pdf'),
    ]);
    expect(counts[ImportStatus.newBook], 1);
    expect(counts[ImportStatus.duplicateFile], 1);
    expect(counts[ImportStatus.probableDuplicate], 1);
    expect(counts[ImportStatus.skip], 0);
  });
}
