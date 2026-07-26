import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Page background and text colour while reading (plan 5 #23).
///
/// Separate from the app's own light/dark theme on purpose: the reader is where
/// people sit for two hours, and sepia at midday with a dark app — or the reverse
/// — is a legitimate combination.
enum ReaderTheme {
  light('Light', Color(0xFFFDFDFB), Color(0xFF1A1A1A)),
  sepia('Sepia', Color(0xFFF4ECD8), Color(0xFF3B3229)),
  grey('Grey', Color(0xFFD8D8D4), Color(0xFF23231F)),
  dark('Dark', Color(0xFF14161A), Color(0xFFD7D9DD));

  const ReaderTheme(this.label, this.background, this.foreground);

  final String label;
  final Color background;
  final Color foreground;
}

/// Type family for EPUB body text. Bundled families only — a reader that offers
/// fonts it can't render is worse than one that offers three that always work.
enum ReaderFont {
  serif('Serif', 'serif'),
  sans('Sans', 'sans-serif'),
  mono('Monospace', 'monospace');

  const ReaderFont(this.label, this.family);

  final String label;

  /// A generic CSS/Flutter family name, resolved by the platform. Deliberately
  /// generic: shipping font files would add megabytes to every build for a
  /// preference three taps away.
  final String family;
}

/// How a PDF page is fitted to the viewport.
enum PdfFit {
  width('Fit width'),
  page('Fit page');

  const PdfFit(this.label);

  final String label;
}

/// Reader preferences, persisted and shared by both readers (plan 5 #23).
///
/// Deliberately one store rather than per-format ones: theme, margins and
/// distraction-free mode mean the same thing in a PDF and an EPUB, and a reader
/// who sets sepia once should not have to set it twice. The format-specific
/// settings (typography for EPUB, fit/night mode for PDF) simply go unread by the
/// other reader.
///
/// These control the *book's* type, never the app's — the UI keeps following the
/// system text scale.
class ReaderSettings extends ChangeNotifier {
  ReaderSettings._(this._prefs);

  static Future<ReaderSettings> load() async =>
      ReaderSettings._(await SharedPreferences.getInstance());

  final SharedPreferences _prefs;

  static const _themeKey = 'reader.theme';
  static const _fontKey = 'reader.font';
  static const _fontSizeKey = 'reader.fontSize';
  static const _lineHeightKey = 'reader.lineHeight';
  static const _measureKey = 'reader.measure';
  static const _pdfFitKey = 'reader.pdfFit';
  static const _nightModeKey = 'reader.pdfNightMode';
  static const _immersiveKey = 'reader.immersive';

  ReaderTheme get theme {
    final stored = _prefs.getString(_themeKey);
    return ReaderTheme.values.where((t) => t.name == stored).firstOrNull ??
        ReaderTheme.light;
  }

  Future<void> setTheme(ReaderTheme value) async {
    await _prefs.setString(_themeKey, value.name);
    notifyListeners();
  }

  ReaderFont get font {
    final stored = _prefs.getString(_fontKey);
    return ReaderFont.values.where((f) => f.name == stored).firstOrNull ??
        ReaderFont.serif;
  }

  Future<void> setFont(ReaderFont value) async {
    await _prefs.setString(_fontKey, value.name);
    notifyListeners();
  }

  /// Body text size in logical pixels. Clamped to a range that stays readable
  /// and still lays out — 40pt text in a 300pt column is not a feature.
  static const minFontSize = 12.0;
  static const maxFontSize = 32.0;

  double get fontSize =>
      (_prefs.getDouble(_fontSizeKey) ?? 17.0).clamp(minFontSize, maxFontSize);

  Future<void> setFontSize(double value) async {
    await _prefs.setDouble(
        _fontSizeKey, value.clamp(minFontSize, maxFontSize).toDouble());
    notifyListeners();
  }

  static const minLineHeight = 1.1;
  static const maxLineHeight = 2.2;

  double get lineHeight => (_prefs.getDouble(_lineHeightKey) ?? 1.5)
      .clamp(minLineHeight, maxLineHeight);

  Future<void> setLineHeight(double value) async {
    await _prefs.setDouble(
        _lineHeightKey, value.clamp(minLineHeight, maxLineHeight).toDouble());
    notifyListeners();
  }

  /// Maximum line length in logical pixels — the "measure". A full-width line on
  /// a 27-inch monitor is unreadable however good the type is.
  static const minMeasure = 420.0;
  static const maxMeasure = 1100.0;

  double get measure =>
      (_prefs.getDouble(_measureKey) ?? 720.0).clamp(minMeasure, maxMeasure);

  Future<void> setMeasure(double value) async {
    await _prefs.setDouble(
        _measureKey, value.clamp(minMeasure, maxMeasure).toDouble());
    notifyListeners();
  }

  PdfFit get pdfFit {
    final stored = _prefs.getString(_pdfFitKey);
    return PdfFit.values.where((f) => f.name == stored).firstOrNull ??
        PdfFit.width;
  }

  Future<void> setPdfFit(PdfFit value) async {
    await _prefs.setString(_pdfFitKey, value.name);
    notifyListeners();
  }

  /// Night mode for PDFs, which are pre-rendered pages the reader theme can't
  /// restyle — the only way to darken one is to filter the raster.
  bool get pdfNightMode => _prefs.getBool(_nightModeKey) ?? false;

  Future<void> setPdfNightMode(bool value) async {
    await _prefs.setBool(_nightModeKey, value);
    notifyListeners();
  }

  /// Hide the app bar and controls until tapped.
  bool get immersive => _prefs.getBool(_immersiveKey) ?? false;

  Future<void> setImmersive(bool value) async {
    await _prefs.setBool(_immersiveKey, value);
    notifyListeners();
  }

  /// Body text style for the EPUB reader, from the current settings and theme.
  TextStyle bodyTextStyle() => TextStyle(
        fontFamily: font.family,
        fontSize: fontSize,
        height: lineHeight,
        color: theme.foreground,
      );
}

/// The colour filter that turns a rendered PDF page into night mode.
///
/// Not a naive invert: a plain inversion turns white paper into pure black and,
/// worse, turns photographs into negatives. This inverts luminance while pulling
/// the result toward a warm near-black/near-grey — dark enough to read in bed,
/// without the harsh contrast or the blue cast a straight `1 - x` gives.
const nightModeMatrix = <double>[
  // R'      G'      B'      A'  offset
  -0.90, -0.05, -0.05, 0, 235, //
  -0.05, -0.90, -0.05, 0, 230, //
  -0.05, -0.05, -0.90, 0, 220, //
  0, 0, 0, 1, 0, //
];
