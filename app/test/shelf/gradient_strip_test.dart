// A spine's shading is drawn from a strip image instead of a gradient
// (gradient_strip.dart, docs/PERFORMANCE.md). That is only worth doing if
// nobody can tell: this paints each spine shape both ways and compares pixels.
import 'dart:math';
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/shelf/gradient_strip.dart';
import 'package:vellum/shelf/spine_style.dart';

/// Device pixels per logical pixel in the capture — 2, so a fractional width
/// (most spines') leaves a partly covered edge column to compare.
const _capture = 2.0;

Future<Uint8List> _pixels(WidgetTester tester, Widget child, Size size) async {
  final key = GlobalKey();
  await tester.pumpWidget(Directionality(
    textDirection: TextDirection.ltr,
    child: Align(
      alignment: Alignment.topLeft,
      child: RepaintBoundary(
        key: key,
        child: SizedBox.fromSize(size: size, child: child),
      ),
    ),
  ));
  late Uint8List bytes;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: _capture);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    bytes = data!.buffer.asUint8List();
  });
  return bytes;
}

/// Worst and mean per-channel difference between two RGBA buffers.
({int max, double mean}) _diff(Uint8List a, Uint8List b, {required Size size}) {
  expect(a.length, b.length, reason: '$size');
  var worst = 0;
  var sum = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    sum += d;
    worst = max(worst, d);
  }
  return (max: worst, mean: sum / a.length);
}

void main() {
  // The sizes a spine is drawn at: widths from page counts (fractional), the
  // shelf's heights, and a zoomed-in room book.
  const sizes = [Size(34, 149), Size(50.857, 160), Size(62, 171), Size(48, 600)];

  testWidgets('a generated spine shades the same as its gradient did',
      (tester) async {
    final colours = [
      for (final title in ['A', 'Garden', 'The Silent River', 'Kingdom 7'])
        SpineStyle.generate(title: title).color,
      const Color(0xFFCEAEE5),
      const Color(0xFF92BC2E),
    ];
    for (final colour in colours) {
      final ramp = [
        Color.lerp(colour, Colors.white, 0.18)!,
        colour,
        Color.lerp(colour, Colors.black, 0.22)!,
      ];
      const stops = [0.0, 0.35, 1.0];
      for (final size in sizes) {
        final before = await _pixels(
          tester,
          DecoratedBox(
            decoration: BoxDecoration(
              borderRadius:
                  const BorderRadius.vertical(top: Radius.circular(3)),
              gradient: LinearGradient(colors: ramp, stops: stops),
            ),
          ),
          size,
        );
        final after = await _pixels(
          tester,
          GradientStripBox(strip: GradientStrip(ramp, stops), topRadius: 3),
          size,
        );
        // Corners included: the clip anti-aliases the curve as the shape did.
        final d = _diff(before, after, size: size);
        expect(d.max, lessThanOrEqualTo(3), reason: '$colour at $size');
        expect(d.mean, lessThan(0.5), reason: '$colour at $size');
      }
    }
  });

  testWidgets('a cover-slice spine shades the same as its gradient did',
      (tester) async {
    const ramp = [Color(0x33FFFFFF), Color(0x00000000), Color(0x59000000)];
    const stops = [0.0, 0.35, 1.0];
    // Over artwork: the shading is translucent, so what is under it shows.
    Widget over(Widget shading) => Stack(
          fit: StackFit.expand,
          children: [
            const DecoratedBox(
              decoration: BoxDecoration(
                gradient: LinearGradient(
                  begin: Alignment.topCenter,
                  end: Alignment.bottomCenter,
                  colors: [Color(0xFF2E5A9C), Color(0xFFE8DCC0)],
                ),
              ),
            ),
            shading,
          ],
        );
    for (final size in sizes) {
      final before = await _pixels(
        tester,
        over(const DecoratedBox(
          decoration: BoxDecoration(
            gradient: LinearGradient(colors: ramp, stops: stops),
          ),
        )),
        size,
      );
      final after = await _pixels(
        tester,
        over(const GradientStripBox(strip: GradientStrip(ramp, stops))),
        size,
      );
      final d = _diff(before, after, size: size);
      expect(d.max, lessThanOrEqualTo(3), reason: '$size');
      expect(d.mean, lessThan(0.5), reason: '$size');
    }
  });

  test('strips are made once and shared', () {
    const a = GradientStrip([Color(0xFF000000), Color(0xFFFFFFFF)], [0, 1]);
    const b = GradientStrip([Color(0xFF000000), Color(0xFFFFFFFF)], [0, 1]);
    expect(identical(a.image, b.image), isTrue);
  });
}
