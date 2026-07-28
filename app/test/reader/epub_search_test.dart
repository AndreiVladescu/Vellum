// Searching an EPUB's text.
//
// pdfrx brings a searcher for PDFs; an EPUB has none, so this is the whole of
// what Ctrl+F does there. The rules worth pinning are the ones a reader would
// notice being wrong: a phrase that broke across a line still matches, and one
// letter doesn't try to list every occurrence in a novel.
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/epub_book.dart';
import 'package:vellum/reader/epub_search.dart';

EpubChapter _chapter(String title, String body) =>
    EpubChapter(title: title, html: '<p>$body</p>');

final _book = [
  _chapter('One', 'The quick brown fox jumps over the lazy dog.'),
  _chapter('Two', 'Nothing of interest here.'),
  _chapter('Three', 'The fox returns. Another fox follows the first fox.'),
];

void main() {
  test('finds every occurrence, in reading order', () {
    final result = searchEpub(_book, 'fox');
    expect(result.hits, hasLength(4));
    expect(result.hits.map((h) => h.chapter), [0, 2, 2, 2]);
    expect(result.hits.first.chapterTitle, 'One');
    expect(result.truncated, isFalse);
  });

  test('is case-insensitive', () {
    expect(searchEpub(_book, 'QUICK BROWN').hits, hasLength(1));
  });

  test('a phrase that broke across lines in the source still matches', () {
    // The reason the query is collapsed as well as the text: someone copies
    // "quick brown" off a page where the line ended after "quick".
    final book = [_chapter('One', 'the quick\n      brown fox')];
    expect(searchEpub(book, 'quick   brown').hits, hasLength(1));
    expect(searchEpub(book, ' quick brown ').hits, hasLength(1));
  });

  test('an empty or blank query matches nothing rather than everything', () {
    expect(searchEpub(_book, '').hits, isEmpty);
    expect(searchEpub(_book, '   ').hits, isEmpty);
  });

  test('overlapping matches are counted once', () {
    // "aa" in "aaa" is one hit, not two nearly-identical ones pointing at the
    // same words.
    final book = [_chapter('One', 'aaa')];
    expect(searchEpub(book, 'aa').hits, hasLength(1));
  });

  test('a flood of matches is capped, and says so', () {
    final book = [_chapter('One', 'e ' * 500)];
    final result = searchEpub(book, 'e', limit: 50);
    expect(result.hits, hasLength(50));
    expect(result.truncated, isTrue);
  });

  test('a hit knows where to jump to', () {
    final result = searchEpub(_book, 'lazy');
    final hit = result.hits.single;
    expect(hit.chapter, 0);
    expect(hit.fraction, greaterThan(0.5), reason: 'it is near the end');
    expect(hit.fraction, lessThanOrEqualTo(1));
  });

  group('snippets', () {
    test('carry the match with context either side', () {
      final hit = searchEpub(_book, 'jumps').hits.single;
      expect(hit.snippet, contains('jumps'));
      expect(hit.snippet, contains('brown fox'));
    });

    test('mark where they were cut', () {
      const text = 'a very long run of words that goes on and on and on and '
          'on before the needle appears and then keeps going for a while yet';
      final at = text.indexOf('needle');
      final snippet = snippetAround(text, at, at + 6);
      expect(snippet, startsWith('…'));
      expect(snippet, endsWith('…'));
      expect(snippet, contains('needle'));
    });

    test('do not start or end mid-word', () {
      const text = 'alpha bravo charlie delta echo foxtrot golf hotel india '
          'juliet kilo lima mike november oscar papa quebec';
      final at = text.indexOf('november');
      final snippet = snippetAround(text, at, at + 8).replaceAll('…', '');
      expect(text, contains(snippet));
      expect(snippet.split(' ').first, isIn(text.split(' ')));
    });

    test('a short chapter needs no ellipses at all', () {
      final hit = searchEpub([_chapter('One', 'Short and sweet.')], 'sweet')
          .hits
          .single;
      expect(hit.snippet, 'Short and sweet.');
    });
  });
}
