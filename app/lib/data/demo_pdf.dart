import 'dart:convert';
import 'dart:io';
import 'dart:math';
import 'dart:typed_data';

/// A small, dependency-free PDF typesetter for the demo library
/// (`tool/demo_library.sh`): it turns a public-domain text into a PDF that
/// reads like a book — a cover page, a title page, justified Times paragraphs,
/// a page per chapter, page numbers.
///
/// It exists because there is no clean source of public-domain PDFs among the
/// sites the demo may download from, and the app has no PDF writer of its own;
/// the profiling seeder's one-line PDF (`seed_profiling.dart`) is the same idea
/// at its smallest. Only the 14 standard PDF fonts are used (nothing embedded),
/// in WinAnsi encoding, so the file stays a few hundred kilobytes.
class DemoPdfBook {
  const DemoPdfBook({
    required this.title,
    required this.author,
    required this.chapters,
    this.translator,
    this.coverJpeg,
    this.colophon,
  });

  final String title;
  final String author;
  final String? translator;

  /// JPEG bytes drawn full-bleed as the first page, or null for none.
  final Uint8List? coverJpeg;

  /// A line at the foot of the title page (where the text came from).
  final String? colophon;
  final List<DemoPdfChapter> chapters;
}

class DemoPdfChapter {
  const DemoPdfChapter({required this.title, required this.paragraphs});

  final String title;
  final List<String> paragraphs;
}

/// Typesets [book] and returns the PDF's bytes and page count. Deterministic:
/// the same book gives the same bytes, so its hash is stable between runs.
({Uint8List bytes, int pages}) typesetDemoPdf(DemoPdfBook book) {
  final pages = <_Page>[];
  // A5, in points.
  const pageW = 420.0, pageH = 595.0;
  const marginX = 50.0, marginTop = 60.0, marginBottom = 62.0;
  const textW = pageW - 2 * marginX;
  const bodySize = 10.5, leading = 14.2;

  // ---- Title page.
  final title = _Page();
  var y = pageH - 190;
  for (final line in _wrap(book.title, 'F2', 22, textW)) {
    title.text('F2', 22, (pageW - _width(line, 'F2', 22)) / 2, y, line);
    y -= 28;
  }
  y -= 14;
  title.text('F3', 14, (pageW - _width(book.author, 'F3', 14)) / 2, y,
      book.author);
  final translator = book.translator;
  if (translator != null) {
    final line = 'Translated by $translator';
    y -= 22;
    title.text('F1', 11, (pageW - _width(line, 'F1', 11)) / 2, y, line);
  }
  final colophon = book.colophon;
  if (colophon != null) {
    var cy = 90.0;
    for (final line in _wrap(colophon, 'F3', 8.5, textW)) {
      title.text('F3', 8.5, (pageW - _width(line, 'F3', 8.5)) / 2, cy, line);
      cy -= 11;
    }
  }

  // ---- The text: each chapter on a fresh page, paragraphs justified.
  final body = <_Page>[];
  for (final chapter in book.chapters) {
    var page = _Page();
    body.add(page);
    var cy = pageH - marginTop - 40;
    for (final line in _wrap(chapter.title, 'F2', 15, textW)) {
      page.text('F2', 15, (pageW - _width(line, 'F2', 15)) / 2, cy, line);
      cy -= 20;
    }
    cy -= 18;
    var first = true;
    for (final paragraph in chapter.paragraphs) {
      final indent = first ? 0.0 : 14.0;
      first = false;
      final lines = _wrap(paragraph, 'F1', bodySize, textW, firstIndent: indent);
      for (var i = 0; i < lines.length; i++) {
        if (cy < marginBottom) {
          page = _Page();
          body.add(page);
          cy = pageH - marginTop;
        }
        final x = marginX + (i == 0 ? indent : 0);
        final last = i == lines.length - 1;
        final spaces = ' '.allMatches(lines[i]).length;
        final slack = textW - (i == 0 ? indent : 0) -
            _width(lines[i], 'F1', bodySize);
        // Justified, except a paragraph's last line — and never stretched
        // past what a reader would accept as a word gap.
        final tw = last || spaces == 0 ? 0.0 : min(slack / spaces, 6.0);
        page.text('F1', bodySize, x, cy, lines[i], wordSpacing: tw);
        cy -= leading;
      }
      cy -= 2;
    }
  }
  for (var i = 0; i < body.length; i++) {
    final n = '${i + 1}';
    body[i].text('F1', 9, (pageW - _width(n, 'F1', 9)) / 2, 34, n);
  }

  final cover = book.coverJpeg;
  if (cover != null) pages.add(_Page()..cover = cover);
  pages
    ..add(title)
    ..addAll(body);
  return (
    bytes: _write(pages, pageW, pageH, book.title, book.author),
    pages: pages.length,
  );
}

class _Page {
  final ops = StringBuffer();
  Uint8List? cover;

  void text(String font, double size, double x, double y, String s,
      {double wordSpacing = 0}) {
    ops.write('BT /$font ${_n(size)} Tf ${_n(wordSpacing)} Tw '
        '1 0 0 1 ${_n(x)} ${_n(y)} Tm (${_escape(s)}) Tj ET\n');
  }
}

String _n(double v) => v.toStringAsFixed(2);

Uint8List _write(
  List<_Page> pages,
  double pageW,
  double pageH,
  String title,
  String author,
) {
  final out = BytesBuilder();
  final offsets = <int>[];
  void raw(String s) => out.add(latin1.encode(s));
  void obj(int n, String body, [List<int>? stream]) {
    offsets.add(out.length);
    raw('$n 0 obj\n$body\n');
    if (stream != null) {
      raw('stream\n');
      out.add(stream);
      raw('\nendstream\n');
    }
    raw('endobj\n');
  }

  raw('%PDF-1.4\n%\xE2\xE3\xCF\xD3\n');
  // 1 catalog, 2 pages, 3-5 fonts, 6 info, then per page: page + contents
  // (+ image for the cover).
  const fixed = 6;
  final pageIds = <int>[];
  var next = fixed + 1;
  final layout = <({int page, int contents, int? image})>[];
  for (final p in pages) {
    final page = next++;
    final contents = next++;
    final image = p.cover == null ? null : next++;
    pageIds.add(page);
    layout.add((page: page, contents: contents, image: image));
  }

  obj(1, '<< /Type /Catalog /Pages 2 0 R >>');
  obj(2, '<< /Type /Pages /Kids [${pageIds.map((i) => '$i 0 R').join(' ')}] '
      '/Count ${pages.length} >>');
  const fonts = ['Times-Roman', 'Times-Bold', 'Times-Italic'];
  for (var f = 0; f < fonts.length; f++) {
    obj(3 + f, '<< /Type /Font /Subtype /Type1 /BaseFont /${fonts[f]} '
        '/Encoding /WinAnsiEncoding >>');
  }
  obj(6, '<< /Title (${_escape(title)}) /Author (${_escape(author)}) '
      '/Producer (Vellum demo typesetter) >>');

  for (var i = 0; i < pages.length; i++) {
    final p = pages[i];
    final ids = layout[i];
    String content;
    var resources = '/Font << /F1 3 0 R /F2 4 0 R /F3 5 0 R >>';
    final jpeg = p.cover;
    ({int w, int h, int components})? info;
    if (jpeg != null) {
      info = _jpegSize(jpeg);
      final scale = max(pageW / info.w, pageH / info.h);
      final w = info.w * scale, h = info.h * scale;
      content = 'q ${_n(w)} 0 0 ${_n(h)} ${_n((pageW - w) / 2)} '
          '${_n((pageH - h) / 2)} cm /Im1 Do Q\n';
      resources += ' /XObject << /Im1 ${ids.image} 0 R >>';
    } else {
      content = p.ops.toString();
    }
    obj(ids.page, '<< /Type /Page /Parent 2 0 R '
        '/MediaBox [0 0 ${_n(pageW)} ${_n(pageH)}] '
        '/Contents ${ids.contents} 0 R /Resources << $resources >> >>');
    final compressed = zlib.encode(latin1.encode(content));
    obj(ids.contents,
        '<< /Length ${compressed.length} /Filter /FlateDecode >>', compressed);
    if (jpeg != null && info != null) {
      final space = info.components == 1 ? '/DeviceGray' : '/DeviceRGB';
      obj(ids.image!, '<< /Type /XObject /Subtype /Image /Width ${info.w} '
          '/Height ${info.h} /ColorSpace $space /BitsPerComponent 8 '
          '/Filter /DCTDecode /Length ${jpeg.length} >>', jpeg);
    }
  }

  // Objects were written in id order, so the offsets list is the xref table.
  final xref = out.length;
  raw('xref\n0 ${offsets.length + 1}\n0000000000 65535 f \n');
  for (final o in offsets) {
    raw('${o.toString().padLeft(10, '0')} 00000 n \n');
  }
  raw('trailer\n<< /Size ${offsets.length + 1} /Root 1 0 R /Info 6 0 R >>\n'
      'startxref\n$xref\n%%EOF\n');
  return out.toBytes();
}

/// Width and height from a JPEG's start-of-frame marker.
({int w, int h, int components}) _jpegSize(Uint8List b) {
  var i = 2;
  while (i + 9 < b.length) {
    if (b[i] != 0xFF) {
      i++;
      continue;
    }
    final marker = b[i + 1];
    final length = (b[i + 2] << 8) | b[i + 3];
    // SOF0..SOF15, except DHT (C4), JPG (C8) and DAC (CC).
    if (marker >= 0xC0 &&
        marker <= 0xCF &&
        marker != 0xC4 &&
        marker != 0xC8 &&
        marker != 0xCC) {
      return (
        h: (b[i + 5] << 8) | b[i + 6],
        w: (b[i + 7] << 8) | b[i + 8],
        components: b[i + 9],
      );
    }
    i += 2 + length;
  }
  throw const FormatException('not a JPEG with a frame header');
}

/// Greedy line breaking by measured width.
List<String> _wrap(
  String text,
  String font,
  double size,
  double width, {
  double firstIndent = 0,
}) {
  final words = text.split(RegExp(r'\s+')).where((w) => w.isNotEmpty);
  final lines = <String>[];
  var line = '';
  for (final word in words) {
    final candidate = line.isEmpty ? word : '$line $word';
    final limit = lines.isEmpty ? width - firstIndent : width;
    if (line.isNotEmpty && _width(candidate, font, size) > limit) {
      lines.add(line);
      line = word;
    } else {
      line = candidate;
    }
  }
  if (line.isNotEmpty) lines.add(line);
  return lines;
}

double _width(String s, String font, double size) {
  var units = 0;
  for (final b in _winAnsi(s)) {
    units += _timesWidths[b] ?? 500;
  }
  // Bold and italic Times run close to the roman's widths; a few per cent
  // wider is enough for centring and line breaks.
  final factor = font == 'F2' ? 1.04 : 1.0;
  return units * size * factor / 1000;
}

String _escape(String s) {
  final out = StringBuffer();
  for (final b in _winAnsi(s)) {
    if (b == 0x28 || b == 0x29 || b == 0x5C) {
      out.write('\\${String.fromCharCode(b)}');
    } else if (b < 0x20 || b > 0x7E) {
      out.write('\\${b.toRadixString(8).padLeft(3, '0')}');
    } else {
      out.writeCharCode(b);
    }
  }
  return out.toString();
}

/// [s] in Windows-1252, the encoding the standard fonts are set to. Invisible
/// joiners are dropped, narrow spaces widen to a space, and anything the
/// encoding cannot say becomes nothing rather than a wrong glyph.
List<int> _winAnsi(String s) {
  final out = <int>[];
  for (final rune in s.runes) {
    if (rune < 0x80 || (rune >= 0xA0 && rune <= 0xFF)) {
      out.add(rune == 0xA0 ? 0x20 : rune);
      continue;
    }
    final mapped = _cp1252[rune];
    if (mapped != null) {
      out.add(mapped);
    } else if (rune == 0x2009 || rune == 0x200A || rune == 0x202F) {
      out.add(0x20);
    }
  }
  return out;
}

const _cp1252 = <int, int>{
  0x20AC: 0x80, 0x201A: 0x82, 0x0192: 0x83, 0x201E: 0x84, 0x2026: 0x85,
  0x2020: 0x86, 0x2021: 0x87, 0x02C6: 0x88, 0x2030: 0x89, 0x0160: 0x8A,
  0x2039: 0x8B, 0x0152: 0x8C, 0x017D: 0x8E, 0x2018: 0x91, 0x2019: 0x92,
  0x201C: 0x93, 0x201D: 0x94, 0x2022: 0x95, 0x2013: 0x96, 0x2014: 0x97,
  0x02DC: 0x98, 0x2122: 0x99, 0x0161: 0x9A, 0x203A: 0x9B, 0x0153: 0x9C,
  0x017E: 0x9E, 0x0178: 0x9F,
};

/// Times-Roman advance widths (thousandths of an em) for the WinAnsi codes
/// that occur in prose; anything missing counts as 500.
const _timesWidths = <int, int>{
  0x20: 250, 0x21: 333, 0x22: 408, 0x23: 500, 0x24: 500, 0x25: 833,
  0x26: 778, 0x27: 180, 0x28: 333, 0x29: 333, 0x2A: 500, 0x2B: 564,
  0x2C: 250, 0x2D: 333, 0x2E: 250, 0x2F: 278, 0x30: 500, 0x31: 500,
  0x32: 500, 0x33: 500, 0x34: 500, 0x35: 500, 0x36: 500, 0x37: 500,
  0x38: 500, 0x39: 500, 0x3A: 278, 0x3B: 278, 0x3C: 564, 0x3D: 564,
  0x3E: 564, 0x3F: 444, 0x40: 921, 0x41: 722, 0x42: 667, 0x43: 667,
  0x44: 722, 0x45: 611, 0x46: 556, 0x47: 722, 0x48: 722, 0x49: 333,
  0x4A: 389, 0x4B: 722, 0x4C: 611, 0x4D: 889, 0x4E: 722, 0x4F: 722,
  0x50: 556, 0x51: 722, 0x52: 667, 0x53: 556, 0x54: 611, 0x55: 722,
  0x56: 722, 0x57: 944, 0x58: 722, 0x59: 722, 0x5A: 611, 0x5B: 333,
  0x5C: 278, 0x5D: 333, 0x5E: 469, 0x5F: 500, 0x60: 333, 0x61: 444,
  0x62: 500, 0x63: 444, 0x64: 500, 0x65: 444, 0x66: 333, 0x67: 500,
  0x68: 500, 0x69: 278, 0x6A: 278, 0x6B: 500, 0x6C: 278, 0x6D: 778,
  0x6E: 500, 0x6F: 500, 0x70: 500, 0x71: 500, 0x72: 333, 0x73: 389,
  0x74: 278, 0x75: 500, 0x76: 500, 0x77: 722, 0x78: 500, 0x79: 500,
  0x7A: 444, 0x7B: 480, 0x7C: 200, 0x7D: 480, 0x7E: 541,
  0x85: 1000, 0x91: 333, 0x92: 333, 0x93: 444, 0x94: 444, 0x95: 350,
  0x96: 500, 0x97: 1000, 0xE6: 667, 0xE9: 444, 0xE8: 444, 0xEA: 444,
  0xEB: 444, 0xE0: 444, 0xE1: 444, 0xE2: 444, 0xE4: 444, 0xEF: 278,
  0xEE: 278, 0xF4: 500, 0xF6: 500, 0xFC: 500, 0xE7: 444, 0xC9: 611,
};
