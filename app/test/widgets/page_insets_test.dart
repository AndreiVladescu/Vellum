import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/widgets/page_insets.dart';

/// [pageInsets] exists because of a real bug: "Move to trash" is the last row
/// of the book page's list, and edge-to-edge put it under Android's navigation
/// bar. These pin both halves of the fix — it adds the inset where there is
/// one, and changes nothing where there isn't.
void main() {
  Future<EdgeInsets> insetsUnder(
    WidgetTester tester,
    EdgeInsets viewPadding,
    EdgeInsets base,
  ) async {
    late EdgeInsets result;
    await tester.pumpWidget(
      MediaQuery(
        data: MediaQueryData(viewPadding: viewPadding),
        child: Builder(
          builder: (context) {
            result = pageInsets(context, base);
            return const SizedBox();
          },
        ),
      ),
    );
    return result;
  }

  testWidgets('adds the system inset below the page padding', (tester) async {
    final insets = await insetsUnder(
      tester,
      const EdgeInsets.only(bottom: 48),
      const EdgeInsets.all(24),
    );
    expect(insets, const EdgeInsets.fromLTRB(24, 24, 24, 72));
  });

  testWidgets('is a no-op with no system inset', (tester) async {
    final insets = await insetsUnder(
      tester,
      EdgeInsets.zero,
      const EdgeInsets.all(24),
    );
    expect(insets, const EdgeInsets.all(24));
  });

  testWidgets('gives a list with no padding of its own the inset alone',
      (tester) async {
    final insets = await insetsUnder(
      tester,
      const EdgeInsets.only(bottom: 48),
      EdgeInsets.zero,
    );
    expect(insets, const EdgeInsets.only(bottom: 48));
  });
}
