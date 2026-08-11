import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/settings/wallpaper.dart';

/// The fern wallpaper against an open keyboard.
///
/// The fronds are painted from the bottom-left corner of whatever canvas they
/// are handed — and on Android that canvas is the Scaffold body, which shrinks
/// to sit above the keyboard. So every time someone typed, the ferns climbed
/// the page. A wall does not move when a keyboard appears.
///
/// The fix is one line in `paint` (`size.height + bottomInset`) plus the widget
/// reading the inset and passing it down. The line is reviewable; what needs a
/// test is the wiring, because a painter quietly given `0` looks exactly like a
/// painter that was never told.
void main() {
  testWidgets('the widget hands the keyboard height to the painter',
      (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(viewInsets: EdgeInsets.only(bottom: 300)),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: WallpaperBackground(
          wallpaper: Wallpaper.fern,
          child: SizedBox.expand(),
        ),
      ),
    ));

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<FernPainter>()
        .single;
    expect(painter.bottomInset, 300);
  });

  testWidgets('with no keyboard it is zero', (tester) async {
    await tester.pumpWidget(const MediaQuery(
      data: MediaQueryData(),
      child: Directionality(
        textDirection: TextDirection.ltr,
        child: WallpaperBackground(
          wallpaper: Wallpaper.fern,
          child: SizedBox.expand(),
        ),
      ),
    ));

    final painter = tester
        .widgetList<CustomPaint>(find.byType(CustomPaint))
        .map((w) => w.painter)
        .whereType<FernPainter>()
        .single;
    expect(painter.bottomInset, 0);
  });

  test('a changed keyboard height repaints', () {
    // Without this the fronds would stay where the last paint put them, which
    // is the same bug wearing a different hat.
    const closed = FernPainter(color: Color(0xFF000000));
    const open = FernPainter(color: Color(0xFF000000), bottomInset: 300);
    expect(open.shouldRepaint(closed), isTrue);
    expect(open.shouldRepaint(open), isFalse);
  });
}
