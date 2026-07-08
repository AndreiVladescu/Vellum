import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:pdfrx/pdfrx.dart';

/// Renders the first page of the PDF at [path] to PNG bytes, sized for a cover.
/// Returns null if the document has no pages or rendering fails.
Future<Uint8List?> renderPdfFirstPagePng(String path) async {
  await pdfrxFlutterInitialize();
  final doc = await PdfDocument.openFile(path);
  try {
    if (doc.pages.isEmpty) return null;
    final page = doc.pages.first;

    // Aim for ~1200px-tall covers, preserving aspect ratio.
    const targetHeight = 1200.0;
    final scale = targetHeight / page.height;
    final w = (page.width * scale).round();
    final h = (page.height * scale).round();
    // Render the WHOLE page: the output rectangle (0,0,w,h) must span the full
    // page (fullWidth/fullHeight), otherwise pdfrx returns just a top-left crop.
    final image = await page.render(
      x: 0,
      y: 0,
      width: w,
      height: h,
      fullWidth: w.toDouble(),
      fullHeight: h.toDouble(),
      backgroundColor: 0xFFFFFFFF, // white, so a transparent page isn't black
    );
    if (image == null) return null;

    ui.Image uiImage;
    try {
      uiImage = await image.createImage();
    } finally {
      image.dispose();
    }
    try {
      final data = await uiImage.toByteData(format: ui.ImageByteFormat.png);
      return data?.buffer.asUint8List();
    } finally {
      uiImage.dispose();
    }
  } finally {
    await doc.dispose();
  }
}
