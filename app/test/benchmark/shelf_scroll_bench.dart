// Laying out and scrolling the shelf at a size where it costs something.
//
// Every shelf row is a fixed height (books + board + gap), so the `ListView`
// takes an `itemExtent`. This times the build and a scroll through the list,
// which is the path that benefits: with a fixed extent the sliver works out
// where each row lands arithmetically, instead of building and measuring rows
// to find the scroll offset.
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/shelf/shelf_view.dart';
import 'package:vellum/shelf/spine_style.dart';

// A real stored style, as the database holds it. Without this the books take
// `fromJson`'s null early-return and the decode path is never exercised — which
// is exactly how an earlier version of this benchmark measured nothing.
Book _book(int i) => Book(
      id: 'b$i',
      title: 'Book number $i',
      spineStyle: SpineStyle.generate(title: 'Book number $i').toJson(),
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      needsPush: false, syncExcluded: false,
      readerNotesNeedsPush: false,
      statusNeedsPush: false,
      needsProgressPush: false,
      status: 'unread',
      readCount: 0,
    );

void main() {
  testWidgets('build and scroll a large shelf', (tester) async {
    const n = 3000;
    final books = [for (var i = 0; i < n; i++) _book(i)];

    await tester.binding.setSurfaceSize(const Size(1400, 900));
    final sw = Stopwatch()..start();
    await tester.pumpWidget(MaterialApp(
      home: Scaffold(
        body: ShelfView(
          books: books,
          detailBuilder: (b) => const SizedBox.shrink(),
        ),
      ),
    ));
    sw.stop();
    // ignore: avoid_print
    print('  first build, $n books: ${sw.elapsedMilliseconds} ms');

    // Scroll through a stretch of the shelf, pumping frames as a finger would.
    final sw2 = Stopwatch()..start();
    final list = find.byType(Scrollable).first;
    for (var i = 0; i < 30; i++) {
      await tester.drag(list, const Offset(0, -400));
      await tester.pump(const Duration(milliseconds: 16));
    }
    sw2.stop();
    // ignore: avoid_print
    print('  30 scroll steps: ${sw2.elapsedMilliseconds} ms '
        '(${(sw2.elapsedMilliseconds / 30).toStringAsFixed(1)} ms per step)');

    addTearDown(() => tester.binding.setSurfaceSize(null));
  });
}
