// The night-mode wrapper must not change the shape of the widget tree.
//
// This is the bug behind "open a book, it's blank; open it again and it shows
// up". The reader's settings load asynchronously, so the first build has night
// mode off and the second — milliseconds later — may have it on. When the
// wrapper was `enabled ? ColorFiltered(child) : child`, that flip changed what
// sat above the viewer, so Flutter unmounted the old element and built a new
// one: the document was opened a second time (visible as two
// `PdfDocument initial load` lines in a device log) and the frame on screen
// belonged to the viewer that had just been thrown away.
//
// Nothing about the *colour* is asserted here. What matters is that the child
// keeps its State across the flip, because in the real tree that State owns an
// open PDF and your place in it.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/night_mode.dart';

/// A child that counts how many times it was built from scratch.
class _Counted extends StatefulWidget {
  const _Counted();

  static int inits = 0;

  @override
  State<_Counted> createState() => _CountedState();
}

class _CountedState extends State<_Counted> {
  @override
  void initState() {
    super.initState();
    _Counted.inits++;
  }

  @override
  Widget build(BuildContext context) => const SizedBox(width: 10, height: 10);
}

void main() {
  setUp(() => _Counted.inits = 0);

  testWidgets('turning night mode on keeps the child that was already there',
      (tester) async {
    Widget wrapped(bool enabled) => MaterialApp(
          home: nightModeWrap(enabled: enabled, child: const _Counted()),
        );

    await tester.pumpWidget(wrapped(false));
    expect(_Counted.inits, 1);

    // What the settings landing does to the reader.
    await tester.pumpWidget(wrapped(true));
    expect(
      _Counted.inits,
      1,
      reason: 'the child survived the flip — in the reader that child is the '
          'open document and the page you were on',
    );

    await tester.pumpWidget(wrapped(false));
    expect(_Counted.inits, 1, reason: 'and survives turning it off again');
  });

  testWidgets('the filter is present either way, so the tree keeps its shape',
      (tester) async {
    for (final enabled in [false, true]) {
      await tester.pumpWidget(MaterialApp(
        home: nightModeWrap(enabled: enabled, child: const _Counted()),
      ));
      expect(
        find.byType(ColorFiltered),
        findsOneWidget,
        reason: 'off is an identity matrix, not a missing wrapper',
      );
    }
  });
}
