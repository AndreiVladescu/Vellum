import 'dart:math' as math;
import 'dart:typed_data';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';

/// The dominant colour of a cover image, or null when [bytes] can't be
/// decoded. Decodes at a tiny size (32 px) and histograms the pixels with a
/// saturation-weighted score, so a vivid accent wins over large near-white or
/// near-black areas (page backgrounds, borders) — those make dull spines.
Future<Color?> dominantColorOf(Uint8List bytes) async {
  final ByteData? data;
  try {
    final codec = await ui.instantiateImageCodec(bytes, targetWidth: 32);
    final frame = await codec.getNextFrame();
    data = await frame.image.toByteData(format: ui.ImageByteFormat.rawRgba);
    frame.image.dispose();
  } catch (_) {
    return null; // not an image (or a codec this platform can't read)
  }
  if (data == null) return null;

  // Buckets keyed by RGB quantized to 3 bits per channel; each keeps a
  // saturation-weighted score and a running sum to average the true colour.
  final scores = <int, double>{};
  final sums = <int, List<int>>{}; // key -> [r, g, b, count]
  for (var i = 0; i + 3 < data.lengthInBytes; i += 4) {
    final r = data.getUint8(i);
    final g = data.getUint8(i + 1);
    final b = data.getUint8(i + 2);
    if (data.getUint8(i + 3) < 128) continue; // transparent
    final maxC = math.max(r, math.max(g, b));
    final minC = math.min(r, math.min(g, b));
    final sat = maxC == 0 ? 0.0 : (maxC - minC) / maxC;
    final lum = maxC / 255.0;
    if (lum < 0.12 || (lum > 0.92 && sat < 0.10)) continue; // near black/white
    final key = (r >> 5) << 6 | (g >> 5) << 3 | (b >> 5);
    scores[key] = (scores[key] ?? 0) + 0.2 + sat;
    final s = sums.putIfAbsent(key, () => [0, 0, 0, 0]);
    s[0] += r;
    s[1] += g;
    s[2] += b;
    s[3] += 1;
  }
  if (scores.isEmpty) return null;
  final best =
      scores.entries.reduce((a, b) => a.value >= b.value ? a : b).key;
  final s = sums[best]!;
  return Color.fromARGB(255, s[0] ~/ s[3], s[1] ~/ s[3], s[2] ~/ s[3]);
}

/// A readable text colour for a spine of [background].
Color spineTextColorFor(Color background) =>
    ThemeData.estimateBrightnessForColor(background) == Brightness.dark
        ? Colors.white
        : const Color(0xFF3A3226);
