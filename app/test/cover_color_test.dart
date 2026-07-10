import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/shelf/cover_color.dart';
import 'package:vellum/shelf/spine_style.dart';

/// Encodes a solid-colour image as PNG bytes, via the engine's own codec.
Future<Uint8List> _solidPng(Color color, {int size = 16}) async {
  final recorder = ui.PictureRecorder();
  final canvas = Canvas(recorder);
  canvas.drawRect(
    Rect.fromLTWH(0, 0, size.toDouble(), size.toDouble()),
    Paint()..color = color,
  );
  final image = await recorder.endRecording().toImage(size, size);
  final data = await image.toByteData(format: ui.ImageByteFormat.png);
  image.dispose();
  return data!.buffer.asUint8List();
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  test('extracts the dominant colour of a solid image', () async {
    final bytes = await _solidPng(const Color(0xFF2E5A9C));
    final color = await dominantColorOf(bytes);
    expect(color, isNotNull);
    // Quantized + averaged, so allow a small tolerance per channel.
    expect(((color!.r * 255) - 0x2E).abs(), lessThan(12));
    expect(((color.g * 255) - 0x5A).abs(), lessThan(12));
    expect(((color.b * 255) - 0x9C).abs(), lessThan(12));
  });

  test('a saturated accent beats a larger near-white area', () async {
    final recorder = ui.PictureRecorder();
    final canvas = Canvas(recorder);
    canvas.drawRect(const Rect.fromLTWH(0, 0, 16, 16),
        Paint()..color = const Color(0xFFF8F8F8));
    canvas.drawRect(const Rect.fromLTWH(0, 0, 16, 5),
        Paint()..color = const Color(0xFFC0392B));
    final image = await recorder.endRecording().toImage(16, 16);
    final data = await image.toByteData(format: ui.ImageByteFormat.png);
    image.dispose();

    final color = await dominantColorOf(data!.buffer.asUint8List());
    expect(color, isNotNull);
    expect(color!.r, greaterThan(color.g),
        reason: 'the red accent should win over the white background');
  });

  test('returns null for bytes that are not an image', () async {
    expect(await dominantColorOf(Uint8List.fromList([1, 2, 3])), isNull);
  });

  test('spine style round-trips the cover colour through JSON', () {
    final style = SpineStyle.generate(title: 'Dune')
        .withCoverColor(const Color(0xFF336699));
    final parsed = SpineStyle.fromJson(style.toJson(), title: 'Dune');
    expect(parsed.coverColor, const Color(0xFF336699));
    // And older JSON without the field still parses (null colour).
    final legacy = SpineStyle.generate(title: 'Dune').toJson();
    expect(SpineStyle.fromJson(legacy, title: 'Dune').coverColor, isNull);
  });
}
