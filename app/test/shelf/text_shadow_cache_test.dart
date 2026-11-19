// A cover spine's title shadow is drawn once into an image and reused
// (text_shadow_cache.dart, docs/PERFORMANCE.md). That is only worth doing if
// nobody can tell: this paints spine titles both ways and compares pixels.
import 'dart:io';
import 'dart:math';
import 'dart:ui' as ui;

import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:path/path.dart' as p;
import 'package:vellum/shelf/shelf_view.dart' show spineTitleShadow;
import 'package:vellum/shelf/text_shadow_cache.dart';

/// A real typeface, so the shadow has real glyph shapes to follow — the test
/// font draws every character as a square. Roboto ships with the Flutter SDK;
/// without it the comparison still runs, in squares.
Future<String> _loadFont() async {
  final root = Platform.environment['FLUTTER_ROOT'] ??
      p.normalize(p.join(p.dirname(Platform.resolvedExecutable), '../../../../..'));
  final dir = p.join(root, 'bin', 'cache', 'artifacts', 'material_fonts');
  final file = File(p.join(dir, 'Roboto-Medium.ttf'));
  if (!file.existsSync()) return 'Ahem';
  final loader = FontLoader('ShadowTestRoboto')
    ..addFont(Future.value(ByteData.sublistView(file.readAsBytesSync())));
  await loader.load();
  return 'ShadowTestRoboto';
}

/// The title as `SpineFace` draws it, over artwork-ish grey, either with the
/// shadow in its style (as it was) or through the cache. [aligned] puts it at
/// a whole-pixel position instead, unrotated, 60 px wide.
Widget _title(
  String title,
  String font, {
  required bool cached,
  bool aligned = false,
}) {
  final style = TextStyle(
    fontFamily: font,
    color: Colors.white,
    fontSize: 13,
    fontWeight: FontWeight.w600,
    letterSpacing: 0.4,
  );
  final text = cached
      ? CachedTextShadow(
          shadow: spineTitleShadow,
          child: Text(
            title,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: style,
          ),
        )
      : Text(
          title,
          maxLines: 1,
          overflow: TextOverflow.ellipsis,
          style: style.copyWith(shadows: const [spineTitleShadow]),
        );
  if (aligned) {
    return Align(
      alignment: Alignment.topLeft,
      child: Padding(
        padding: const EdgeInsets.only(left: 4, top: 4),
        child: SizedBox(width: 60, child: text),
      ),
    );
  }
  return ClipRRect(
    borderRadius: const BorderRadius.vertical(top: Radius.circular(3)),
    child: Stack(
      fit: StackFit.expand,
      children: [
        const ColoredBox(color: Color(0xFF7A8C9E)),
        Padding(
          padding: const EdgeInsets.symmetric(vertical: 10),
          child: RotatedBox(quarterTurns: 1, child: Center(child: text)),
        ),
      ],
    ),
  );
}

Future<Uint8List> _pixels(
  WidgetTester tester,
  Widget child,
  Size size,
  double dpr, {
  GlobalKey? boundary,
}) async {
  final key = boundary ?? GlobalKey();
  await tester.pumpWidget(MediaQuery(
    data: MediaQueryData(devicePixelRatio: dpr),
    child: Directionality(
      textDirection: TextDirection.ltr,
      child: Align(
        alignment: Alignment.topLeft,
        child: RepaintBoundary(
          key: key,
          child: SizedBox.fromSize(size: size, child: child),
        ),
      ),
    ),
  ));
  // Whatever a frame asked for after itself (a shadow that was waiting).
  await tester.pumpAndSettle();
  late Uint8List bytes;
  await tester.runAsync(() async {
    final boundary =
        key.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage(pixelRatio: dpr);
    final data = await image.toByteData(format: ui.ImageByteFormat.rawRgba);
    bytes = data!.buffer.asUint8List();
    image.dispose();
  });
  return bytes;
}

({int max, double mean}) _diff(Uint8List a, Uint8List b) {
  expect(a.length, b.length);
  var worst = 0;
  var sum = 0;
  for (var i = 0; i < a.length; i++) {
    final d = (a[i] - b[i]).abs();
    sum += d;
    worst = max(worst, d);
  }
  return (max: worst, mean: sum / a.length);
}

void main() {
  late String font;
  setUpAll(() async => font = await _loadFont());
  setUp(() => TextShadowCache.instance.clear());

  const titles = [
    'A',
    'Dune',
    'The Silent River of Kings',
    'Ångström — ειρήνη & Co.',
  ];

  // Spine sizes: a thin room book, a room book zoomed in, the shelf's, and one
  // fractional width. The title runs down the height, so the height decides
  // where it is cut off.
  const sizes = [
    Size(9.6, 64),
    Size(14.2, 97.3),
    Size(34, 149),
    Size(50.857, 160),
    Size(48, 600),
  ];

  // On the pixel grid the image is drawn unresampled, and it is the engine's
  // own shadow: the pixels are the same.
  testWidgets('a cached title shadow on whole pixels is the same pixels',
      (tester) async {
    for (final dpr in [1.0, 2.0, 2.75]) {
      for (final title in titles) {
        const size = Size(80, 40);
        final before = await _pixels(
          tester,
          _title(title, font, cached: false, aligned: true),
          size,
          dpr,
        );
        final after = await _pixels(
          tester,
          _title(title, font, cached: true, aligned: true),
          size,
          dpr,
        );
        final d = _diff(before, after);
        expect(d.max, lessThanOrEqualTo(2), reason: '"$title" at ${dpr}x');
        expect(d.mean, lessThan(0.05), reason: '"$title" at ${dpr}x');
      }
    }
  });

  // Where a spine puts it — rotated, centred, at a fractional position — the
  // image lands between device pixels and is resampled, which moves the blur
  // by under half a pixel: a few levels at the steepest part of its edge
  // (measured: at most 7, at 2.75x), a fraction of a level on average, and
  // nothing in the crisp title on top.
  for (final dpr in [1.0, 2.0, 2.75]) {
    testWidgets('a cached title shadow on a spine looks the same at ${dpr}x',
        (tester) async {
      for (final title in titles) {
        for (final size in sizes) {
          final before =
              await _pixels(tester, _title(title, font, cached: false), size, dpr);
          final after =
              await _pixels(tester, _title(title, font, cached: true), size, dpr);
          final d = _diff(before, after);
          expect(d.max, lessThanOrEqualTo(8), reason: '"$title" at $size');
          expect(d.mean, lessThan(0.5), reason: '"$title" at $size');
        }
      }
    });
  }

  testWidgets('zooming reuses a shadow while the cut-off stays put, and '
      'still draws the same pixels', (tester) async {
    // A sweep of heights in small steps, as a zoom does, without clearing the
    // cache between them: a shadow reused for the wrong cut-off would show.
    const title = 'The Silent River of Kings';
    var steps = 0;
    for (var h = 50.0; h < 260; h += 4.3) {
      steps++;
      final size = Size(16, h);
      final before =
          await _pixels(tester, _title(title, font, cached: false), size, 2);
      final after =
          await _pixels(tester, _title(title, font, cached: true), size, 2);
      final d = _diff(before, after);
      expect(d.max, lessThanOrEqualTo(8), reason: 'height $h');
      expect(d.mean, lessThan(0.5), reason: 'height $h');
    }
    // One drawing per cut-off, not one per height.
    expect(TextShadowCache.instance.drawn, lessThan(steps * 3 ~/ 4));
  });

  testWidgets('a title zoomed in place ends up with the right shadow',
      (tester) async {
    // The same box resized step by step, as the room's zoom does: the cut-off
    // moves, the box shows its old shadow while it does, and once it holds
    // still the new one is drawn.
    const title = 'The Silent River of Kings';
    final sizes = [for (var h = 60.0; h < 200; h += 13.7) Size(16, h)];
    final reference = [
      for (final size in sizes)
        await _pixels(tester, _title(title, font, cached: false), size, 2),
    ];
    final boundary = GlobalKey();
    RenderObject? box;
    for (var i = 0; i < sizes.length; i++) {
      final after = await _pixels(
        tester,
        _title(title, font, cached: true),
        sizes[i],
        2,
        boundary: boundary,
      );
      final now = tester.renderObject(find.byType(CachedTextShadow));
      expect(box == null || identical(box, now), isTrue);
      box = now;
      final d = _diff(reference[i], after);
      expect(d.max, lessThanOrEqualTo(8), reason: '${sizes[i]}');
      expect(d.mean, lessThan(0.5), reason: '${sizes[i]}');
    }
  });

  testWidgets('a repaint with nothing changed draws nothing new',
      (tester) async {
    // The parent repaints (a new colour, no repaint boundary in between), so
    // the title paints again on every pump — from the image it already has.
    final colour = ValueNotifier(0);
    await tester.pumpWidget(Directionality(
      textDirection: TextDirection.ltr,
      child: ValueListenableBuilder<int>(
        valueListenable: colour,
        child: SizedBox(
          width: 20,
          height: 120,
          child: _title('Dune', font, cached: true),
        ),
        builder: (context, c, child) =>
            ColoredBox(color: Color(0xFF000000 + c), child: child),
      ),
    ));
    expect(TextShadowCache.instance.drawn, 1);
    for (var i = 1; i <= 5; i++) {
      colour.value = i;
      await tester.pump();
    }
    expect(TextShadowCache.instance.drawn, 1);
  });
}
