import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:image/image.dart' as img;
import 'package:path/path.dart' as p;
import 'package:vellum/data/cover_thumbnails.dart';

void main() {
  late Directory covers;
  setUp(() => covers = Directory.systemTemp.createTempSync('vellum_thumbs'));
  tearDown(() => covers.deleteSync(recursive: true));

  /// A cover on disk, as the app stores them: `covers/<id>.jpg`, whatever the
  /// bytes actually are (a rendered PDF page used to be a PNG under that name).
  File cover(String id, img.Image image) =>
      File(p.join(covers.path, '$id.jpg'))
        ..writeAsBytesSync(img.encodePng(image));

  img.Image solid(int w, int h, img.Color c) =>
      img.Image(width: w, height: h)..clear(c);

  img.Image decode(File f) => img.decodeImage(f.readAsBytesSync())!;

  test('makes a JPEG at the asked-for height, keeping the aspect ratio',
      () async {
    final source = cover('b1', solid(600, 900, img.ColorRgb8(200, 30, 30)));

    expect(await CoverThumbnails.make(source, 256), isTrue);

    final thumb = CoverThumbnails.fileFor(source, 256);
    expect(thumb.path, p.join(covers.path, 'thumbs', 'b1-h256.jpg'));
    final bytes = thumb.readAsBytesSync();
    expect(bytes.sublist(0, 2), [0xFF, 0xD8], reason: 'a JPEG, not a PNG');
    final decoded = decode(thumb);
    expect(decoded.height, 256);
    expect(decoded.width, closeTo(171, 1));
    expect(bytes.length, lessThan(source.lengthSync()));
  });

  test('never upscales a cover smaller than asked for', () async {
    final source = cover('small', solid(100, 150, img.ColorRgb8(0, 0, 255)));

    expect(await CoverThumbnails.make(source, 512), isTrue);

    expect(decode(CoverThumbnails.fileFor(source, 512)).height, 150);
  });

  test('is current only while the cover is no newer than it', () async {
    final source = cover('b1', solid(300, 450, img.ColorRgb8(0, 120, 0)));
    await CoverThumbnails.make(source, 128);
    final thumb = CoverThumbnails.fileFor(source, 128);
    final made = thumb.lastModifiedSync();

    expect(
      await CoverThumbnails.current(source, 128, coverModified: made),
      isNotNull,
    );
    // The cover rewritten after the thumbnail was made — a sync, a new pick.
    expect(
      await CoverThumbnails.current(source, 128,
          coverModified: made.add(const Duration(seconds: 1))),
      isNull,
      reason: 'a stale thumbnail would show the old cover',
    );
    expect(
      await CoverThumbnails.current(source, 64, coverModified: made),
      isNull,
      reason: 'never made at this height',
    );
  });

  test('flattens transparency onto white rather than black', () async {
    final source = cover(
      'clear',
      img.Image(width: 40, height: 60, numChannels: 4)
        ..clear(img.ColorRgba8(0, 0, 0, 0)),
    );

    expect(await CoverThumbnails.make(source, 32), isTrue);

    final pixel = decode(CoverThumbnails.fileFor(source, 32)).getPixel(5, 5);
    expect(pixel.r, greaterThan(245));
    expect(pixel.g, greaterThan(245));
    expect(pixel.b, greaterThan(245));
  });

  test('declines sizes past the ceiling and covers it cannot decode',
      () async {
    final source = cover('b1', solid(300, 450, img.ColorRgb8(1, 2, 3)));
    expect(await CoverThumbnails.make(source, 2048), isFalse);
    expect(CoverThumbnails.fileFor(source, 2048).existsSync(), isFalse);

    final junk = File(p.join(covers.path, 'junk.jpg'))
      ..writeAsStringSync('not an image');
    expect(await CoverThumbnails.make(junk, 256), isFalse);
    expect(CoverThumbnails.fileFor(junk, 256).existsSync(), isFalse);
  });

  test('a thumbnail asked for twice at once is made once', () {
    final source = cover('b1', solid(300, 450, img.ColorRgb8(9, 9, 9)));
    final first = CoverThumbnails.make(source, 256);
    final second = CoverThumbnails.make(source, 256);
    expect(identical(first, second), isTrue);
    return first;
  });

  test('deleting a book removes its thumbnails and no one else\'s', () async {
    final mine = cover('b1', solid(300, 450, img.ColorRgb8(9, 9, 9)));
    final theirs = cover('b10', solid(300, 450, img.ColorRgb8(9, 9, 9)));
    await CoverThumbnails.make(mine, 128);
    await CoverThumbnails.make(mine, 256);
    await CoverThumbnails.make(theirs, 128);

    await CoverThumbnails.deleteFor(mine);

    expect(CoverThumbnails.fileFor(mine, 128).existsSync(), isFalse);
    expect(CoverThumbnails.fileFor(mine, 256).existsSync(), isFalse);
    expect(CoverThumbnails.fileFor(theirs, 128).existsSync(), isTrue,
        reason: '"b1-h" is not a prefix of "b10-h128.jpg"');
  });
}
