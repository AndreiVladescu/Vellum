// Not a test — a `flutter test`-hosted CLI for generating a large synthetic
// library on disk for manual profiling with `flutter run --profile`. It has
// to run inside `flutter test` rather than plain `dart run` because
// `database.dart` pulls in `drift_flutter`, which needs the Flutter engine's
// `dart:ui` — unavailable to the standalone Dart VM. See docs/PERFORMANCE.md.
//
// Skipped by default so a normal `flutter test` run stays fast; opt in with:
//
//   SEED_LIBRARY_COUNT=5000 flutter test test/tool/seed_library_tool.dart
//
// Writes `<SEED_LIBRARY_OUT, default /tmp/vellum_seed>/vellum.sqlite`.
import 'dart:io';

import 'package:drift/native.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:vellum/data/database.dart';
import 'package:vellum/data/seed_library.dart';

void main() {
  final countStr = Platform.environment['SEED_LIBRARY_COUNT'];
  test(
    'seed a synthetic library to disk',
    () async {
      final count = int.parse(countStr!);
      final seed = int.parse(Platform.environment['SEED_LIBRARY_SEED'] ?? '1');
      final outDir =
          Platform.environment['SEED_LIBRARY_OUT'] ?? '/tmp/vellum_seed';

      final dir = Directory(outDir)..createSync(recursive: true);
      final dbFile = File('${dir.path}/vellum.sqlite');
      if (dbFile.existsSync()) dbFile.deleteSync();

      final db = VellumDatabase(NativeDatabase(dbFile));
      final stopwatch = Stopwatch()..start();
      await seedLibrary(
        db,
        count: count,
        seed: seed,
        onProgress: (done, total) => stdout.write('\r  seeded $done / $total'),
      );
      await db.close();
      stdout.writeln();
      // ignore: avoid_print
      print('Wrote $count books to ${dbFile.path} '
          'in ${stopwatch.elapsedMilliseconds} ms');
    },
    skip: countStr == null ? 'set SEED_LIBRARY_COUNT to run' : false,
  );
}
