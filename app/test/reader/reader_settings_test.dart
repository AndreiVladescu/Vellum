// Reader comfort settings (plan 5 #23). These are the app's only preferences
// that deliberately do *not* follow the system text scale — they set the book's
// type, not the UI's — so the clamps and the persistence are what matter.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:vellum/reader/dark_pages.dart';
import 'package:vellum/reader/reader_settings.dart';
import 'package:vellum/reader/reader_settings_sheet.dart';

void main() {
  setUp(() => SharedPreferences.setMockInitialValues({}));

  test('defaults are the comfortable ones, not the extremes', () async {
    final settings = await ReaderSettings.load();
    expect(settings.theme, ReaderTheme.light);
    expect(settings.font, ReaderFont.serif);
    expect(settings.fontSize, 17.0);
    expect(settings.lineHeight, 1.5);
    expect(settings.measure, 720.0);
    expect(settings.pdfFit, PdfFit.width);
    expect(settings.darkPages, false);
    expect(settings.immersive, false);
  });

  test('every setting round-trips through preferences', () async {
    final settings = await ReaderSettings.load();
    await settings.setTheme(ReaderTheme.sepia);
    await settings.setFont(ReaderFont.sans);
    await settings.setFontSize(21);
    await settings.setLineHeight(1.8);
    await settings.setMeasure(900);
    await settings.setPdfFit(PdfFit.page);
    await settings.setDarkPages(true);
    await settings.setImmersive(true);

    // A second load is the next launch.
    final reloaded = await ReaderSettings.load();
    expect(reloaded.theme, ReaderTheme.sepia);
    expect(reloaded.font, ReaderFont.sans);
    expect(reloaded.fontSize, 21);
    expect(reloaded.lineHeight, 1.8);
    expect(reloaded.measure, 900);
    expect(reloaded.pdfFit, PdfFit.page);
    expect(reloaded.darkPages, true);
    expect(reloaded.immersive, true);
  });

  test('out-of-range values are clamped, not stored as given', () async {
    final settings = await ReaderSettings.load();
    await settings.setFontSize(500);
    await settings.setLineHeight(0);
    await settings.setMeasure(10);

    expect(settings.fontSize, ReaderSettings.maxFontSize);
    expect(settings.lineHeight, ReaderSettings.minLineHeight);
    expect(settings.measure, ReaderSettings.minMeasure);
    // And the clamp survives a reload — the bad value never reached storage.
    final reloaded = await ReaderSettings.load();
    expect(reloaded.fontSize, ReaderSettings.maxFontSize);
  });

  test('a value stored by an older/newer build is clamped on read', () async {
    SharedPreferences.setMockInitialValues({
      'reader.fontSize': 999.0,
      'reader.measure': 1.0,
      'reader.theme': 'a-theme-that-no-longer-exists',
    });
    final settings = await ReaderSettings.load();
    expect(settings.fontSize, ReaderSettings.maxFontSize);
    expect(settings.measure, ReaderSettings.minMeasure);
    expect(settings.theme, ReaderTheme.light, reason: 'unknown falls back');
  });

  test('changing a setting notifies, so an open reader restyles', () async {
    final settings = await ReaderSettings.load();
    var notifications = 0;
    settings.addListener(() => notifications++);
    await settings.setTheme(ReaderTheme.dark);
    await settings.setFontSize(20);
    expect(notifications, 2);
  });

  test('bodyTextStyle reflects the current settings and theme', () async {
    final settings = await ReaderSettings.load();
    await settings.setTheme(ReaderTheme.dark);
    await settings.setFont(ReaderFont.mono);
    await settings.setFontSize(19);
    await settings.setLineHeight(1.7);

    final style = settings.bodyTextStyle();
    expect(style.fontFamily, 'monospace');
    expect(style.fontSize, 19);
    expect(style.height, 1.7);
    expect(style.color, ReaderTheme.dark.foreground);
  });

  test('every theme is legible — background and foreground really differ', () {
    // Cheap guard against a future palette tweak producing dark-on-dark.
    for (final theme in ReaderTheme.values) {
      final delta =
          (theme.background.computeLuminance() - theme.foreground.computeLuminance())
              .abs();
      expect(delta, greaterThan(0.4), reason: '${theme.label} has poor contrast');
    }
  });

  test('the dark-pages matrix inverts the paper and drains the colour', () {
    // Stated as arithmetic: white must come out near black, black near white,
    // and a saturated colour must come out near grey — the point of draining it
    // is that a photograph reads as a photograph instead of as a negative.
    double channel(int row, List<double> rgb) =>
        darkPageMatrix[row * 5 + 0] * rgb[0] +
        darkPageMatrix[row * 5 + 1] * rgb[1] +
        darkPageMatrix[row * 5 + 2] * rgb[2] +
        darkPageMatrix[row * 5 + 4];

    final white = [255.0, 255.0, 255.0];
    final black = [0.0, 0.0, 0.0];
    expect(channel(0, white), lessThan(40), reason: 'paper goes dark');
    expect(channel(0, black), greaterThan(200), reason: 'ink goes light');

    // A strong red comes out as a grey: the three channels end up close
    // together, and the residual tilt is still in the direction inversion
    // implies (red in, cyan-ish out) rather than an arbitrary hue shift.
    final red = [220.0, 20.0, 20.0];
    final out = [channel(0, red), channel(1, red), channel(2, red)];
    final spread = out.reduce((a, b) => a > b ? a : b) -
        out.reduce((a, b) => a < b ? a : b);
    expect(spread, lessThan(30),
        reason: 'a saturated colour lands within 12% of neutral grey');
    expect(out[0], lessThan(out[1]), reason: 'what tilt remains is an inversion');
  });

  test('dark pages override the page colour rather than fighting it', () async {
    final settings = await ReaderSettings.load();
    await settings.setTheme(ReaderTheme.sepia);
    expect(settings.effectiveTheme, ReaderTheme.sepia);
    await settings.setDarkPages(true);
    expect(settings.effectiveTheme, ReaderTheme.dark,
        reason: 'sepia-with-dark-pages means nothing');
    expect(settings.theme, ReaderTheme.sepia,
        reason: 'the choice is remembered for when dark pages go off again');
  });

  test('the picture filter removes colour without touching white type', () {
    double channel(int row, List<double> rgb) =>
        greyImageMatrix[row * 5 + 0] * rgb[0] +
        greyImageMatrix[row * 5 + 1] * rgb[1] +
        greyImageMatrix[row * 5 + 2] * rgb[2] +
        greyImageMatrix[row * 5 + 4];

    final green = [40.0, 200.0, 60.0];
    final out = [channel(0, green), channel(1, green), channel(2, green)];
    expect(out[0], closeTo(out[1], 0.01));
    expect(out[1], closeTo(out[2], 0.01), reason: 'all colour is gone');
    expect(out[0], lessThan(200), reason: 'and it is dimmed a little');
  });

  testWidgets('the sheet shows only the controls that apply to the format',
      (tester) async {
    late ReaderSettings settings;
    await tester.runAsync(() async => settings = await ReaderSettings.load());

    // EPUB: typography, no PDF options.
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderSettingsSheet(
          settings: settings,
          showTypography: true,
          showPdfOptions: false,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Typeface'), findsOneWidget);
    expect(find.text('Text size'), findsOneWidget);
    expect(find.text('Dark pages'), findsOneWidget,
        reason: 'dark pages apply to both formats');

    // PDF: fit and night mode, no typography (a rendered page can't reflow).
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderSettingsSheet(
          settings: settings,
          showTypography: false,
          showPdfOptions: true,
        ),
      ),
    ));
    await tester.pump();
    expect(find.text('Typeface'), findsNothing);
    expect(find.text('Dark pages'), findsOneWidget);
    expect(find.text('Page fit'), findsOneWidget);
    // The shared row is present either way.
    expect(find.text('Hide controls while reading'), findsOneWidget);
  });

  testWidgets('picking a theme in the sheet persists it', (tester) async {
    late ReaderSettings settings;
    await tester.runAsync(() async => settings = await ReaderSettings.load());
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ReaderSettingsSheet(
          settings: settings,
          showTypography: true,
          showPdfOptions: false,
        ),
      ),
    ));
    await tester.pump();

    await tester.tap(find.text('Sepia'));
    await tester.pump();

    expect(settings.theme, ReaderTheme.sepia);
  });
}
