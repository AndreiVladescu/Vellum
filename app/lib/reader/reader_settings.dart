import 'dart:ui' show PlatformDispatcher;

import 'package:flutter/material.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'translate/on_device.dart';
import 'translate/translation_backend.dart';

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

  /// The page colours you can choose. [dark] is not among them: it is what
  /// night mode looks like, not a paper colour.
  ///
  /// Offering both was offering the same thing twice — a dark page from here
  /// and a dark page from the switch, differing only in whether the pictures
  /// were greyed, which is not a distinction anyone should have to make.
  static const choices = [light, sepia, grey];

  /// Whether the page is dark enough that the book's own colours have to go.
  ///
  /// Measured rather than named, so a repalette can't quietly leave this
  /// behind: a heading whose stylesheet asked for near-black is invisible on a
  /// near-black page, whatever put it there.
  bool get isDark => background.computeLuminance() < 0.3;
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

/// How the PDF viewer moves through the document.
///
/// The two are genuinely different reading postures, not a cosmetic toggle:
/// [paged] is a book you turn, [scroll] is a document you run through looking
/// for something. Trying to serve both at once is what makes most PDF readers
/// feel wrong — a continuous scroll that snaps to pages fights your drag, and a
/// paged view you can nudge half a page leaves you reading across a seam.
enum PdfPageMode {
  paged('Pages', 'One page at a time'),
  scroll('Scrolling', 'Continuous, with a scrollbar');

  const PdfPageMode(this.label, this.description);

  final String label;
  final String description;
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

  static Future<ReaderSettings> load() async {
    final settings = ReaderSettings._(await SharedPreferences.getInstance());
    await settings._adoptNightMode();
    return settings;
  }

  /// Moves anyone who had chosen the Dark *page colour* onto night mode.
  ///
  /// The two did the same job, so Dark is no longer offered — but a stored
  /// `dark` would otherwise fall through to Light, and someone who reads at
  /// night would open their book to a white page. They asked for a dark page;
  /// this is where a dark page lives now.
  Future<void> _adoptNightMode() async {
    if (_prefs.getString(_themeKey) != ReaderTheme.dark.name) return;
    await _prefs.setBool(_nightModeKey, true);
    await _prefs.remove(_themeKey);
  }

  final SharedPreferences _prefs;

  static const _themeKey = 'reader.theme';
  static const _fontKey = 'reader.font';
  static const _fontSizeKey = 'reader.fontSize';
  static const _lineHeightKey = 'reader.lineHeight';
  static const _measureKey = 'reader.measure';
  static const _pdfFitKey = 'reader.pdfFit';
  static const _nightModeKey = 'reader.pdfNightMode';
  static const _immersiveKey = 'reader.immersive';
  static const _pdfModeKey = 'reader.pdfMode';
  static const _highlightColorKey = 'reader.highlightColor';
  // Translation (next features #12). The URL is what decides whether the
  // feature exists at all: no server, no button — the same rule the sync
  // server's own features follow.
  static const _translateUrlKey = 'reader.translate.url';
  static const _onDeviceTranslateKey = 'reader.translate.onDevice';
  static const _translateKeyKey = 'reader.translate.apiKey';
  static const _translateToKey = 'reader.translate.to';

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

  /// How a PDF is framed when it opens. **Fit page by default**: opening a
  /// book should show you the page, and fitting the width means arriving
  /// zoomed into the top third of it with no way to tell how much you are
  /// missing. Anyone who has already chosen keeps their choice — this only
  /// answers for someone who never went looking.
  PdfFit get pdfFit {
    final stored = _prefs.getString(_pdfFitKey);
    return PdfFit.values.where((f) => f.name == stored).firstOrNull ??
        PdfFit.page;
  }

  Future<void> setPdfFit(PdfFit value) async {
    await _prefs.setString(_pdfFitKey, value.name);
    notifyListeners();
  }

  /// Black paper, white type, pictures in grey — in both formats.
  ///
  /// A switch rather than a fourth page colour, because it is not only a
  /// colour: it greys out the pictures, and for a PDF it is a filter over a
  /// rendered page rather than a choice about how to draw one. It overrides the
  /// page colour while it is on.
  ///
  /// The stored key has always been `pdfNightMode` — it began as a PDF-only
  /// switch — and now the name matches again.
  bool get nightMode => _prefs.getBool(_nightModeKey) ?? false;

  Future<void> setNightMode(bool value) async {
    await _prefs.setBool(_nightModeKey, value);
    notifyListeners();
  }

  /// The page colours actually in force. [nightMode] brings its own, which is
  /// why [ReaderTheme.dark] still exists without being on offer.
  ReaderTheme get effectiveTheme => nightMode ? ReaderTheme.dark : theme;

  PdfPageMode get pdfMode {
    final stored = _prefs.getString(_pdfModeKey);
    return PdfPageMode.values.where((m) => m.name == stored).firstOrNull ??
        PdfPageMode.scroll;
  }

  Future<void> setPdfMode(PdfPageMode value) async {
    await _prefs.setString(_pdfModeKey, value.name);
    notifyListeners();
  }

  /// The highlighter currently in hand, as a full-opacity ARGB int.
  ///
  /// A *setting*, not a per-highlight question: a marker is an object you pick
  /// up once and then use, and asking for the colour on every highlight turns a
  /// one-tap gesture into a two-step dialogue. Stored raw rather than as an enum
  /// name so the palette can change without stranding the preference.
  int? get highlightColor => _prefs.getInt(_highlightColorKey);

  Future<void> setHighlightColor(int argb) async {
    await _prefs.setInt(_highlightColorKey, argb);
    notifyListeners();
  }

  /// Hide the app bar and controls until tapped.
  /// The LibreTranslate address, or empty when none is set.
  String get translateUrl => _prefs.getString(_translateUrlKey) ?? '';

  /// Whether translating is possible at all — a server named here, or a
  /// device translator this build has *and* the reader has turned on. No
  /// translate button appears until it is true, because a button that can only
  /// fail is worse than none.
  ///
  /// A translator installed on the machine deliberately does not count. Finding
  /// one means running a command, which is async and this is read while
  /// building; the old code drew the same line, and moving it would put a
  /// button on every desktop whether or not anything is installed.
  bool get canTranslate =>
      (onDeviceTranslationAvailable && useOnDeviceTranslation) ||
      translateUrl.trim().isNotEmpty;

  /// Whether to use the device's own translator, where this build has one.
  ///
  /// **Defaults to using it where the build has it**, which is what a build
  /// carrying ML Kit is for — a phone that has already paid the 17 MB should
  /// not also have to be told to use it. The switch is there for anyone who
  /// would rather it didn't run.
  ///
  /// In the free build there is no such translator, so this reads false
  /// whatever is stored and nothing acts on it.
  bool get useOnDeviceTranslation =>
      _prefs.getBool(_onDeviceTranslateKey) ?? onDeviceTranslationAvailable;

  Future<void> setUseOnDeviceTranslation(bool value) async {
    await _prefs.setBool(_onDeviceTranslateKey, value);
    notifyListeners();
  }

  String get translateApiKey => _prefs.getString(_translateKeyKey) ?? '';

  /// Where translations go, remembered between uses — someone reading out of
  /// German today will be reading out of German tomorrow. Defaults to the
  /// device's own language, falling back to English when it isn't one this app
  /// offers.
  TranslationLanguage get translateTo =>
      TranslationLanguage.byCode(_prefs.getString(_translateToKey)) ??
      TranslationLanguage.byCode(
          PlatformDispatcher.instance.locale.languageCode) ??
      const TranslationLanguage('en', 'English');

  Future<void> setTranslateServer({required String url, String? apiKey}) async {
    await _prefs.setString(_translateUrlKey, url.trim());
    await _prefs.setString(_translateKeyKey, (apiKey ?? '').trim());
    notifyListeners();
  }

  Future<void> setTranslateTo(TranslationLanguage value) async {
    await _prefs.setString(_translateToKey, value.code);
    notifyListeners();
  }

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
        color: effectiveTheme.foreground,
      );
}
