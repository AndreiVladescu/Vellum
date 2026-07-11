import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/book_detail/cover_thumb.dart';

Widget _host(TargetPlatform platform, VoidCallback onTap) => MaterialApp(
      theme: ThemeData(platform: platform),
      home: Scaffold(body: Center(child: CoverThumb(cover: null, onTap: onTap))),
    );

void main() {
  testWidgets('shows a persistent edit badge on touch platforms', (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.android, () {}));
    // The hover overlay never fires on touch, so a visible edit affordance must
    // be present without any pointer interaction.
    expect(find.byIcon(Icons.edit), findsOneWidget);
  });

  testWidgets('no edit badge on desktop (hover reveals the overlay instead)',
      (tester) async {
    await tester.pumpWidget(_host(TargetPlatform.linux, () {}));
    expect(find.byIcon(Icons.edit), findsNothing);
  });

  testWidgets('tapping the cover triggers onTap on touch', (tester) async {
    var tapped = false;
    await tester.pumpWidget(_host(TargetPlatform.android, () => tapped = true));
    await tester.tap(find.byType(CoverThumb));
    expect(tapped, isTrue);
  });
}
