import 'package:flutter/material.dart';

import '../data/database.dart';
import '../shelf/spine_style.dart';

/// Measured calibration: a 367-page B5 softcover is 21 mm thick, i.e. 17.476
/// pages per millimetre → ~0.0572 mm per page, with no separate cover base.
/// The default and softcover presets use exactly this.
const double _mmPerPage = 21.0 / 367.0;

/// A size preset for a physical book: a trim height plus the spine growth per
/// page and a fixed cover/binding allowance. Picking one sets a book's default
/// thickness and height from its page count; explicit overrides still win.
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
  final double coverMm; // fixed covers / binding (boards)

  static const presets = <BookFormat>[
    BookFormat('mass', 'Mass-market paperback', 0.175, _mmPerPage, 0.0),
    BookFormat('trade', 'Trade paperback', 0.203, _mmPerPage, 0.0),
    BookFormat('a5', 'A5', 0.210, _mmPerPage, 0.0),
    BookFormat('b5soft', 'B5 softcover', 0.250, _mmPerPage, 0.0),
    BookFormat('hardcover', 'Hardcover', 0.235, _mmPerPage, 5.0),
    BookFormat('a4', 'A4', 0.297, _mmPerPage, 0.0),
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

  // Defaults when no preset is chosen — the measured B5/default curve.
  static const double _defaultMmPerPage = _mmPerPage;
  static const double _defaultCoverMm = 0.0;
  static const double _minThickness = 0.003;
  static const double _maxThickness = 0.15;

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
