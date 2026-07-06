import 'dart:convert';

import 'package:flutter/material.dart';

/// Visual parameters for a generated book spine.
///
/// No online source provides spine images, so Vellum generates spines: a
/// deterministic color + decoration derived from title/author, thickness from
/// page count. The result is stored as JSON in `book.spine_style` so it stays
/// stable and can be user-tweaked later (e.g. replaced by colors extracted
/// from the cover).
class SpineStyle {
  const SpineStyle({
    required this.color,
    required this.textColor,
    required this.width,
    required this.heightFactor,
    required this.variant,
  });

  final Color color;
  final Color textColor;

  /// Spine thickness in logical pixels (driven by page count).
  final double width;

  /// 0..1 fraction of the shelf's book height (books vary in height).
  final double heightFactor;

  /// Decoration: 0 = plain, 1 = bands top/bottom, 2 = framed label.
  final int variant;

  // Palette inspired by a classic shelf: navy, green, red, cream, brown,
  // orange, gray, teal, burgundy, mustard.
  static const _palette = [
    Color(0xFF2E5A9C),
    Color(0xFF3E8E4E),
    Color(0xFFC0392B),
    Color(0xFFE8DCC0),
    Color(0xFF5B3A29),
    Color(0xFFE67E22),
    Color(0xFF808487),
    Color(0xFF2E7D7B),
    Color(0xFF7B2D3B),
    Color(0xFFC8A02D),
  ];

  static SpineStyle generate({
    required String title,
    String? author,
    int? pageCount,
  }) {
    final h = _fnv1a('$title|${author ?? ''}');
    final color = _palette[h % _palette.length];
    final textColor =
        ThemeData.estimateBrightnessForColor(color) == Brightness.dark
            ? Colors.white
            : const Color(0xFF3A3226);
    final pages = pageCount ?? 220;
    final width = 34.0 + ((pages - 120) / 14.0).clamp(0.0, 28.0);
    final heightFactor = 0.85 + ((h >> 4) % 14) / 100.0;
    return SpineStyle(
      color: color,
      textColor: textColor,
      width: width,
      heightFactor: heightFactor,
      variant: (h >> 8) % 3,
    );
  }

  /// Parses the stored JSON, falling back to [generate] on missing/bad data.
  static SpineStyle fromJson(String? json, {required String title}) {
    if (json == null || json.isEmpty) return generate(title: title);
    try {
      final m = jsonDecode(json) as Map<String, dynamic>;
      return SpineStyle(
        color: _parseHex(m['color'] as String),
        textColor: _parseHex(m['textColor'] as String),
        width: (m['width'] as num).toDouble(),
        heightFactor: (m['heightFactor'] as num).toDouble(),
        variant: m['variant'] as int,
      );
    } catch (_) {
      return generate(title: title);
    }
  }

  String toJson() => jsonEncode({
        'color': _toHex(color),
        'textColor': _toHex(textColor),
        'width': width,
        'heightFactor': heightFactor,
        'variant': variant,
      });

  static Color _parseHex(String hex) =>
      Color(int.parse(hex.substring(1), radix: 16) | 0xFF000000);

  static String _toHex(Color c) {
    final rgb = c.toARGB32() & 0xFFFFFF;
    return '#${rgb.toRadixString(16).padLeft(6, '0').toUpperCase()}';
  }

  /// FNV-1a: stable across runs/platforms (String.hashCode is not).
  static int _fnv1a(String s) {
    var h = 0x811c9dc5;
    for (final c in s.codeUnits) {
      h ^= c;
      h = (h * 0x01000193) & 0x7FFFFFFF;
    }
    return h;
  }
}
