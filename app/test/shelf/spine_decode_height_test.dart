// Why this exists: `cacheHeight` is part of an Image's cache key, and the
// physical room's spines change height on every frame of a pinch. Feeding the
// live height straight in minted a new provider — and a new asynchronous decode
// — per frame, so books went blank while you zoomed and "rasterized in"
// afterwards. These pin the bucketing that stops it.
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/shelf/shelf_view.dart';

void main() {
  test('a whole zoom gesture stays in one bucket', () {
    // The actual bug: 300 -> 340 -> 391 px as a pinch runs must not be three
    // different cache keys, or it is three decodes and two blank frames.
    final heights = [300.0, 311.0, 340.0, 372.4, 391.0, 420.0];
    final buckets = {for (final h in heights) spineDecodeHeight(h)};
    expect(buckets, hasLength(1), reason: 'one gesture, one decode');
  });

  test('rounds up, so the decode is never smaller than the spine', () {
    expect(spineDecodeHeight(65), 128);
    expect(spineDecodeHeight(128), 128);
    expect(spineDecodeHeight(129), 256);
    expect(spineDecodeHeight(600), 1024);
  });

  test('clamps small spines to a floor', () {
    // A room zoomed right out draws spines a few pixels tall; decoding a 3 px
    // cover is not worth a cache entry of its own.
    expect(spineDecodeHeight(3), 64);
    expect(spineDecodeHeight(64), 64);
    expect(spineDecodeHeight(0), 64);
  });

  test('clamps large spines to a ceiling', () {
    // Past this the visible slice is a few hundred pixels wide and the rest is
    // memory. The room zooms to 1600 px/m, so this is reachable.
    expect(spineDecodeHeight(3000), 2048);
    expect(spineDecodeHeight(100000), 2048);
  });

  test('survives the values a layout can actually hand it', () {
    // An unbounded box gives infinity; a collapsed one gives zero or worse.
    expect(spineDecodeHeight(double.infinity), 64);
    expect(spineDecodeHeight(double.nan), 64);
    expect(spineDecodeHeight(-10), 64);
  });

  test('every bucket is a power of two', () {
    for (var px = 1.0; px < 4000; px += 7) {
      final bucket = spineDecodeHeight(px);
      expect(bucket & (bucket - 1), 0, reason: '$px gave $bucket');
    }
  });

  group('the provider a spine actually resolves', () {
    final book = Book(
      id: 'b1',
      title: 'Dune',
      createdAt: DateTime(2026),
      updatedAt: DateTime(2026),
      needsPush: false, syncExcluded: false,
      readerNotesNeedsPush: false,
      needsProgressPush: false,
      status: 'unread',
      readCount: 0,
    );

    /// The image provider `SpineFace` hands to the engine at [height] logical
    /// pixels. The file need not exist: the widget — and so its cache key —
    /// is built either way.
    Future<Object> providerAt(WidgetTester tester, double height) async {
      await tester.pumpWidget(
        MaterialApp(
          home: Center(
            child: SizedBox(
              width: 30,
              height: height,
              child: SpineFace(
                book: book,
                coverFile: File('/nonexistent/cover.jpg'),
              ),
            ),
          ),
        ),
      );
      return tester.widget<Image>(find.byType(Image)).image;
    }

    testWidgets('does not change while a pinch runs', (tester) async {
      // The end-to-end form of the bug: same provider means same cache entry
      // means no re-decode and no blank spine. Heights chosen to sit inside one
      // bucket at the test's device pixel ratio — a wider zoom does cross a
      // boundary, which is what `gaplessPlayback` below is for.
      final a = await providerAt(tester, 300);
      final b = await providerAt(tester, 320);
      final c = await providerAt(tester, 340);
      expect(a, equals(b));
      expect(b, equals(c));
    });

    testWidgets('does change once the spine has doubled', (tester) async {
      // The other half: zoom far enough and it really should re-decode, or a
      // spine that fills the screen stays a thumbnail.
      final small = await providerAt(tester, 100);
      final large = await providerAt(tester, 900);
      expect(small, isNot(equals(large)));
    });

    testWidgets('keeps the previous frame while a new decode runs',
        (tester) async {
      await providerAt(tester, 300);
      expect(
        tester.widget<Image>(find.byType(Image)).gaplessPlayback,
        isTrue,
        reason: 'without this the spine blanks when the bucket changes',
      );
    });
  });
}
