import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Back unwinds what is on top of the page before leaving it.
///
/// Reported on Android: searching the library fills the screen with a
/// keyboard, and Back — what everyone reaches for to get it out of the way —
/// left the page instead, taking the search with it.
///
/// The shape is a `PopScope` whose `canPop` is false while the field has
/// focus, plus a listener so a focus change actually rebuilds. That listener
/// is the part worth pinning: without it `canPop` holds whatever it was when
/// the frame was built, and the fix silently does nothing.
void main() {
  /// A miniature of the library page's arrangement: a focusable field, a
  /// PopScope that guards on its focus, and a rebuild on focus change.
  Widget harness({required VoidCallback onBlocked, required FocusNode focus}) {
    return MaterialApp(
      home: _Guarded(focus: focus, onBlocked: onBlocked),
    );
  }

  // `PopScope` is generic, so `find.byType(PopScope)` matches nothing — the
  // instance is a `PopScope<Object?>`. Match on the runtime type instead.
  bool canPopOf(WidgetTester tester) {
    final scope = tester
        .widgetList(find.byWidgetPredicate((w) => w is PopScope))
        .cast<PopScope>()
        .single;
    return scope.canPop;
  }

  testWidgets('Back is blocked while the field has focus', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);
    var blocked = 0;

    await tester.pumpWidget(harness(onBlocked: () => blocked++, focus: focus));
    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    expect(focus.hasFocus, isTrue);

    expect(canPopOf(tester), isFalse, reason: 'the keyboard is showing');

    await _pressBack(tester);
    expect(blocked, 1, reason: 'handled here rather than popping');
    expect(focus.hasFocus, isFalse, reason: 'the keyboard was dismissed');
  });

  testWidgets('with nothing focused, Back is allowed through', (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);

    await tester.pumpWidget(harness(onBlocked: () {}, focus: focus));
    await tester.pump();

    expect(canPopOf(tester), isTrue);
  });

  testWidgets('focus changes rebuild, so canPop is never stale',
      (tester) async {
    final focus = FocusNode();
    addTearDown(focus.dispose);

    await tester.pumpWidget(harness(onBlocked: () {}, focus: focus));
    expect(canPopOf(tester), isTrue);

    await tester.tap(find.byType(TextField));
    await tester.pumpAndSettle();
    // Without the focus listener this would still read true — the bug the
    // listener exists to prevent.
    expect(canPopOf(tester), isFalse);
  });
}

Future<void> _pressBack(WidgetTester tester) async {
  await tester.binding.handlePopRoute();
  await tester.pumpAndSettle();
}

class _Guarded extends StatefulWidget {
  const _Guarded({required this.focus, required this.onBlocked});

  final FocusNode focus;
  final VoidCallback onBlocked;

  @override
  State<_Guarded> createState() => _GuardedState();
}

class _GuardedState extends State<_Guarded> {
  @override
  void initState() {
    super.initState();
    widget.focus.addListener(_rebuild);
  }

  @override
  void dispose() {
    widget.focus.removeListener(_rebuild);
    super.dispose();
  }

  void _rebuild() {
    if (mounted) setState(() {});
  }

  @override
  Widget build(BuildContext context) {
    return PopScope(
      canPop: !widget.focus.hasFocus,
      onPopInvokedWithResult: (didPop, _) {
        if (didPop) return;
        widget.onBlocked();
        widget.focus.unfocus();
      },
      child: Scaffold(
        appBar: AppBar(title: TextField(focusNode: widget.focus)),
        body: const SizedBox.expand(),
      ),
    );
  }
}
