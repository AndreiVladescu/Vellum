import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/widgets/page_insets.dart';

/// Bottom sheets have to clear two different things, and only one of them is
/// visible while developing.
///
/// Typing in a sheet raises the keyboard, so the keyboard half gets written.
/// The gesture bar is the half nobody hits at a desk: it needs a phone drawing
/// edge-to-edge *and* nothing focused, which is precisely the state a sheet is
/// in when you go to press the button at the bottom of it. Reported against a
/// book's edit sheet, where the buttons sat underneath it.
void main() {
  /// Reads the helper under a MediaQuery describing a particular device state.
  Future<double> insetFor(
    WidgetTester tester, {
    required double keyboard,
    required double navBar,
  }) async {
    late double result;
    await tester.pumpWidget(MediaQuery(
      // `padding` is what survives of the system inset after the keyboard has
      // covered part of it — the engine computes it that way, so a raised
      // keyboard leaves nothing of the gesture bar for the sheet to dodge.
      data: MediaQueryData(
        viewInsets: EdgeInsets.only(bottom: keyboard),
        viewPadding: EdgeInsets.only(bottom: navBar),
        padding: EdgeInsets.only(bottom: keyboard > 0 ? 0 : navBar),
      ),
      child: Builder(builder: (context) {
        result = sheetBottomInset(context);
        return const SizedBox();
      }),
    ));
    return result;
  }

  testWidgets('with the keyboard down it clears the gesture bar',
      (tester) async {
    // The reported case: no keyboard, and the buttons hidden behind the bar.
    expect(await insetFor(tester, keyboard: 0, navBar: 48), 48);
  });

  testWidgets('with the keyboard up it clears the keyboard', (tester) async {
    expect(await insetFor(tester, keyboard: 300, navBar: 48), 300,
        reason: 'the bar is drawn over the keyboard, so it is not added twice');
  });

  testWidgets('on a device with neither it adds nothing', (tester) async {
    expect(await insetFor(tester, keyboard: 0, navBar: 0), 0);
  });

  test('no sheet pads for the keyboard alone', () {
    // The bug was five copies of the same half-right line, so the thing worth
    // pinning is that a sixth does not appear. `sheetBottomInset` is the only
    // place allowed to ask for the raw keyboard height.
    final offenders = <String>[];
    for (final file in Directory('lib').listSync(recursive: true)) {
      if (file is! File || !file.path.endsWith('.dart')) continue;
      if (file.path.endsWith('widgets/page_insets.dart')) continue;
      final lines = file.readAsLinesSync();
      for (var i = 0; i < lines.length; i++) {
        if (lines[i].contains('viewInsetsOf(context).bottom')) {
          offenders.add('${file.path}:${i + 1}');
        }
      }
    }
    expect(offenders, isEmpty,
        reason: 'use sheetBottomInset(context) so the gesture bar is counted');
  });
}
