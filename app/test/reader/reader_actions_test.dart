// How much of the reader's toolbar fits (8/23 report: "on a small screen the
// icons overflow the back arrow image").
//
// An AppBar gives its actions their intrinsic width and squeezes the *title*,
// so a row that is too long does not complain — it draws over the leading
// control. The arithmetic that stops that happening again is here, and the rule
// that matters is that nothing becomes unreachable: what does not fit is in the
// menu, not gone.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/reader_actions.dart';

void main() {
  group('what fits', () {
    test('everything, when there is room for everything', () {
      expect(
        fittingActions(width: 1200, reserved: kLeadingWidth, total: 9),
        9,
      );
    });

    test('one fewer than fits, so the menu has a slot of its own', () {
      // Room for exactly seven buttons: showing seven and hiding the eighth
      // where nothing can reach it is the failure being prevented.
      const width = kLeadingWidth + 7 * 48;
      expect(fittingActions(width: width, reserved: kLeadingWidth, total: 8), 6);
    });

    test('a phone with a counter in the bar', () {
      // 360dp, back arrow, page counter, nine actions.
      final shown = fittingActions(
        width: 360,
        reserved: kLeadingWidth + kCounterWidth,
        total: 9,
      );
      expect(shown, lessThan(9));
      expect(shown * 48 + 48, lessThanOrEqualTo(360 - kLeadingWidth - kCounterWidth),
          reason: 'the buttons and the menu together fit what is left');
    });

    test('a desktop shows the lot', () {
      expect(
        fittingActions(width: 1600, reserved: kLeadingWidth + kCounterWidth, total: 13),
        13,
      );
    });

    test('a menu that is always there costs a slot even when all fit', () {
      expect(
        fittingActions(width: 1200, reserved: 0, total: 3, alwaysMenu: true),
        3,
      );
      const tight = 4 * 48.0;
      expect(
        fittingActions(width: tight, reserved: 0, total: 4, alwaysMenu: true),
        3,
      );
    });

    test('a bar with no room shows nothing rather than a negative number', () {
      expect(fittingActions(width: 40, reserved: kLeadingWidth, total: 9), 0);
      expect(fittingActions(width: 0, reserved: 0, total: 9), 0);
      expect(fittingActions(width: 400, reserved: 0, total: 0), 0);
    });
  });

  group('the bar', () {
    List<ReaderAction> actions(int count) => [
          for (var i = 0; i < count; i++)
            ReaderAction(
              icon: Icons.star,
              label: 'Action $i',
              onPressed: () {},
            ),
        ];

    Future<void> pump(WidgetTester tester, double width,
        {int count = 9, List<PopupMenuEntry<VoidCallback?>> extras = const []}) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: MediaQueryData(size: Size(width, 800)),
          child: Scaffold(
            appBar: AppBar(
              // Explicit, because this Scaffold is the first route and would
              // otherwise have no leading control to overlap.
              leading: const BackButton(),
              title: const Text('A book with quite a long title'),
              actions: [
                ReaderActionBar(actions: actions(count), menuExtras: extras),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();
    }

    testWidgets('on a phone the last actions move into the menu',
        (tester) async {
      await pump(tester, 360);

      expect(find.byIcon(Icons.star), findsWidgets);
      expect(find.byType(PopupMenuButton<VoidCallback?>), findsOneWidget);

      await tester.tap(find.byType(PopupMenuButton<VoidCallback?>));
      await tester.pumpAndSettle();
      expect(find.text('Action 8'), findsOneWidget,
          reason: 'the last one is reachable, by name');
    });

    testWidgets('nothing is drawn over the back arrow', (tester) async {
      await pump(tester, 360);

      final leading = tester.getRect(find.byType(BackButton));
      final icons = find.byIcon(Icons.star);
      expect(icons, findsWidgets);
      for (var i = 0; i < icons.evaluate().length; i++) {
        expect(tester.getRect(icons.at(i)).left,
            greaterThanOrEqualTo(leading.right),
            reason: 'this is the reported bug, in one assertion');
      }
    });

    testWidgets('on a wide window there is no menu at all', (tester) async {
      await pump(tester, 1400, count: 6);

      expect(find.byIcon(Icons.star), findsNWidgets(6));
      expect(find.byType(PopupMenuButton<VoidCallback?>), findsNothing);
    });

    testWidgets('a disabled action is offered and greyed, not hidden',
        (tester) async {
      await tester.pumpWidget(MaterialApp(
        home: MediaQuery(
          data: const MediaQueryData(size: Size(360, 800)),
          child: Scaffold(
            appBar: AppBar(
              actions: [
                ReaderActionBar(actions: [
                  ...actions(8),
                  const ReaderAction(
                    icon: Icons.search,
                    label: 'Search in this book',
                    onPressed: null,
                  ),
                ]),
              ],
            ),
          ),
        ),
      ));
      await tester.pumpAndSettle();

      await tester.tap(find.byType(PopupMenuButton<VoidCallback?>));
      await tester.pumpAndSettle();
      expect(find.text('Search in this book'), findsOneWidget);
    });

    testWidgets('the standing menu entries are still there', (tester) async {
      await pump(tester, 360, extras: [
        PopupMenuItem(value: () {}, child: const Text('Go to page…')),
      ]);

      await tester.tap(find.byType(PopupMenuButton<VoidCallback?>));
      await tester.pumpAndSettle();
      expect(find.text('Go to page…'), findsOneWidget);
    });
  });
}
