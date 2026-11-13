// How a PDF highlight is blended onto the page.
//
// A page with a highlight on it went soft on Linux: Impeller draws "advanced"
// blend modes (multiply among them) by copying what is already on the canvas
// into a texture and compositing it back, and the copy resampled the sharp page
// tile under the mark. The marker now uses `modulate`, a plain Porter-Duff
// blend Impeller does in a single pass. These pin both halves: the blend stays
// a pipeline one, and the page looks exactly as it did with multiply.
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/annotations/highlight_palette.dart';
import 'package:vellum/reader/annotations/pdf_highlight_painter.dart';

/// Paints [backdrop] opaque, then one mark over it, and reads the pixel back.
Future<Uint8List> _pixel(Color backdrop, Paint mark) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  const rect = Rect.fromLTWH(0, 0, 1, 1);
  canvas.drawRect(rect, Paint()..color = backdrop);
  canvas.drawRect(rect, mark);
  final image = await recorder.endRecording().toImage(1, 1);
  final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('the marker uses a blend Impeller draws without copying the page', () {
    for (final colour in HighlightColor.values) {
      final paint = markerPaint(colour.inkColor);
      // Clear .. modulate are Impeller's pipeline blends; everything after
      // (screen, multiply, ...) is an advanced blend and snapshots the canvas.
      expect(paint.blendMode.index, lessThanOrEqualTo(BlendMode.modulate.index),
          reason: '${colour.name} uses ${paint.blendMode}');
      // Opaque, so modulate leaves the page's alpha alone.
      expect(paint.color.a, 1.0);
    }
  });

  test('the marker looks the way multiply did on every kind of page', () async {
    const backdrops = [
      Color(0xFFFFFFFF), // paper
      Color(0xFF000000), // a glyph
      Color(0xFF808080), // anti-aliased edge
      Color(0xFF3366CC), // a coloured figure
      Color(0xFFF4ECD8), // sepia paper
    ];
    for (final colour in HighlightColor.values) {
      final multiply = Paint()
        ..color = colour.inkColor
        ..blendMode = BlendMode.multiply;
      for (final backdrop in backdrops) {
        final before = await _pixel(backdrop, multiply);
        final after = await _pixel(backdrop, markerPaint(colour.inkColor));
        for (var c = 0; c < 4; c++) {
          expect((before[c] - after[c]).abs(), lessThanOrEqualTo(1),
              reason: '${colour.name} on $backdrop, channel $c: '
                  '${before[c]} before, ${after[c]} now');
        }
      }
    }
  });
}
