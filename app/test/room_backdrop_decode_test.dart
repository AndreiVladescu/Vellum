import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/physical/room_backdrop.dart';

Future<Uint8List> _png(int w, int h) async {
  final recorder = ui.PictureRecorder();
  ui.Canvas(recorder).drawRect(
    ui.Rect.fromLTWH(0, 0, w.toDouble(), h.toDouble()),
    ui.Paint()..color = const ui.Color(0xFF336699),
  );
  final image = await recorder.endRecording().toImage(w, h);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  testWidgets('a large backdrop decodes at display size, keeping its source', (
    tester,
  ) async {
    await tester.runAsync(() async {
      final bytes = await _png(4000, 3000);
      final d = await decodeBackdrop(bytes);
      expect(d.image.width, backdropMaxSide);
      expect(d.image.height, closeTo(1536, 1));
      expect(d.sourceSize, const ui.Size(4000, 3000));
      d.image.dispose();
    });
  });

  testWidgets('a small backdrop is not upscaled', (tester) async {
    await tester.runAsync(() async {
      final bytes = await _png(600, 800);
      final d = await decodeBackdrop(bytes);
      expect(d.image.width, 600);
      expect(d.image.height, 800);
      expect(d.sourceSize, const ui.Size(600, 800));
      d.image.dispose();
    });
  });
}
