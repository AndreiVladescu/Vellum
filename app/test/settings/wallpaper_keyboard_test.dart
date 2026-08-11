import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/settings/wallpaper.dart';

/// The fern wallpaper against an open keyboard.
///
/// The fronds are painted from the bottom-left of their canvas, which on
/// Android is the Scaffold body — and that shrinks to sit above the keyboard,
/// so the ferns climbed the page every time someone typed. A wall does not
/// move when a keyboard appears.
///
/// **The inset has to come from the view, not the MediaQuery.** A Scaffold with
/// `resizeToAvoidBottomInset` applies the inset by shrinking its body and then
/// zeroes it for descendants, so `MediaQuery.viewInsetsOf` inside the body
/// always reads 0. A first attempt at this fix did exactly that and changed
/// nothing on a real phone; these tests drive `tester.view` so they would have
/// caught it.
void main() {
  FernPainter painterIn(WidgetTester tester) => tester
      .widgetList<CustomPaint>(find.byType(CustomPaint))
      .map((w) => w.painter)
      .whereType<FernPainter>()
      .single;

  Future<void> pumpWallpaper(WidgetTester tester) => tester.pumpWidget(
        const Directionality(
          textDirection: TextDirection.ltr,
          child: WallpaperBackground(
            wallpaper: Wallpaper.fern,
            child: SizedBox.expand(),
          ),
        ),
      );

  testWidgets('the keyboard height reaches the painter', (tester) async {
    tester.view.devicePixelRatio = 2;
    tester.view.viewInsets = const FakeViewPadding(bottom: 600); // 300 logical
    addTearDown(tester.view.reset);

    await pumpWallpaper(tester);
    expect(painterIn(tester).bottomInset, 300);
  });

  testWidgets('a Scaffold body still sees it', (tester) async {
    // The real arrangement: the wallpaper lives inside a Scaffold, which is
    // exactly where the MediaQuery route was silently zeroed.
    tester.view.devicePixelRatio = 2;
    tester.view.viewInsets = const FakeViewPadding(bottom: 600);
    addTearDown(tester.view.reset);

    await tester.pumpWidget(const MaterialApp(
      home: Scaffold(
        body: WallpaperBackground(
          wallpaper: Wallpaper.fern,
          child: SizedBox.expand(),
        ),
      ),
    ));
    expect(painterIn(tester).bottomInset, 300,
        reason: 'the Scaffold zeroes MediaQuery insets for its body');
  });

  testWidgets('with no keyboard it is zero', (tester) async {
    await pumpWallpaper(tester);
    expect(painterIn(tester).bottomInset, 0);
  });

  test('a changed keyboard height repaints', () {
    // Without this the fronds stay where the last paint put them, which is the
    // same bug wearing a different hat.
    const closed = FernPainter(color: Color(0xFF000000));
    const open = FernPainter(color: Color(0xFF000000), bottomInset: 300);
    expect(open.shouldRepaint(closed), isTrue);
    expect(open.shouldRepaint(open), isFalse);
  });
}
