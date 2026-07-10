import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:archive/archive.dart';
import 'package:path/path.dart' as p;
import 'package:xml/xml.dart';

/// One spine entry of an EPUB: its display [title] and the chapter's XHTML,
/// with images inlined as data URIs so it renders self-contained.
class EpubChapter {
  const EpubChapter({required this.title, required this.html});

  final String title;
  final String html;
}

/// A parsed EPUB. An EPUB is a zip: `META-INF/container.xml` names the OPF
/// package file, whose `<manifest>` lists resources and `<spine>` gives the
/// reading order. Vellum parses just enough of that to page through chapters —
/// no external renderer package, so the dependency surface stays small.
class EpubBook {
  const EpubBook({required this.title, required this.chapters});

  final String? title;
  final List<EpubChapter> chapters;

  static Future<EpubBook> open(File file) async {
    final archive = ZipDecoder().decodeBytes(await file.readAsBytes());
    final byPath = {
      for (final f in archive.files)
        if (f.isFile) p.posix.normalize(f.name): f,
    };
    Uint8List? read(String path) => byPath[p.posix.normalize(path)]?.content;
    String? readText(String path) {
      final bytes = read(path);
      return bytes == null ? null : utf8.decode(bytes, allowMalformed: true);
    }

    // container.xml -> the OPF package file.
    final container = readText('META-INF/container.xml');
    if (container == null) {
      throw const FormatException('not an EPUB: missing container.xml');
    }
    final opfPath = XmlDocument.parse(container)
        .findAllElements('rootfile')
        .first
        .getAttribute('full-path');
    final opfText = opfPath == null ? null : readText(opfPath);
    if (opfPath == null || opfText == null) {
      throw const FormatException('not an EPUB: missing package file');
    }
    final opf = XmlDocument.parse(opfText);
    final opfDir = p.posix.dirname(opfPath);
    String resolve(String base, String href) => p.posix
        .normalize(p.posix.join(base, Uri.decodeComponent(href.split('#').first)));

    final bookTitle = opf
        .findAllElements('dc:title')
        .map((e) => e.innerText.trim())
        .where((t) => t.isNotEmpty)
        .firstOrNull;

    // Manifest: id -> (absolute path, media type); spine: ordered idrefs.
    final items = <String, ({String path, String type})>{};
    for (final item in opf.findAllElements('item')) {
      final id = item.getAttribute('id');
      final href = item.getAttribute('href');
      if (id == null || href == null) continue;
      items[id] = (
        path: resolve(opfDir, href),
        type: item.getAttribute('media-type') ?? '',
      );
    }
    final spine = opf.findAllElements('spine').firstOrNull;
    final chapterPaths = <String>[
      for (final ref in spine?.findAllElements('itemref') ??
          const Iterable<XmlElement>.empty())
        if (items[ref.getAttribute('idref')] case final item?) item.path,
    ];

    // Chapter titles from the EPUB2 NCX or EPUB3 nav doc, when present.
    final titles = _chapterTitles(opf, items, spine, readText, resolve);

    final chapters = <EpubChapter>[];
    for (final path in chapterPaths) {
      final html = readText(path);
      if (html == null) continue;
      chapters.add(EpubChapter(
        title: titles[path] ?? 'Chapter ${chapters.length + 1}',
        html: _inlineImages(html, p.posix.dirname(path), read, resolve),
      ));
    }
    if (chapters.isEmpty) {
      throw const FormatException('EPUB has no readable chapters');
    }
    return EpubBook(title: bookTitle, chapters: chapters);
  }

  /// Chapter path -> human title, from the NCX (`<navPoint>`) or the EPUB3
  /// nav document (`<nav>` links). Best-effort; absent entries fall back to
  /// "Chapter N".
  static Map<String, String> _chapterTitles(
    XmlDocument opf,
    Map<String, ({String path, String type})> items,
    XmlElement? spine,
    String? Function(String) readText,
    String Function(String, String) resolve,
  ) {
    final titles = <String, String>{};
    // EPUB3: the manifest item with properties="nav".
    for (final item in opf.findAllElements('item')) {
      if (!(item.getAttribute('properties') ?? '').contains('nav')) continue;
      final entry = items[item.getAttribute('id')];
      final text = entry == null ? null : readText(entry.path);
      if (text == null) continue;
      final navDir = p.posix.dirname(entry!.path);
      for (final a in XmlDocument.parse(text).findAllElements('a')) {
        final href = a.getAttribute('href');
        final label = a.innerText.trim();
        if (href != null && label.isNotEmpty) {
          titles.putIfAbsent(resolve(navDir, href), () => label);
        }
      }
      return titles;
    }
    // EPUB2: the NCX named by <spine toc="...">.
    final ncxEntry = items[spine?.getAttribute('toc')];
    final ncxText = ncxEntry == null ? null : readText(ncxEntry.path);
    if (ncxText != null) {
      final ncxDir = p.posix.dirname(ncxEntry!.path);
      for (final point in XmlDocument.parse(ncxText).findAllElements('navPoint')) {
        final label =
            point.findAllElements('text').map((e) => e.innerText.trim()).firstOrNull;
        final src = point.findAllElements('content').firstOrNull?.getAttribute('src');
        if (label != null && label.isNotEmpty && src != null) {
          titles.putIfAbsent(resolve(ncxDir, src), () => label);
        }
      }
    }
    return titles;
  }

  /// Replaces `src` / `xlink:href` references to archive-local images with
  /// data URIs, so the rendered HTML needs no resolver.
  static String _inlineImages(
    String html,
    String chapterDir,
    Uint8List? Function(String) read,
    String Function(String, String) resolve,
  ) {
    const mimes = {
      '.jpg': 'image/jpeg',
      '.jpeg': 'image/jpeg',
      '.png': 'image/png',
      '.gif': 'image/gif',
      '.webp': 'image/webp',
      '.svg': 'image/svg+xml',
    };
    return html.replaceAllMapped(
      RegExp(r'''(src|xlink:href)\s*=\s*["']([^"']+)["']'''),
      (m) {
        final href = m[2]!;
        if (href.startsWith('data:') || href.contains('://')) return m[0]!;
        final mime = mimes[p.posix.extension(href).toLowerCase()];
        final bytes = mime == null ? null : read(resolve(chapterDir, href));
        if (bytes == null) return m[0]!;
        return '${m[1]}="data:$mime;base64,${base64Encode(bytes)}"';
      },
    );
  }
}
