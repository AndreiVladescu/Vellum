import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:drift/native.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/local_text_index.dart';

/// Local content search: the text *inside* books, indexed on this machine.
///
/// The contract worth pinning is that a phrase which appears only in a book's
/// body — never in its title, author or genres — is findable, and that the hit
/// says which book and where. Extraction runs for real against an EPUB built
/// here, rather than against a stub, because "we extracted something" is the
/// part most likely to rot silently.
void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  late Directory dir;
  late VellumDatabase db;
  late LocalTextIndex index;

  setUp(() async {
    dir = Directory.systemTemp.createTempSync('vellum_text_index');
    // pdfrx asks path_provider for a scratch directory, which has no
    // implementation in a headless test — without this the PDF case fails with
    // MissingPluginException, which reads like a broken extractor rather than a
    // missing plugin. The rest of the suite sidesteps path_provider instead;
    // here the PDF path is exactly what needs covering.
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
      const MethodChannel('plugins.flutter.io/path_provider'),
      (call) async => dir.path,
    );
    db = VellumDatabase(NativeDatabase.memory());
    // beforeOpen builds book_text_fts; touching the database triggers it.
    await db.customSelect('SELECT 1').get();
    index = LocalTextIndex(db, dataDir: dir);
  });
  tearDown(() async {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(
            const MethodChannel('plugins.flutter.io/path_provider'), null);
    await db.close();
    dir.deleteSync(recursive: true);
  });

  /// A minimal but genuinely valid EPUB, so `EpubBook.open` parses it the same
  /// way it parses a real one.
  File writeEpub(String name, List<(String title, String body)> chapters) {
    final archive = Archive();
    void add(String path, String content) {
      final bytes = utf8.encode(content);
      archive.add(ArchiveFile(path, bytes.length, bytes));
    }

    add('mimetype', 'application/epub+zip');
    add('META-INF/container.xml', '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles><rootfile full-path="OEBPS/content.opf"
    media-type="application/oebps-package+xml"/></rootfiles>
</container>''');
    final items = <String>[];
    final refs = <String>[];
    for (var i = 0; i < chapters.length; i++) {
      add('OEBPS/ch$i.xhtml',
          '<html><body><h1>${chapters[i].$1}</h1>'
          '<p>${chapters[i].$2}</p></body></html>');
      items.add('<item id="c$i" href="ch$i.xhtml" '
          'media-type="application/xhtml+xml"/>');
      refs.add('<itemref idref="c$i"/>');
    }
    add('OEBPS/content.opf', '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="3.0" unique-identifier="i">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Test Book</dc:title><dc:identifier id="i">urn:test</dc:identifier>
  </metadata>
  <manifest>${items.join()}</manifest>
  <spine>${refs.join()}</spine>
</package>''');
    final file = File('${dir.path}/$name')
      ..writeAsBytesSync(ZipEncoder().encodeBytes(archive));
    return file;
  }

  /// Filler so a fixture chapter clears [LocalTextIndex]'s "essentially
  /// nothing was extracted" floor, which exists to classify scanned PDFs. A
  /// 16-character chapter is not a book, and the floor is right to reject it.
  String prose(String phrase) =>
      '$phrase. ${'Lorem ipsum dolor sit amet, consectetur adipiscing elit. ' * 3}';

  Future<void> seed(String bookId, String title, String fileName) async {
    await db.into(db.books).insert(
        BooksCompanion.insert(id: bookId, title: title));
    await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
          id: 'f_$bookId',
          bookId: bookId,
          format: 'epub',
          path: fileName,
          sizeBytes: 1,
          sha256: 'x',
        ));
  }

  test('a phrase only in the body is findable, with book and page', () async {
    writeEpub('a.epub', [
      ('Preface', 'Nothing of interest here.'),
      ('Chapter One', 'The loader honours LD_PRELOAD before anything else. '
          'It is the first thing consulted when resolving a symbol at runtime.'),
    ]);
    await seed('b1', 'A Book Whose Title Says Nothing', 'a.epub');

    await index.enqueueMissing();
    expect(await index.processPending(), 1);

    final hits = await index.search('LD_PRELOAD');
    expect(hits, hasLength(1));
    expect(hits.single.bookId, 'b1');
    expect(hits.single.title, 'A Book Whose Title Says Nothing');
    // Second spine section, so the reader can be sent to the right place.
    expect(hits.single.page, 2);
    expect(hits.single.snippet, contains('LD_PRELOAD'));
  });

  test('a PDF is indexed too, not only an EPUB', () async {
    // Built rather than committed as a fixture: a few hundred bytes of valid
    // PDF with one text stream, so the pdfium path is genuinely exercised.
    // PDFs are the bulk of a reference library, and this is the format whose
    // extraction needs `pdfrxFlutterInitialize` — a missing call there looks
    // like an infinitely slow book, not an error.
    File('${dir.path}/a.pdf').writeAsBytesSync(_minimalPdf());
    await db.into(db.books).insert(
        BooksCompanion.insert(id: 'b1', title: 'A PDF'));
    await db.into(db.bookFiles).insert(BookFilesCompanion.insert(
          id: 'f_b1',
          bookId: 'b1',
          format: 'pdf',
          path: 'a.pdf',
          sizeBytes: 1,
          sha256: 'x',
        ));

    await index.enqueueMissing();
    await index.processPending();
    expect((await index.statusCounts())['ok'], 1,
        reason: 'the PDF should extract, not fail or come back no_text');

    final hits = await index.search('LD_PRELOAD');
    expect(hits, hasLength(1));
    expect(hits.single.page, 1);
  },
      // pdfium is a native library that ships *inside the built app bundle*
      // (`build/linux/x64/release/bundle/lib/libpdfium.so`) and is not on the
      // system library path, so `flutter test` cannot load it: the extractor
      // hangs in `getPdfium` and the test times out. The EPUB cases above cover
      // every shared step — queue, storage, search, statuses — and the PDF
      // branch differs only in `_extractPdf`. Verified by hand against the real
      // library instead; see docs/PERFORMANCE.md.
      skip: 'pdfium cannot be loaded from the test runner');

  test('the queue is the table: pending drains, and re-running is a no-op',
      () async {
    writeEpub('a.epub', [('One', prose('alpha beta gamma'))]);
    await seed('b1', 'Book', 'a.epub');

    await index.enqueueMissing();
    expect((await index.statusCounts())['pending'], 1);
    await index.processPending();
    expect((await index.statusCounts())['ok'], 1);

    // Enqueuing again must not resurrect work that is already done, or every
    // launch would re-extract the whole library.
    await index.enqueueMissing();
    expect((await index.statusCounts())['pending'], isNull);
    expect(await index.processPending(), 0);
  });

  test('a file with no extractable text records no_text, not failed', () async {
    writeEpub('empty.epub', [('One', '')]);
    await seed('b1', 'Scanned', 'empty.epub');
    await index.enqueueMissing();
    await index.processPending();
    // 'no_text' is the scanned-PDF outcome; recording it as such is what stops
    // the file being retried on every launch for ever.
    expect((await index.statusCounts())['no_text'], 1);
    expect(await index.search('anything'), isEmpty);
  });

  test('a missing file is skipped rather than failing the queue', () async {
    await seed('b1', 'Gone', 'not-on-disk.epub');
    await index.enqueueMissing();
    await index.processPending();
    expect((await index.statusCounts())['skipped'], 1);
  });

  test('a trashed book drops out of results', () async {
    writeEpub('a.epub', [('One', prose('a unique phrase worth finding'))]);
    await seed('b1', 'Book', 'a.epub');
    await index.enqueueMissing();
    await index.processPending();
    expect(await index.search('unique phrase'), hasLength(1));

    await db.customStatement(
        "UPDATE books SET deleted_at = datetime('now') WHERE id = 'b1'");
    // The index still holds the text — the book is only hidden, not deleted —
    // but search must not surface a book the shelf no longer shows.
    expect(await index.search('unique phrase'), isEmpty);
  });

  test('dropping the book_text row sweeps its FTS rows', () async {
    writeEpub('a.epub', [('One', prose('sweepable content here'))]);
    await seed('b1', 'Book', 'a.epub');
    await index.enqueueMissing();
    await index.processPending();

    await db.customStatement("DELETE FROM book_text WHERE file_id = 'f_b1'");
    // A virtual table has no foreign keys, so this is the trigger's job.
    final left = await db
        .customSelect('SELECT COUNT(*) AS n FROM book_text_fts')
        .getSingle();
    expect(left.read<int>('n'), 0);
  });

  test('reindexAll puts everything back in the queue', () async {
    writeEpub('a.epub', [('One', prose('alpha'))]);
    await seed('b1', 'Book', 'a.epub');
    await index.enqueueMissing();
    await index.processPending();
    await index.reindexAll();
    expect((await index.statusCounts())['pending'], 1);
  });

  test('query punctuation cannot break the MATCH expression', () async {
    writeEpub('a.epub', [('One', prose('setuid and setgid bits'))]);
    await seed('b1', 'Book', 'a.epub');
    await index.enqueueMissing();
    await index.processPending();
    // Raw FTS5 operators in user text are a syntax error if they reach MATCH.
    for (final nasty in ['setuid AND', 'set"uid', 'setuid OR (', '"']) {
      await expectLater(index.search(nasty), completes);
    }
  });
}

/// The smallest PDF that still has real, extractable text: catalog, one page,
/// one content stream with a `Tj` show-text operator, and a base-14 font. Built
/// here so the repository carries no binary fixture, and verified against
/// `pdftotext` when it was written.
List<int> _minimalPdf() {
  const text = 'BT /F1 24 Tf 72 700 Td '
      '(The loader honours LD_PRELOAD before all else.) Tj ET';
  final objects = <String>[
    '<< /Type /Catalog /Pages 2 0 R >>',
    '<< /Type /Pages /Kids [3 0 R] /Count 1 >>',
    '<< /Type /Page /Parent 2 0 R /MediaBox [0 0 612 792] '
        '/Contents 4 0 R /Resources << /Font << /F1 5 0 R >> >> >>',
    '<< /Length ${text.length} >>\nstream\n$text\nendstream',
    '<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica >>',
  ];
  final out = StringBuffer('%PDF-1.4\n');
  final offsets = <int>[];
  for (var i = 0; i < objects.length; i++) {
    offsets.add(out.length);
    out.write('${i + 1} 0 obj\n${objects[i]}\nendobj\n');
  }
  final xref = out.length;
  out.write('xref\n0 ${objects.length + 1}\n0000000000 65535 f \n');
  for (final off in offsets) {
    out.write('${off.toString().padLeft(10, '0')} 00000 n \n');
  }
  out.write('trailer\n<< /Size ${objects.length + 1} /Root 1 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return out.toString().codeUnits;
}
