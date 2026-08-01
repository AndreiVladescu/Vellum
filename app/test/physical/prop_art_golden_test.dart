// Renders every prop side by side and writes it out, so the drawing can be
// *looked at* rather than only asserted on. Not a golden test — there is no
// committed reference image — just a way to see the set as a whole.
//
//   flutter test test/physical/prop_art_golden_test.dart
//
// The PNG lands in build/prop_art.png.
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/physical/room_prop.dart';

void main() {
  testWidgets('draw the whole set for inspection', (tester) async {
    final key = GlobalKey();
    // 600 px/m — a room zoomed in far enough to be arranging things on a shelf.
    const pxPerM = 600.0;

    await tester.pumpWidget(
      MaterialApp(
        home: RepaintBoundary(
          key: key,
          child: Container(
            color: const Color(0xFFF2EDE4),
            padding: const EdgeInsets.all(16),
            child: Wrap(
              spacing: 28,
              runSpacing: 16,
              crossAxisAlignment: WrapCrossAlignment.end,
              children: [
                for (final kind in PropKind.values)
                  Column(
                    mainAxisSize: MainAxisSize.min,
                    mainAxisAlignment: MainAxisAlignment.end,
                    children: [
                      SizedBox(
                        width: kind.width * pxPerM,
                        height: kind.height * pxPerM,
                        child: PropArt(
                          kind: kind,
                          color: const Color(0xFF7A5A42),
                        ),
                      ),
                      const SizedBox(height: 6),
                      // The plank they stand on, so the sizes read against
                      // something.
                      Container(
                        width: kind.width * pxPerM + 20,
                        height: 5,
                        color: const Color(0xFF8B6F55),
                      ),
                      // No labels: `flutter test` has no real font, so text
                      // renders as nothing at all and its box only overflows
                      // across the picture. They appear in `PropKind.values`
                      // order — statuette, plant, vase, clock, boxes, bookend.
                    ],
                  ),
              ],
            ),
          ),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.runAsync(() async {
      final boundary =
          key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
      final image = await boundary.toImage(pixelRatio: 2);
      final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
      final out = File('build/prop_art.png')
        ..createSync(recursive: true)
        ..writeAsBytesSync(bytes!.buffer.asUint8List());
      // ignore: avoid_print
      print('wrote ${out.path}');
    });
  });
}
