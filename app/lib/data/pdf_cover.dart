import 'dart:isolate';
import 'dart:typed_data';

import 'package:image/image.dart' as img;
import 'package:pdfrx/pdfrx.dart';

/// Number of pages in the PDF at [path], or null if it can't be opened.
Future<int?> pdfPageCount(String path) async {
  await pdfrxFlutterInitialize();
  final doc = await PdfDocument.openFile(path);
  try {
    final count = doc.pages.length;
    return count > 0 ? count : null;
  } finally {
    await doc.dispose();
  }
}

/// Renders the first page of the PDF at [path] to JPEG bytes, sized for a
/// cover. Returns null if the document has no pages or rendering fails.
///
/// JPEG rather than the PNG this used to return (performance round #3): a
/// rendered page is a photograph-like image with no transparency, and as a PNG
/// it came to 1.7 MB — more than most books' downloaded covers by a factor of
/// ten, paid again on every sync, backup and shelf decode. The encode runs in a
/// background isolate, so the UI isolate never waits on it.
Future<Uint8List?> renderPdfFirstPageJpeg(String path) async {
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
    try {
      final pixels = image.pixels;
      final width = image.width;
      final height = image.height;
      // The pixels are copied into the isolate along with the closure, so
      // the render can be disposed of as soon as it returns.
      return await Isolate.run(() => _encodeJpeg(pixels, width, height));
    } finally {
      image.dispose();
    }
  } finally {
    await doc.dispose();
  }
}

/// pdfrx renders BGRA; quality 90 because this is the cover itself, not a
/// thumbnail of it.
Uint8List _encodeJpeg(Uint8List bgra, int width, int height) => img.encodeJpg(
      img.Image.fromBytes(
        width: width,
        height: height,
        bytes: bgra.buffer,
        bytesOffset: bgra.offsetInBytes,
        numChannels: 4,
        order: img.ChannelOrder.bgra,
      ),
      quality: 90,
    );
