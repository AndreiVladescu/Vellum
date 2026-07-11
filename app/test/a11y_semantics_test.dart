import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/book_detail/cover_thumb.dart';
import 'package:vellum/shelf/shelf_view.dart';

void main() {
  group('bookSemanticLabel', () {
    test('title only when there is no subtitle', () {
      expect(bookSemanticLabel('Dune', null), 'Dune');
      expect(bookSemanticLabel('Dune', ''), 'Dune');
    });
    test('appends the subtitle when present', () {
      expect(bookSemanticLabel('Dune', 'Deluxe Edition'),
          'Dune: Deluxe Edition');
    });
  });

  testWidgets('CoverThumb exposes a "Change cover" button to screen readers',
      (tester) async {
    final handle = tester.ensureSemantics();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(body: CoverThumb(cover: null, onTap: () {})),
    ));
    expect(find.bySemanticsLabel('Change cover'), findsOneWidget);
    handle.dispose();
  });
}
