import 'package:flutter/material.dart';

import '../data/database.dart';
import '../shelf/spine_style.dart';

/// A size preset for a physical book: a trim height plus the spine growth per
/// page and a fixed cover/binding allowance. Picking one sets a book's default
/// thickness and height from its page count; explicit overrides still win.
///
/// Calibrated against a real data point — a 367-page B5 softcover measured
/// 2.2 cm: 367 × 0.06 mm + ~1 mm covers ≈ 23 mm. (A "page" is one printed side,
/// so ~0.12 mm of paper per leaf.)
class BookFormat {
  const BookFormat(
    this.key,
    this.label,
    this.heightM,
    this.mmPerPage,
    this.coverMm,
  );

  final String key;
  final String label;
  final double heightM; // trim height
  final double mmPerPage; // spine growth per page
  final double coverMm; // fixed covers / binding

  static const presets = <BookFormat>[
    BookFormat('mass', 'Mass-market paperback', 0.175, 0.055, 0.8),
    BookFormat('trade', 'Trade paperback', 0.203, 0.060, 1.0),
    BookFormat('a5', 'A5', 0.210, 0.060, 1.0),
    BookFormat('b5soft', 'B5 softcover', 0.250, 0.060, 1.0),
    BookFormat('hardcover', 'Hardcover', 0.235, 0.065, 5.0),
    BookFormat('a4', 'A4', 0.297, 0.070, 2.0),
  ];

  static BookFormat? byKey(String? key) {
    if (key == null) return null;
    for (final f in presets) {
      if (f.key == key) return f;
    }
    return null;
  }
}

/// Real-world dimensions and colour for a book placed on a physical shelf. All
/// lengths are in **metres**. Thickness and height come from a size preset (or
/// a sensible default) and can be overridden per placement.
class PhysicalMetrics {
  const PhysicalMetrics._();

  /// Default spine height when nothing sets it — a typical book (~20 cm).
  static const double defaultHeight = 0.20;

  // Defaults when no preset is chosen (roughly standard book paper).
  static const double _defaultMmPerPage = 0.06;
  static const double _defaultCoverMm = 1.0;
  static const double _minThickness = 0.005;
  static const double _maxThickness = 0.12;

  /// Spine thickness in metres. Priority: explicit [override] → [format] curve
  /// from the page count → the default curve.
  static double thickness(Book book, {BookFormat? format, double? override}) {
    if (override != null) return override;
    final pages = (book.pageCount ?? 220).toDouble();
    final mmPerPage = format?.mmPerPage ?? _defaultMmPerPage;
    final coverMm = format?.coverMm ?? _defaultCoverMm;
    final metres = (pages * mmPerPage + coverMm) / 1000;
    return metres.clamp(_minThickness, _maxThickness);
  }

  /// Spine height in metres. Priority: [override] → [format] trim → default.
  static double height(Book book, {BookFormat? format, double? override}) =>
      override ?? format?.heightM ?? defaultHeight;

  /// Reuse the generated spine palette so a book looks the same everywhere.
  static Color color(Book book) =>
      SpineStyle.fromJson(book.spineStyle, title: book.title).color;

  static Color textColor(Book book) =>
      SpineStyle.fromJson(book.spineStyle, title: book.title).textColor;
}
