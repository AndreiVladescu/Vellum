import 'dart:async';
import 'dart:io';
import 'dart:ui' as ui;

import 'package:flutter/painting.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:vellum/data/cover_thumbnails.dart';
import 'package:vellum/shelf/cover_image.dart';

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory covers;
  late File cover;
  setUp(() {
    covers = Directory.systemTemp.createTempSync('vellum_cover_image');
    cover = File(p.join(covers.path, 'b1.jpg'))
      ..writeAsBytesSync(img.encodePng(
          img.Image(width: 400, height: 600)..clear(img.ColorRgb8(0, 0, 255))));
  });
  tearDown(() {
    imageCache.clear();
    covers.deleteSync(recursive: true);
  });

  test('a rewritten cover gets a new cache key', () async {
    // The cover keeps one path per book, so a path-only key (FileImage's)
    // can't tell a new cover from the old one.
    const config = ImageConfiguration.empty;
    final before = await CoverImage(cover, height: 256).obtainKey(config);
    expect(await CoverImage(cover, height: 256).obtainKey(config), before);

    cover.setLastModifiedSync(
        cover.lastModifiedSync().add(const Duration(seconds: 5)));
    expect(await CoverImage(cover, height: 256).obtainKey(config),
        isNot(before));
  });

  test('equality follows path, height and version — not the file', () {
    expect(CoverImage(cover, height: 256, version: 1),
        CoverImage(File(cover.path), height: 256, version: 1));
    expect(CoverImage(cover, height: 256, version: 1),
        isNot(CoverImage(cover, height: 512, version: 1)));
    expect(CoverImage(cover, height: 256, version: 1),
        isNot(CoverImage(cover, height: 256, version: 2)),
        reason: 'a new version is what makes an Image re-check the file');
  });

  testWidgets('decodes the cover on a miss, then the thumbnail it made',
      (tester) async {
    await tester.runAsync(() async {
      Future<ui.Image> resolve() {
        final done = Completer<ui.Image>();
        final stream = CoverImage(cover, height: 256)
            .resolve(ImageConfiguration.empty);
        late final ImageStreamListener listener;
        listener = ImageStreamListener(
          (info, _) {
            done.complete(info.image);
            // Detached, or the image stays "live" and the cache clear below
            // can't drop it.
            stream.removeListener(listener);
          },
          onError: (e, _) => done.completeError(e),
        );
        stream.addListener(listener);
        return done.future;
      }

      // First look: no thumbnail yet, so the cover itself at the target size.
      final first = await resolve();
      expect(first.height, 256);

      // ...and the thumbnail is being made in the background. Wait for it,
      // then swap in a red one so the next decode shows where it came from.
      await CoverThumbnails.make(cover, 256);
      final thumb = CoverThumbnails.fileFor(cover, 256);
      expect(thumb.existsSync(), isTrue);
      thumb.writeAsBytesSync(img.encodeJpg(
          img.Image(width: 171, height: 256)..clear(img.ColorRgb8(255, 0, 0))));

      imageCache
        ..clear()
        ..clearLiveImages();
      final second = await resolve();
      final pixels = await second.toByteData();
      expect(pixels!.getUint8(0), greaterThan(200), reason: 'red: the thumb');
      expect(pixels.getUint8(2), lessThan(50), reason: 'not the blue cover');
    });
  });
}
