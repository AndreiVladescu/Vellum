import 'package:flutter/material.dart';

import '../data/database.dart';
import '../shelf/spine_style.dart';

/// Real-world dimensions and colour for a book placed on a physical shelf.
///
/// Everything is in **metres**. Thickness is estimated from the page count
/// (paper + covers) and clamped to a believable range; height defaults to a
/// standard hardcover. Both can be overridden per placement, in which case the
/// stored override (also metres) wins.
class PhysicalMetrics {
  const PhysicalMetrics._();

  /// Default spine height when nothing overrides it — a typical book (~20 cm).
  static const double defaultHeight = 0.20;

  // ~0.06 mm of paper per leaf, plus ~8 mm of covers, clamped to 6–90 mm.
  static const double _perPage = 0.00006;
  static const double _coverBase = 0.008;
  static const double _minThickness = 0.006;
  static const double _maxThickness = 0.09;

  /// Spine thickness in metres, from an explicit override or the page count.
  static double thickness(Book book, {double? override}) {
    if (override != null) return override;
    final pages = book.pageCount ?? 220;
    final t = _coverBase + pages * _perPage;
    return t.clamp(_minThickness, _maxThickness);
  }

  /// Spine height in metres, from an override or the default.
  static double height(Book book, {double? override}) =>
      override ?? defaultHeight;

  /// Reuse the generated spine palette so a book looks the same everywhere.
  static Color color(Book book) =>
      SpineStyle.fromJson(book.spineStyle, title: book.title).color;

  static Color textColor(Book book) =>
      SpineStyle.fromJson(book.spineStyle, title: book.title).textColor;
}
