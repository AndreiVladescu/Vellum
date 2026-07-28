// Back and forward from the mouse's side buttons.
//
// The part worth testing is the forward stack, because `Navigator` has no such
// concept: a popped route is disposed, so forward means *rebuild that page*,
// and the bookkeeping around when to throw that memory away is where this can
// go wrong.
import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/navigation_history.dart';

/// The app shell, near enough: a home page that can push named pages, with the
/// history installed as an observer and the mouse wrapper above it.
Widget _app(NavigationHistory history, {GlobalKey<NavigatorState>? navigator}) {
  return MaterialApp(
    navigatorKey: navigator,
    navigatorObservers: [history],
    builder: (context, child) =>
        MouseNavigation(history: history, child: child!),
    home: Builder(
      builder: (context) => Scaffold(
        body: Center(
          child: TextButton(
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute<void>(
                builder: (_) => const Scaffold(body: Text('Second')),
              ),
            ),
            child: const Text('Home'),
          ),
        ),
      ),
    ),
  );
}

/// A press of a mouse side button, as the framework reports one.
Future<void> _sideButton(WidgetTester tester, int button) async {
  final center = tester.getCenter(find.byType(Scaffold).first);
  GestureBinding.instance.handlePointerEvent(
    PointerDownEvent(position: center, buttons: button, kind: PointerDeviceKind.mouse),
  );
  GestureBinding.instance.handlePointerEvent(
    PointerUpEvent(position: center, kind: PointerDeviceKind.mouse),
  );
  await tester.pumpAndSettle();
}

void main() {
  testWidgets('the back button closes the page, forward reopens it',
      (tester) async {
    final history = NavigationHistory();
    await tester.pumpWidget(_app(history));

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    expect(find.text('Second'), findsOneWidget);

    await _sideButton(tester, kBackMouseButton);
    expect(find.text('Second'), findsNothing, reason: 'back closed it');

    await _sideButton(tester, kForwardMouseButton);
    expect(find.text('Second'), findsOneWidget, reason: 'forward rebuilt it');
  });

  testWidgets('forward does nothing once you go somewhere else',
      (tester) async {
    // Browser behaviour: a new page abandons the forward history, or forward
    // jumps to somewhere you have no memory of asking for.
    final history = NavigationHistory();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(history, navigator: navigator));

    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();
    await _sideButton(tester, kBackMouseButton);

    navigator.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Scaffold(body: Text('Elsewhere'))),
    );
    await tester.pumpAndSettle();
    await _sideButton(tester, kBackMouseButton);
    await _sideButton(tester, kForwardMouseButton);

    expect(find.text('Elsewhere'), findsOneWidget);
    expect(find.text('Second'), findsNothing);
  });

  testWidgets('replaying a page does not wipe the rest of the forward history',
      (tester) async {
    final history = NavigationHistory();
    final navigator = GlobalKey<NavigatorState>();
    await tester.pumpWidget(_app(history, navigator: navigator));

    for (final label in ['One', 'Two']) {
      navigator.currentState!.push(
        MaterialPageRoute<void>(builder: (_) => Scaffold(body: Text(label))),
      );
      await tester.pumpAndSettle();
    }
    await _sideButton(tester, kBackMouseButton); // back off Two
    await _sideButton(tester, kBackMouseButton); // back off One
    expect(find.text('Home'), findsOneWidget);

    await _sideButton(tester, kForwardMouseButton);
    expect(find.text('One'), findsOneWidget);
    await _sideButton(tester, kForwardMouseButton);
    expect(find.text('Two'), findsOneWidget,
        reason: 'the second step forward survived the first');
  });

  testWidgets('a plain left click navigates nowhere', (tester) async {
    final history = NavigationHistory();
    await tester.pumpWidget(_app(history));
    await tester.tap(find.text('Home'));
    await tester.pumpAndSettle();

    await _sideButton(tester, kPrimaryMouseButton);
    expect(find.text('Second'), findsOneWidget);
  });

  group('sections', () {
    test('back and forward step through the tabs you visited', () async {
      // The shell owns the tab; the history only remembers the order.
      final history = NavigationHistory();
      var tab = 0;
      history.currentSection = () => tab;
      history.applySection = (section) => tab = section;

      history.recordSection(0);
      tab = 1;
      history.recordSection(1);
      tab = 2;

      final navigator = _NoPopNavigator();
      await history.back(navigator);
      expect(tab, 1);
      await history.back(navigator);
      expect(tab, 0);
      history.forward(navigator);
      expect(tab, 1);
      history.forward(navigator);
      expect(tab, 2);
      history.forward(navigator);
      expect(tab, 2, reason: 'nothing further ahead');
    });

    test('going somewhere new abandons what was ahead', () async {
      final history = NavigationHistory();
      var tab = 0;
      history.currentSection = () => tab;
      history.applySection = (section) => tab = section;

      history.recordSection(0);
      tab = 1;
      final navigator = _NoPopNavigator();
      await history.back(navigator);
      expect(tab, 0);

      history.recordSection(0); // a fresh move
      tab = 1;
      history.forward(navigator);
      expect(tab, 1, reason: 'the old forward entry was dropped');
    });
  });
}

/// A navigator with nothing to pop, so `back` falls through to the sections.
class _NoPopNavigator implements NavigatorState {
  @override
  Future<bool> maybePop<T extends Object?>([T? result]) async => false;

  @override
  String toString({DiagnosticLevel minLevel = DiagnosticLevel.info}) =>
      '_NoPopNavigator';

  @override
  dynamic noSuchMethod(Invocation invocation) =>
      throw UnimplementedError('${invocation.memberName} is not needed here');
}
