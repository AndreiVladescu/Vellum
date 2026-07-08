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

    // Aim for ~1000px-tall covers, preserving aspect ratio.
    const targetHeight = 1000.0;
    final scale = targetHeight / page.height;
    final image = await page.render(
      width: (page.width * scale).round(),
      height: (page.height * scale).round(),
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
