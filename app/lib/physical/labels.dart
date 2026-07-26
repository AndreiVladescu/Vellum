/// Printable shelf labels (plan 5 #28).
///
/// **HTML, not PDF.** The plan allowed either; HTML wins because printing is a
/// thing the operating system already does well and a browser's print dialog
/// gives page size, margins and a preview for free. A PDF generator would mean
/// a layout engine of our own, a new dependency, and paper-size decisions we'd
/// have to guess. The sheet is written to a temp file and opened; you print it
/// with Ctrl+P.
///
/// The generator itself is a pure function so the markup can be asserted in a
/// test rather than eyeballed on paper.
library;

import 'dart:convert';

import 'package:meta/meta.dart';
import 'package:qr/qr.dart';

import 'locate.dart';

/// One label to print: a shelf's name, the room it's in, and how many books are
/// on it.
class ShelfLabel {
  const ShelfLabel({
    required this.shelfId,
    required this.environmentName,
    this.shelfName,
    this.bookCount = 0,
  });

  final String shelfId;
  final String environmentName;

  /// The shelf's own label. Null for an unlabelled shelf, which still gets a
  /// printable label — you stick it on, *then* it has a name.
  final String? shelfName;

  final int bookCount;

  String get displayName {
    final trimmed = shelfName?.trim();
    return (trimmed == null || trimmed.isEmpty) ? 'Unlabelled shelf' : trimmed;
  }
}

/// Builds the printable sheet.
///
/// Sized in millimetres with `@page` margins so what comes out of the printer
/// matches the preview, and the labels are a plain CSS grid — three across on
/// A4, which lands at about 60 mm wide: big enough to read across a room,
/// small enough that a shelf edge can carry one.
String buildLabelSheetHtml({
  required List<ShelfLabel> labels,
  String title = 'Vellum shelf labels',
  bool includeQr = true,
}) {
  final cards = StringBuffer();
  for (final label in labels) {
    final link = shelfLink(label.shelfId);
    cards.writeln('''
    <div class="label">
      ${includeQr ? '<div class="qr">${_qrSvg(link)}</div>' : ''}
      <div class="text">
        <div class="shelf">${_escape(label.displayName)}</div>
        <div class="room">${_escape(label.environmentName)}</div>
        <div class="count">${_books(label.bookCount)}</div>
        <!-- The link in text as well as in the QR: a desktop has no camera,
             and the shelf-label scanner accepts a typed link for exactly that
             reason. -->
        <div class="link">${_escape(link)}</div>
      </div>
    </div>''');
  }

  return '''<!doctype html>
<html lang="en">
<head>
<meta charset="utf-8">
<title>${_escape(title)}</title>
<style>
  /* Print first: this document exists to be printed, and the on-screen view is
     just a preview of that. */
  @page { size: A4; margin: 12mm; }
  body {
    font-family: system-ui, -apple-system, "Segoe UI", Roboto, sans-serif;
    margin: 0;
    color: #111;
    background: #fff;
  }
  h1 { font-size: 14pt; font-weight: 600; margin: 0 0 6mm; }
  .sheet {
    display: grid;
    grid-template-columns: repeat(3, 1fr);
    gap: 4mm;
  }
  .label {
    display: flex;
    align-items: center;
    gap: 3mm;
    border: 0.4mm solid #999;
    border-radius: 2mm;
    padding: 3mm;
    min-height: 22mm;
    /* Never split a label across a page break — half a label is rubbish. */
    break-inside: avoid;
    page-break-inside: avoid;
  }
  .qr { flex: 0 0 18mm; }
  .qr svg { width: 18mm; height: 18mm; display: block; }
  .text { min-width: 0; }
  .shelf {
    font-size: 12pt;
    font-weight: 600;
    line-height: 1.15;
    overflow-wrap: anywhere;
  }
  .room { font-size: 9pt; color: #444; overflow-wrap: anywhere; }
  .count { font-size: 8pt; color: #777; margin-top: 1mm; }
  .link {
    font-size: 5pt;
    color: #aaa;
    font-family: ui-monospace, "SF Mono", Menlo, Consolas, monospace;
    overflow-wrap: anywhere;
  }
  .hint { font-size: 9pt; color: #555; margin: 0 0 6mm; }
  @media print { .hint, h1 { display: none; } }
</style>
</head>
<body>
<h1>${_escape(title)}</h1>
<p class="hint">
  Press Ctrl+P (⌘P on a Mac) to print, then cut along the boxes.
  Scanning a label in Vellum opens that shelf's room.
</p>
<div class="sheet">
$cards</div>
</body>
</html>
''';
}

/// A QR code for [data] as inline SVG.
///
/// Inline rather than a data-URI image so the sheet is one self-contained file
/// with no base64 blobs, and vector so it prints crisply at any size — a
/// rasterised QR at 18 mm is exactly the kind of thing that scans on screen and
/// fails on paper.
@visibleForTesting
String qrSvgForTesting(String data) => _qrSvg(data);

String _qrSvg(String data) {
  final image = QrImage(
    QrCode(
      payload: QrPayload.fromString(data),
      // High correction: these get taped to shelf edges and scuffed. The size
      // cost is a few more modules in an 18 mm square.
      errorCorrectLevel: QrErrorCorrectLevel.high,
    ),
  );
  final n = image.moduleCount;
  // One path of many little squares beats one <rect> per module: a version-3
  // code is ~700 modules, and 700 elements per label is a heavy document.
  final path = StringBuffer();
  for (var row = 0; row < n; row++) {
    for (var col = 0; col < n; col++) {
      if (image.isDark(row, col)) path.write('M$col ${row}h1v1h-1z');
    }
  }
  // A 4-module quiet zone is required by the spec; without it readers struggle.
  const quiet = 4;
  final side = n + quiet * 2;
  return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 $side $side" '
      'shape-rendering="crispEdges">'
      '<rect width="$side" height="$side" fill="#fff"/>'
      '<g transform="translate($quiet $quiet)" fill="#000">'
      '<path d="$path"/></g></svg>';
}

String _books(int count) => switch (count) {
      0 => 'No books recorded',
      1 => '1 book',
      _ => '$count books',
    };

/// Escapes text for HTML. Shelf names and room names are user text and go
/// straight into the markup, so `Ana & Bob's <shelf>` has to survive intact
/// rather than breaking the document.
///
/// Element mode, not the default: everything here is element *content*, and the
/// default also escapes quotes and slashes — which is correct for an attribute
/// and turns a printed `vellum://shelf/x` into `vellum:&#47;&#47;shelf&#47;x`.
String _escape(String raw) =>
    const HtmlEscape(HtmlEscapeMode.element).convert(raw);
