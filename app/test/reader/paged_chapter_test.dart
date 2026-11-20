// The paged view's page-turn glide: it slides one painted column, never lays
// the chapter out again, and does nothing under reduced motion.
//
// No HtmlWidget here (it hangs under testWidgets): the chapter is a plain
// column of Text, which the viewport measures the same way.
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/reader/epub_pagination.dart';
import 'package:vellum/reader/paged_chapter.dart';

/// Counts how many times the chapter is laid out.
class _CountingBox extends SingleChildRenderObjectWidget {
  const _CountingBox({required this.counter, super.child});
  final List<int> counter;
  @override
  RenderObject createRenderObject(BuildContext context) =>
      _RenderCounting(counter);
}

class _RenderCounting extends RenderProxyBox {
  _RenderCounting(this.counter);
  final List<int> counter;
  @override
  void performLayout() {
    counter[0]++;
    super.performLayout();
  }
}

Widget _host({
  required PageAnchor anchor,
  required List<int> layouts,
  required void Function(ChapterPages) onPaginated,
  bool reduceMotion = false,
}) {
  return MaterialApp(
    home: MediaQuery(
      data: MediaQueryData(disableAnimations: reduceMotion),
      child: Align(
        alignment: Alignment.topLeft,
        child: SizedBox(
          width: 300,
          height: 120,
          child: PagedChapterView(
            anchor: anchor,
            onPaginated: onPaginated,
            child: _CountingBox(
              counter: layouts,
              child: Column(
                children: [
                  for (var i = 0; i < 30; i++)
                    SizedBox(height: 20, child: Text('line $i')),
                ],
              ),
            ),
          ),
        ),
      ),
    ),
  );
}

void main() {
  Future<ChapterPages> open(
    WidgetTester tester,
    List<int> layouts, {
    bool reduceMotion = false,
  }) async {
    ChapterPages? pages;
    await tester.pumpWidget(
      _host(
        anchor: const AtContentFraction(0),
        layouts: layouts,
        reduceMotion: reduceMotion,
        onPaginated: (p) => pages = p,
      ),
    );
    await tester.pump();
    expect(pages, isNotNull);
    return pages!;
  }

  Future<void> turnTo(
    WidgetTester tester,
    ChapterPages pages,
    int page,
    List<int> layouts, {
    bool reduceMotion = false,
  }) => tester.pumpWidget(
    _host(
      anchor: AtContentFraction(pages.contentFractionOf(page)),
      layouts: layouts,
      reduceMotion: reduceMotion,
      onPaginated: (_) {},
    ),
  );

  testWidgets(
    'a turn glides in between, ends on the page, and lays nothing out',
    (tester) async {
      final layouts = [0];
      final pages = await open(tester, layouts);
      expect(pages.count, greaterThan(2));
      final laidOut = layouts[0];
      expect(tester.getTopLeft(find.text('line 0')).dy, closeTo(0, 1));

      await turnTo(tester, pages, 1, layouts);
      await tester.pump(pageTurnDuration ~/ 3);
      final mid = tester.getTopLeft(find.text('line 0')).dy;
      expect(mid, lessThan(-1), reason: 'moving');
      expect(mid, greaterThan(-pages.starts[1]), reason: 'not there yet');

      await tester.pump(pageTurnDuration);
      expect(
        tester.getTopLeft(find.text('line 0')).dy,
        closeTo(-pages.starts[1], 0.01),
      );
      expect(layouts[0], laidOut, reason: 'a turn repaints, never re-lays out');
    },
  );

  testWidgets('reduced motion turns in one frame', (tester) async {
    final layouts = [0];
    final pages = await open(tester, layouts, reduceMotion: true);
    await turnTo(tester, pages, 1, layouts, reduceMotion: true);
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('line 0')).dy,
      closeTo(-pages.starts[1], 0.01),
    );
  });

  testWidgets('a jump of several pages does not glide', (tester) async {
    final layouts = [0];
    final pages = await open(tester, layouts);
    await turnTo(tester, pages, 3, layouts);
    await tester.pump();
    expect(
      tester.getTopLeft(find.text('line 0')).dy,
      closeTo(-pages.starts[3], 0.01),
    );
  });
}
