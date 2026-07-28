// Bookmarks, highlights and notes (plan 5 #22). Three things are pinned here:
// the locator round-trip per format (it's versioned JSON that outlives app
// versions), the quote-first resolution that keeps an EPUB highlight on the
// right sentence when offsets drift, and the Markdown export — the escape hatch
// that stops highlights being held hostage.
import 'dart:io';

import 'package:drift/drift.dart' hide isNull, isNotNull;
import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/library_repository.dart';
import 'package:vellum/reader/annotations/annotation_locator.dart';
import 'package:vellum/reader/annotations/markdown_export.dart';
import 'package:vellum/reader/epub_book.dart';

Future<LibraryRepository> _repo(Directory dir) async =>
    LibraryRepository.forTesting(VellumDatabase(NativeDatabase.memory()), dir);

void main() {
  group('locator round-trip', () {
    test('a PDF page locator survives encode/decode', () {
      final decoded =
          AnnotationLocator.decode(const PdfPageLocator(page: 214).encode());
      expect(decoded, isA<PdfPageLocator>());
      expect((decoded! as PdfPageLocator).page, 214);
    });

    test('a PDF text locator keeps its character range', () {
      final decoded = AnnotationLocator.decode(
          const PdfTextLocator(page: 12, start: 100, end: 160).encode());
      final locator = decoded! as PdfTextLocator;
      expect((locator.page, locator.start, locator.end), (12, 100, 160));
    });

    test('an EPUB scroll locator keeps its fraction', () {
      final decoded = AnnotationLocator.decode(
          const EpubScrollLocator(chapter: 7, fraction: 0.42).encode());
      final locator = decoded! as EpubScrollLocator;
      expect(locator.chapter, 7);
      expect(locator.fraction, closeTo(0.42, 1e-9));
    });

    test('an EPUB text locator keeps its offsets', () {
      final decoded = AnnotationLocator.decode(
          const EpubTextLocator(chapter: 3, start: 1200, end: 1260).encode());
      final locator = decoded! as EpubTextLocator;
      expect((locator.chapter, locator.start, locator.end), (3, 1200, 1260));
    });

    test('the encoded form carries a version', () {
      expect(const PdfPageLocator(page: 1).toJson()['v'],
          AnnotationLocator.version);
    });

    test('a locator from a newer app is ignored, not misread', () {
      // The reason for the version field: a future format must degrade to "no
      // fine position" rather than being parsed under the wrong rules.
      const future = '{"v":99,"kind":"pdfText","page":1,"start":0,"end":5}';
      expect(AnnotationLocator.decode(future), isNull);
    });

    test('malformed or absent locators decode to null', () {
      expect(AnnotationLocator.decode(null), isNull);
      expect(AnnotationLocator.decode(''), isNull);
      expect(AnnotationLocator.decode('not json'), isNull);
      expect(AnnotationLocator.decode('{"v":1,"kind":"unknown"}'), isNull);
      expect(AnnotationLocator.decode('{"v":1,"kind":"pdfText"}'), isNull);
    });
  });

  group('resolveOffsets', () {
    const text = 'The spice must flow. The sleeper must awaken. The spice '
        'must flow again.';

    test('exact offsets are used when the text still matches', () {
      final at = resolveOffsets(text: text, quote: 'sleeper', hintStart: 25);
      expect(at, (start: 25, end: 32));
      expect(text.substring(at!.start, at.end), 'sleeper');
    });

    test('a drifted offset still finds the quote', () {
      // Offsets shifted (a reflow, a parser tweak): the quote is authoritative.
      final at = resolveOffsets(text: text, quote: 'sleeper', hintStart: 999);
      expect(text.substring(at!.start, at.end), 'sleeper');
    });

    test('a repeated quote resolves to the occurrence nearest the hint', () {
      const quote = 'The spice must flow';
      final first = resolveOffsets(text: text, quote: quote, hintStart: 0);
      final second = resolveOffsets(text: text, quote: quote, hintStart: 60);
      expect(first!.start, 0);
      expect(second!.start, greaterThan(30),
          reason: 'the second occurrence is nearer offset 60');
    });

    test('no hint falls back to the first occurrence', () {
      expect(resolveOffsets(text: text, quote: 'The spice')!.start, 0);
    });

    test('a quote that is simply gone resolves to null', () {
      expect(resolveOffsets(text: text, quote: 'Arrakis', hintStart: 3), isNull);
      expect(resolveOffsets(text: text, quote: ''), isNull);
    });
  });

  group('EPUB plain text', () {
    test('markup goes, words stay separated', () {
      const html = '<h1>Chapter One</h1><p>The spice<br>must flow.</p>'
          '<p>And <em>again</em>.</p>';
      expect(
        stripHtml(html),
        'Chapter One The spice must flow. And again.',
        reason: 'inline tags leave no gap; only block ends become spaces',
      );
    });

    test('scripts and styles contribute nothing', () {
      const html = '<style>p{color:red}</style><p>Text</p>'
          '<script>alert("x")</script>';
      expect(stripHtml(html), 'Text');
    });

    test('entities are decoded and whitespace collapsed', () {
      expect(stripHtml('<p>a&nbsp;&amp;&nbsp;b\n\n   c</p>'), 'a & b c');
    });

    test('it is deterministic — the property annotation offsets rely on', () {
      const html = '<p>The spice must flow.</p>';
      expect(stripHtml(html), stripHtml(html));
      expect(const EpubChapter(title: 't', html: html).plainText,
          stripHtml(html));
    });
  });

  group('store', () {
    late Directory dir;
    setUp(() => dir = Directory.systemTemp.createTempSync('vellum_annots'));
    tearDown(() => dir.deleteSync(recursive: true));

    Future<LibraryRepository> seeded() async {
      final repo = await _repo(dir);
      final db = repo.db;
      await db.into(db.books).insert(BooksCompanion.insert(
            id: 'b1',
            title: 'Dune',
            needsPush: const Value(false),
            readerNotesNeedsPush: const Value(false),
          ));
      return repo;
    }

    test('adding a highlight stores its quote and location', () async {
      final repo = await seeded();
      await repo.annotations.add(
        bookId: 'b1',
        kind: AnnotationKind.highlight,
        page: 214,
        locator: const PdfTextLocator(page: 214, start: 10, end: 30),
        quotedText: 'The spice must flow',
      );

      final rows = await repo.annotations.forBook('b1');
      expect(rows, hasLength(1));
      expect(rows.single.kind, 'highlight');
      expect(rows.single.page, 214);
      expect(rows.single.quotedText, 'The spice must flow');
      expect(AnnotationLocator.decode(rows.single.locator),
          isA<PdfTextLocator>());
    });

    test('an annotation never dirties the book — it is not catalogue data',
        () async {
      final repo = await seeded();
      final before = (await repo.watchBook('b1').first)!;
      await repo.annotations.add(
        bookId: 'b1',
        kind: AnnotationKind.bookmark,
        page: 3,
        locator: const PdfPageLocator(page: 3),
      );
      final after = (await repo.watchBook('b1').first)!;
      expect(after.needsPush, false);
      expect(after.updatedAt, before.updatedAt);
    });

    test('a bookmark on a page is found so the action can toggle', () async {
      final repo = await seeded();
      expect(await repo.annotations.bookmarkAtPage('b1', 7), isNull);
      final id = await repo.annotations.add(
        bookId: 'b1',
        kind: AnnotationKind.bookmark,
        page: 7,
        locator: const PdfPageLocator(page: 7),
      );
      expect((await repo.annotations.bookmarkAtPage('b1', 7))?.id, id);
      await repo.annotations.delete(id);
      expect(await repo.annotations.bookmarkAtPage('b1', 7), isNull);
    });

    test('chapter bookmarks are per chapter', () async {
      final repo = await seeded();
      await repo.annotations.add(
        bookId: 'b1',
        kind: AnnotationKind.bookmark,
        chapter: 2,
        locator: const EpubScrollLocator(chapter: 2, fraction: 0.5),
      );
      expect(await repo.annotations.bookmarkAtChapter('b1', 2), isNotNull);
      expect(await repo.annotations.bookmarkAtChapter('b1', 3), isNull);
    });

    test('a note can be edited and cleared, the quote cannot', () async {
      final repo = await seeded();
      final id = await repo.annotations.add(
        bookId: 'b1',
        kind: AnnotationKind.highlight,
        page: 1,
        quotedText: 'A passage',
        note: 'first thought',
      );
      await repo.annotations.setNote(id, '  second thought  ');
      var row = (await repo.annotations.forBook('b1')).single;
      expect(row.note, 'second thought', reason: 'trimmed');
      await repo.annotations.setNote(id, '   ');
      row = (await repo.annotations.forBook('b1')).single;
      expect(row.note, isNull);
      expect(row.quotedText, 'A passage',
          reason: 'clearing a note leaves the highlight itself intact');
    });

    test('annotations are ordered by location for the panel', () async {
      final repo = await seeded();
      for (final page in [30, 10, 20]) {
        await repo.annotations.add(
          bookId: 'b1',
          kind: AnnotationKind.bookmark,
          page: page,
          locator: PdfPageLocator(page: page),
        );
      }
      expect(
        (await repo.annotations.forBook('b1')).map((a) => a.page),
        [10, 20, 30],
      );
    });

    test('deleting a book takes its annotations with it', () async {
      final repo = await seeded();
      await repo.annotations.add(
        bookId: 'b1',
        kind: AnnotationKind.highlight,
        page: 1,
        quotedText: 'gone with the book',
      );
      final book = (await repo.watchBook('b1').first)!;
      await repo.deleteBook(book);
      expect(await repo.annotations.watchAll().first, isEmpty);
    });
  });

  group('Markdown export', () {
    Book book(String title) => Book(
          id: 'b1',
          title: title,
          readerNotesNeedsPush: false,
          createdAt: DateTime(2024),
          updatedAt: DateTime(2024),
          needsPush: false,
          needsProgressPush: false,
          status: 'unread',
          readCount: 0,
        );

    Annotation annotation({
      required String kind,
      int? page,
      int? chapter,
      String? quote,
      String? note,
    }) =>
        Annotation(
          id: 'a-$kind-$page$chapter',
          bookId: 'b1',
          kind: kind,
          page: page,
          chapter: chapter,
          quotedText: quote,
          note: note,
          createdAt: DateTime(2026),
          updatedAt: DateTime(2026),
          needsPush: false,
        );

    test('a book exports as headed, quoted Markdown', () {
      final out = MarkdownExport.forBook(
        book: book('Dune'),
        authors: ['Frank Herbert'],
        annotations: [
          annotation(
              kind: 'highlight',
              page: 214,
              quote: 'The spice must flow',
              note: 'the whole economy in four words'),
          annotation(kind: 'bookmark', page: 300),
          annotation(kind: 'note', chapter: 2, note: 'chapter two drags'),
        ],
      );

      expect(out, '''
# Dune

*Frank Herbert*

## Highlight — page 214

> The spice must flow

the whole economy in four words

## Bookmark — page 300

## Note — chapter 3

chapter two drags

''');
    });

    test('a multi-line quote stays fully quoted', () {
      final out = MarkdownExport.forBook(
        book: book('Dune'),
        annotations: [
          annotation(kind: 'highlight', page: 1, quote: 'first line\nsecond line'),
        ],
      );
      expect(out, contains('> first line\n> second line'));
    });

    test('a book with nothing says so rather than exporting a bare title', () {
      final out =
          MarkdownExport.forBook(book: book('Dune'), annotations: const []);
      expect(out, contains('_No highlights, notes, or bookmarks yet._'));
    });

    test('the library export counts books and demotes their headings', () {
      final out = MarkdownExport.forLibrary(
        books: [book('Dune')],
        byBook: {
          'b1': [annotation(kind: 'highlight', page: 1, quote: 'A line')],
        },
      );
      expect(out, startsWith('# Vellum highlights'));
      expect(out, contains('1 book with annotations.'));
      expect(out, contains('## Dune'), reason: 'demoted from #');
      expect(out, contains('### Highlight — page 1'));
    });

    test('books without annotations are omitted from the library export', () {
      final out = MarkdownExport.forLibrary(
        books: [book('Dune')],
        byBook: const {},
      );
      expect(out, contains('_Nothing highlighted yet._'));
      expect(out, isNot(contains('Dune')));
    });

    test('the file name is filesystem-safe', () {
      expect(MarkdownExport.fileNameFor(book('Dune: Part One/Two')),
          'Dune-Part-OneTwo-highlights.md');
      expect(MarkdownExport.fileNameFor(book('///')), 'book-highlights.md');
    });
  });
}
