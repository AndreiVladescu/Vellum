import 'package:flutter/gestures.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// Back and forward for the mouse's side buttons, and for Alt+Left/Right.
///
/// **Why forward needs bookkeeping at all.** `Navigator` has a back stack and
/// nothing else: a popped route is disposed, so "forward" cannot mean *resume
/// that route*. What it can mean is *build that page again* — and a
/// [MaterialPageRoute] keeps its `builder`, which is a closure over the things
/// the page needed. Catching the builder as the route pops and pushing a fresh
/// route with it gives the browser behaviour people expect, without routing
/// every `push` in the app through a registry.
///
/// The consequence, which is the honest one: forward *rebuilds* the page rather
/// than restoring it. You return to the same book, not to the same scroll
/// position. Dialogs and sheets are not [MaterialPageRoute]s and are left out
/// entirely, which is right — nobody means "reopen that dialog".
class NavigationHistory extends NavigatorObserver {
  /// Pages gone back from, newest last. Bounded because each entry pins a
  /// closure — and its captures — alive.
  final List<WidgetBuilder> _forwardPages = [];
  static const _limit = 20;

  /// Sections (the shell's tabs) behind and ahead of where we are.
  final List<int> _behind = [];
  final List<int> _ahead = [];

  /// Wired up by the shell, which owns the selected tab.
  void Function(int section)? applySection;
  int Function()? currentSection;

  /// The builder being replayed right now, so its own push isn't mistaken for a
  /// new one and doesn't wipe the rest of the forward stack.
  WidgetBuilder? _replaying;

  @override
  void didPop(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! MaterialPageRoute) return;
    _forwardPages.add(route.builder);
    if (_forwardPages.length > _limit) _forwardPages.removeAt(0);
  }

  @override
  void didPush(Route<dynamic> route, Route<dynamic>? previousRoute) {
    if (route is! MaterialPageRoute) return;
    if (identical(route.builder, _replaying)) {
      _replaying = null;
      return;
    }
    // Going somewhere new abandons the forward history, exactly as a browser
    // does — the alternative is a forward button that jumps to a page you have
    // no memory of asking for.
    _forwardPages.clear();
  }

  /// Records that the shell is moving away from [previous].
  void recordSection(int previous) {
    _behind.add(previous);
    _ahead.clear();
  }

  /// A page if there is one to close, otherwise the section behind this one.
  ///
  /// [target] is only for tests; in the app the observer already knows the
  /// navigator it was installed on, which is the one thing `Navigator.of` can't
  /// find from `MaterialApp.builder` — that context sits *above* the navigator.
  Future<void> back([NavigatorState? target]) async {
    final nav = target ?? navigator;
    if (nav != null && await nav.maybePop()) return;
    final apply = applySection;
    final current = currentSection;
    if (apply == null || current == null || _behind.isEmpty) return;
    _ahead.add(current());
    apply(_behind.removeLast());
  }

  void forward([NavigatorState? target]) {
    final nav = target ?? navigator;
    if (nav != null && _forwardPages.isNotEmpty) {
      final builder = _forwardPages.removeLast();
      _replaying = builder;
      nav.push(MaterialPageRoute<void>(builder: builder));
      return;
    }
    final apply = applySection;
    final current = currentSection;
    if (apply == null || current == null || _ahead.isEmpty) return;
    _behind.add(current());
    apply(_ahead.removeLast());
  }
}

/// Wraps the app so the mouse's side buttons and Alt+arrows navigate.
///
/// Both, not one: the side buttons are what a hand reaches for, but whether they
/// arrive at all is up to the platform — the Linux embedder in particular has
/// not always forwarded them — and Alt+Left/Right is the keyboard equivalent
/// every desktop already agrees on.
class MouseNavigation extends StatelessWidget {
  const MouseNavigation({
    super.key,
    required this.history,
    required this.child,
  });

  final NavigationHistory history;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return CallbackShortcuts(
      bindings: {
        const SingleActivator(LogicalKeyboardKey.arrowLeft, alt: true):
            history.back,
        const SingleActivator(LogicalKeyboardKey.arrowRight, alt: true):
            history.forward,
      },
      child: Focus(
        // Not autofocus: stealing focus from a text field to serve a shortcut
        // that only fires with Alt held would be a bad trade. `canRequestFocus:
        // false` keeps this node purely a place for the bindings to live, and
        // key events still bubble up to it.
        canRequestFocus: false,
        child: Listener(onPointerDown: _onPointer, child: child),
      ),
    );
  }

  void _onPointer(PointerDownEvent event) {
    // `buttons` is a bitfield of what is held; the side buttons come through as
    // their own bits rather than as a primary press.
    if (event.buttons & kBackMouseButton != 0) {
      history.back();
    } else if (event.buttons & kForwardMouseButton != 0) {
      history.forward();
    }
  }
}
