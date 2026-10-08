import 'dart:io';
import 'dart:typed_data';

import 'package:crypto/crypto.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/file_hash.dart';

void main() {
  late Directory dir;
  setUp(() => dir = Directory.systemTemp.createTempSync('vellum_file_hash'));
  tearDown(() => dir.deleteSync(recursive: true));

  test('matches a one-shot SHA-256 across chunk boundaries', () async {
    // Sizes either side of the 1 MB read chunk, and an empty file.
    for (final size in [0, 1, (1 << 20) - 1, 1 << 20, (1 << 20) + 1, 3 << 20]) {
      final bytes = Uint8List.fromList(List.generate(size, (i) => (i * 31) & 0xff));
      final file = File('${dir.path}/f$size')..writeAsBytesSync(bytes);
      expect(await sha256OfFileInBackground(file.path), '${sha256.convert(bytes)}',
          reason: '$size bytes');
    }
  });

  test('several at once all come back right', () async {
    final files = [
      for (var i = 0; i < 9; i++)
        File('${dir.path}/p$i')..writeAsStringSync('book $i' * 1000),
    ];
    final hashes = await Future.wait([for (final f in files) sha256OfFileInBackground(f.path)]);
    for (var i = 0; i < files.length; i++) {
      expect(hashes[i], '${sha256.convert(files[i].readAsBytesSync())}');
    }
  });
}
