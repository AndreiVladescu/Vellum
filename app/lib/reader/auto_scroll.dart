/// The arithmetic behind the self-scroller (next features: "calculate how many
/// rows you read per second and have a self-scrolling feature which will scroll
/// for you slowly, continuously").
///
/// The two readers measure the same motion in different units. A PDF page is a
/// fixed thing on screen, so its speed is *pages a minute* — and the reader's
/// own recorded sittings already measure that, which is where the starting
/// speed comes from. An EPUB has no pages, only reflowed text, so its speed is
/// *lines a minute*: the row height is `fontSize × lineHeight`, which the
/// settings know exactly. Nothing here guesses a pace and calls it measured.
library;

/// Where a PDF starts when there is no measured pace to start from.
///
/// A page every quarter of a minute is a slow, comfortable read. Guessing is
/// unavoidable — but this is a starting point with a control under it, not a
/// number presented as your pace.
const defaultAutoScrollPagesPerMinute = 4.0;
const minAutoScrollPagesPerMinute = 0.5;
const maxAutoScrollPagesPerMinute = 30.0;

/// Where an EPUB starts: about 250 words a minute over lines of ten words,
/// which is an ordinary reading speed for prose.
const defaultAutoScrollLinesPerMinute = 25.0;
const minAutoScrollLinesPerMinute = 4.0;
const maxAutoScrollLinesPerMinute = 200.0;

/// How far the viewport should travel each second, in view pixels.
///
/// [unitHeightPixels] is the height of one unit *as drawn* — a PDF page times
/// the zoom, or one line of text at the current font size — so zooming in slows
/// the scroll to match. The same words go past per minute either way, which is
/// the point.
double autoScrollPixelsPerSecond({
  required double unitsPerMinute,
  required double unitHeightPixels,
}) {
  if (unitsPerMinute <= 0 || unitHeightPixels <= 0) return 0;
  return unitsPerMinute / 60 * unitHeightPixels;
}

double clampAutoScrollSpeed(
  double speed, {
  required double min,
  required double max,
}) => speed.isFinite ? speed.clamp(min, max) : min;

/// One press of slower/faster.
///
/// Proportional rather than a fixed step: a tenth of a page a minute matters at
/// 0.5 and is invisible at 20.
double stepAutoScrollSpeed(
  double speed, {
  required bool faster,
  required double min,
  required double max,
}) {
  final stepped = faster ? speed * 1.25 : speed / 1.25;
  // Two decimals at the slow end, where the steps are small, and one further
  // up — a speed readout of "7.8125" helps nobody.
  final rounded = stepped < 2
      ? (stepped * 100).round() / 100
      : (stepped * 10).round() / 10;
  return clampAutoScrollSpeed(rounded, min: min, max: max);
}

/// The speed as it is shown on the control: "6 pages/min", "0.75 pages/min".
String autoScrollSpeedLabel(double speed, String unit) {
  final fixed = speed < 2 ? speed.toStringAsFixed(2) : speed.toStringAsFixed(1);
  final trimmed = fixed.contains('.')
      ? fixed.replaceFirst(RegExp(r'0+$'), '').replaceFirst(RegExp(r'\.$'), '')
      : fixed;
  return '$trimmed $unit/min';
}

/// How many frames of no movement mean the document has run out, rather than a
/// momentary clamp. Half a second at 60 Hz: long enough not to trip on a
/// bounce, short enough that the scroller does not sit buzzing at the last page.
const autoScrollStuckFrames = 30;

/// Rounds a speed for storage, so the persisted value cannot drift by floating
/// point across sessions.
double roundAutoScrollSpeed(double speed) => (speed * 100).round() / 100;
