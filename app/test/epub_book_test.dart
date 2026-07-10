import 'dart:convert';
import 'dart:io';

import 'package:archive/archive.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/reader/epub_book.dart';

/// Builds a tiny but structurally valid EPUB 2 on disk: container.xml → OPF
/// with a two-chapter spine + NCX titles, and an image referenced by ch1.
File _makeEpub(Directory dir) {
  final archive = Archive();
  void add(String path, String content) {
    final bytes = utf8.encode(content);
    archive.addFile(ArchiveFile(path, bytes.length, bytes));
  }

  add('mimetype', 'application/epub+zip');
  add('META-INF/container.xml', '''
<?xml version="1.0"?>
<container version="1.0" xmlns="urn:oasis:names:tc:opendocument:xmlns:container">
  <rootfiles>
    <rootfile full-path="OEBPS/content.opf" media-type="application/oebps-package+xml"/>
  </rootfiles>
</container>''');
  add('OEBPS/content.opf', '''
<?xml version="1.0"?>
<package xmlns="http://www.idpf.org/2007/opf" version="2.0" unique-identifier="id">
  <metadata xmlns:dc="http://purl.org/dc/elements/1.1/">
    <dc:title>Tiny Book</dc:title>
    <meta name="cover" content="img"/>
  </metadata>
  <manifest>
    <item id="ncx" href="toc.ncx" media-type="application/x-dtbncx+xml"/>
    <item id="c1" href="text/ch1.xhtml" media-type="application/xhtml+xml"/>
    <item id="c2" href="text/ch2.xhtml" media-type="application/xhtml+xml"/>
    <item id="img" href="images/pic.png" media-type="image/png"/>
  </manifest>
  <spine toc="ncx">
    <itemref idref="c1"/>
    <itemref idref="c2"/>
  </spine>
</package>''');
  add('OEBPS/toc.ncx', '''
<?xml version="1.0"?>
<ncx xmlns="http://www.daisy.org/z3986/2005/ncx/" version="2005-1">
  <navMap>
    <navPoint id="n1"><navLabel><text>The Beginning</text></navLabel>
      <content src="text/ch1.xhtml"/></navPoint>
    <navPoint id="n2"><navLabel><text>The End</text></navLabel>
      <content src="text/ch2.xhtml"/></navPoint>
  </navMap>
</ncx>''');
  add('OEBPS/text/ch1.xhtml',
      '<html><body><p>Hello.</p><img src="../images/pic.png"/></body></html>');
  add('OEBPS/text/ch2.xhtml', '<html><body><p>Goodbye.</p></body></html>');
  // A 1x1 transparent PNG.
  final png = base64Decode(
      'iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mNk'
      'YPhfDwAChwGA60e6kgAAAABJRU5ErkJggg==');
  archive.addFile(ArchiveFile('OEBPS/images/pic.png', png.length, png));

  final file = File(p.join(dir.path, 'tiny.epub'));
  file.writeAsBytesSync(ZipEncoder().encode(archive));
  return file;
}

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_epub_test'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('parses chapters in spine order with NCX titles', () async {
    final epub = await EpubBook.open(_makeEpub(dir));
    expect(epub.title, 'Tiny Book');
    expect(epub.chapters, hasLength(2));
    expect(epub.chapters[0].title, 'The Beginning');
    expect(epub.chapters[1].title, 'The End');
    expect(epub.chapters[0].html, contains('Hello.'));
  });

  test('inlines referenced images as data URIs', () async {
    final epub = await EpubBook.open(_makeEpub(dir));
    expect(epub.chapters[0].html, contains('src="data:image/png;base64,'));
    expect(epub.chapters[0].html, isNot(contains('../images')));
  });

  test('extracts the declared cover image (EPUB2 meta)', () async {
    final bytes = await EpubBook.coverBytes(_makeEpub(dir));
    expect(bytes, isNotNull);
    // PNG magic bytes — it round-trips the manifest-declared cover.
    expect(bytes!.sublist(0, 4), [0x89, 0x50, 0x4E, 0x47]);
  });

  test('returns null when no cover is declared', () async {
    // An EPUB whose OPF has no cover meta and no cover-image property.
    final archive = Archive();
    void add(String path, String content) {
      final b = utf8.encode(content);
      archive.addFile(ArchiveFile(path, b.length, b));
    }
    add('META-INF/container.xml',
        '<container xmlns="urn:oasis:names:tc:opendocument:xmlns:container">'
        '<rootfiles><rootfile full-path="content.opf"/></rootfiles></container>');
    add('content.opf',
        '<package xmlns="http://www.idpf.org/2007/opf"><manifest>'
        '<item id="c1" href="ch1.xhtml" media-type="application/xhtml+xml"/>'
        '</manifest><spine><itemref idref="c1"/></spine></package>');
    final file = File(p.join(dir.path, 'nocover.epub'))
      ..writeAsBytesSync(ZipEncoder().encode(archive));
    expect(await EpubBook.coverBytes(file), isNull);
  });

  test('rejects a zip that is not an EPUB', () async {
    final archive = Archive();
    final bytes = utf8.encode('hi');
    archive.addFile(ArchiveFile('readme.txt', bytes.length, bytes));
    final file = File(p.join(dir.path, 'bogus.epub'))
      ..writeAsBytesSync(ZipEncoder().encode(archive));
    expect(EpubBook.open(file), throwsFormatException);
  });
}
