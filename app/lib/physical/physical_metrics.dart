import 'package:flutter/material.dart';

import '../data/database.dart';
import '../shelf/spine_style.dart';

/// Measured calibration: a 720-page book is 40 mm thick, i.e. 18 pages per
/// millimetre → ~0.0556 mm per page, with no separate cover base. The default
/// and softcover presets use exactly this.
///
/// It replaced an earlier measurement (a 367-page B5 at 21 mm, ~0.0572 mm per
/// page) taken from a different book. The two are within 3% of each other,
/// which is about what paper stock varies by anyway — this one is written down
/// because it is the one somebody actually held a ruler against.
const double _mmPerPage = 40.0 / 720.0;

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

  // Defaults when no preset is chosen — the measured default curve.
  static const double _defaultMmPerPage = _mmPerPage;
  static const double _defaultCoverMm = 0.0;

  /// **Nothing is bigger than A3** (297 × 420 mm), in either direction.
  ///
  /// A book on a shelf is drawn thickness-wide and trim-high, and until now
  /// only the *computed* thickness was bounded: an explicit override returned
  /// before the clamp and the height was never clamped at all, so a number
  /// typed into the resize dialog went straight through. Reported with a
  /// screenshot of a book several times the size of the bookcase it stood in
  /// (issue #10 item 6).
  ///
  /// The ceiling is deliberately generous rather than tight: an atlas or a
  /// folio really is that big, and a limit that refuses real books would be
  /// its own bug. What it rules out is the order of magnitude.
  static const double maxHeight = 0.420;
  static const double maxThickness = 0.297;

  static const double _minThickness = 0.003;

  /// No book is thinner than a pamphlet or shorter than a passport, and a zero
  /// or negative size would draw as nothing at all.
  static const double minHeight = 0.05;

  /// Spine thickness in metres. Priority: explicit [override] → [format] curve
  /// from the page count → the default curve. Always within bounds — see
  /// [maxThickness]; an override is a preference, not permission.
  static double thickness(Book book, {BookFormat? format, double? override}) {
    if (override != null) {
      return override.clamp(_minThickness, maxThickness);
    }
    final pages = (book.pageCount ?? 220).toDouble();
    final mmPerPage = format?.mmPerPage ?? _defaultMmPerPage;
    final coverMm = format?.coverMm ?? _defaultCoverMm;
    final metres = (pages * mmPerPage + coverMm) / 1000;
    return metres.clamp(_minThickness, maxThickness);
  }

  /// Spine height in metres. Priority: [override] → [format] trim → default,
  /// and bounded the same way.
  static double height(Book book, {BookFormat? format, double? override}) =>
      (override ?? format?.heightM ?? defaultHeight)
          .clamp(minHeight, maxHeight);

  /// Reuse the generated spine palette so a book looks the same everywhere.
  static Color color(Book book) =>
      SpineStyle.fromJson(book.spineStyle, title: book.title).color;

  static Color textColor(Book book) =>
      SpineStyle.fromJson(book.spineStyle, title: book.title).textColor;

  /// The same palette, for a book this device holds no row for — a spine in a
  /// room someone shared (next features #9). Derived from the title, exactly as
  /// a generated spine is, so the room looks the way its owner sees it.
  static Color colorForTitle(String title) =>
      SpineStyle.generate(title: title).color;
}
