import 'package:flutter/semantics.dart';
import 'package:flutter_test/flutter_test.dart';

/// Every label under the semantics node of [finder], in tree order.
///
/// `find.bySemanticsLabel` only sees nodes that come from render objects; the
/// heat map's days are `CustomPainter` semantics, so they are read off the
/// semantics tree directly.
List<String> semanticsLabelsUnder(WidgetTester tester, Finder finder) {
  final labels = <String>[];
  void walk(SemanticsNode node) {
    if (node.label.isNotEmpty) labels.add(node.label);
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(tester.getSemantics(finder));
  return labels;
}

/// The semantics node of the day whose label starts with [prefix] under
/// [finder].
SemanticsNode semanticsDayNode(
  WidgetTester tester,
  Finder finder,
  String prefix,
) {
  SemanticsNode? found;
  void walk(SemanticsNode node) {
    if (node.label.startsWith(prefix)) found = node;
    node.visitChildren((child) {
      walk(child);
      return true;
    });
  }

  walk(tester.getSemantics(finder));
  return found!;
}
